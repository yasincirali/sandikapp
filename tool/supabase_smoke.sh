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

echo "== 6c) Yasal onay (0102) — metin herkese okunur, dogru hash yazilir, yanlis hash reddedilir, kapi sorgusu"
# Metin anon ile okunur (belgeler herkese acik). Onay yalniz RPC ile ve
# yalniz sunucudaki metnin hash'iyle yazilir; doğrudan INSERT yetkisi yok.
# Satir silinemez (tasarim geregi) — tohum kullanicida kalir; CI yigini taze.
# Belgeler 1.1'den baslar (0102 ikinci tur): "1.0" adiyla birden cok metin
# yayimlandi, arsiv satiri uydurulmadi.
metin_hash() {  # tur surum dil
  curl -sS -f "$SUPABASE_URL/rest/v1/yasal_metinler?select=govde_hash&tur=eq.$1&surum=eq.$2&dil=eq.$3" \
    -H "apikey: $SUPABASE_ANON_KEY" | json 'd[0]["govde_hash"] if d else ""'
}
HASH=$(metin_hash kosullar 1.1 tr)
[[ ${#HASH} == 64 ]] || { echo "kosullar/1.1/tr metni okunamadi (hash='$HASH')"; exit 1; }
ESKI=$(metin_hash kosullar 1.0 tr)
[[ -z "$ESKI" ]] || { echo "kosullar/1.0/tr satiri olmamali (uydurma arsiv)"; exit 1; }
YAZILAN=$(curl -sS -f -X POST "$SUPABASE_URL/rest/v1/rpc/yasal_onay_kaydet" "${AUTH[@]}" \
  -d "{\"p_ogeler\":[{\"tur\":\"kosullar\",\"surum\":\"1.1\",\"dil\":\"tr\",\"hash\":\"$HASH\"}],\"p_kanal\":\"kayit\",\"p_platform\":\"duman\"}")
[[ "$YAZILAN" == "1" || "$YAZILAN" == "0" ]] || { echo "yasal_onay_kaydet beklenmeyen donus: $YAZILAN"; exit 1; }
SATIR=$(curl -sS -f "$SUPABASE_URL/rest/v1/yasal_onaylar?select=id&kanal=eq.kayit" "${AUTH[@]}" | json 'len(d)')
[[ "$SATIR" -ge 1 ]] || { echo "onay satiri geri okunamadi (adet=$SATIR)"; exit 1; }
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$SUPABASE_URL/rest/v1/rpc/yasal_onay_kaydet" "${AUTH[@]}" \
  -d "{\"p_ogeler\":[{\"tur\":\"kosullar\",\"surum\":\"1.1\",\"dil\":\"tr\",\"hash\":\"$(printf '0%.0s' {1..64})\"}],\"p_kanal\":\"kayit\"}")
[[ "$HTTP" == "400" ]] || { echo "yanlis hash reddedilmedi: HTTP $HTTP"; exit 1; }
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$SUPABASE_URL/rest/v1/yasal_onaylar" "${AUTH[@]}" \
  -d "{\"user_id\":\"$UID_SMOKE\",\"metin_id\":1,\"kanal\":\"kayit\"}")
[[ "$HTTP" == "401" || "$HTTP" == "403" ]] || { echo "yasal_onaylar dogrudan yazilabildi: HTTP $HTTP"; exit 1; }

# Yeniden onay kapisi (bayrak yeniden_onay_kapisi): yeni kanal belgeyi ve
# kapi ayni ekranda gosterdiyse yatirim uyarisini yazar; Zirve'yi yazamaz.
GHASH=$(metin_hash gizlilik_politikasi 1.1 tr)
YHASH=$(metin_hash yatirim_uyarisi 1.0 tr)
YAZILAN=$(curl -sS -f -X POST "$SUPABASE_URL/rest/v1/rpc/yasal_onay_kaydet" "${AUTH[@]}" \
  -d "{\"p_ogeler\":[{\"tur\":\"gizlilik_politikasi\",\"surum\":\"1.1\",\"dil\":\"tr\",\"hash\":\"$GHASH\",\"degiskenler\":{\"onceki_surum\":null}},{\"tur\":\"yatirim_uyarisi\",\"surum\":\"1.0\",\"dil\":\"tr\",\"hash\":\"$YHASH\"}],\"p_kanal\":\"yeniden_onay\",\"p_platform\":\"duman\"}")
[[ "$YAZILAN" == "2" || "$YAZILAN" == "1" || "$YAZILAN" == "0" ]] || { echo "yeniden_onay beklenmeyen donus: $YAZILAN"; exit 1; }
ZHASH=$(metin_hash zirve_riza 2026-10-01 tr)
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$SUPABASE_URL/rest/v1/rpc/yasal_onay_kaydet" "${AUTH[@]}" \
  -d "{\"p_ogeler\":[{\"tur\":\"zirve_riza\",\"surum\":\"2026-10-01\",\"dil\":\"tr\",\"hash\":\"$ZHASH\"}],\"p_kanal\":\"yeniden_onay\"}")
[[ "$HTTP" == "400" ]] || { echo "yeniden_onay kanalinda zirve reddedilmedi: HTTP $HTTP"; exit 1; }
# Istemcinin kapi sorgusu (YasalOnayService._etkinOnaylar) — RLS kendi
# satiri + yasal_metinler gomulu; yeni RPC gerekmez.
TURLER=$(curl -sS -f "$SUPABASE_URL/rest/v1/yasal_onaylar?select=yasal_metinler!inner(tur,surum)&user_id=eq.$UID_SMOKE&geri_cekildi_at=is.null" \
  "${AUTH[@]}" | json '",".join(sorted({r["yasal_metinler"]["tur"]+"@"+r["yasal_metinler"]["surum"] for r in d}))')
[[ "$TURLER" == *"kosullar@1.1"* && "$TURLER" == *"gizlilik_politikasi@1.1"* && "$TURLER" == *"yatirim_uyarisi@1.0"* ]] \
  || { echo "kapi sorgusu beklenen turleri dondurmedi: $TURLER"; exit 1; }
# Hesap silme (satirlar kalir + damga, Zirve silinir, 3 yil saklama) burada
# denenmez: tohum kullanici silinemez. Migration'in kendi dogrulama blogu
# tetikleyiciyi, politikayi ve cron isini kontrol eder.

echo "== 6d) Fon para akisi (0103) — oturum okur, yazamaz; anon okuyamaz; ic tablo ve RPC kapali"
# Tablolar piyasa verisi: authenticated yalniz SELECT. Taze yiginda bos
# olmalari normal (veriyi akis-gozlem yazar); sinanan sey yetki siniri.
for T in fon_akis_gunluk balina_olay; do
  HTTP=$(curl -sS -o /dev/null -w '%{http_code}' "$SUPABASE_URL/rest/v1/$T?select=tarih&limit=1" "${AUTH[@]}")
  [[ "$HTTP" == "200" ]] || { echo "$T oturumla okunamadi: HTTP $HTTP"; exit 1; }
  HTTP=$(curl -sS -o /dev/null -w '%{http_code}' "$SUPABASE_URL/rest/v1/$T?select=tarih&limit=1"     -H "apikey: $SUPABASE_ANON_KEY")
  [[ "$HTTP" == "401" || "$HTTP" == "403" ]] || { echo "$T anon ile okunabildi: HTTP $HTTP"; exit 1; }
done
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$SUPABASE_URL/rest/v1/fon_akis_gunluk" "${AUTH[@]}"   -d '{"fon_kodu":"ZZZ","tarih":"2026-01-02","fon_tipi":"YAT","pay_adedi":1,"portfoy_degeri":1}')
[[ "$HTTP" == "401" || "$HTTP" == "403" ]] || { echo "fon_akis_gunluk istemciden yazilabildi: HTTP $HTTP"; exit 1; }
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$SUPABASE_URL/rest/v1/balina_olay" "${AUTH[@]}"   -d '{"ticker":"TEFAS:ZZZ","tarih":"2026-01-02","tur":"fon_giris","tutar":1,"buyukluk_orani":1,"sapma_kati":1}')
[[ "$HTTP" == "401" || "$HTTP" == "403" ]] || { echo "balina_olay istemciden yazilabildi: HTTP $HTTP"; exit 1; }
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' "$SUPABASE_URL/rest/v1/fon_akis_tur?select=tarih&limit=1" "${AUTH[@]}")
[[ "$HTTP" == "401" || "$HTTP" == "403" ]] || { echo "fon_akis_tur istemciye acik: HTTP $HTTP"; exit 1; }
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$SUPABASE_URL/rest/v1/rpc/akis_sapma" "${AUTH[@]}"   -d '{"p_gun":"2026-01-02"}')
[[ "$HTTP" == "401" || "$HTTP" == "403" || "$HTTP" == "404" ]] || { echo "akis_sapma istemciye acik: HTTP $HTTP"; exit 1; }

echo "== 7) Temizlik"
curl -sS -f -X DELETE "$SUPABASE_URL/rest/v1/assets?id=eq.$ASSET_ID" "${AUTH[@]}" >/dev/null
curl -sS -f -X DELETE "$SUPABASE_URL/rest/v1/user_push_tokens?device_id=eq.duman-cihaz-$$" "${AUTH[@]}" >/dev/null

echo "OK — başsız duman testi geçti"
