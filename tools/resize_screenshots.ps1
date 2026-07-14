Add-Type -AssemblyName System.Drawing

# Ayarlar
$inputFolder = "C:\Screenshots\input"
$outputRoot  = "C:\Screenshots\output"
$bgColor     = [System.Drawing.ColorTranslator]::FromHtml("#0D1F1A")

# App Store review için gerekli iki set:
#   iPhone 6.7" (iPhone 15 Pro Max / 14 Pro Max) — zorunlu
#   iPad 12.9"  (iPad Pro 6.gen) — iPad target aktifse zorunlu
$targets = @(
    @{ Name = "iphone_6.7"; W = 1284; H = 2778 },
    @{ Name = "ipad_12.9";  W = 2048; H = 2732 }
)

if (-not (Test-Path $inputFolder)) {
    Write-Host "HATA: $inputFolder bulunamadi." -ForegroundColor Red
    exit 1
}

$files = Get-ChildItem $inputFolder -Include *.png,*.jpg,*.jpeg -Recurse
if ($files.Count -eq 0) {
    Write-Host "HATA: $inputFolder klasoründe PNG/JPG bulunamadi." -ForegroundColor Red
    exit 1
}

foreach ($target in $targets) {
    $outFolder = Join-Path $outputRoot $target.Name
    if (-not (Test-Path $outFolder)) {
        New-Item -ItemType Directory -Path $outFolder | Out-Null
    }

    $targetW = $target.W
    $targetH = $target.H

    Write-Host "`n=== $($target.Name) ($targetW x $targetH) ===" -ForegroundColor Cyan

    foreach ($file in $files) {
        $src = [System.Drawing.Image]::FromFile($file.FullName)

        $scaleW = $targetW / $src.Width
        $scaleH = $targetH / $src.Height
        $scale  = [Math]::Min($scaleW, $scaleH)

        $newW = [int]($src.Width  * $scale)
        $newH = [int]($src.Height * $scale)
        $x    = [int](($targetW - $newW) / 2)
        $y    = [int](($targetH - $newH) / 2)

        $canvas = New-Object System.Drawing.Bitmap($targetW, $targetH)
        $g      = [System.Drawing.Graphics]::FromImage($canvas)
        $g.Clear($bgColor)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($src, $x, $y, $newW, $newH)
        $g.Dispose()
        $src.Dispose()

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $outPath  = Join-Path $outFolder ("{0}.png" -f $baseName)
        $canvas.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $canvas.Dispose()

        Write-Host "OK: $($file.Name) -> $outPath" -ForegroundColor Green
    }
}

Write-Host "`nTamamlandi! $($files.Count) dosya x $($targets.Count) hedef = $($files.Count * $targets.Count) cikti." -ForegroundColor Cyan
