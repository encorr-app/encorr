#Requires -Version 5.1
<#
.SYNOPSIS
  Full Plezy -> Encorr rebrand for the Flutter client fork.

.DESCRIPTION
  Idempotent one-shot script. Safe to re-run.

  Prerequisites (must exist before running):
    assets/encorr_logo.png  — ticket mark on black (in-app branding + splash)
    assets/encorr_icon.png  — glass squircle (home-screen / launcher icon)

  Passes:
    0  Preflight — verify logo assets exist
    1  Asset-path and splash widget fixes
    2  Brand strings, bundle IDs, repo URLs
    3  pubspec.yaml name, description, asset list
    4  Kotlin/Java package directory moves
    5  Rename files/dirs still containing "plezy"
    6  Android launcher mipmaps from encorr_icon.png
    7  Android native splash drawable from encorr_logo.png
    8  Linux packaging icon tree
    9  Website logo copy
   10  Update generate_android_icons.sh reference
   11  Remove legacy Plezy brand assets (unless -KeepOldAssets)

  Preserved: edde746/* dependency fork URLs (plus_plugins, libmpv-android, etc.)

.PARAMETER KeepOldAssets
  Keep legacy assets/plezy*.png|svg after rebrand.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\rebrand-to-encorr.ps1
#>

[CmdletBinding()]
param(
    [switch]$KeepOldAssets
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$assetsDir = Join-Path $root 'assets'
$logoSrc = Join-Path $assetsDir 'encorr_logo.png'
$iconSrc = Join-Path $assetsDir 'encorr_icon.png'
$selfNames = @('rebrand-to-encorr.ps1', 'rename-to-encorr.ps1')

$excludeDirs = @(
    '.git', 'graphify-out', 'build', '.dart_tool', 'node_modules', '.gradle',
    'ephemeral', 'Pods', 'DerivedData', '.fvm', 'agent-tools'
)
$binaryExt = @(
    '.png', '.jpg', '.jpeg', '.webp', '.gif', '.ico', '.icns', '.ttf', '.otf',
    '.woff', '.woff2', '.zip', '.7z', '.dmg', '.exe', '.dll', '.so', '.a',
    '.jar', '.aar', '.keystore', '.jks', '.p12', '.mp4', '.bin', '.pdf',
    '.lockb', '.heic', '.car', '.db', '.dill'
)

function Test-Excluded([string]$path) {
    $rel = $path.Substring($root.Length).TrimStart('\', '/')
    foreach ($d in $excludeDirs) {
        if ($rel -split '[\\/]' -ccontains $d) { return $true }
    }
    return $false
}

function Test-SelfFile([System.IO.FileInfo]$file) {
    return $selfNames -ccontains $file.Name
}

function Get-FileEncoding([byte[]]$bytes) {
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.UTF8Encoding]::new($true)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.UnicodeEncoding]::new($false, $true)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [System.Text.UnicodeEncoding]::new($true, $true)
    }
    return [System.Text.UTF8Encoding]::new($false)
}

function Read-TextFile([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -eq 0) { return $null, $null }
    $enc = Get-FileEncoding $bytes
    $text = $enc.GetString($bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return $text, $enc
}

function Write-TextFile([string]$path, [string]$text, [System.Text.Encoding]$enc) {
    [System.IO.File]::WriteAllText($path, $text, $enc)
}

function Apply-Replacements([string]$text, [array]$rules) {
    $new = $text
    foreach ($r in $rules) {
        $new = $new.Replace($r[0], $r[1])
    }
    return $new
}

function Edit-TextFiles([array]$rules, [string]$label) {
    $edited = 0
    Get-ChildItem -Path $root -Recurse -File | ForEach-Object {
        if (Test-Excluded $_.FullName) { return }
        if (Test-SelfFile $_) { return }
        if ($binaryExt -contains $_.Extension.ToLower()) { return }

        $text, $enc = Read-TextFile $_.FullName
        if ($null -eq $text) { return }

        $matched = $false
        foreach ($r in $rules) {
            if ($text.Contains($r[0])) { $matched = $true; break }
        }
        if (-not $matched) { return }

        $new = Apply-Replacements $text $rules
        if ($new -cne $text) {
            Write-TextFile $_.FullName $new $enc
            $edited++
            Write-Host "  edited: $($_.FullName.Substring($root.Length + 1))"
        }
    }
    Write-Host "$label files edited: $edited"
}

function Resize-Png([string]$sourcePath, [string]$destPath, [int]$size) {
    Add-Type -AssemblyName System.Drawing
    $src = [System.Drawing.Image]::FromFile($sourcePath)
    try {
        $bmp = New-Object System.Drawing.Bitmap $size, $size
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.DrawImage($src, 0, 0, $size, $size)
        } finally { $g.Dispose() }
        $dir = Split-Path $destPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $src.Dispose()
    }
}

function Compose-TvBanner([string]$iconPath, [string]$destPath, [int]$width, [int]$height) {
    Add-Type -AssemblyName System.Drawing
    $src = [System.Drawing.Image]::FromFile($iconPath)
    try {
        $bmp = New-Object System.Drawing.Bitmap $width, $height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $bg = [System.Drawing.Color]::FromArgb(255, 18, 16, 26)
            $g.Clear($bg)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

            # TV banners are 16:9 — fill most of the height and anchor left like
            # typical leanback rows (Plex/Jellyfin), not a tiny centered square.
            $padY = [int]($height * 0.06)
            $padX = [int]($height * 0.05)
            $targetH = $height - (2 * $padY)
            $scale = $targetH / $src.Height
            $targetW = [int][Math]::Round($src.Width * $scale)
            $targetH = [int][Math]::Round($src.Height * $scale)

            # Keep the mark inside the left ~45% so it never crowds the row label.
            $maxW = [int]($width * 0.44)
            if ($targetW -gt $maxW) {
                $scale = $maxW / $src.Width
                $targetW = [int][Math]::Round($src.Width * $scale)
                $targetH = [int][Math]::Round($src.Height * $scale)
            }

            $x = $padX
            $y = [int](($height - $targetH) / 2)
            $g.DrawImage($src, $x, $y, $targetW, $targetH)

            # Soft vignette on the right so the tile feels intentional on wide rows.
            $vignette = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                [System.Drawing.Rectangle]::new([int]($width * 0.55), 0, [int]($width * 0.45), $height),
                [System.Drawing.Color]::FromArgb(0, $bg),
                [System.Drawing.Color]::FromArgb(180, $bg),
                [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal
            )
            try { $g.FillRectangle($vignette, [int]($width * 0.55), 0, [int]($width * 0.45), $height) }
            finally { $vignette.Dispose() }
        } finally { $g.Dispose() }
        $dir = Split-Path $destPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    } finally {
        $src.Dispose()
    }
}

function Resize-TvBannerCover([string]$sourcePath, [string]$destPath, [int]$width, [int]$height) {
    Add-Type -AssemblyName System.Drawing
    $src = [System.Drawing.Image]::FromFile($sourcePath)
    try {
        $bmp = New-Object System.Drawing.Bitmap $width, $height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $scale = [Math]::Max($width / $src.Width, $height / $src.Height)
            $drawW = [int][Math]::Round($src.Width * $scale)
            $drawH = [int][Math]::Round($src.Height * $scale)
            $x = [int](($width - $drawW) / 2)
            $y = [int](($height - $drawH) / 2)
            $g.DrawImage($src, $x, $y, $drawW, $drawH)
        } finally { $g.Dispose() }
        $dir = Split-Path $destPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    } finally {
        $src.Dispose()
    }
}

# Back-compat alias used by older script sections.
function Resize-TvBanner([string]$sourcePath, [string]$destPath, [int]$width, [int]$height) {
    Compose-TvBanner $sourcePath $destPath $width $height
}

function Resize-PngFit([string]$sourcePath, [string]$destPath, [int]$maxSize) {
    Add-Type -AssemblyName System.Drawing
    $src = [System.Drawing.Image]::FromFile($sourcePath)
    try {
        $scale = [Math]::Min($maxSize / $src.Width, $maxSize / $src.Height)
        $w = [int][Math]::Round($src.Width * $scale)
        $h = [int][Math]::Round($src.Height * $scale)
        $bmp = New-Object System.Drawing.Bitmap $w, $h
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.DrawImage($src, 0, 0, $w, $h)
        } finally { $g.Dispose() }
        $dir = Split-Path $destPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $src.Dispose()
    }
}

# --- Pass 0 -----------------------------------------------------------------

Write-Host '== Pass 0: preflight =='
foreach ($required in @($logoSrc, $iconSrc)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing required asset: $required`nPlace encorr_logo.png and encorr_icon.png in assets/ before running."
    }
}
Write-Host "  encorr_logo.png: $((Get-Item $logoSrc).Length) bytes"
Write-Host "  encorr_icon.png: $((Get-Item $iconSrc).Length) bytes"

# --- Pass 1: asset paths (before generic plezy rename) ----------------------

Write-Host '== Pass 1: asset paths and splash widget =='
$assetRules = @(
    @("Center(child: SvgPicture.asset('assets/plezy_adaptive_foreground.svg', width: 288, height: 288))",
      "Center(child: Image.asset('assets/encorr_logo.png', width: 288, height: 288, fit: BoxFit.contain))"),
    @("SvgPicture.asset('assets/plezy_adaptive_foreground.svg'", "Image.asset('assets/encorr_logo.png'"),
    @("Image.asset('assets/plezy.png'", "Image.asset('assets/encorr_logo.png'"),
    @('assets/plezy_adaptive_foreground.svg', 'assets/encorr_logo.png'),
    @('assets/plezy.png', 'assets/encorr_logo.png'),
    @('assets/plezy.svg', 'assets/encorr_icon.png'),
    @('alt="Plezy Logo"', 'alt="Encorr Logo"')
)
Edit-TextFiles $assetRules 'Asset-path'

# --- Pass 2: generic rebrand ------------------------------------------------

Write-Host '== Pass 2: brand strings, bundle IDs, repo URLs =='
$brandRules = @(
    @('0.4.1-plezy.1', '<<<ASS_CORE_VERSION>>>'),
    @('https://bugs.plezy.app', 'https://bugs.encorr.app'),
    @('bugs.plezy.app', 'bugs.encorr.app'),
    @('https://plezy.app', 'https://encorr.app'),
    @('plezy.app', 'encorr.app'),
    @('edde746/plezy', 'encorr-app/encorr'),
    @('edde746.Plezy', 'encorr-app.Encorr'),
    @('com.edde746.plezy', 'app.encorr.encorr'),
    @('com/edde746/plezy', 'app/encorr/encorr'),
    @('android:scheme="plezy"', 'android:scheme="encorr"'),
    @('Plezy-Seerr fork additions', 'Encorr fork additions'),
    @('Plezy-Seerr', 'Encorr'),
    @('Plezy', 'Encorr'),
    @('plezy', 'encorr'),
    @('PLEZY', 'ENCORR'),
    @('<<<ASS_CORE_VERSION>>>', '0.4.1-plezy.1'),
    @('0.4.1-encorr.1', '0.4.1-plezy.1')
)
Edit-TextFiles $brandRules 'Brand'

# --- Pass 2b: JNI symbol fixes (native code) ----------------------------------

Write-Host '== Pass 2b: JNI native symbols =='
$jniRules = @(
    @('Java_com_edde746_plezy', 'Java_app_encorr_encorr'),
    @('Java_com_edde746_encorr', 'Java_app_encorr_encorr'),
    @('com/edde746/plezy', 'app/encorr/encorr'),
    @('com/edde746/encorr', 'app/encorr/encorr'),
    @('com/encorr-app/encorr', 'app/encorr/encorr')
)
Edit-TextFiles $jniRules 'JNI'

# --- Pass 3: pubspec.yaml ---------------------------------------------------

Write-Host '== Pass 3: pubspec.yaml =='
$pubspec = Join-Path $root 'pubspec.yaml'
if (Test-Path $pubspec) {
    $text, $enc = Read-TextFile $pubspec
    $new = $text
    $new = $new -replace '(?m)^name:\s*plezy\s*$', 'name: encorr'
    $new = $new -replace '(?m)^description:\s*".*"$', 'description: "Encorr — Plex & Jellyfin client with Seerr requests"'
    $new = $new -replace '(?m)^  org:\s*plezy\s*$', '  org: encorr'
    $new = $new -replace '(?m)^  project:\s*plezy\s*$', '  project: encorr'
    if ($new -notmatch 'encorr_logo\.png') {
        $new = $new -replace '(?m)^(\s+assets:\s*)$', "`$1`n    - assets/encorr_logo.png`n    - assets/encorr_icon.png"
    }
    $new = ($new -split "`n" | Where-Object {
        $_ -notmatch 'assets/plezy\.png' -and $_ -notmatch 'assets/plezy_adaptive_foreground\.svg'
    }) -join "`n"
    if ($new -cne $text) {
        Write-TextFile $pubspec $new $enc
        Write-Host '  updated pubspec.yaml'
    } else {
        Write-Host '  pubspec.yaml already up to date'
    }
}

# --- Pass 4: Kotlin/Java package directories --------------------------------

Write-Host '== Pass 4: Kotlin/Java package directories =='
Get-ChildItem -Path $root -Recurse -Directory -Filter 'plezy' -ErrorAction SilentlyContinue | Where-Object {
    -not (Test-Excluded $_.FullName) -and $_.FullName -match '\\com\\edde746\\plezy$'
} | ForEach-Object {
    $srcRoot = $_.Parent.Parent.Parent.FullName
    $dest = Join-Path $srcRoot 'app\encorr\encorr'
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Get-ChildItem -Path $_.FullName | Move-Item -Destination $dest -Force
    Write-Host "  moved: $($_.FullName.Substring($root.Length + 1)) -> app\encorr\encorr"
    Remove-Item -Path (Join-Path $srcRoot 'com\edde746\plezy') -Force -Recurse -ErrorAction SilentlyContinue
    $edde = Join-Path $srcRoot 'com\edde746'
    if ((Test-Path $edde) -and -not (Get-ChildItem $edde)) { Remove-Item $edde -Force }
    $com = Join-Path $srcRoot 'com'
    if ((Test-Path $com) -and -not (Get-ChildItem $com)) { Remove-Item $com -Force }
}

# --- Pass 5: rename files/dirs containing plezy ---------------------------

Write-Host '== Pass 5: rename files and directories =='
$renameTargets = @(
    Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue
    Get-ChildItem -Path $root -Recurse -Directory -ErrorAction SilentlyContinue
) | Where-Object {
    $null -ne $_ -and $null -ne $_.FullName -and $_.Name -match 'plezy' -and -not (Test-Excluded $_.FullName)
} | Sort-Object { $_.FullName.Length } -Descending

foreach ($item in $renameTargets) {
    if ($null -eq $item -or [string]::IsNullOrWhiteSpace($item.FullName) -or $null -eq $item.Parent) { continue }
    $newName = $item.Name.Replace('Plezy', 'Encorr').Replace('plezy', 'encorr').Replace('PLEZY', 'ENCORR')
    if ($newName -ceq $item.Name) { continue }
    if (-not (Test-Path -LiteralPath $item.FullName)) { continue }
    $dest = Join-Path $item.Parent.FullName $newName
    if (-not (Test-Path -LiteralPath $dest)) {
        Rename-Item -LiteralPath $item.FullName -NewName $newName
        Write-Host "  renamed: $($item.Name) -> $newName"
    }
}

# --- Pass 6: Android launcher mipmaps ---------------------------------------

Write-Host '== Pass 6: Android launcher icons =='
$androidRes = Join-Path $root 'android\app\src\main\res'
$mipmapSizes = @{
    'mipmap-mdpi'    = 48
    'mipmap-hdpi'    = 72
    'mipmap-xhdpi'   = 96
    'mipmap-xxhdpi'  = 144
    'mipmap-xxxhdpi' = 192
}
foreach ($folder in $mipmapSizes.Keys) {
    $size = $mipmapSizes[$folder]
    $outDir = Join-Path $androidRes $folder
    foreach ($name in @('ic_launcher.png', 'ic_launcher_round.png', 'ic_launcher_foreground.png')) {
        $out = Join-Path $outDir $name
        Resize-Png $iconSrc $out $size
        Write-Host "  $folder/$name (${size}px)"
    }
}

$colorsXml = Join-Path $androidRes 'values\colors.xml'
if (Test-Path $colorsXml) {
    $text, $enc = Read-TextFile $colorsXml
    $new = $text
    $new = $new.Replace('<color name="ic_launcher_background">#ffffff</color>', '<color name="ic_launcher_background">#12101A</color>')
    if ($new -cne $text) {
        Write-TextFile $colorsXml $new $enc
        Write-Host '  updated values/colors.xml ic_launcher_background'
    }
}
$colorsNight = Join-Path $androidRes 'values-night\colors.xml'
if (Test-Path $colorsNight) {
    $text, $enc = Read-TextFile $colorsNight
    $new = $text.Replace('<color name="ic_launcher_background">#1a1a1a</color>', '<color name="ic_launcher_background">#12101A</color>')
    if ($new -cne $text) {
        Write-TextFile $colorsNight $new $enc
        Write-Host '  updated values-night/colors.xml ic_launcher_background'
    }
}

$adaptiveXml = Join-Path $androidRes 'mipmap-anydpi-v26\ic_launcher.xml'
$adaptive = @'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground android:drawable="@mipmap/ic_launcher_foreground" />
  <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'@
Set-Content -Path $adaptiveXml -Value $adaptive -Encoding UTF8
Write-Host '  updated mipmap-anydpi-v26/ic_launcher.xml'

# --- Pass 6b: Android TV leanback banner --------------------------------------

Write-Host '== Pass 6b: Android TV banner (leanback launcher) =='
$tvBannerSrc = Join-Path $assetsDir 'encorr_tv_banner.png'
$useCustomTvBanner = Test-Path $tvBannerSrc
if ($useCustomTvBanner) {
    Write-Host "  using custom banner source: assets/encorr_tv_banner.png"
} else {
    Write-Host '  composing banner from assets/encorr_icon.png (add assets/encorr_tv_banner.png for full-bleed art)'
}
$tvBanners = @{
    'drawable-xhdpi'    = @(640, 360)
    'drawable-xxhdpi'   = @(960, 540)
    'drawable-xxxhdpi'  = @(1280, 720)
}
foreach ($folder in $tvBanners.Keys) {
    $w = $tvBanners[$folder][0]
    $h = $tvBanners[$folder][1]
    $outDir = Join-Path $androidRes $folder
    $out = Join-Path $outDir 'tv_banner.png'
    if ($useCustomTvBanner) {
        Resize-TvBannerCover $tvBannerSrc $out $w $h
    } else {
        Compose-TvBanner $iconSrc $out $w $h
    }
    Write-Host "  $folder/tv_banner.png (${w}x${h})"
}

# --- Pass 7: Android native splash ------------------------------------------

Write-Host '== Pass 7: Android splash icon =='
$splashDir = Join-Path $androidRes 'drawable-nodpi'
New-Item -ItemType Directory -Path $splashDir -Force | Out-Null
Resize-PngFit $logoSrc (Join-Path $splashDir 'encorr_splash_logo.png') 512
Write-Host '  drawable-nodpi/encorr_splash_logo.png'

$splashXml = @'
<?xml version="1.0" encoding="utf-8"?>
<bitmap xmlns:android="http://schemas.android.com/apk/res/android"
    android:src="@drawable/encorr_splash_logo"
    android:gravity="center" />
'@
Set-Content -Path (Join-Path $androidRes 'drawable\splash_icon.xml') -Value $splashXml -Encoding UTF8
Write-Host '  updated drawable/splash_icon.xml'

# --- Pass 8: Linux packaging icons ------------------------------------------

Write-Host '== Pass 8: Linux packaging icons =='
$linuxIcons = Join-Path $root 'linux\packaging\icons'
if (Test-Path $linuxIcons) {
    $sizes = @(16, 24, 32, 48, 64, 128, 256, 512)
    foreach ($size in $sizes) {
        $dir = Join-Path $linuxIcons "${size}x${size}"
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $dest = Join-Path $dir 'encorr.png'
        Resize-Png $iconSrc $dest $size
        $legacy = Join-Path $dir 'plezy.png'
        if (Test-Path $legacy) { Remove-Item $legacy -Force }
        Write-Host "  linux/packaging/icons/${size}x${size}/encorr.png"
    }
}

# --- Pass 9: website assets -------------------------------------------------

Write-Host '== Pass 9: website logo =='
$websiteAssets = Join-Path $root 'website\src\lib\assets'
if (Test-Path $websiteAssets) {
    Copy-Item -LiteralPath $logoSrc -Destination (Join-Path $websiteAssets 'encorr_logo.png') -Force
    Copy-Item -LiteralPath $iconSrc -Destination (Join-Path $websiteAssets 'encorr_icon.png') -Force
    Write-Host '  copied logos to website/src/lib/assets/'
}

# --- Pass 10: icon generator script -----------------------------------------

Write-Host '== Pass 10: Android icon generator script =='
$iconScript = Join-Path $root 'scripts\generate_android_icons.sh'
if (Test-Path $iconScript) {
    $text, $enc = Read-TextFile $iconScript
    $new = $text.Replace('SVG_SOURCE="assets/plezy.svg"', 'SVG_SOURCE="assets/encorr_icon.png"')
    if ($new -cne $text) {
        Write-TextFile $iconScript $new $enc
        Write-Host '  updated scripts/generate_android_icons.sh'
    }
}

# --- Pass 11: remove legacy Plezy assets ------------------------------------

Write-Host '== Pass 11: legacy assets =='
if (-not $KeepOldAssets) {
    foreach ($legacy in @('plezy.png', 'plezy.svg', 'plezy_adaptive_foreground.svg')) {
        $path = Join-Path $assetsDir $legacy
        if (Test-Path $path) {
            Remove-Item $path -Force
            Write-Host "  removed assets/$legacy"
        }
    }
} else {
    Write-Host '  skipped (-KeepOldAssets)'
}

# --- done -------------------------------------------------------------------

Write-Host ''
Write-Host '== Rebrand complete =='
Write-Host ''
Write-Host 'Assets:'
Write-Host '  encorr_logo.png  -> splash, auth, about, in-app branding'
Write-Host '  encorr_icon.png  -> launcher + Linux packaging icons'
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  flutter pub get'
Write-Host '  flutter analyze'
Write-Host '  flutter build apk --debug   # installs as app.encorr.encorr (separate from Plezy)'
Write-Host '  graphify update .'
Write-Host ''
Write-Host 'Re-run anytime: powershell -ExecutionPolicy Bypass -File .\rebrand-to-encorr.ps1'
