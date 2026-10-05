# hacim-gozlem

Portföylerde tutulan **BIST hisselerinin** (`ticker` `.IS` ile biten, `type =
hisse`) günlük kapanış ve hacmini Yahoo'dan okur, `hisse_hacim_gunluk`'a yazar;
olağandışı hacim günlerini `balina_olay`'a `hisse_hacim_yukselis` /
`hisse_hacim_dusus` türüyle işler (0107). İstemci kartı ("Hacim radarı")
Remote Config `balina_radari_acik` bayrağının arkasında.

- Kaynak: Yahoo `chart` ucu, `interval=1d&range=3mo`; sembol başına tek istek,
  4'lü paralel, tur başına en çok 200 sembol.
- Para hacmi = kapanış × işlem adedi (TL). Seansı bitmemiş günün barı
  (18:30 TR öncesi) yazılmaz.
- Olay kuralı (`_shared/hacim.ts`): önceki 20 işlem gününe göre z ≥ 3 VE
  ortalamanın ≥ 2 katı VE para hacmi ≥ ₺50 mn. Yön akış değil FİYAT yönü.
- **Sınır:** hacim kimin alıp sattığını söylemez; kart "balina" ve
  "giriş/çıkış" demez. Aracı kurum dağılımı lisans ister (B5).
- Ölçüm (2026-10-04, 15 büyük hisse, 40 gün): 10 olay (hisse başına ayda
  ~0,5).
- Okunan sembollerin penceredeki hisse olayları her tur silinip yeniden
  yazılır; okunamayan sembolün olaylarına dokunulmaz.
- Saklama: 400 gün.
- Auth: `x-cron-secret` = `PRICE_ALERTS_CRON_SECRET` (Vault:
  `price_alerts_cron_secret`) — check-price-alerts ile paylaşılır, fail-closed.
- Gövde `{"dry_run": true}` → okur, yazmaz.
- Yanıt `{ok, sembol, satir, olay, bos}`; `bos` = Yahoo'nun yanıt vermediği
  sembol sayısı.
- Testler: `tests/hacim_test.ts`, `test/hacim_radari_test.dart`,
  `tool/supabase_smoke.sh` 6d.
