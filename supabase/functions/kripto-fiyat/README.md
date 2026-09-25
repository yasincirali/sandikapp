# kripto-fiyat

Katalogdaki (`kripto_varlik`, aktif) her coin'in **TL fiyatını ve İstanbul
gününün açılışını** dakikada bir `kripto_fiyat`'a yazar. Uygulama kripto
fiyatını yalnızca bu tablodan okur; sağlayıcıya giden istek sayısı kullanıcı
sayısından bağımsızdır.

- Kaynak: Binance `ticker/tradingDay` (`timeZone=3`), 100'lük parçalar.
  TRY paritesi doğrudan; yoksa `USDT paritesi × USDTTRY` (aynı borsa).
  Tek kaynak Binance: yanıt vermezse tur yazmaz (502), istemci satırın
  yaşından "gecikmeli" gösterir.
- Auth: `x-cron-secret` = `KRIPTO_CRON_SECRET` (Vault: `kripto_cron_secret`),
  fail-closed (bkz. `_shared/CRON_AUTH.md`).
- Bölge: cron `x-region: eu-central-1` ile çağırır (Binance ABD'ye 451).
- Gövde `{"dry_run": true}` → hesaplar, yazmaz.
- Yanıt `{ok, katalog, yazilan}`; hata ayrıntısı yalnız sunucu günlüğünde.
- Saf yardımcılar `_shared/kripto.ts`, testleri `tests/kripto_test.ts`.
