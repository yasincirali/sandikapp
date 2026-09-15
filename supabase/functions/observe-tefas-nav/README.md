# observe-tefas-nav

TEFAS fon NAV'ının **yayın anını gözlemler**. TEFAS yanıtı NAV'ın tarihini
taşır, yayımlandığı saati değil; uygulama fonun gün içi basamağını bu yüzden
sabit 10:00'a çapalıyordu. Bu fonksiyon iş günleri TR 06:00–21:30 arası yarım
saatte bir (pg_cron, `0063_tefas_nav_gozlem.sql`) portföylerdeki her fon kodu
için son NAV satırını çeker; daha önce görülmemiş bir (kod, NAV tarihi) çifti
ilk kez göründüğünde `tefas_nav_gozlem`'e `ilk_gorulme = now()` ile yazar.
İstemci (`HistoryService.fonBasamakAni`) basamağı o ana koyar; kayıt yoksa
10:00 aynen.

- Auth: `x-cron-secret` = `TEFAS_NAV_CRON_SECRET` (Vault: `tefas_nav_cron_secret`),
  fail-closed (bkz. `_shared/CRON_AUTH.md`).
- Maliyet: kod başına tek istek; bugün tarihli NAV'ı görülen kod o gün bir daha
  sorulmaz. Tur başına en çok 150 kod, 4'lü paralel, 10 sn zaman aşımı.
- Gövde `{"dry_run": true}` → sorar, yazmaz.
- Yanıt `{ok, checked, asked, sightings, skipped, bracketed}`; hata ayrıntısı
  yalnız sunucu günlüğünde.
- Saf yardımcılar `_shared/tefas_nav.ts`, testleri `tests/tefas_nav_test.ts`.
