#!/usr/bin/env bash
# integration_test'i emülatörde İKİ denemeyle koşar (CI, integration.yml).
#
# Neden ayrı dosya: reactivecircus/android-emulator-runner `script:` bloğunu
# SATIR SATIR `sh -c` ile çalıştırır; çok satırlı `for … done` orada
# "Syntax error: end of file unexpected" ile kırılır (2026-09-21'de yaşandı).
#
# Neden iki deneme: aynı gün iki kez giriş `PGRST303 "JWT issued at future"`
# ile düştü, yeniden koşuda geçti — runner saati NTP ile geri çekilince
# GoTrue'nun az önce verdiği JWT PostgREST'e göre gelecekten geliyor. Kod
# hatası değil. İkinci deneme de düşerse gerçek hata: kırmızı kalır.
set -u

: "${SUPABASE_URL:?SUPABASE_URL yok}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY yok}"
CIHAZ="${1:-emulator-5554}"
DIZIN="${GITHUB_WORKSPACE:-$(pwd)}/integration_test"

for deneme in 1 2; do
  if flutter test "$DIZIN" -d "$CIHAZ" \
      --dart-define=SUPABASE_URL="$SUPABASE_URL" \
      --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"; then
    exit 0
  fi
  if [ "$deneme" = "1" ]; then
    echo "::warning::integration_test ilk denemede düştü — 15 sn sonra bir kez daha (emülatör/saat kayması flake'i)"
    date -u
    sleep 15
  fi
done
exit 1
