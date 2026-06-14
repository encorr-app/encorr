# Build debug APK and install to the first connected adb device/emulator.
$ErrorActionPreference = "Stop"

$build = Join-Path $PSScriptRoot "build-apk.ps1"
$install = Join-Path $PSScriptRoot "install-apk.ps1"

& $build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $install
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
