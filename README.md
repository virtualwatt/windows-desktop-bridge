# Windows desktop bridge

MCP server that lets Muse work in native Windows programs through
screenshots, mouse clicks and keyboard input. Built for a Windows work
computer where part of the work lives in a desktop client that the
browser cannot reach.

Status: skeleton, not yet run on Windows. Verified on the authoring
machine: syntax (`py_compile`), bearer-token check, connect/disconnect
gating and the OBS WebSocket command sequence against a fake socket.
First real test happens on the target machine (smoke plan below).

## Session model: connect / disconnect

Every screen, mouse and keyboard tool works **only while connected**:

- `connect(profile="")` opens the session. It switches OBS Studio to
  the given profile (or `OBS_PROFILE`, or the current OBS profile) and
  starts recording. If OBS is unreachable or refuses, `connect` fails
  and no other tool works — there is no unrecorded work by accident.
- `disconnect()` stops the OBS recording and locks all tools again.
- `status()` reports whether a session is open; it works either way.

Tools: `screenshot`, `click`, `double_click`, `type_text`, `key`,
`scroll`, `list_windows`, `focus_window`.

## OBS Studio setup (on the Windows machine)

`install_bridge.bat` runs `configure_obs.ps1`, which does this without
manual clicks (OBS must be closed while it runs):

1. Enables the WebSocket server in
   `%APPDATA%\obs-studio\plugin_config\obs-websocket\config.json`
   (port 4455; an existing password is kept).
2. Creates the recording profile (`basic\profiles\<name>\basic.ini`)
   if it does not exist yet; on re-runs it corrects the profile's
   resolution if it no longer matches the monitor (physical pixels,
   DPI-aware). Screens larger than Full HD prompt on the console:
   record full native resolution or downscale to Full HD.
3. Creates a scene collection (`basic\scenes\<name>.json`) with
   full-screen capture + system audio if it does not exist yet.

`start_bridge.bat` launches OBS minimized with that profile and scene
collection (`--profile`, `--collection`, `--minimize-to-tray`) if OBS
is not already running. The bridge itself only sends commands; it
does not launch OBS.

## Run

Dependencies are managed with [uv](https://docs.astral.sh/uv/):
`pyproject.toml` declares them, `uv.lock` pins exact versions.

On Windows, `install_bridge.bat` does the setup: it installs
Chocolatey if missing, then Python, uv and OBS Studio through it
(skipping whatever is already installed), and finishes with `uv sync`.
`start_bridge.bat` only starts the server.

Manual equivalent:

```powershell
uv sync
$env:BRIDGE_TOKEN = "<long random token generated on this machine>"
$env:OBS_WS_PASSWORD = "<only if OBS auth is on>"
$env:OBS_PROFILE = "Work"
uv run python windows_desktop_bridge.py
```

The server binds to `127.0.0.1:8765`, Streamable HTTP at `POST /mcp`,
and refuses to start without `BRIDGE_TOKEN`. The token never goes in
chat or in a file; on the Muse side it is entered through the Secure
Vault / connector credential flow.

## Smoke test locally (before any tunnel)

With OBS running and the bridge started:

1. Request without the token → `401`.
2. `tools/list` with the token → the tools above.
3. `click` before `connect` → refused with "not connected".
4. `connect` → OBS switches to the profile and starts recording.
5. Open Notepad, `screenshot`, `focus_window("Notepad")`, `click`,
   `type_text("hello")`, `screenshot` again — text is there.
6. `disconnect` → OBS stops recording; `click` is refused again.

Only after this passes: expose it with a manually started cloudflared
tunnel and register the connector on the Muse side.

## Tailscale (alternative to a public tunnel)

`install_tailscale.bat` installs Tailscale via Chocolatey (skipping
it if already installed) and connects the machine to the tailnet
(`tailscale up --unattended`; interactive browser login by default,
or set `TAILSCALE_AUTHKEY` for unattended setup; optional
`TAILSCALE_HOSTNAME`). Tailscale SSH stays off — Tailscale is only
the transport. The bridge binds the host from `BRIDGE_HOST`
(default `127.0.0.1`); `start_bridge.bat` sets it to this machine's
Tailscale IP when Tailscale is up, so the port is reachable only
inside the tailnet. Muse then connects to
`http://<tailscale-ip>:8765/mcp` from inside the same tailnet.

## Limits of this skeleton

- Not yet run on Windows: pyautogui/mss paths are written for it but
  untested on the target machine.
- Single monitor assumed for coordinates.
- Keyboard input is English-layout text via `pyautogui.write()`.
- No shell, no file access, no process control — by design.
- pyautogui FAILSAFE stays on: mouse to a screen corner aborts.
