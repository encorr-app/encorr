# Run Flutter using the SDK path this project expects (not on global PATH).
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs
)

$ErrorActionPreference = "Stop"

$flutter = "C:\Users\NerdOne\flutter-sdk\flutter\bin\flutter.bat"
$gitUsrBin = "C:\Program Files\Git\usr\bin"

if (-not (Test-Path $flutter)) {
    throw "Flutter not found at: $flutter`nInstall Flutter or update the path in scripts/flutter.ps1"
}

$env:PATH = "$gitUsrBin;$env:PATH"

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    & $flutter @FlutterArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
