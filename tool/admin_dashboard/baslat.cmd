@echo off
setlocal
title sandik destek paneli

rem Masaustu kisayolunun hedefi. Tek isi: dev sunucusunu ayaga kaldirip
rem tarayiciyi acmak, pencere kapaninca sunucuyu da birlikte goturmek.
rem Bu pencere sunucunun kendisidir; kapatilinca Vite de olur, boylece
rem panel arka planda unutulmus halde canli veriye bagli kalmaz.
rem
rem NOT: bu dosya CRLF satir sonlariyla ve saf ASCII olarak tutulur.
rem LF ile kaydedilirse batch yorumlayicisi rem satirlarini boler.

cd /d "%~dp0"

where node >nul 2>&1
if errorlevel 1 (
  echo.
  echo  [HATA] Node.js bulunamadi. https://nodejs.org adresinden kur.
  echo.
  pause
  exit /b 1
)

rem Bagimliliklar kurulu mu? Repoyu taze klonlayan icin tek adim.
if not exist "node_modules\vite" (
  echo.
  echo  Bagimliliklar kuruluyor, ilk acilis biraz surebilir...
  echo.
  call npm install
  if errorlevel 1 (
    echo.
    echo  [HATA] npm install basarisiz.
    pause
    exit /b 1
  )
)

if not exist ".env.local" (
  echo.
  echo  [HATA] .env.local yok. Once sunu calistir:
  echo         copy .env.example .env.local
  echo  Sonra icindeki URL ve anon key alanlarini doldur.
  echo.
  pause
  exit /b 1
)

rem Sunucu zaten ayakta mi? Kisayola ikinci kez basildiginda yeni bir
rem Vite baslatmak yerine var olan sekmeye don. Vite strictPort ile
rem 5273e sabitli; port doluysa o bizimkidir.
powershell -NoProfile -Command "try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 5273); $c.Close(); exit 0 } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 (
  echo.
  echo  Panel zaten calisiyor, tarayici aciliyor...
  start "" "http://127.0.0.1:5273/"
  exit /b 0
)

echo.
echo  sandik destek paneli baslatiliyor...
echo  Bu pencereyi kapatmak paneli de kapatir.
echo.

rem Tarayiciyi sunucu HAZIR olunca ac: hemen acilirsa "baglanilamadi"
rem sayfasi gelir ve kullanici elle yenilemek zorunda kalir.
start "" /b powershell -NoProfile -Command "$u = 'http://127.0.0.1:5273/'; for ($i = 0; $i -lt 60; $i++) { try { Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 2 | Out-Null; Start-Process $u; break } catch { Start-Sleep -Milliseconds 500 } }"

rem Vite on planda kosar: bu pencere = sunucu.
call npx vite --port 5273

endlocal
