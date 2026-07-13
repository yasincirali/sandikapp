Add-Type -AssemblyName System.Drawing

# Ayarlar
$inputFolder  = "C:\screenshots\input"   # screenshot'larini buraya koy
$outputFolder = "C:\screenshots\output"  # cikti buraya gelir
$targetW      = 1284
$targetH      = 2778
$bgColor      = [System.Drawing.ColorTranslator]::FromHtml("#0D1F1A")

if (-not (Test-Path $outputFolder)) { New-Item -ItemType Directory -Path $outputFolder | Out-Null }

$files = Get-ChildItem $inputFolder -Include *.png,*.jpg,*.jpeg -Recurse

if ($files.Count -eq 0) {
    Write-Host "HATA: $inputFolder klasoründe PNG/JPG bulunamadi." -ForegroundColor Red
    exit 1
}

foreach ($file in $files) {
    $src = [System.Drawing.Image]::FromFile($file.FullName)

    # Orana gore hesapla
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

    $outPath = Join-Path $outputFolder $file.Name
    $canvas.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()

    Write-Host "OK: $($file.Name) -> $outPath" -ForegroundColor Green
}

Write-Host "`nTamamlandi! $($files.Count) dosya islendi." -ForegroundColor Cyan
