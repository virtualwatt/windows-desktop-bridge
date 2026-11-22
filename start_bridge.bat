@echo off
rem Start the Windows desktop bridge MCP server.
rem Dependencies are managed by uv (pyproject.toml + uv.lock).

cd /d "%~dp0"

rem --- Settings -------------------------------------------------------
rem BRIDGE_TOKEN must match the token entered on the Muse side
rem (Secure Vault / connector credential flow). Set it once for your
rem Windows user, e.g.:  setx BRIDGE_TOKEN "<long random token>"
rem Do not write the real token into this file.

if "%BRIDGE_TOKEN%"=="" (
    echo BRIDGE_TOKEN is not set.
    echo Generate a long random token on this machine and set it once:
    echo   setx BRIDGE_TOKEN "your-long-random-token"
    echo then open a new terminal and run this file again.
    pause
    exit /b 1
)

rem OBS Studio WebSocket settings. OBS_PROFILE is the recording
rem profile used on connect; OBS_WS_PASSWORD only if OBS auth is on.
if "%OBS_PROFILE%"=="" set OBS_PROFILE=Work
rem set OBS_WS_PASSWORD=
rem set OBS_WS_HOST=127.0.0.1
rem set OBS_WS_PORT=4455

rem --- Run ------------------------------------------------------------
uv sync
if errorlevel 1 (
    echo uv sync failed.
    pause
    exit /b 1
)

echo Starting bridge on http://127.0.0.1:8765/mcp (OBS profile: %OBS_PROFILE%)
uv run python windows_desktop_bridge.py
pause
