@echo off
rem Installer for the Windows desktop bridge.
rem Installs Chocolatey (if missing), then Python, uv and OBS Studio
rem through it (skipping whatever is already installed), and finally
rem syncs the project dependencies with uv.
rem Needs administrator rights; relaunches itself elevated if needed.

cd /d "%~dp0"

rem --- Require administrator ------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

rem --- Chocolatey -------------------------------------------------------
where choco >nul 2>&1
if %errorlevel% equ 0 (
    echo Chocolatey is already installed.
) else (
    echo Installing Chocolatey...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    if errorlevel 1 (
        echo Chocolatey installation failed.
        pause
        exit /b 1
    )
    call refreshenv.cmd
)

rem --- Python -------------------------------------------------------------
where python >nul 2>&1
if %errorlevel% equ 0 (
    echo Python is already installed.
) else (
    echo Installing Python via Chocolatey...
    choco install python -y
    if errorlevel 1 (
        echo Python installation failed.
        pause
        exit /b 1
    )
    call refreshenv.cmd
)

rem --- uv -------------------------------------------------------------------
where uv >nul 2>&1
if %errorlevel% equ 0 (
    echo uv is already installed.
) else (
    echo Installing uv via Chocolatey...
    choco install uv -y
    if errorlevel 1 (
        echo uv installation failed.
        pause
        exit /b 1
    )
    call refreshenv.cmd
)

rem --- OBS Studio -----------------------------------------------------------
if exist "%ProgramFiles%\obs-studio\bin\64bit\obs64.exe" (
    echo OBS Studio is already installed.
) else (
    echo Installing OBS Studio via Chocolatey...
    choco install obs-studio -y
    if errorlevel 1 (
        echo OBS Studio installation failed.
        pause
        exit /b 1
    )
)

rem --- Project dependencies ---------------------------------------------------
echo Syncing project dependencies with uv...
uv sync
if errorlevel 1 (
    echo uv sync failed.
    pause
    exit /b 1
)

rem --- OBS configuration ------------------------------------------------------
rem Enables the WebSocket server and creates the recording profile and
rem scene collection (full screen + system audio) if they do not exist.
rem OBS must be closed for this; configure_obs.ps1 checks that.
if "%OBS_PROFILE%"=="" set OBS_PROFILE=Work
echo Configuring OBS (profile: %OBS_PROFILE%)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0configure_obs.ps1" -ProfileName "%OBS_PROFILE%"
if errorlevel 1 (
    echo OBS configuration failed.
    pause
    exit /b 1
)

echo.
echo Installation complete. Next steps:
echo   1. Set the bridge token once:  setx BRIDGE_TOKEN "your-long-random-token"
echo   2. Start the bridge with start_bridge.bat (it launches OBS with the profile)
pause
