# One-shot rename: Plezy -> Encorr
# - Brand strings:      Plezy -> Encorr, plezy -> encorr, PLEZY -> ENCORR
# - Bundle/app ID:      com.edde746.plezy -> app.encorr.encorr
# - Project repo:       edde746/plezy -> encorr-app/encorr (other edde746/* dependency forks are preserved)
# - Winget ID:          edde746.Plezy -> encorr-app.Encorr
# - Renames files/dirs containing "plezy" and moves Kotlin package directories.
# Idempotent: safe to re-run.

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$excludeDirs = @('.git', 'graphify-out', 'build', '.dart_tool', 'node_modules', '.gradle', 'ephemeral', 'Pods', 'DerivedData', '.fvm')
$binaryExt = @('.png', '.jpg', '.jpeg', '.webp', '.gif', '.ico', '.icns', '.ttf', '.otf', '.woff', '.woff2', '.zip', '.7z', '.dmg', '.exe', '.dll', '.so', '.a', '.jar', '.aar', '.keystore', '.jks', '.p12', '.mp4', '.bin', '.pdf', '.lockb', '.heic', '.car')

function Test-Excluded($path) {
    $rel = $path.Substring($root.Length).TrimStart('\', '/')
    foreach ($d in $excludeDirs) {
        if ($rel -split '[\\/]' -ccontains $d) { return $true }
    }
    return $false
}

# Ordered, case-sensitive replacements. Most specific first.
$replacements = @(
    @('edde746/plezy', 'encorr-app/encorr'),
    @('edde746.Plezy', 'encorr-app.Encorr'),
    @('com.edde746.plezy', 'app.encorr.encorr'),
    @('com/edde746/plezy', 'app/encorr/encorr'),
    @('Plezy', 'Encorr'),
    @('plezy', 'encorr'),
    @('PLEZY', 'ENCORR')
)

Write-Host '== Pass 1: file contents =='
$changed = 0
Get-ChildItem -Path $root -Recurse -File | ForEach-Object {
    if (Test-Excluded $_.FullName) { return }
    if ($binaryExt -contains $_.Extension.ToLower()) { return }

    # Detect BOM so we can write back with the same encoding.
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -eq 0) { return }
    $enc = [System.Text.UTF8Encoding]::new($false)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $enc = [System.Text.UTF8Encoding]::new($true)
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $enc = [System.Text.UnicodeEncoding]::new($false, $true)
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $enc = [System.Text.UnicodeEncoding]::new($true, $true)
    }

    $text = $enc.GetString($bytes)
    # Strip BOM char that GetString may include
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    if ($text.IndexOf('plezy', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return }

    $new = $text
    foreach ($r in $replacements) {
        $new = $new.Replace($r[0], $r[1])  # ordinal, case-sensitive
    }
    if ($new -cne $text) {
        [System.IO.File]::WriteAllText($_.FullName, $new, $enc)
        $script:changed++
        Write-Host "  edited: $($_.FullName.Substring($root.Length + 1))"
    }
}
Write-Host "Files edited: $changed"

Write-Host '== Pass 2: Kotlin/Java package directories =='
Get-ChildItem -Path $root -Recurse -Directory -Filter 'plezy' -ErrorAction SilentlyContinue | Where-Object {
    -not (Test-Excluded $_.FullName) -and $_.FullName -match '\\com\\edde746\\plezy$'
} | ForEach-Object {
    $srcRoot = $_.Parent.Parent.Parent.FullName    # .../kotlin or .../java
    $dest = Join-Path $srcRoot 'app\encorr\encorr'
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Get-ChildItem -Path $_.FullName | Move-Item -Destination $dest -Force
    Write-Host "  moved: $($_.FullName.Substring($root.Length + 1)) -> app\encorr\encorr"
    # Remove now-empty com/edde746 tree
    Remove-Item -Path (Join-Path $srcRoot 'com\edde746\plezy') -Force -Recurse -ErrorAction SilentlyContinue
    $edde = Join-Path $srcRoot 'com\edde746'
    if ((Test-Path $edde) -and -not (Get-ChildItem $edde)) { Remove-Item $edde -Force }
    $com = Join-Path $srcRoot 'com'
    if ((Test-Path $com) -and -not (Get-ChildItem $com)) { Remove-Item $com -Force }
}

Write-Host '== Pass 3: rename files and dirs containing plezy =='
# Deepest paths first so child renames happen before parents.
Get-ChildItem -Path $root -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match 'plezy' -and -not (Test-Excluded $_.FullName)
} | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
    $newName = $_.Name.Replace('Plezy', 'Encorr').Replace('plezy', 'encorr').Replace('PLEZY', 'ENCORR')
    if ($newName -cne $_.Name) {
        Rename-Item -Path $_.FullName -NewName $newName
        Write-Host "  renamed: $($_.Name) -> $newName"
    }
}

Write-Host '== Done =='
