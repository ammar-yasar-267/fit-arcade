<#
.SYNOPSIS
    Build, install, and launch FitArcade on a connected Android device -
    no Godot editor menus, similar to Android Studio's Run button.

.PARAMETER Preset
    Export preset name from export_presets.cfg. Default: "Android"
    (the "Android Debug" preset still has a placeholder package name and
    isn't wired up - use "Android" for both debug and release CLI exports;
    debug/release is controlled by -Release, not by which preset you pick).

.PARAMETER Release
    Export a release build instead of debug. Default: debug.

.PARAMETER NoLaunch
    Skip launching the app on the device after installing.

.PARAMETER Logcat
    Stream logcat (filtered to Godot's own tag) after launching.

.PARAMETER GodotExe
    Path to the Godot editor executable. Defaults to the version currently
    in Downloads - update this (or pass -GodotExe) if you install a newer one.

.EXAMPLE
    .\deploy_android.ps1
    Debug build, install, launch.

.EXAMPLE
    .\deploy_android.ps1 -Release -Logcat
    Release build, install, launch, and stream logs.
#>
param(
    [string]$Preset = "Android",
    [switch]$Release,
    [switch]$NoLaunch,
    [switch]$Logcat,
    # The _console.exe variant that normally ships alongside this fails outright
    # (CreateProcess error 193) in this environment for reasons unrelated to this
    # script - the plain GUI-subsystem exe below works fine and still writes to
    # the inherited console when launched from an existing terminal session.
    [string]$GodotExe = "C:\Users\Sami Naveed\Downloads\Godot_4.7.2\Godot_v4.7.2-stable_win64.exe",
    [string]$PackageName = "com.fitarcade.app"
)

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $ProjectDir "build\android"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$Config = if ($Release) { "release" } else { "debug" }
$ApkPath = Join-Path $BuildDir "FitArcade-$Config.apk"

if (-not (Test-Path $GodotExe)) {
    Write-Error "Godot executable not found at '$GodotExe'. Pass -GodotExe <path> or update the default in this script."
}
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    Write-Error "adb not found on PATH. Install Android SDK platform-tools or add it to PATH."
}

Write-Host "==> Exporting '$Preset' ($Config) to $ApkPath" -ForegroundColor Cyan
Write-Host "    (close any Godot editor window with this project open first - it locks the" -ForegroundColor DarkGray
Write-Host "     GDExtension libs' hot-reload temp copies and export will silently fail to load them)" -ForegroundColor DarkGray

# Start-Process -Wait with redirected output, not "&" - this Godot build is a
# GUI-subsystem binary whose stdout isn't reliably synchronized with process exit
# when inherited via "&" (confirmed: --version printed its output after control
# had already returned to the prompt). Redirecting to real files sidesteps that
# console-attachment timing issue entirely and gives a trustworthy exit code.
$exportFlag = if ($Release) { "--export-release" } else { "--export-debug" }
$stdout = Join-Path $BuildDir "export_stdout.log"
$stderr = Join-Path $BuildDir "export_stderr.log"
# Start-Process -ArgumentList does not auto-quote elements containing spaces
# (paths under "Sami Naveed" do), so quotes are embedded manually here.
$exportArgs = @("--headless", "--path", "`"$ProjectDir`"", $exportFlag, "`"$Preset`"", "`"$ApkPath`"")
$proc = Start-Process -FilePath $GodotExe -ArgumentList $exportArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Get-Content $stdout -ErrorAction SilentlyContinue
Get-Content $stderr -ErrorAction SilentlyContinue
if ($proc.ExitCode -ne 0 -or -not (Test-Path $ApkPath)) {
    Write-Error "Godot export failed (exit code $($proc.ExitCode)) or produced no APK at $ApkPath."
}

$devices = (adb devices) -split "`n" | Select-String "\tdevice$"
if (-not $devices) {
    Write-Error "No Android device/emulator detected by adb. Run 'adb devices' to check connection/authorization."
}

Write-Host "==> Installing $ApkPath" -ForegroundColor Cyan
adb install -r $ApkPath
if ($LASTEXITCODE -ne 0) {
    Write-Error "adb install failed (exit code $LASTEXITCODE)."
}

if (-not $NoLaunch) {
    Write-Host "==> Launching $PackageName" -ForegroundColor Cyan
    adb shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
}

if ($Logcat) {
    Write-Host "==> Streaming logcat (Ctrl+C to stop)" -ForegroundColor Cyan
    adb logcat -c
    adb logcat | Select-String "Godot"
}
