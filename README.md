# Windows desktop bridge

MCP server that lets Muse work in native Windows programs through
screenshots, mouse clicks and keyboard input. Built for a Windows work
computer where part of the work lives in a desktop client that the
browser cannot reach.

Status: working. Tested end-to-end on a Windows 11 machine
(3840×2160, DPI 250%): connect/disconnect with OBS recording
(video and audio verified in the recording), screenshots, clicks,
keyboard input, window listing and focus.

## Session model: connect / disconnect

Every screen, mouse and keyboard tool works **only while connected**:

- `connect(profile="")` opens the session. It switches OBS Studio to
  the given profile (or `OBS_PROFILE`, or the current OBS profile),
  makes sure the recording scene exists (full-screen monitor capture
  plus desktop audio, created through the OBS WebSocket API with
  capture devices selected), and starts recording. If OBS is
  unreachable or refuses, `connect` fails and no other tool works —
  there is no unrecorded work by accident.
- `disconnect()` stops the OBS recording, returns the recording's
  file path, and locks all tools again.
- `status()` reports whether a session is open; it works either way.
- `obs_input_info()` is a read-only diagnostic: it dumps OBS inputs
  with their settings, device property lists, volume/mute, and the
  items of every scene.

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

The recording scene is not written to disk by the installer: the
bridge creates it through the OBS WebSocket API at `connect` time
(scene named after the profile, `Monitor` capture and `Desktop Audio`
inputs with devices selected).

`start_bridge.bat` launches OBS minimized with that profile
(`--profile`, `--minimize-to-tray`) if OBS is not already running.
The bridge itself only sends commands; it does not launch OBS.

## Run

Dependencies are managed with [uv](https://docs.astral.sh/uv/):
`pyproject.toml` declares them, `uv.lock` pins exact versions.

On Windows, `install_bridge.bat` does the setup: it installs
Chocolatey if missing, then Python, uv and OBS Studio through it
(skipping whatever is already installed), configures OBS, and
finishes with `uv sync`. `start_bridge.bat` only starts the server.

Configuration lives in a local `.env` next to the script (copy
`.env.example` and fill it in; the file is git-ignored and never
committed). Real environment variables take priority over `.env`.

Manual equivalent:

```powershell
uv sync
$env:BRIDGE_TOKEN = "<long random token generated on this machine>"
$env:OBS_WS_PASSWORD = "<only if OBS auth is on>"
$env:OBS_PROFILE = "Work"
uv run python windows_desktop_bridge.py
```

The server binds to `127.0.0.1:8765` (host from `BRIDGE_HOST`),
Streamable HTTP at `POST /mcp`, and refuses to start without
`BRIDGE_TOKEN`. On the Muse side the token is entered through the
Secure Vault / connector credential flow, never in chat.

## Diagnostics

`check_bridge.bat` — run it after starting the bridge. It prints the
environment variables the bridge and its setup use (secrets masked to
first/last two characters plus length), checks that ports 8765 (bridge) and 4455 (OBS WebSocket) are
listening, and probes the MCP endpoint with curl: locally without a
token (expect 401), locally with the token (expect 200), and through
the Funnel URL with the token (expect 200).

## Smoke test locally (before any tunnel)

With OBS running and the bridge started:

1. Request without the token → `401`.
2. `tools/list` with the token → the tools above.
3. `click` before `connect` → refused with "not connected".
4. `connect` → OBS switches to the profile and starts recording.
5. Open Notepad, `screenshot`, `focus_window("Notepad")`, `click`,
   `type_text("hello")`, `screenshot` again — text is there.
6. `disconnect` → OBS stops recording; `click` is refused again.

Only after this passes: expose it (Tailscale Funnel below, or a
cloudflared tunnel) and register the connector on the Muse side.

## Tailscale Funnel

`install_tailscale.bat` installs Tailscale via Chocolatey (skipping
it if already installed), connects the machine to the tailnet
(`tailscale up --unattended`; interactive browser login by default,
or set `TAILSCALE_AUTHKEY` for unattended setup; optional
`TAILSCALE_HOSTNAME`), then enables Tailscale Funnel for port 8765
and sets `BRIDGE_HOST=127.0.0.1`. Tailscale SSH stays off.

Why Funnel: Muse's credential substitution does not happen on the
tailnet proxy path, so the bridge is reached over public HTTPS at
`https://<machine>.<tailnet>.ts.net/mcp` instead, with the Bearer
token as the protection. The bridge binds the host from
`BRIDGE_HOST` (default `127.0.0.1`); Funnel forwards to
`127.0.0.1:8765`, so keep the bind on localhost when Funnel is used.
`start_bridge.bat` falls back to the Tailscale IP only when
`BRIDGE_HOST` is unset, which suits tailnet-only local tests.

## Limits

- Single monitor assumed for coordinates.
- Keyboard input is English-layout text via `pyautogui.write()`.
- No shell, no file access, no process control — by design.
- pyautogui FAILSAFE stays on: mouse to a screen corner aborts.
