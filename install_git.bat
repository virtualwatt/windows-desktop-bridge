@echo off
rem Install Git (needed to clone and update this repository).
rem Installs Chocolatey first if missing, then Git via choco
rem (skipped if already installed).
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

rem --- Git --------------------------------------------------------------
set GIT_EXE=
where git >nul 2>&1
if %errorlevel% equ 0 (
    for /f "delims=" %%i in ('where git') do set GIT_EXE=%%i
)
if "%GIT_EXE%"=="" if exist "%ProgramFiles%\Git\cmd\git.exe" set GIT_EXE=%ProgramFiles%\Git\cmd\git.exe

if not "%GIT_EXE%"=="" (
    echo Git is already installed.
) else (
    echo Installing Git via Chocolatey...
    choco install git -y
    if errorlevel 1 (
        echo Git installation failed.
        pause
        exit /b 1
    )
    call refreshenv.cmd
    for /f "delims=" %%i in ('where git') do set GIT_EXE=%%i
    if "%GIT_EXE%"=="" set GIT_EXE=%ProgramFiles%\Git\cmd\git.exe
)

echo.
"%GIT_EXE%" --version
pause
