# kripto-hacim-gozlem

Portföylerde tutulan **coinlerin** (`ticker` `KRIPTO:` önekli, `type = kripto`)
Binance USDT paritesindeki günlük mumlarını okur; işlem hacmini (USDT) ve
alıcı payını `kripto_hacim_gunluk`'a yazar, olağandışı hacim günlerini
`balina_olay`'a `kripto_hacim_yukselis` / `kripto_hacim_dusus` türüyle işler
(0107). İstemci kartı ("Alıcı baskısı") `balina_radari_acik` bayrağının
arkasında.

- Kaynak: Binance `/api/v3/klines`, `interval=1d&limit=90&timeZone=3` (gün
  İstanbul gece yarısında açılır); coin başına tek istek, 3'lü paralel.
- Alıcı payı = taker alış (quote) / toplam quote hacim. Bugünün yarım mumu
  yazılmaz.
- Olay kuralı hisse radarıyla aynı (`_shared/hacim.ts`): z ≥ 3 VE ortalamanın
  ≥ 2 katı; taban ≥ 10 mn USDT.
- **Sınır:** yalnız Binance, yalnız USDT paritesi; zincir üstü veri yok.
  USDT'nin kendisi ve USDT paritesi olmayan coin atlanır (`bos` sayacı).
  Tutarlar TL'ye çevrilmez; kart "$" ile yazar.
- Ölçüm (2026-10-05, 6 büyük coin, 40 gün): 9 olay.
- Saklama: 400 gün.
- Auth: `x-cron-secret` = `PRICE_ALERTS_CRON_SECRET` — paylaşılır, fail-closed.
- Gövde `{"dry_run": true}` → okur, yazmaz. Yanıt `{ok, sembol, satir, olay, bos}`.
- Testler: `tests/hacim_test.ts`, `test/hacim_radari_test.dart`,
  `tool/supabase_smoke.sh` 6d.
