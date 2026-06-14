# Install app-debug.apk via adb (auto-finds platform-tools).
$ErrorActionPreference = "Stop"

function Find-Adb {
    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:ANDROID_HOME\platform-tools\adb.exe",
        "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }

    if ($candidates.Count -gt 0) {
        return @($candidates)[0]
    }

    $found = Get-ChildItem -Path "$env:LOCALAPPDATA\Android" -Filter "adb.exe" -Recurse -Depth 5 -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if ($found) { return $found }

    throw "adb.exe not found. Install Android SDK Platform-Tools or set ANDROID_HOME."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$apk = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-debug.apk"

if (-not (Test-Path $apk)) {
    Write-Host "APK not found; running scripts\build-apk.ps1 ..."
    & (Join-Path $PSScriptRoot "build-apk.ps1")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if (-not (Test-Path $apk)) {
        throw "Build finished but APK still missing: $apk"
    }
}

$adb = Find-Adb
Write-Host "Using adb: $adb"

$deviceList = & $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\S' }
$serials = @($deviceList | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ -ne 'List' })

if ($serials.Count -eq 0) {
    throw "No adb devices. Start an emulator or connect a device, then retry."
}

$installArgs = @("install", "-r", $apk)
if ($serials.Count -gt 1) {
    if ($env:ANDROID_SERIAL) {
        $installArgs = @("-s", $env:ANDROID_SERIAL) + $installArgs
    } else {
        Write-Warning "Multiple devices: $($serials -join ', '). Using first: $($serials[0]). Set `$env:ANDROID_SERIAL to override."
        $installArgs = @("-s", $serials[0]) + $installArgs
    }
} elseif ($serials.Count -eq 1) {
    $installArgs = @("-s", $serials[0]) + $installArgs
}

& $adb @installArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Install succeeded."
