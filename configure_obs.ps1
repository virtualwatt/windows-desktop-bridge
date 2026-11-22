# Configure OBS Studio for the Windows desktop bridge:
#   1. WebSocket server enabled (plugin_config/obs-websocket/config.json)
#   2. A recording profile (basic/profiles/<name>/basic.ini)
#   3. A scene collection with full-screen capture + system audio
#      (basic/scenes/<name>.json)
# Existing files are checked first: the WebSocket config only gets
# server_enabled/server_port ensured (existing password kept), the
# scene collection is left alone, and the profile gets its resolution
# corrected if it no longer matches the monitor (physical pixels,
# DPI-aware; screens larger than Full HD prompt for full vs
# downscaled recording). OBS must be closed while this runs; OBS
# reads these files at startup.

param(
    [string]$ProfileName = "Work",
    [int]$Port = 4455,
    [string]$Password = ""
)

$ErrorActionPreference = "Stop"

if (Get-Process obs64 -ErrorAction SilentlyContinue) {
    Write-Host "OBS is running. Close OBS first, then run the installer again."
    exit 1
}

$obsConfig = Join-Path $env:APPDATA "obs-studio"

# --- 1. WebSocket server config ----------------------------------------
$wsDir = Join-Path $obsConfig "plugin_config\obs-websocket"
$wsFile = Join-Path $wsDir "config.json"
New-Item -ItemType Directory -Force -Path $wsDir | Out-Null

if (Test-Path $wsFile) {
    $ws = Get-Content $wsFile -Raw | ConvertFrom-Json
    $ws.server_enabled = $true
    $ws.server_port = $Port
    if ($Password) {
        $ws.server_password = $Password
        $ws.auth_required = $true
    }
    Write-Host "WebSocket config exists: server enabled on port $Port (existing settings kept)."
} else {
    $ws = [ordered]@{
        alerts_enabled  = $true
        auth_required   = [bool]$Password
        first_load      = $false
        server_enabled  = $true
        server_password = $Password
        server_port     = $Port
    }
    Write-Host "WebSocket config created: server enabled on port $Port."
}
$ws | ConvertTo-Json | Set-Content -Encoding UTF8 $wsFile

# --- 2. Recording profile ------------------------------------------------
$profileDir = Join-Path $obsConfig "basic\profiles\$ProfileName"
$profileFile = Join-Path $profileDir "basic.ini"

# Physical resolution of the primary screen. Screen.Bounds returns
# DPI-scaled (logical) pixels, so ask user32 with DPI awareness on.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class NativeScreen {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
}
"@
[NativeScreen]::SetProcessDPIAware() | Out-Null
$screenWidth = [NativeScreen]::GetSystemMetrics(0)   # SM_CXSCREEN
$screenHeight = [NativeScreen]::GetSystemMetrics(1)  # SM_CYSCREEN
if ($screenWidth -le 0 -or $screenHeight -le 0) {
    $video = Get-CimInstance Win32_VideoController |
        Where-Object { $_.CurrentHorizontalResolution } | Select-Object -First 1
    $screenWidth = [int]$video.CurrentHorizontalResolution
    $screenHeight = [int]$video.CurrentVerticalResolution
}
Write-Host "Primary screen resolution: ${screenWidth}x${screenHeight}"

# Recording (output) resolution: full native, or downscaled to fit
# Full HD when the screen is bigger than 1920x1080 (asked on console).
$outputWidth = $screenWidth
$outputHeight = $screenHeight
if ($screenWidth -gt 1920 -or $screenHeight -gt 1080) {
    $scale = [Math]::Min(1920 / $screenWidth, 1080 / $screenHeight)
    $fhdWidth = [int][Math]::Round($screenWidth * $scale / 2) * 2
    $fhdHeight = [int][Math]::Round($screenHeight * $scale / 2) * 2
    Write-Host "Screen is larger than Full HD. Recording resolution:"
    Write-Host "  1) Full native ${screenWidth}x${screenHeight}"
    Write-Host "  2) Downscale to ${fhdWidth}x${fhdHeight} (Full HD)"
    $choice = Read-Host "Choose 1 or 2"
    if ($choice -eq "2") {
        $outputWidth = $fhdWidth
        $outputHeight = $fhdHeight
    }
}
Write-Host "Recording resolution: ${outputWidth}x${outputHeight}"

if (Test-Path $profileFile) {
    # Fix our own profile if its resolution no longer matches the
    # monitor / chosen recording resolution; keep everything else.
    $ini = Get-Content $profileFile -Raw
    $fixed = $ini `
        -replace "(?m)^BaseCX=\d+", "BaseCX=$screenWidth" `
        -replace "(?m)^BaseCY=\d+", "BaseCY=$screenHeight" `
        -replace "(?m)^OutputCX=\d+", "OutputCX=$outputWidth" `
        -replace "(?m)^OutputCY=\d+", "OutputCY=$outputHeight"
    if ($fixed -ne $ini) {
        Set-Content -Encoding UTF8 $profileFile $fixed
        Write-Host "Profile '$ProfileName' existed: resolution corrected to base ${screenWidth}x${screenHeight}, output ${outputWidth}x${outputHeight}."
    } else {
        Write-Host "Profile '$ProfileName' already exists and resolution matches, left as is."
    }
} else {
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    @"
[General]
Name=$ProfileName

[Video]
BaseCX=$screenWidth
BaseCY=$screenHeight
OutputCX=$outputWidth
OutputCY=$outputHeight
FPSType=0
FPSCommon=10

[Output]
Mode=Simple

[SimpleOutput]
RecFormat=mkv
RecQuality=Small
"@ | Set-Content -Encoding UTF8 $profileFile
    Write-Host "Profile '$ProfileName' created (base ${screenWidth}x${screenHeight}, output ${outputWidth}x${outputHeight}, 10 fps)."
}

# --- 3. Scene collection: full screen + system audio ---------------------
$scenesDir = Join-Path $obsConfig "basic\scenes"
$sceneFile = Join-Path $scenesDir "$ProfileName.json"
New-Item -ItemType Directory -Force -Path $scenesDir | Out-Null

if (Test-Path $sceneFile) {
    Write-Host "Scene collection '$ProfileName' already exists, left as is."
} else {
    $displayUuid = [guid]::NewGuid().ToString()
    $audioUuid = [guid]::NewGuid().ToString()
    $sceneUuid = [guid]::NewGuid().ToString()

    $collection = [ordered]@{
        current_scene         = "Scene"
        current_program_scene = "Scene"
        scene_order           = @(@{ name = "Scene" })
        name                  = $ProfileName
        sources               = @(
            [ordered]@{
                prev_ver     = 503316480
                name         = "Display Capture"
                uuid         = $displayUuid
                id           = "monitor_capture"
                versioned_id = "monitor_capture"
                settings     = @{ monitor = 0 }
                mixers       = 255
                sync         = 0
                flags        = 0
                volume       = 1.0
                balance      = 0.5
                enabled      = $true
                muted        = $false
                "push-to-mute"       = $false
                "push-to-mute-delay" = 0
                "push-to-talk"       = $false
                "push-to-talk-delay" = 0
                hotkeys      = @{}
                deinterlace_mode        = 0
                deinterlace_field_order = 0
                monitoring_type = 0
                private_settings = @{}
            },
            [ordered]@{
                prev_ver     = 503316480
                name         = "Desktop Audio"
                uuid         = $audioUuid
                id           = "wasapi_output_capture"
                versioned_id = "wasapi_output_capture"
                settings     = @{ device_id = "default" }
                mixers       = 255
                sync         = 0
                flags        = 0
                volume       = 1.0
                balance      = 0.5
                enabled      = $true
                muted        = $false
                "push-to-mute"       = $false
                "push-to-mute-delay" = 0
                "push-to-talk"       = $false
                "push-to-talk-delay" = 0
                hotkeys      = @{}
                deinterlace_mode        = 0
                deinterlace_field_order = 0
                monitoring_type = 0
                private_settings = @{}
            },
            [ordered]@{
                prev_ver     = 503316480
                name         = "Scene"
                uuid         = $sceneUuid
                id           = "scene"
                versioned_id = "scene"
                settings     = [ordered]@{
                    id_counter  = 3
                    custom_size = $false
                    items       = @(
                        [ordered]@{
                            name        = "Display Capture"
                            source_uuid = $displayUuid
                            visible     = $true
                            locked      = $false
                            rot         = 0.0
                            pos         = @{ x = 0.0; y = 0.0 }
                            scale       = @{ x = 1.0; y = 1.0 }
                            align       = 5
                            bounds_type = 0
                            bounds_align = 0
                            bounds      = @{ x = 0.0; y = 0.0 }
                            crop_left   = 0
                            crop_top    = 0
                            crop_right  = 0
                            crop_bottom = 0
                            id          = 1
                            group_item_backup = $false
                            pos_rel     = @{ x = 0.0; y = 0.0 }
                            scale_rel   = @{ x = 1.0; y = 1.0 }
                            bounds_rel  = @{ x = 0.0; y = 0.0 }
                            scale_filter = "disable"
                            blend_method = "default"
                            blend_type   = "normal"
                            show_transition = @{ duration = 0 }
                            hide_transition = @{ duration = 0 }
                            private_settings = @{}
                        },
                        [ordered]@{
                            name        = "Desktop Audio"
                            source_uuid = $audioUuid
                            visible     = $true
                            locked      = $false
                            rot         = 0.0
                            pos         = @{ x = 0.0; y = 0.0 }
                            scale       = @{ x = 1.0; y = 1.0 }
                            align       = 5
                            bounds_type = 0
                            bounds_align = 0
                            bounds      = @{ x = 0.0; y = 0.0 }
                            crop_left   = 0
                            crop_top    = 0
                            crop_right  = 0
                            crop_bottom = 0
                            id          = 2
                            group_item_backup = $false
                            pos_rel     = @{ x = 0.0; y = 0.0 }
                            scale_rel   = @{ x = 1.0; y = 1.0 }
                            bounds_rel  = @{ x = 0.0; y = 0.0 }
                            scale_filter = "disable"
                            blend_method = "default"
                            blend_type   = "normal"
                            show_transition = @{ duration = 0 }
                            hide_transition = @{ duration = 0 }
                            private_settings = @{}
                        }
                    )
                }
                mixers       = 0
                sync         = 0
                flags        = 0
                volume       = 1.0
                balance      = 0.5
                enabled      = $true
                muted        = $false
                "push-to-mute"       = $false
                "push-to-mute-delay" = 0
                "push-to-talk"       = $false
                "push-to-talk-delay" = 0
                hotkeys      = @{}
                deinterlace_mode        = 0
                deinterlace_field_order = 0
                monitoring_type = 0
                private_settings = @{}
            }
        )
        groups                = @()
        transitions           = @()
        transition_duration   = 300
        current_transition    = "Fade"
    }

    $collection | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $sceneFile
    Write-Host "Scene collection '$ProfileName' created (full screen + system audio)."
}

Write-Host "OBS configuration done."
