#!/usr/bin/env bash
# sandık — her değişiklikten sonra emülatörlere dağıt.
#
# Kullanım:  bash tool/deploy_emulators.sh
#
# Sıra: analyze → test → build → install (her cihaza) → launch → crash kontrolü.
# Herhangi bir adım kırılırsa durur; kırık APK emülatöre gitmez.
#
# BİLİNEN SINIR: bu emülatörler Flutter'ı RENDER EDEMİYOR (ekran görüntüsü
# tamamen siyah gelir, bkz. TECHNICAL_DEBT.md). Bu betik "çalışıyor mu"
# sorusunu yanıtlar — "doğru görünüyor mu" sorusunu YANITLAMAZ.
# Görsel doğrulama gerçek cihazda veya widget testiyle yapılmalı.

set -euo pipefail

ADB="C:/Users/vasin/Android/sdk/platform-tools/adb.exe"
PKG="com.sandik.app"
APK="build/app/outputs/flutter-apk/app-debug.apk"
export MSYS_NO_PATHCONV=1

step() { printf '\n\033[1m── %s\033[0m\n' "$1"; }

step "1/5  Statik analiz"
if ! flutter analyze --no-pub 2>&1 | tee /tmp/_an.txt | tail -2; then :; fi
if grep -qE " error " /tmp/_an.txt; then
  echo "HATA: analyze hata veriyor — dağıtım durduruldu."
  grep -E " error " /tmp/_an.txt | head -10
  exit 1
fi

step "2/5  Testler"
flutter test --no-pub 2>&1 | tail -3

step "3/5  APK derleme"
flutter build apk --debug --dart-define-from-file=.env.local 2>&1 | tail -3

# Bağlı tüm emülatörler (offline olanlar hariç)
DEVICES=$("$ADB" devices | awk '/emulator-.*\tdevice$/{print $1}')
if [ -z "$DEVICES" ]; then
  echo "HATA: bağlı emülatör yok. Önce:"
  echo "  bash tool/launch_emulators.sh"
  exit 1
fi

# ── Saat dilimini host ile hizala ───────────────────────────────────────────
#
# Emülatör GMT açılıyor, host GMT+3. Aynı AN ama farklı gösterim; bu
# uygulamada saatin GÖRÜNEN değeri işlevsel:
#   * "GÜNLÜK" sekmesi içinde bulunulan TAKVİM GÜNÜNÜ çiziyor,
#   * fon NAV basamağı TR 10:00'a çapalı,
#   * BIST seans pencereleri TR saatiyle.
# GMT'de test edilen bir ekran, gece yarısına yakın saatlerde YANLIŞ GÜNÜ
# gösterir ve bu sessizce yanlış doğrulamaya yol açar.
#
# ⚠️ Kalıcı DEĞİL: emülatör her açılışta GMT'ye dönüyor (`auto_time_zone=0`
# yapılsa bile — ölçüldü 2026-09-14, iki reboot). Kalıcı çözüm başlatma
# bayrağı: `tool/launch_emulators.sh` `-timezone Europe/Istanbul` veriyor.
# Buradaki adım, emülatör elle başlatılmışsa devreye giren emniyet ağı.
for d in $DEVICES; do
  tz=$("$ADB" -s "$d" shell getprop persist.sys.timezone 2>/dev/null | tr -d '\r')
  if [ "$tz" != "Europe/Istanbul" ]; then
    "$ADB" -s "$d" shell settings put global auto_time_zone 0 >/dev/null 2>&1
    "$ADB" -s "$d" shell "service call alarm 3 s16 Europe/Istanbul" >/dev/null 2>&1
    echo "  $d saat dilimi $tz → Europe/Istanbul"
  fi
done

step "4/5  Kurulum"
for d in $DEVICES; do
  # Cihaz gerçekten hazır mı? Boot bitmeden install session açılamaz.
  until [ "$("$ADB" -s "$d" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    echo "  $d açılış bekleniyor..."
    sleep 3
  done

  # Disk doluluğunu ÖNCEDEN kontrol et. Debug APK ~215 MB ve kurulum
  # sırasında geçici olarak iki katı yer ister; /data dolduğunda adb
  # "INSTALL_FAILED_INSUFFICIENT_STORAGE" verir. Bu sessizce geçilirse
  # emülatörde ESKİ sürüm çalışmaya devam eder ve testi yanıltır.
  avail=$("$ADB" -s "$d" shell df /data 2>/dev/null | awk 'END{print $4}')
  if [ -n "$avail" ] && [ "$avail" -lt 900000 ]; then
    echo "  $d  ✗ /data'da yetersiz alan ($((avail/1024)) MB)."
    echo "     Çözüm — AVD'yi sıfırla:"
    echo "       $ADB -s $d emu kill"
    echo "       \"C:/Users/vasin/Android/sdk/emulator/emulator.exe\" -avd <ad> -wipe-data"
    exit 1
  fi

  printf '  %s ... ' "$d"
  # Çıkışı yakala: `| grep` kullanılırsa adb'nin hata kodu kaybolur ve
  # başarısız kurulum başarılı sanılır (bu hata bir kez yaşandı).
  if out=$("$ADB" -s "$d" install -r "$APK" 2>&1); then
    echo "Success"
  else
    echo "BAŞARISIZ"
    echo "$out" | grep -iE "failed|exception" | head -3
    exit 1
  fi
done

step "5/5  Başlatma + çökme kontrolü"
for d in $DEVICES; do
  "$ADB" -s "$d" logcat -c 2>/dev/null || true
  "$ADB" -s "$d" shell am start -n "$PKG/.MainActivity" >/dev/null 2>&1
done
sleep 6

fail=0
for d in $DEVICES; do
  pid=$("$ADB" -s "$d" shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
  crash=$("$ADB" -s "$d" logcat -d 2>/dev/null | grep -cE "FATAL EXCEPTION|AndroidRuntime.*$PKG" || true)
  if [ -n "$pid" ] && [ "$crash" = "0" ]; then
    echo "  $d  ✓ çalışıyor (pid $pid)"
  else
    echo "  $d  ✗ SORUN (pid='$pid' crash=$crash)"
    "$ADB" -s "$d" logcat -d 2>/dev/null | grep -A6 "FATAL EXCEPTION" | head -12 || true
    fail=1
  fi
done

[ "$fail" = "0" ] && echo -e "\nTamam — her iki emülatörde çalışıyor." || exit 1
