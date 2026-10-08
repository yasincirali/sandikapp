# sandik kontrol paneli -- her acilista GUNCEL surumu acan baslatici.
#
# Masaustu kisayolu bu betigin depo DISINDAKI kopyasini calistirir
# (%LOCALAPPDATA%\sandik-panel\guncel_baslat.ps1). Neden disarida:
# betik, paneli calistirdigi klasoru guncelliyor; kendi dosyasi o klasorde
# olsaydi guncelleme ayagini kesen dal olurdu. Depodaki bu dosya asil
# kaynaktir; her acilista disaridaki kopya bundan tazelenir.
#
# Ne yapar:
#   1. Panel zaten aciksa yalnizca tarayiciyi acar.
#   2. Panele AYRILMIS klasoru ($Kok, ayrik HEAD) origin/main'e ceker.
#      Klasor bir dalda ise ya da izlenen dosyada degisiklik varsa
#      DOKUNMAZ -- gelistirme klasoru yanlislikla sifirlanmasin.
#      Cevrimdisiysa mevcut surumle devam eder.
#   3. package-lock degistiyse bagimliliklari yeniden kurar.
#   4. baslat.cmd ile Vite'i on planda kaldirir (pencere = sunucu).
#
# NOT: saf ASCII tutulur. Windows PowerShell 5.1 BOM'suz dosyayi ANSI
# okur; Turkce harf burada bozulurdu.

param(
  [string]$Kok = 'C:\projects\PortfoyTakip-panel',
  [string]$Depo = 'C:\projects\PortfoyTakip',
  [string]$Dal = 'main',
  # Yalnizca guncelle ve cik (deneme / bakim icin).
  [switch]$YalnizGuncelle
)

$Panel = Join-Path $Kok 'tool\admin_dashboard'
try { $Host.UI.RawUI.WindowTitle = 'sandik kontrol paneli' } catch {}

function Yaz([string]$m) { Write-Host "  $m" }

function PanelAcikMi {
  try {
    $c = New-Object Net.Sockets.TcpClient
    $c.Connect('127.0.0.1', 5273)
    $c.Close()
    return $true
  } catch { return $false }
}

if (-not $YalnizGuncelle -and (PanelAcikMi)) {
  Yaz 'Panel zaten calisiyor, tarayici aciliyor...'
  Start-Process 'http://127.0.0.1:5273/'
  exit 0
}

# -- 1. Ayrilmis klasor yoksa kur ------------------------------------------
if (-not (Test-Path (Join-Path $Kok '.git'))) {
  Yaz "Panel klasoru kuruluyor: $Kok"
  git -C $Depo fetch --quiet origin $Dal
  git -C $Depo worktree add --detach $Kok "origin/$Dal"
  if ($LASTEXITCODE -ne 0) {
    Yaz '[HATA] Panel klasoru kurulamadi.'
    Read-Host '  Kapatmak icin Enter'
    exit 1
  }
  $ornek = Join-Path $Depo 'tool\admin_dashboard\.env.local'
  if (Test-Path $ornek) { Copy-Item $ornek (Join-Path $Panel '.env.local') }
}

# -- 2. origin/main'e cek --------------------------------------------------
$kilit = Join-Path $Panel 'package-lock.json'
$kilitOnce = if (Test-Path $kilit) { (Get-FileHash $kilit).Hash } else { '' }

git -C $Kok symbolic-ref -q HEAD *> $null
$dalda = ($LASTEXITCODE -eq 0)
$degisik = git -C $Kok status --porcelain --untracked-files=no

if ($dalda) {
  Yaz "[UYARI] $Kok bir dalda; guncellenmedi (yalnizca ayrik HEAD guncellenir)."
} elseif ($degisik) {
  Yaz "[UYARI] $Kok icinde degisiklik var; guncellenmedi."
} else {
  git -C $Kok fetch --quiet origin $Dal
  if ($LASTEXITCODE -ne 0) {
    Yaz '[UYARI] Guncelleme alinamadi (ag?); mevcut surum aciliyor.'
  } else {
    $once = git -C $Kok rev-parse --short HEAD
    git -C $Kok checkout --quiet --detach "origin/$Dal"
    $sonra = git -C $Kok rev-parse --short HEAD
    $baslik = git -C $Kok log -1 --format=%s
    if ($once -ne $sonra) { Yaz "Guncellendi: $once -> $sonra  ($baslik)" }
    else { Yaz "Guncel: $sonra  ($baslik)" }
  }
}

# -- 3. Bagimliliklar -------------------------------------------------------
$kilitSonra = if (Test-Path $kilit) { (Get-FileHash $kilit).Hash } else { '' }
if (($kilitOnce -ne $kilitSonra) -or -not (Test-Path (Join-Path $Panel 'node_modules\vite'))) {
  Yaz 'Bagimliliklar kuruluyor...'
  Push-Location $Panel
  npm ci --no-audit --no-fund
  Pop-Location
}

# -- 4. Disaridaki baslatici kopyasini tazele -------------------------------
$kaynak = Join-Path $Panel 'guncel_baslat.ps1'
if ((Test-Path $kaynak) -and $PSCommandPath -and ($PSCommandPath -ne $kaynak)) {
  if ((Get-FileHash $kaynak).Hash -ne (Get-FileHash $PSCommandPath).Hash) {
    # Calisan betik bellege okundu; dosyayi degistirmek bu kosuyu etkilemez.
    Copy-Item $kaynak $PSCommandPath -Force
  }
}

if ($YalnizGuncelle) { exit 0 }

# -- 5. Paneli ac ------------------------------------------------------------
& cmd.exe /c (Join-Path $Panel 'baslat.cmd')
