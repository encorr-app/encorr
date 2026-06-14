# Regenerate Android TV leanback banners (tv_banner.png).
# Uses assets/encorr_tv_banner.png when present (1280x720 recommended, 16:9).
# Otherwise composes a left-hero banner from assets/encorr_icon.png.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$iconSrc = Join-Path $repoRoot 'assets\encorr_icon.png'
$customSrc = Join-Path $repoRoot 'assets\encorr_tv_banner.png'
$androidRes = Join-Path $repoRoot 'android\app\src\main\res'

if (-not (Test-Path $iconSrc)) {
    throw "Missing launcher icon: $iconSrc"
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

            $padY = [int]($height * 0.06)
            $padX = [int]($height * 0.05)
            $targetH = $height - (2 * $padY)
            $scale = $targetH / $src.Height
            $targetW = [int][Math]::Round($src.Width * $scale)
            $targetH = [int][Math]::Round($src.Height * $scale)

            $maxW = [int]($width * 0.44)
            if ($targetW -gt $maxW) {
                $scale = $maxW / $src.Width
                $targetW = [int][Math]::Round($src.Width * $scale)
                $targetH = [int][Math]::Round($src.Height * $scale)
            }

            $x = $padX
            $y = [int](($height - $targetH) / 2)
            $g.DrawImage($src, $x, $y, $targetW, $targetH)

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

$useCustom = Test-Path $customSrc
if ($useCustom) {
    Write-Host "Using custom TV banner: assets/encorr_tv_banner.png"
} else {
    Write-Host "Composing TV banner from assets/encorr_icon.png"
    Write-Host "Tip: drop a 1280x720 PNG at assets/encorr_tv_banner.png for full-bleed art"
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
    if ($useCustom) {
        Resize-TvBannerCover $customSrc $out $w $h
    } else {
        Compose-TvBanner $iconSrc $out $w $h
    }
    Write-Host "Wrote $out (${w}x${h})"
}

Write-Host 'Done. Rebuild the APK and reinstall to refresh the TV home row tile.'
