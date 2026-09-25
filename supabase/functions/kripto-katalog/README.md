# kripto-katalog

İzlenebilir coin listesini (`kripto_varlik`) saatte bir yeniler.

- Evren: Binance'te TRY paritesi olan her coin + CoinGecko piyasa değerinde
  ilk 250 içinde olup USDT paritesi olanlar.
- Ad, logo, sıra CoinGecko `/coins/markets` (`COINGECKO_DEMO_KEY` varsa
  header'da). CoinGecko yanıtsızsa ad/logo alanları ezilmez.
- Listeden düşen coin silinmez, `aktif = false` olur.
- Auth: `KRIPTO_CRON_SECRET` (kripto-fiyat ile ortak), fail-closed.
- Gövde `{"dry_run": true}` → hesaplar, yazmaz.
- Yanıt `{ok, toplam, try_paritesi, usdt_paritesi, gecko}`.
