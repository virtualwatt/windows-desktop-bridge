@echo off
rem Diagnostics for the windows-desktop-bridge setup.
rem Run after start_bridge.bat. Prints the environment variables the
rem bridge and its setup use, checks the local ports, and probes the
rem MCP endpoint with curl (locally and through the Funnel URL).
rem Secrets are shown masked: first and last two characters plus length.

setlocal EnableDelayedExpansion

rem Load .env beside this file (real environment variables win).
if exist "%~dp0.env" (
    for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%~dp0.env") do (
        if not defined %%a set "%%a=%%b"
    )
)

echo === Environment ===
call :show BRIDGE_HOST
call :show OBS_WS_HOST
call :show OBS_WS_PORT
call :show OBS_PROFILE
call :show TAILSCALE_HOSTNAME
call :show_secret BRIDGE_TOKEN
call :show_secret OBS_WS_PASSWORD
call :show_secret TAILSCALE_AUTHKEY

echo.
echo === Listening ports ===
netstat -ano | findstr ":8765 " | findstr LISTENING
if errorlevel 1 echo port 8765: NOT listening (bridge not running?)
netstat -ano | findstr ":4455 " | findstr LISTENING
if errorlevel 1 echo port 4455: NOT listening (OBS WebSocket off or OBS not running?)

echo.
echo === Local MCP probe (127.0.0.1:8765) ===
if not defined BRIDGE_TOKEN (
    echo BRIDGE_TOKEN is not set in this terminal - skipping probes.
    echo Open a NEW terminal after setx, or set it here first.
    goto :funnel
)
curl -s -o nul -w "without token: HTTP %%{http_code} (expect 401)\n" -X POST http://127.0.0.1:8765/mcp -H "Content-Type: application/json" -d "{}"
curl -s -o nul -w "with token:    HTTP %%{http_code} (expect 200)\n" -X POST http://127.0.0.1:8765/mcp -H "Authorization: Bearer %BRIDGE_TOKEN%" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"check\",\"version\":\"1\"}}}"

:funnel
echo.
echo === Funnel probe ===
set "DNSNAME="
powershell -NoProfile -Command "try { (tailscale status --json | ConvertFrom-Json).Self.DNSName.TrimEnd('.') } catch { '' }" > "%TEMP%\bridge-dnsname.txt" 2>nul
if exist "%TEMP%\bridge-dnsname.txt" set /p DNSNAME=<"%TEMP%\bridge-dnsname.txt"
if not defined DNSNAME (
    echo Could not get the MagicDNS name - Tailscale not up? Skipping.
    goto :done
)
echo Funnel URL: https://%DNSNAME%/mcp
if defined BRIDGE_TOKEN (
    curl -s -o nul -w "with token:    HTTP %%{http_code} - expect 200\n" --ssl-no-revoke -X POST https://%DNSNAME%/mcp -H "Authorization: Bearer %BRIDGE_TOKEN%" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"check\",\"version\":\"1\"}}}"
) else (
    echo BRIDGE_TOKEN not set - skipping the Funnel probe too.
)

:done
echo.
echo Done.
pause
exit /b 0

:show
if defined %~1 (
    echo %~1 = !%~1!
) else (
    echo %~1 = ^(not set^)
)
exit /b 0

:show_secret
if defined %~1 (
    set "V=!%~1!"
    call :strlen LEN V
    echo %~1 = !V:~0,2!...!V:~-2! ^(length !LEN!^)
) else (
    echo %~1 = ^(not set^)
)
exit /b 0

:strlen
set "S=!%~2!"
set /a N=0
:strlen_loop
if defined S (
    set "S=!S:~1!"
    set /a N+=1
    goto :strlen_loop
)
set "%~1=%N%"
exit /b 0
