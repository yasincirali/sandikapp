#!/usr/bin/env bash
# Emülatörleri DOĞRU SAAT DİLİMİYLE başlatır.
#
# ## Neden ayrı bir betik
# `flutter emulators --launch <ad>` saat dilimi bayrağı geçiremiyor ve
# emülatör varsayılan olarak GMT açılıyor. Host ise GMT+3.
#
# Aynı AN, farklı gösterim — ama bu uygulamada saatin GÖRÜNEN değeri
# işlevsel:
#   * "GÜNLÜK" sekmesi içinde bulunulan TAKVİM GÜNÜNÜ çiziyor,
#   * fon NAV basamağı TR 10:00'a çapalı,
#   * BIST seans pencereleri TR saatiyle.
#
# GMT'de koşan bir emülatör, TR saatiyle 00:00–03:00 arasında hâlâ DÜNÜ
# gösterir. O pencerede yapılan görsel doğrulama sessizce yanlış olur —
# ekran "dünü çiziyor" sanılır, oysa emülatör için gerçekten dündür.
#
# ## Neden çalışma zamanında ayarlamak yetmiyor
# `service call alarm 3 s16 Europe/Istanbul` ANINDA çalışıyor ama
# emülatör her açılışta GMT'ye dönüyor — `auto_time_zone=0` yapılsa bile
# (ölçüldü 2026-09-14, iki ayrı reboot ile doğrulandı). `adb root` da
# Google Play imajlarında kapalı, yani prop'u kalıcı yazmak mümkün değil.
#
# Tek kalıcı yol başlatma bayrağı: `-timezone`.
#
# Kullanım:  bash tool/launch_emulators.sh [avd_adi ...]
# Varsayılan: pixel7_1 pixel7_2
set -u

EMULATOR="C:/Users/vasin/Android/sdk/emulator/emulator.exe"
ADB="C:/Users/vasin/Android/sdk/platform-tools/adb.exe"
TZ_NAME="Europe/Istanbul"

AVDS=${*:-"pixel7_1 pixel7_2"}

if [ ! -f "$EMULATOR" ]; then
  echo "HATA: emulator bulunamadı: $EMULATOR" >&2
  exit 1
fi

for avd in $AVDS; do
  # Zaten çalışıyor mu? Aynı AVD'yi ikinci kez başlatmak kilit hatası verir.
  if "$ADB" devices | grep -q "emulator-.*device"; then
    running=$("$ADB" devices | awk '/emulator-.*\tdevice$/{print $1}' | while read -r d; do
      "$ADB" -s "$d" emu avd name 2>/dev/null | head -1 | tr -d '\r'
    done | grep -Fx "$avd" || true)
    if [ -n "$running" ]; then
      echo "  $avd zaten çalışıyor — atlandı"
      continue
    fi
  fi

  echo "  $avd başlatılıyor (-timezone $TZ_NAME)"
  "$EMULATOR" -avd "$avd" -timezone "$TZ_NAME" >/dev/null 2>&1 &
done

echo
echo "Emülatörler arka planda açılıyor. Hazır olunca:"
echo "  bash tool/deploy_emulators.sh"
