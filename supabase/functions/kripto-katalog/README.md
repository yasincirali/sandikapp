# kripto-katalog

İzlenebilir coin listesini (`kripto_varlik`) saatte bir yeniler. Tek kaynak
Binance.

- Evren: TRY paritesi olan her coin + USDT paritesinin 24 saatlik hacmine
  göre ilk 250 (`exchangeInfo` + `ticker/24hr`).
- Ad ve logo Binance'in herkese açık varlık listesinden (belgesiz `bapi`
  ucu). Gelmezse ad/logo alanları ezilmez; yeni satırda NULL kalır.
- Listeden düşen coin silinmez, `aktif = false` olur.
- Auth: `KRIPTO_CRON_SECRET` (kripto-fiyat ile ortak), fail-closed.
- Gövde `{"dry_run": true}` → hesaplar, yazmaz.
- Yanıt `{ok, toplam, try_paritesi, usdt_paritesi, adli}`.
