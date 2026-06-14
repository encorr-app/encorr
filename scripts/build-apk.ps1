# Build debug APK with Git unzip on PATH and explicit Flutter SDK.
$ErrorActionPreference = "Stop"

$flutter = "C:\Users\NerdOne\flutter-sdk\flutter\bin\flutter.bat"
$gitUsrBin = "C:\Program Files\Git\usr\bin"

if (-not (Test-Path $flutter)) {
    Write-Error "Flutter not found at: $flutter"
    exit 1
}

if (-not (Test-Path $gitUsrBin)) {
    Write-Warning "Git usr/bin not found at: $gitUsrBin (Flutter may fail to unzip packages)"
} else {
    $env:PATH = "$gitUsrBin;$env:PATH"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    Write-Host "== flutter pub get =="
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Error "flutter pub get failed (exit $LASTEXITCODE)"
        exit $LASTEXITCODE
    }

    Write-Host "== flutter build apk --debug =="
    & $flutter build apk --debug
    if ($LASTEXITCODE -ne 0) {
        Write-Error "flutter build apk --debug failed (exit $LASTEXITCODE)"
        exit $LASTEXITCODE
    }

    $apk = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-debug.apk"
    if (Test-Path $apk) {
        Write-Host "Build succeeded: $apk"
    }
}
finally {
    Pop-Location
}
