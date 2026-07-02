# sandik Store Screenshot Script
# Kullanim: .\take_screenshots.ps1 -DeviceId emulator-5554
# Emulator acik ve uygulama yuklu olmali.

param(
    [string]$DeviceId = "emulator-5554",
    [string]$OutDir = "$PSScriptRoot\screenshots\tr-TR\phone"
)

$adb = "C:\Users\vasin\Android\sdk\platform-tools\adb.exe"
$pkg = "com.sandik.app"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Take-Screenshot {
    param([string]$Name)
    $remote = "/sdcard/ss_$Name.png"
    $local  = "$OutDir\$Name.png"
    & $adb -s $DeviceId shell screencap -p $remote
    & $adb -s $DeviceId pull $remote $local
    & $adb -s $DeviceId shell rm $remote
    Write-Host "Saved: $local"
}

# Uygulama basli mi?
& $adb -s $DeviceId shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
Start-Sleep -Seconds 3

Write-Host "1/4 Ana Ekran..."
Take-Screenshot "01_home"
Start-Sleep -Seconds 2

Write-Host "2/4 Dagılım..."
# Bottom nav index 1 (Dagılım) — koordinat tahmini, emulator ekran 1080x2340
& $adb -s $DeviceId shell input tap 324 2260
Start-Sleep -Seconds 2
Take-Screenshot "02_charts"

Write-Host "3/4 Performans..."
& $adb -s $DeviceId shell input tap 756 2260
Start-Sleep -Seconds 2
Take-Screenshot "03_performance"

Write-Host "4/4 Profil..."
& $adb -s $DeviceId shell input tap 972 2260
Start-Sleep -Seconds 2
Take-Screenshot "04_profile"

Write-Host ""
Write-Host "Tamamlandi. Dosyalar: $OutDir"
