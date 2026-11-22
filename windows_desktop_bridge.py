# Windows desktop bridge: MCP server that lets Muse work in native
# Windows programs through screenshots, mouse clicks and keyboard input.
#
# Transport: Streamable HTTP, POST /mcp. Bind host from BRIDGE_HOST
# (default 127.0.0.1; set to the Tailscale IP for tailnet access).
# Expose it outside the machine with a cloudflared tunnel started
# manually on that machine; this server never starts the tunnel itself.
#
# Auth: static bearer token from the BRIDGE_TOKEN environment variable.
# The token is never hardcoded, never logged and never passed in chat.
# On the Muse side it belongs in Secure Vault / the connector credential
# flow, not in any file.
#
# Session model: every screen/mouse/keyboard tool works only while
# "connected". The connect tool opens the session and tells OBS Studio
# (over its WebSocket API) to start recording with the chosen profile;
# disconnect stops the recording and closes the session. If OBS cannot
# be reached or refuses, connect fails and nothing else works, so there
# is no unrecorded work by accident.
#
# OBS settings come from the environment: OBS_WS_HOST (default
# 127.0.0.1), OBS_WS_PORT (default 4455), OBS_WS_PASSWORD (only if the
# OBS WebSocket server has authentication on) and OBS_PROFILE (default
# profile name; the connect tool can override it per session).
#
# Scope by design: screen + mouse + keyboard + OBS recording control.
# No shell, no file access, no process control. Start it manually,
# stop it when done. pyautogui FAILSAFE stays on: moving the mouse to
# a screen corner aborts the current action.

import base64
import ctypes
import hashlib
import hmac
import json
import os
import sys
import uuid

import mss
import mss.tools
import pyautogui
import uvicorn
import websocket
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse
from starlette.routing import Mount

pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.1

# DNS rebinding protection is off: by default FastMCP only allows
# localhost Host headers and rejects tailnet addresses with 421.
# The server binds only 127.0.0.1 or the Tailscale IP and requires
# the Bearer token, so the Host check adds nothing here.
mcp = FastMCP(
    "windows-desktop-bridge",
    transport_security=TransportSecuritySettings(
        enable_dns_rebinding_protection=False
    ),
)

# Session state. The OBS websocket stays open for the whole session so
# disconnect can stop the recording on the same connection.
_connected = False
_obs_ws = None


def check_bearer(authorization_header, expected_token):
    # Pure helper, kept separate so it can be unit-tested without a GUI.
    if not authorization_header or not expected_token:
        return False
    prefix = "Bearer "
    if not authorization_header.startswith(prefix):
        return False
    presented = authorization_header[len(prefix):]
    return hmac.compare_digest(presented, expected_token)


class BearerAuthMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, expected_token):
        super().__init__(app)
        self.expected_token = expected_token

    async def dispatch(self, request, call_next):
        if not check_bearer(
            request.headers.get("Authorization", ""), self.expected_token
        ):
            return JSONResponse(
                {"error": "unauthorized"},
                status_code=401,
                headers={"WWW-Authenticate": 'Bearer realm="mcp"'},
            )
        return await call_next(request)


def require_connected():
    if not _connected:
        raise RuntimeError("not connected: call the connect tool first")


# --- OBS Studio WebSocket (obs-websocket v5) ---------------------------

def _obs_auth_string(password, salt, challenge):
    secret = base64.b64encode(
        hashlib.sha256((password + salt).encode("utf-8")).digest()
    )
    return base64.b64encode(
        hashlib.sha256(secret + challenge.encode("utf-8")).digest()
    ).decode("ascii")


def _obs_connect():
    host = os.environ.get("OBS_WS_HOST", "127.0.0.1")
    port = os.environ.get("OBS_WS_PORT", "4455")
    password = os.environ.get("OBS_WS_PASSWORD", "")
    ws = websocket.create_connection("ws://%s:%s" % (host, port), timeout=10)
    hello = json.loads(ws.recv())
    if hello.get("op") != 0:
        ws.close()
        raise RuntimeError("unexpected OBS hello: %r" % (hello,))
    identify = {"op": 1, "d": {"rpcVersion": 1}}
    auth = hello.get("d", {}).get("authentication")
    if auth:
        if not password:
            ws.close()
            raise RuntimeError(
                "OBS WebSocket requires a password: set OBS_WS_PASSWORD"
            )
        identify["d"]["authentication"] = _obs_auth_string(
            password, auth["salt"], auth["challenge"]
        )
    ws.send(json.dumps(identify))
    identified = json.loads(ws.recv())
    if identified.get("op") != 2:
        ws.close()
        raise RuntimeError("OBS identification failed: %r" % (identified,))
    return ws


def _obs_request(ws, request_type, request_data=None):
    request_id = uuid.uuid4().hex
    ws.send(
        json.dumps(
            {
                "op": 6,
                "d": {
                    "requestType": request_type,
                    "requestId": request_id,
                    "requestData": request_data or {},
                },
            }
        )
    )
    while True:
        message = json.loads(ws.recv())
        if message.get("op") == 7 and message["d"].get("requestId") == request_id:
            status = message["d"].get("requestStatus", {})
            if not status.get("result"):
                raise RuntimeError(
                    "OBS request %s failed: %s"
                    % (request_type, status.get("comment", status))
                )
            return message["d"].get("responseData", {})


# --- Session tools ------------------------------------------------------

@mcp.tool()
def connect(profile=""):
    """Open a session: switch OBS to the profile and start recording.

    profile: OBS profile name to record with. Empty means the
    OBS_PROFILE environment variable; if that is empty too, OBS keeps
    its current profile. All other tools refuse to work until this
    succeeds, and a failed OBS start means no session.
    """
    global _connected, _obs_ws
    if _connected:
        return {"connected": True, "note": "already connected"}
    chosen = profile or os.environ.get("OBS_PROFILE", "")
    ws = _obs_connect()
    try:
        if chosen:
            _obs_request(ws, "SetCurrentProfile", {"profileName": chosen})
        _obs_request(ws, "StartRecord")
    except Exception:
        ws.close()
        raise
    _obs_ws = ws
    _connected = True
    return {"connected": True, "obs_profile": chosen or "(current)", "recording": True}


@mcp.tool()
def disconnect():
    """Close the session: stop the OBS recording and lock all tools."""
    global _connected, _obs_ws
    if not _connected:
        return {"connected": False, "note": "was not connected"}
    output_path = ""
    try:
        result = _obs_request(_obs_ws, "StopRecord")
        output_path = result.get("outputPath", "")
    finally:
        try:
            _obs_ws.close()
        finally:
            _obs_ws = None
            _connected = False
    return {"connected": False, "recording": False, "output_path": output_path}


@mcp.tool()
def status():
    """Report whether a session is open. Works while disconnected."""
    return {"connected": _connected}


# --- Screen / mouse / keyboard tools (connected sessions only) ----------

def screen_size():
    size = pyautogui.size()
    return size.width, size.height


def check_point(x, y):
    width, height = screen_size()
    if not (0 <= x < width and 0 <= y < height):
        raise ValueError(
            "point (%s, %s) is outside the screen %sx%s" % (x, y, width, height)
        )


@mcp.tool()
def screenshot():
    """Take a screenshot of the full virtual screen.

    Returns a dict with the PNG image as base64 plus the screen size in
    pixels, so click coordinates can be given in the same pixels.
    Single-monitor assumption for this skeleton: with several monitors
    the screenshot covers the whole virtual screen, while pyautogui
    coordinates start at the primary monitor.
    """
    require_connected()
    with mss.mss() as sct:
        shot = sct.grab(sct.monitors[0])
        png = mss.tools.to_png(shot.rgb, shot.size)
    width, height = screen_size()
    return {
        "image_png_base64": base64.b64encode(png).decode("ascii"),
        "width": width,
        "height": height,
    }


@mcp.tool()
def click(x, y):
    """Left-click at pixel coordinates (x, y)."""
    require_connected()
    check_point(x, y)
    pyautogui.click(x=x, y=y)
    return {"clicked": [x, y]}


@mcp.tool()
def double_click(x, y):
    """Double left-click at pixel coordinates (x, y)."""
    require_connected()
    check_point(x, y)
    pyautogui.doubleClick(x=x, y=y)
    return {"double_clicked": [x, y]}


@mcp.tool()
def type_text(text):
    """Type text with the keyboard (English layout assumed)."""
    require_connected()
    pyautogui.write(text, interval=0.01)
    return {"typed_chars": len(text)}


@mcp.tool()
def key(combo):
    """Press a key or a combination, e.g. "enter" or "ctrl+s"."""
    require_connected()
    parts = [part.strip().lower() for part in combo.split("+") if part.strip()]
    if not parts:
        raise ValueError("empty key combination")
    if len(parts) == 1:
        pyautogui.press(parts[0])
    else:
        pyautogui.hotkey(*parts)
    return {"pressed": combo}


@mcp.tool()
def scroll(x, y, delta):
    """Scroll at pixel coordinates (x, y); positive delta scrolls up."""
    require_connected()
    check_point(x, y)
    pyautogui.scroll(delta, x=x, y=y)
    return {"scrolled": delta, "at": [x, y]}


def _enum_windows():
    if sys.platform != "win32":
        raise RuntimeError("window listing works only on Windows")
    user32 = ctypes.windll.user32
    windows = []

    def callback(hwnd, _lparam):
        if user32.IsWindowVisible(hwnd):
            length = user32.GetWindowTextLengthW(hwnd)
            if length > 0:
                buffer = ctypes.create_unicode_buffer(length + 1)
                user32.GetWindowTextW(hwnd, buffer, length + 1)
                windows.append((hwnd, buffer.value))
        return True

    enum_proc = ctypes.WINFUNCTYPE(
        ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p
    )(callback)
    user32.EnumWindows(enum_proc, 0)
    return windows


@mcp.tool()
def list_windows():
    """List visible top-level windows with their titles."""
    require_connected()
    return {"windows": [title for _hwnd, title in _enum_windows()]}


@mcp.tool()
def focus_window(title_part):
    """Bring the first window whose title contains title_part to front."""
    require_connected()
    if sys.platform != "win32":
        raise RuntimeError("window focusing works only on Windows")
    user32 = ctypes.windll.user32
    for hwnd, title in _enum_windows():
        if title_part.lower() in title.lower():
            user32.ShowWindow(hwnd, 9)  # SW_RESTORE
            user32.SetForegroundWindow(hwnd)
            return {"focused": title}
    raise ValueError("no visible window with %r in the title" % title_part)


def main():
    token = os.environ.get("BRIDGE_TOKEN", "")
    if not token:
        raise SystemExit(
            "BRIDGE_TOKEN is not set. Generate a long random token on "
            "this machine, set it in the environment for this session "
            "only, and never put it in chat or in a file."
        )
    app = Starlette(
        routes=[Mount("/", app=mcp.streamable_http_app())],
        middleware=[Middleware(BearerAuthMiddleware, expected_token=token)],
        # FastMCP's session manager needs its task group running;
        # without this lifespan every request fails with
        # "Task group is not initialized".
        lifespan=lambda app: mcp.session_manager.run(),
    )
    # BRIDGE_HOST defaults to localhost. For Tailscale access, set it
    # to this machine's Tailscale IP (100.x.x.x) so the port is only
    # reachable inside the tailnet, never on the LAN or internet.
    host = os.environ.get("BRIDGE_HOST", "127.0.0.1")
    uvicorn.run(app, host=host, port=8765)


if __name__ == "__main__":
    main()
