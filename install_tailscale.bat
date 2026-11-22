@echo off
rem Install and configure Tailscale (private network access to this
rem machine, so the bridge does not need a public tunnel).
rem Installs Chocolatey first if missing, then Tailscale via choco
rem (skipped if already installed), then connects to the tailnet.
rem Needs administrator rights; relaunches itself elevated if needed.
rem
rem Login: by default "tailscale up" opens the browser for an
rem interactive login. For unattended setup, set TAILSCALE_AUTHKEY
rem (a Tailscale auth key) in the environment before running.
rem Optional: TAILSCALE_HOSTNAME sets this machine's tailnet name.
rem Tailscale SSH is NOT enabled; Tailscale is only the transport.

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

rem --- Tailscale --------------------------------------------------------
set TAILSCALE_EXE=
where tailscale >nul 2>&1
if %errorlevel% equ 0 (
    for /f "delims=" %%i in ('where tailscale') do set TAILSCALE_EXE=%%i
)
if "%TAILSCALE_EXE%"=="" if exist "%ProgramFiles%\Tailscale\tailscale.exe" set TAILSCALE_EXE=%ProgramFiles%\Tailscale\tailscale.exe

if not "%TAILSCALE_EXE%"=="" (
    echo Tailscale is already installed.
) else (
    echo Installing Tailscale via Chocolatey...
    choco install tailscale -y
    if errorlevel 1 (
        echo Tailscale installation failed.
        pause
        exit /b 1
    )
    call refreshenv.cmd
    for /f "delims=" %%i in ('where tailscale') do set TAILSCALE_EXE=%%i
    if "%TAILSCALE_EXE%"=="" set TAILSCALE_EXE=%ProgramFiles%\Tailscale\tailscale.exe
)

rem --- Connect ----------------------------------------------------------
set UP_ARGS=up --unattended
if not "%TAILSCALE_AUTHKEY%"=="" set UP_ARGS=%UP_ARGS% --authkey=%TAILSCALE_AUTHKEY%
if not "%TAILSCALE_HOSTNAME%"=="" set UP_ARGS=%UP_ARGS% --hostname=%TAILSCALE_HOSTNAME%

echo Connecting to the tailnet...
if "%TAILSCALE_AUTHKEY%"=="" echo A browser window will open for login - sign in to the tailnet there.
"%TAILSCALE_EXE%" %UP_ARGS%
if errorlevel 1 (
    echo tailscale up failed.
    pause
    exit /b 1
)

echo.
echo Tailscale status:
"%TAILSCALE_EXE%" status
echo.
echo This machine's Tailscale IP:
"%TAILSCALE_EXE%" ip -4
pause
