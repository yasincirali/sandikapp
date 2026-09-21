#!/usr/bin/env bash
# Başsız duman testi — yerel Supabase yığını + tohum kullanıcı, Flutter'sız.
#
# integration_test/smoke_test.dart ile AYNI akış (giriş → varlık ekle →
# portföyü oku), ama uygulama yerine düz REST: GoTrue'dan token al, PostgREST
# ile `assets`'e yaz, geri oku, sil. Emülatör gerektirmediği için saniyeler
# içinde biter ve şu soruyu kesin yanıtlar: "migration'lar + seed sıfırdan
# bir yığında tutarlı mı, RLS tohum kullanıcıyı içeri alıp başkasını dışarıda
# tutuyor mu?" Emülatör testi çökerse önce buna bakılır: burası yeşilse sorun
# uygulama tarafındadır, kırmızıysa sunucu tarafında.
#
# Kullanım:
#   supabase start
#   bash tool/supabase_smoke.sh
# Ortam: SUPABASE_URL / SUPABASE_ANON_KEY verilmezse `supabase status`'tan okunur.

set -euo pipefail

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  eval "$(supabase status -o env 2>/dev/null | grep -E '^(API_URL|ANON_KEY)=')"
  SUPABASE_URL="${SUPABASE_URL:-$API_URL}"
  SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-$ANON_KEY}"
fi

# seed.sql ile birebir.
EMAIL='smoke@sandik.test'
PASSWORD='Duman1234'
UID_SMOKE='11111111-1111-4111-8111-111111111111'

json() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }

echo "== 1) Giriş (GoTrue password grant)"
TOKEN=$(curl -sS -f -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" | json 'd["access_token"]')
[[ -n "$TOKEN" ]] || { echo "token boş"; exit 1; }

AUTH=(-H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")

echo "== 2) Profil (0000 tetikleyicisi + seed onboarding=true)"
ONB=$(curl -sS -f "$SUPABASE_URL/rest/v1/profiles?id=eq.$UID_SMOKE&select=onboarding_completed" \
  "${AUTH[@]}" | json 'd[0]["onboarding_completed"]')
[[ "$ONB" == "True" ]] || { echo "profil onboarding_completed beklenen true, gelen: $ONB"; exit 1; }

echo "== 3) Varlık ekle (assets_own RLS)"
NAME="Duman $$"
ASSET_ID=$(curl -sS -f -X POST "$SUPABASE_URL/rest/v1/assets" \
  "${AUTH[@]}" -H "Prefer: return=representation" \
  -d "{\"user_id\":\"$UID_SMOKE\",\"name\":\"$NAME\",\"type\":\"diger\",\"quantity\":2,\"purchase_price\":100,\"current_price\":100,\"is_manual_price\":true}" \
  | json 'd[0]["id"]')
[[ -n "$ASSET_ID" ]] || { echo "asset id boş"; exit 1; }

echo "== 4) Portföyü oku"
COUNT=$(curl -sS -f "$SUPABASE_URL/rest/v1/assets?select=id&name=eq.$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$NAME")" \
  "${AUTH[@]}" | json 'len(d)')
[[ "$COUNT" == "1" ]] || { echo "eklenen varlık geri okunamadı (adet=$COUNT)"; exit 1; }

echo "== 5) Başkası adına yazma REDDEDİLMELİ"
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$SUPABASE_URL/rest/v1/assets" \
  "${AUTH[@]}" \
  -d "{\"user_id\":\"22222222-2222-4222-8222-222222222222\",\"name\":\"Yabanci\",\"type\":\"diger\",\"quantity\":1,\"purchase_price\":1,\"current_price\":1}")
[[ "$HTTP" == "401" || "$HTTP" == "403" ]] || { echo "RLS kaçağı: yabancı insert HTTP $HTTP"; exit 1; }

echo "== 6) Push token devralma RPC'si (0069) — yaz, ayni cihazda yenile, geri oku"
# Token cihaza baglidir; RPC onu cagirana yazar, ayni cihazin bayat token'ini
# siler. Baska hesaptan devralma tek tohum kullanicisiyla denenemez; o yol
# migration'in kendi dogrulamasi + canli db_logs ile izlenir.
TOK="duman-token-$$-$(python3 -c 'import secrets;print(secrets.token_hex(24))')"
DEVRALINAN=$(curl -sS -f -X POST "$SUPABASE_URL/rest/v1/rpc/claim_push_token" "${AUTH[@]}"   -d "{\"p_token\":\"$TOK\",\"p_platform\":\"android\",\"p_device_id\":\"duman-cihaz-$$\"}")
[[ "$DEVRALINAN" == "0" ]] || { echo "ilk yazim devralma saymamali, gelen: $DEVRALINAN"; exit 1; }
curl -sS -f -X POST "$SUPABASE_URL/rest/v1/rpc/claim_push_token" "${AUTH[@]}"   -d "{\"p_token\":\"$TOK-yeni\",\"p_platform\":\"android\",\"p_device_id\":\"duman-cihaz-$$\"}" >/dev/null
SATIR=$(curl -sS -f "$SUPABASE_URL/rest/v1/user_push_tokens?select=token&device_id=eq.duman-cihaz-$$"   "${AUTH[@]}" | json 'len(d)')
[[ "$SATIR" == "1" ]] || { echo "ayni cihazin bayat token'i silinmedi (adet=$SATIR)"; exit 1; }
echo "== 6b) anon RPC'yi cagiramamali"
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$SUPABASE_URL/rest/v1/rpc/claim_push_token"   -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json"   -d "{\"p_token\":\"$TOK-anon-0123456789\",\"p_platform\":\"android\"}")
[[ "$HTTP" == "401" || "$HTTP" == "403" || "$HTTP" == "404" ]] || { echo "anon claim_push_token HTTP $HTTP"; exit 1; }

echo "== 7) Temizlik"
curl -sS -f -X DELETE "$SUPABASE_URL/rest/v1/assets?id=eq.$ASSET_ID" "${AUTH[@]}" >/dev/null
curl -sS -f -X DELETE "$SUPABASE_URL/rest/v1/user_push_tokens?device_id=eq.duman-cihaz-$$" "${AUTH[@]}" >/dev/null

echo "OK — başsız duman testi geçti"
