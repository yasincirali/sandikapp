# akis-gozlem

TEFAS'taki **tüm yatırım ve emeklilik fonlarının** günlük pay adedini ve
toplam değerini okur, net para akışını hesaplayıp `fon_akis_gunluk`'a yazar;
kurala uyan günleri `balina_olay`'a işler (0106). Amaç: fon sayfasındaki
"Para akışı" kartı ve büyük giriş/çıkış listesi. İstemci tarafı Remote Config
`balina_radari_acik` bayrağının arkasında (varsayılan kapalı).

- Kaynak: `tefas.gov.tr/api/funds/fonBuyuklukBazliBilgiGetir` (gün başına 2
  istek: `YAT` + `EMK`, tarih `YYYYMMDD`) ve yalnız portföylerde tutulan
  fonlar için `fonBilgiGetir` (yatırımcı sayısı).
- Net akış = (pay − önceki günün payı) × (değer / pay). Önceki gün yoksa
  `NULL`; fiyat hareketi akış sayılmaz.
- Olay kuralı (`_shared/balina.ts`): |akış| ≥ max(4 × 90 günlük sapma,
  akıştan ÖNCEKİ fon büyüklüğünün %3'ü), fon ≥ ₺250 mn, en az 20 gözlem, para piyasası
  fonu değil (`fon_turu`). Sapma ve penceredeki en büyük akış
  `akis_sapma(p_gun)` RPC'sinden (yalnız service_role).
- Bildirim kademesi (`balina_olay.bildirime_deger`): ayrıca ≥ %5, ≥ ₺25 mn
  ve penceredeki en büyük akış. Bildirimi bu fonksiyon GÖNDERMEZ; bayrak
  olay akışı diliminde (B4) okunacak.
- Ölçüm (2026-10-04, 29 işlem günü): günde ~16 olay, 1.375 fonun 293'ünde en
  az bir olay; 275 olay bildirim kademesinde (203 fon). Eşiği değiştiren
  sıklığı yeniden ölçsün.
- Sıra eskiden yeniye; çekilemeyen günde tur durur (gün atlanmaz). Son iki
  gün her tur yeniden çekilir (TEFAS fon fon yayınlıyor), eskiler
  `fon_akis_tur.kesin` ile kilitlenir.
- İlk kurulum: 130 günlük pencere tur başına 14 günle dolar (~7 tur). Cron
  beklemeden doldurmak için `select public.trigger_akis_gozlem();` 90 sn
  arayla, yanıt `gun` küçülene kadar.
- Saklama: 400 gün; eski satırlar aynı turda silinir.
- Auth: `x-cron-secret` = `TEFAS_NAV_CRON_SECRET` (Vault:
  `tefas_nav_cron_secret`) — observe-tefas-nav ile paylaşılır, fail-closed.
- Gövde `{"dry_run": true}` → ilk günü okur, yazmaz.
- Yanıt `{ok, gun, satir, olay, yatirimci, kalan}`; hata ayrıntısı yalnız
  sunucu günlüğünde.
- Testler: `tests/balina_test.ts` (kural ve hesap), `tool/supabase_smoke.sh`
  6d (yetki sınırı).
