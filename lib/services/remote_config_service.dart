import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import '../models/asset_type.dart';
import 'crash_reporter.dart';
import 'sunucu_secimi.dart';

/// Firebase Remote Config wrapper.
///
/// Server-side kontrol edilebilir feature flag'ler için tek merkez. Firebase
/// init başarısız olursa (config eksik / offline) default değerlerle no-op
/// çalışır — çağıran kodun try/catch ile sarmalanmasına gerek yok.
///
/// Kullanım:
///   RemoteConfigService.instance.premiumEnabled → bool
///   RemoteConfigService.instance.freeAssetLimit → int
///
/// Değer güncellemeleri fetch-and-activate ile alınır. `init` çağrısı fetch
/// tetikler; sonrasında değişiklikler bir sonraki uygulama açılışında (veya
/// TTL dolduğunda arka planda) yansır.
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  FirebaseRemoteConfig? _rc;
  bool _initialized = false;

  // ── Default değerler ─────────────────────────────────────────────────────
  // Firebase Console'dan override edilene kadar bu değerler geçerli.
  static const _defaults = <String, dynamic>{
    // Master kill switch: kullanıcının göreceği TÜM üyelik/ödeme ekranları,
    // banner, chip, kilit overlay, paywall trigger'ları buna bağlı. false ise
    // premium sistem uygulamada hiç yokmuş gibi davranır. RevenueCat entegrasyonu
    // + store onayları tamamlanana kadar kapalı tutulur.
    'paywall_enabled': false,

    // Premium feature kill switch: paywall açık olsa bile emergency rollback
    // için premium özellikleri kapatabilir.
    'premium_enabled': true,

    // Free tier varlık limiti. 20 → 7 (yasin, 2026-10-08: "ilk varlık
    // eklemeyi 7 varlık yapalım … premium istemeli"): 8. varlık paywall'u
    // açar. Yalnız `paywall_enabled` açıkken; var olan varlıklar silinmez,
    // yalnız YENİ ekleme durur.
    'free_asset_limit': 7,

    // Takip listesi limiti. Portföy limitinden AYRI ve paywall kapalıyken
    // de geçerli (kullanıcı kararı 2026-09-25: "şimdilik 7, ilerde paywall'la
    // artırılır"). Sunucuya yazılmadan önce istemcide kontrol edilir.
    // Paywall KAPALIYKEN okunan ürün sınırı budur ve 7 kalır: canlıdaki
    // kullanıcının listesi daralmaz (ana kural).
    'free_watchlist_limit': 7,

    // Paywall AÇIKKEN Premium olmayanın takip sınırı (yasin, 2026-10-08:
    // "takip listesini 3 yapalım"). Ayrı anahtar: eski build'ler
    // `free_watchlist_limit`'i paywall'dan bağımsız okur; o değeri 3'e
    // çekmek canlıdaki herkesin listesini kısardı. Var olan takipler
    // silinmez, yalnız yeni ekleme durur.
    'paywall_watchlist_limit': 3,

    // NOT: `paywall_variant` kaldırıldı (2026-10-04, sadeleştirme C) — hiçbir
    // kod okumuyordu; paywall tek tasarımla çiziliyor. A/B testi yazılınca
    // bayrak getter'ıyla birlikte geri eklenir.

    // Aylık fiyat gösterimi (paywall'da lokalize göstermek için).
    'premium_price_monthly': '49₺/ay',
    // 349 → 399 (yasin, 2026-10-05): yıllıkta KDV + mağaza sonrası aya
    // 20,6 ₺ kalıyordu; hesap /mnt/project-files/balina/premium_fiyat_hesabi_2026-10-05.md.
    'premium_price_yearly': '399₺/yıl',

    // Ücretsiz sürümde tür başına günde en fazla kaç sinyal bildirimi
    // (Premium planı, 2026-10-08). Yalnız `paywall_enabled` açıkken ve
    // Premium olmayana uygulanır; sığmayan sıklık "günde 1 kez"e, seçilen
    // ilk saate iner (`slotaSigdir`). 2026-10-04'te okuyan yokken
    // kaldırılmıştı, kapıyla geri geldi. Sunucudaki karşılığı
    // `SINYAL_UCRETSIZ_SLOT` secret'ı: ikisi paywall'la birlikte açılır.
    'free_signal_slots_per_day': 1,

    // Ücretsiz sürümde sinyal bildiriminin açık olduğu varlık sayısı (yasin,
    // 2026-10-08: "sinyal 1 varlıkta ücretsiz, 2. varlık Premium"). 0 =
    // kapı yok. Bugün yalnız 0/1 anlamlı: seçim tablosu tek satır tutar
    // (`sinyal_varlik_secimi`, 0126). Yalnız `paywall_enabled` açıkken;
    // sunucudaki karşılığı `SINYAL_UCRETSIZ_VARLIK` secret'ı.
    'free_signal_assets': 1,

    // Ücretsiz sürümde Karşılaştır grafiğindeki seri sayısı (Premium planı
    // "1 seri ücretsiz" = kendi serisine EK bir kıyas, toplam 2). Premium
    // eskisi gibi 5 (renk paleti beşte bitiyor). Yalnız paywall açıkken.
    'free_compare_series': 2,

    // Ücretsiz sürümde en fazla kaç ortaklık (yasin kararı 2026-10-08:
    // "1 ortak"). Yalnız paywall açıkken; var olan ortaklıklar korunur,
    // sınır yalnız YENİ ortak eklemeyi (kod üret / kod gir / daveti kabul)
    // durdurur. Gizlenmiş ortak da sayılır: gizlemek ortaklığı bitirmez.
    'free_partner_limit': 1,

    // NOT: `free_ai_report_enabled` kaldırıldı — AI portföy raporunun hiçbir
    // implementasyonu yoktu, flag var olmayan bir özelliği gate'liyordu.
    // Özellik yazıldığında flag'i geri ekle.

    // NOT: `deposits_enabled` kaldırıldı (2026-09-14) — vadeli mevduat
    // özelliği koddan tamamen çıkarıldı; flag'in gate'leyeceği bir şey yok.

    // ── Tutundurma (Sprint 1) ────────────────────────────────────────────
    // TestFlight'ta görünür olmaları için AÇIK doğuyorlar (2026-09-07,
    // kullanıcı kararı). Önceki hâl: hepsi kapalıydı ve Sprint 0'ın taban
    // çizgisi birikene kadar Firebase Console'dan açılmaları bekleniyordu.
    //
    // ⚠️ Bunun BEDELİ: bu değerler `setDefaults` ile yükleniyor, yani Firebase
    // Console'da o anahtar tanımlı DEĞİLSE varsayılan kazanır. Artık bir
    // özelliği geri kapatmanın iki yolu var — Console'a anahtarı `false`
    // olarak eklemek (uygulama yeniden yayımlanmadan çalışır, tercih edilen)
    // ya da yeni sürüm çıkmak. Uzaktan kapatma yeteneği KAYBOLMADI, ama
    // artık Console'da anahtarın var olmasına bağlı.
    //
    // ⚠️ A/B ölçümü: kapalı/açık kollarının karşılaştırması için "öncesi"
    // verisi gerekiyordu; hepsi birden açıldığı için Sprint 1'in etkisi
    // taban çizgisine karşı ölçülemeyecek.

    // Küresel yarış (haftanın/ayın portföyleri): 2026-09-21'de havuz 3
    // kişiyken parametrik KAPATILMIŞTI ("N kişi katıldı" yanlış anlaşılıyor).
    // 2026-09-28 kullanıcı kararı: AÇIK — özellik ortaktan bağımsız, kendi
    // sayfası (LeaderboardScreen) ortak şartı olmadan ulaşılabilir. Havuz
    // dolana kadar sıralama yerine "yeterli katılımcı olunca" metni çıkar;
    // k-anonimlik eşiği (k_min=8) sunucuda, bayrak onu gevşetmez.
    // Console'da parametre tanımlıysa o değer bu varsayılanı EZER —
    // YAPMAN_GEREKENLER'de kayıtlı.
    'global_leaderboard_enabled': true,
    // Ana ekranda anonim yüzdelik dilim şeridi: yalnızca yarış opt-in'i
    // açık kullanıcıya. "N kişi" sayısı sorunu bu şeritteydi; havuz dolana
    // kadar KAPALI kalır (küresel bayraktan bağımsız karar).
    'percentile_strip_enabled': false,

    // İlk varlık eklendikten sonra ana ekran widget'ı önerisi.
    'widget_prompt_enabled': true,

    // Bildirim izni ne zaman istensin?
    // false → eski davranış: ana ekran açıldıktan 2 sn sonra.
    // true  → ilk varlık eklendikten sonra ("ASELS hareket ederse haber
    //         verelim mi?"). Bağlamlı istemin kabul oranını yükseltmesi
    //         beklenir; iki kol `prompt_context` ile ayrışır.
    'push_prompt_after_first_asset': true,

    // Reel getiri (TÜFE) rozeti. `inflation_index` tablosu boşken zaten
    // hiçbir şey çizilmez — bayrak açık olsa bile tablo doldurulmadan rozet
    // GÖRÜNMEZ. Bu bir hata değil, kasıtlı: doğrulanmamış bir TÜFE değeri
    // finansal hesabı yanlış gösterirdi (bkz. YAPMAN_GEREKENLER.md).
    'real_return_enabled': true,

    // Free tier fiyat alarmı limiti. Alarm kullanıcının KENDİ istediği
    // bildirim olduğu için cömert bir sınır: 3 alarm gündelik kullanımı
    // karşılar, üstü premium için doğal bir kanca.
    'free_price_alert_limit': 3,

    // Kilometre taşı kutlamaları. Ayda en fazla bir kutlama yapılır;
    // bayrak, tonun kullanıcıda karşılık bulup bulmadığını ölçmek için.
    'milestones_enabled': true,

    // Yıllık "sandık Özeti". Diğer tutundurma bayrakları gibi AÇIK doğar
    // ama asıl kapı bayrak değil TAKVİM: ekran yalnızca 26 Aralık–10 Ocak
    // penceresinde ve anlamlı veri varken görünür
    // (bkz. RecapService.isYearlyWindow).
    'recap_enabled': true,

    // Dönem Özeti (Performans → Özet sekmesi) ve ana ekrandaki "Bu hafta"
    // kartı. TAMAMEN ÜCRETSİZ — paywall'a bağlı değil.
    //
    // Bayrak asıl olarak ana ekran kartı için var: Performans ekranındaki
    // sekme zaten kullanıcının bilinçli olarak girdiği bir yer, ama ana
    // ekrana eklenen her satır dikkat bütçesinden yiyor ve geri alınabilir
    // olması gerekiyor.
    'period_summary_enabled': true,

    // Mağaza değerlendirme istemi (`ReviewPromptService`). Kapatınca hiçbir
    // mutlu anda sorulmaz; Ayarlar'daki elle satır bayraktan bağımsızdır.
    'review_prompt_enabled': true,

    // Ön soru ("sandık'ı seviyor musun?") gösterilsin mi. Google Play
    // tasarım kılavuzu sistem kartından ÖNCE soru sormamayı önerir; mağaza
    // incelemesinde takılırsa bayrak kapatılır ve doğrudan sistem kartı
    // istenir — yayın beklemeden, aynı gün.
    'review_prompt_soft_gate': true,

    // ── Köprü sürümü (K1, 2026-09-27) ────────────────────────────────────
    // Hangi Supabase projesi: 'tokyo' | 'frankfurt'. Geçiş gecesi Console'da
    // çevrilir; açık uygulamalar gerçek zamanlı dinleyiciyle saniyeler içinde
    // "kapatıp aç" ekranına düşer. Karar `SunucuSecimi`'nde.
    SunucuSecimi.anahtar: 'tokyo',
    // Zorunlu güncelleme kapısı: bu build'in altındakiler "Güncelle"
    // ekranında kalır. 0 = kapı kapalı. Android versionCode / iOS build.
    SunucuSecimi.minBuildAndroid: 0,
    SunucuSecimi.minBuildIos: 0,

    // ── Büyüme özellikleri (docs/BUYUME_OZELLIKLERI_TEKNIK_PLAN_2026_09.md) ──
    // AÇIK doğar (2026-09-30, kullanıcı kararı: "hepsini çalışacak şekilde
    // ayarla" — özellikler TestFlight'ta çalışmalı). Önceki hâl `kDebugMode`:
    // release derlemesi olan TestFlight'ta kapalıydı, Console'dan açılmaları
    // bekleniyordu. 2026-09-07 tutundurma kararıyla aynı desen ve aynı
    // BEDEL (yukarıdaki not): kapatmak için Console'a anahtarı `false`
    // olarak eklemek gerekir — yayın gerekmez.
    'demo_mode_enabled': true,
    'lock_offer_after_first_asset': true,
    'fund_report_card_enabled': true,
    'dividend_capture_enabled': true,
    'ipo_calendar_enabled': true,
    // Temettü önerisinde stopaj oranı (0..1). -1 = bilinmiyor: öneri BRÜT
    // gösterir, net tutarı kullanıcı girer (uydurma oran yazılmaz).
    //
    // 0.15 (karar 8.1, 2026-09-30): kâr payı stopajı 22.12.2024'ten beri
    // %15 — 9286 sayılı Cumhurbaşkanı Kararı, Resmî Gazete 32760. Bu
    // uydurma değil, kaynaklı mevzuat değeri; mevzuat değişirse Console'a
    // yeni değer (yayın gerekmez) ve bu satır birlikte güncellenir.
    'temettu_stopaj_orani': 0.15,

    // Kilit ekranı (Live Activity) uygulama KAPALIYKEN de dakikada bir
    // Performans GÜNLÜK ile aynı rakamı göstersin (2026-10-03, kullanıcı
    // kararı: "canlı aktiviteler her zaman 1 dk'da bir performans günlükle
    // eş olmalı"). Açıkken istemci özetle birlikte bir tarif yazar
    // (`CanliEtkinlikTarifi`), sunucu onu canlı kotasyonla ileri taşır.
    // KAPALI doğar (CLAUDE.md "riskli yeni davranış bayrakla açılır"):
    // sunucu fonksiyonu ve dakikalık cron canlıya çıktıktan sonra Console'da
    // açılır; kapalıyken kilit ekranı birebir eski davranışta kalır.
    'canli_etkinlik_dakikalik': false,

    // GÜNLÜK grafikte altın/dövizin şekli, uluslararası seri sustuğunda
    // (hafta sonu) sunucunun yurt içi kotasyon kaydından çizilsin
    // (2026-10-03, kullanıcı: "fiyat tutarlı ve doğru şeyi göstermeli").
    // KAPALI doğar: `yurt-ici-kotasyon` fonksiyonu ve 0101 cron'u canlıda
    // en az bir hafta sonu kayıt biriktirdikten sonra Console'da açılır.
    // Kapalıyken GÜNLÜK birebir eski davranışta (hafta sonu düz) kalır.
    'hafta_sonu_yurt_ici_seri': false,

    // Fon sayfasında "Para akışı" kartı ve büyük giriş/çıkış olayları
    // (Balina B1, 2026-10-04). KAPALI doğar: veri `akis-gozlem` fonksiyonu
    // ve 0106 cron'u iki sunucuda koşup pencereyi doldurduktan sonra gelir;
    // tablo boşken kart zaten çizilmez ama bayrak, dağıtım sırasını
    // uygulama sürümünden bağımsız kılar. Kapalıyken hiçbir istek atılmaz.
    'balina_radari_acik': false,

    // Dövizli satışta ele geçen tutar SATIŞ GÜNÜNÜN kuruyla TL'ye çevrilsin
    // (2026-10-05, kullanıcı onayı). Eskiden alım kuruyla çevriliyordu:
    // dolar varlığın kur kazancı gerçekleşen kâra ve nakit akışına girmiyordu.
    // KAPALI doğar: açıkken yeni satış satırı `sell_fx_rate` (0111) yazar —
    // sütun iki sunucuya ulaşmadan açılırsa PostgREST satışı reddeder
    // (PGRST204). Önce migration, sonra Console. Kapalıyken satış birebir
    // eski; geçmiş satırlar hiçbir zaman değişmez (kur bilinmiyor).
    'satis_gunu_kuru': false,

    // Aylık birikim serisi (2026-10-05, yasin kararları: aylık ritim, son 12
    // ayda 1 mola, BES dahil). Özet › Birikim disiplini kartına seri satırı
    // ve 12 aylık şerit, `contribution_streak` kilometre taşı. KAPALI doğar:
    // ana yüzeyde yeni bilgi; önce yasin'in cihazında açılır. Sunucu
    // değişikliği yok — kapalıyken kart ve kutlamalar birebir eski.
    'birikim_serisi': false,

    // Eurobond varlık türü (2026-10-08, yasin: "varlık tiplerimize eurobond
    // … eklemeliyiz"). Varlık Ekle çipi, sinyal ayarı ve filtrelerdeki tür
    // seçeneği buna bağlı. KAPALI doğar: fiyat tablosu (0124) iki sunucuya
    // dağıtılıp eurobond-fiyat ilk turunu atmadan açılırsa eklenen lot
    // fiyatsız kalır. Kapalıyken ekranlar birebir eski; kayıtlı eurobond
    // lotu (bayrak açıkken eklenmiş) yine görünür ve fiyatlanır.
    'eurobond': false,

    // Kayıt hunisi birinci taraf ölçümü (0097, PR #69; yasin 2026-10-08).
    // 0097 iki sunucuda canlı ama istemci main'e hiç girmemişti. KAPALI
    // doğar: kapalıyken `HuniKaydi` yalnız cihazda kurulum kimliği ve
    // bekleyen adım kuyruğu tutar, ağa hiç çıkmaz (`huni_kaydet` çağrılmaz).
    // Açılınca kuyruk sırayla gönderilir — kapalıyken biriken adımlar
    // (tavan 30) kaybolmaz. Firebase `signup_step` (F11) bundan bağımsız.
    'kayit_hunisi': false,

    // Portföy satırından varlık ekranına başlık uçuşu (yol haritası 2.14,
    // yasin 2026-10-08: "bunları sen yapamıyor musun"). KAPALI doğar: uçuş
    // iki farklı yazı boyutu arasında ölçekleniyor ve cihazda görülmedi
    // (bulutta emülatör yok). Kapalıyken `Hero` kurulmaz, geçiş birebir
    // eski. Gerekçe `varlik_baslik_hero.dart`.
    'varlik_hero_gecisi': false,

    // Sadeleştirme 2 (2026-10-08, yasin: "featureları koruyarak karmaşıklığı
    // düşür", hepsi bayrak altında; plan artifact'ı "sandık Sade Ekran
    // Planı"). Yedisi de KAPALI doğar ve kapalıyken ilgili ekran birebir
    // eski; sunucu değişikliği yok. Önce yasin'in TestFlight cihazında açılır.
    //
    // S1 — tek dönem hafızası: Performans, varlık detayı/sayfası, Takip
    // listesi ve Karşılaştır aynı seçili dönemi paylaşır (bugün dördünün
    // varsayılanı farklı: Bugün / 1 hf / 1 ay / 3 ay → sayılar "tutmuyor").
    'donem_hafizasi': false,
    // S2 — Performans tek akış: Grafik | Özet sekmesi kalkar, ikisi tek
    // kaydırmada; kontrol satırı 3 → 1 (dönem + Filtre).
    'performans_tek_akis': false,
    // S3 — Portföy: büyük halka yerine küçük halka + lejant (yasin'in
    // seçimi "C", 2026-10-08; ilk ekranda daha çok varlık, vitrin hissi
    // kalır). Ad tarihî: ilk taslak çubuktu, anahtar Console'da aynı kalsın.
    // Büyük halka küçüğe dokununca açılır.
    'portfoy_dagilim_cubugu': false,
    // S4 — varlık detayı katmanlı sıra: fiyat+grafik → pozisyonun → analiz
    // (katlı) → geçmiş ve belgeler.
    'varlik_detay_katmanli': false,
    // S5 — sinyal ayarları önce ön ayar (Az / Dengeli / Çok), ayrıntı katlı.
    'sinyal_on_ayar': false,
    // S6 — Performans başlığında "Raporlar" kapısı (hafta özeti, aylık
    // rapor, yıl özeti, Sıralama).
    'raporlar_kapisi': false,
    // S7 — Ana ekranda genel arama (Yenile ikonunun yerine; varlık + eylem).
    'genel_arama': false,
    // Paywall yeniden tasarımı (yasin 2026-10-08): sandık başlığı + sonsuz
    // kart destesi; deste kullanıcının dokunduğu kilidin kartıyla açılır.
    // Kapalıyken eski paywall birebir.
    'paywall_deste': false,

    // Ekstre tanılama iskeleti (2026-10-05, yasin: "tüm banka ve aracı
    // kurumları kapsamalıyız"). Motor bir ekstreyi tam anlayamadığında eşleme
    // kartında "Tanılama metnini kopyala" çıkar: tablo düzeni korunur, ad/
    // rakam maskelenir (`ekstreIskeleti`), kullanıcı kendisi gönderir. KAPALI
    // doğar: önce yasin'in cihazında; kapalıyken kart birebir eski.
    'ekstre_tanilama': false,

    // Ekstre hesap hareketlerinden gerçek alış tarihi/fiyatı (2026-10-05,
    // yasin: "bunun içinden varlık alım satımları nasıl ayıklarsın").
    // Varlık satırı dönem içindeki alışlara bölünür; maliyet ekstre günü
    // fiyatı yerine gerçek alış fiyatı olur (`hareket_tablosu.dart`). KAPALI
    // doğar: içe aktarılan maliyeti değiştirir; kapalıyken çıktı birebir eski.
    'ekstre_hareketleri': false,

    // Ekstre AI sütun eşleme (2026-10-05, yasin kararı: "AI sütun eşleme").
    // Okuyucu emin değilken kartta "Yapay zekâyla eşle": anonim iskelet
    // `ekstre-esle` (0121) üzerinden Claude'a gider, yalnız sütun numaraları
    // döner. KAPALI doğar: önce 0121 + fonksiyon iki sunucuya, Gizlilik 1.6
    // (0122) yayına; sonra açılır. Kapalıyken hiçbir istek atılmaz.
    'ekstre_ai_esleme': false,

    // ABD hissesi (2026-10-08). Hisse türünde "BIST | ABD" seçimi, ABD
    // kataloğu (`abd_hisseleri.dart`) ve aramada ABD sonuçları. Veri yeni
    // tür DEĞİL: `type='hisse'`, `sub_category='abd'`, `currency='USD'`,
    // sembol Yahoo'nunki (AAPL, BRK-B). Eski sürümler `.IS` olmayan USD
    // hisseyi zaten Yahoo + USDTRY ile fiyatlıyor; yeni enum değeri eski
    // build'de "Diğer"e düşer, tam satır yazımı türü ezerdi. KAPALI doğar:
    // kapalıyken form, arama ve rozetler birebir eski.
    'abd_hisse': false,

    // Varlık ekranında "Masraflar" kartı (2026-10-08, kullanıcı: "her
    // varlık türü için detaycı olmalıyız, kendine has masraflarını ekranda
    // gösterebilmeliyiz"). Tutar yalnız kayıtlı komisyondan ya da resmî
    // orandan (`varlik_masraflari.dart`); aracı kurum makası uydurulmaz.
    // KAPALI doğar: ana yüzeyde yeni kart; kapalıyken ekran birebir eski.
    'varlik_masraflari': false,

    // Varlık Ekle tür seçicisi: arama + gruplu ızgara (2026-10-08, yasin:
    // "göz alıcı ama işlevsel" tür seçici). Tür sayısı 11'e çıktı (ABD,
    // eurobond); çip yığını sayfanın ilk sorusunu kalabalıklaştırıyordu.
    // Açıkken üstte arama (THYAO/Apple/BTC/ISIN → tür + kimlik tek dokunuşta),
    // altında üç gruplu 4 sütunlu ızgara; seçimden sonra tek satıra katlanır.
    // KAPALI doğar: formun ilk sorusu; kapalıyken çip `Wrap`'ı birebir eski.
    'tur_secici_izgara': false,

    // Göz alıcılık (2026-10-09, yasin: "uygulamayı göz alıcı hale
    // getirelim, fonksiyonelitesinden hiçbir şey kaybetmeden"; rapor
    // https://claude.ai/artifact/8Wuo6BMHugYnb2Z6LbC5RU). TEK bayrak, bütün
    // paketler (A, B, C…) bunun arkasına girer — yasin: "aşırı fazla flag
    // olmasın, yönetimi karmaşıklaşıyor". Paket A:
    //  · satır rozeti: hisse/fon/kripto satırında tür ikonu yerine sembolün
    //    kendisi (ASE, DLY, BTC) tür renginde (`varlik_monogrami.dart`);
    //  · akan rakam: büyük fiyat değişince yalnız değişen hane döner, ₺ ve
    //    kuruş geri çekilir (`para_metni.dart`). Ana ekran toplam kartına
    //    DOKUNMAZ (yasin: "ana sayfa toplam kartına çok dokunma").
    // KAPALI doğar: ana yüzeylerin görünüşü; kapalıyken birebir eski.
    'goz_alici': false,

    // ── Sadeleştirme (2026-10-04) — bayraklar KALDIRILDI (2026-10-05) ────
    // 2026-10-04'te "bugün yapılan tüm geliştirmeler için flagleri açık
    // olarak mergele maine" kararıyla AÇIK doğan 15 bayrak 2026-10-05'te
    // (kullanıcı kararı: "önerilerin hepsini uygula") koddan çıkarıldı;
    // açık davranış KALICI, kapalı (eski) yollar silindi. Bedeli: bunlar
    // artık Console'dan kapatılamaz — geri almak yeni sürüm ister. Anahtar
    // Console'da tanımlıysa artık hiçbir kod okumaz (zararsız).
    // `remote_config_defaults_test` bu anahtarların geri gelmesini kilitler.
    //
    // Her birinin kalıcı davranışı ve gerekçesi kendi yerinde:
    //   · karsilama_tanitimi  → girişten önce tanıtım (`KarsilamaScreen`,
    //     `_AuthGate`), giriş ekranında Apple/Google üstte + demo düğmesi.
    //   · seviye_anketi       → sade Başlangıç (`seviyeGorunurlugu`), turda
    //     ve Ayarlar'da 3 soruluk anket (`SeviyeAnketi`), zil her seviyede.
    //   · ilk_varlik_kolay    → boş ana ekranda vitrin
    //     (`IlkVarlikVitrini`), Varlık Ekle'de iki hızlı yol + "Ayrıntı ekle".
    //   · varlik_islem_cubugu → varlık ekranında Al · Sat · Temettü çubuğu
    //     ve dönem yüzdesinin tek yerde kalması.
    //   · tek_kiyas_yuzeyi    → varlık ekranının kıyası Karşılaştır'da.
    //   · tek_onay_kutusu     → kayıtta ve yeniden onay kapısında tek kutu
    //     (avukat görüşü YAPMAN_GEREKENLER "Sadeleştirme 2. parti").
    //   · yasal_onay_kaydi    → onaylar `yasal_onay_kaydet` (0102) ile yazılır.
    //   · yasal_kapi_en_yeni  → girişte yeniden onay kapısı, en yeni sürüm.
    //     Eski anahtar `yeniden_onay_kapisi` Console'da KALICI `false`
    //     kalır: o anahtarı okuyan eski sürümlerin kapısı açılmasın.
    //   · zorunlu_okuma       → onay metinleri tam, sona kadar okunur.
    //   · tek_ortak_secici    → tek `OrtakSecici` kabuğu (`SandikSegment`).
    //   · bugun_karti_kiyas   → Bugün kartı "H · enflasyon kıyası öne".
    //   · siralama_tek_sayfa  → Yarış + Zirve tek `SiralamaScreen`.
    //   · performans_ayar_sade → grafik tipi Çizgi/Mum, "Bugünkü portföyle"
    //     Ayarlar › Görünüm'de, Ayarlar gruplu + katlanır "Gelişmiş".
    //   · yaris_duello_arena  → iki kişilik yarışta düello arenası.
    //   · ortak_secimi_tasi   → karttan açılan ekran kartın ortak seçimiyle.
  };

  /// Yerel deneme anahtarı: `--dart-define=RC_ACIK=a,b` ile verilen bayraklar
  /// Firebase'e dokunmadan açılır. Yalnız debug/profile derlemede okunur;
  /// release'de (mağaza, TestFlight) HİÇ etkisi yok, uzak değer tek kaynak.
  /// Neden: bayrak arkasındaki ekranı emülatörde görmek için Console'da kendi
  /// cihazına koşul yazmak gerekiyordu; emülatörün Firebase kimliği her
  /// sıfırlamada değişiyor. (2026-10-05: 15 sadeleştirme bayrağı kalkınca bu
  /// altyapı da kalkmıştı; `balina_radari_acik` kullandığı için geri geldi.
  /// Eski 15 bayrağa özgü `testKapali` kancası geri gelmedi.)
  static const _yerelAcikHam = String.fromEnvironment('RC_ACIK');
  static final Set<String> _yerelAcik = kReleaseMode || _yerelAcikHam.isEmpty
      ? const {}
      : _yerelAcikHam.split(',').map((e) => e.trim()).toSet();

  /// Widget testinde bayrak açmak için (Firebase testte ayağa kalkmaz).
  @visibleForTesting
  static Set<String> testAcik = {};

  /// Admin hesabı mı (`push_admins`). Uygulama kökü (`_AuthGate`)
  /// `isPushAdminProvider`'dan yazar; provider'ı olmayan yerler
  /// (bildirim yönlendirmesi) buradan okur. Oturum yokken false.
  bool yonetici = false;

  /// Premium'a özgü özellikler (Balina Radarı ve ekstre AI eşleme)
  /// görünür mü. TEK anahtar `paywall_enabled` (yasin 2026-10-09: "Tek
  /// flag"; "adminde hepsi açık olmalı, geri kalan userlar için paywall
  /// gerektiren işlemleri kapatabiliriz"). Ödeme hazır olmadan bu
  /// özellikler herkese ücretsiz açılırsa sonra kilitlemek alınan şeyi
  /// geri almak olur; bu yüzden paywall kapalıyken yalnız admin görür.
  /// Eskiden beri ücretsiz olanlar (sınırsız varlık, sinyal sıklığı,
  /// göstergeler, 5 seri, ortaklar) bu kapıya bağlı DEĞİL: canlıdaki
  /// kullanıcının kullandığı şey elinden alınmaz.
  /// `balina_radari_acik` / `ekstre_ai_esleme` Console değerleri artık
  /// okunmaz (yalnız yerel `RC_ACIK` ve test kancası).
  bool get premiumOzellikleriGorunur => paywallEnabled || yonetici;

  bool _yerelVeyaTest(String anahtar) =>
      testAcik.contains(anahtar) || _yerelAcik.contains(anahtar);

  bool _bayrak(String anahtar) =>
      testAcik.contains(anahtar) ||
      _yerelAcik.contains(anahtar) ||
      (_rc?.getBool(anahtar) ?? _defaults[anahtar] as bool);

  /// Adıyla bayrak (sürüm notu maddesi gibi veri tarafından anılan
  /// bayraklar için). Varsayılanlarda olmayan ad → kapalı.
  bool bayrakAcik(String anahtar) =>
      _defaults[anahtar] is bool && _bayrak(anahtar);

  Future<void> init() async {
    if (_initialized) return;
    try {
      _rc = FirebaseRemoteConfig.instance;
      await _rc!.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // Debug'da hemen; prod'da 15 dk. Eskiden 1 saatti. Köprü sürümünde
        // (K1) bu aralık, geçiş gecesi gerçek zamanlı bildirimi KAÇIRAN açık
        // bir uygulamanın dondurulmuş Tokyo'da en fazla ne kadar kalacağıdır
        // (ön plana dönüşte `refresh()`). 2026-09-27 emülatör denemesinde
        // gerçek zamanlı yol ulaşmadı; soğuk açılış yolu ~5 sn'de çalıştı.
        // 15 dk RC kotasının çok altında (istemci başına saatte 4 fetch).
        minimumFetchInterval:
            kDebugMode ? Duration.zero : const Duration(minutes: 15),
      ));
      await _rc!.setDefaults(_defaults);
      // Fetch başlat ama beklet — offline'da default'lar geçerli olur.
      // Bitince sunucu/güncelleme kararı yeniden değerlendirilir.
      CrashReporter.arkaPlan(
        _rc!.fetchAndActivate().then((_) => _sunucuyaBildir()),
        reason: 'remote_config_service.fetchAndActivate',
      );
      // Gerçek zamanlı güncelleme: geçiş gecesi bayrak çevrildiğinde AÇIK
      // uygulamalar saatlik fetch'i beklemez. Dinleyici değişen anahtarları
      // bildirir ama ETKİNLEŞTİRMEZ — activate şart.
      _rc!.onConfigUpdated.listen(
        (_) async {
          // `onError` yalnızca akışın hatasını alır, bu async gövdenin
          // fırlattığını değil — activate düşerse zone'a ÇÖKME olarak
          // giderdi. Etkinleşmeyen değer saatlik fetch'te yine gelir.
          try {
            await _rc!.activate();
            _sunucuyaBildir();
          } catch (e, st) {
            CrashReporter.report(e, st,
                reason: 'remote_config_service.onConfigUpdated.activate');
          }
        },
        onError: (Object e, StackTrace st) => CrashReporter.report(e, st,
            reason: 'remote_config_service.onConfigUpdated'),
      );
      _initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('RemoteConfigService init failed: $e');
    }
  }

  /// Uygulama uzun süredir açıksa (bir gün, uçuş modundan çıkma, vs.)
  /// çağrılabilir. Foreground'a döndüğünde yenile.
  Future<void> refresh() async {
    if (_rc == null) return;
    try {
      await _rc!.fetchAndActivate();
      _sunucuyaBildir();
    } catch (_) {}
  }

  void _sunucuyaBildir() {
    final rc = _rc;
    if (rc == null) return;
    SunucuSecimi.instance.rcGuncellendi(
      istenen: rc.getString(SunucuSecimi.anahtar),
      minBuild: rc.getInt(SunucuSecimi.minBuildAnahtari),
    );
  }

  // ── Feature flag getter'ları ─────────────────────────────────────────────
  /// Kullanıcının göreceği tüm üyelik/ödeme UI'ları buna bağlı. false ise
  /// paywall, premium banner, kilit overlay, "Premium" chip'leri hiç render
  /// edilmez; add-asset limit'i devreye girmez. Store + RevenueCat hazır
  /// olunca Firebase Console'dan true'ya çekilecek.
  // `_bayrak` üstünden: yerel testte RC_ACIK ile açılabilsin (sunucu kapısı
  // açık bir yığında istemci kilidi kapalı kalınca not "açılamadı" diyordu).
  // Release'te `_yerelAcik` boş, davranış değişmez.
  bool get paywallEnabled => _bayrak('paywall_enabled');

  bool get premiumEnabled =>
      _rc?.getBool('premium_enabled') ?? _defaults['premium_enabled'] as bool;

  int get freeAssetLimit =>
      _rc?.getInt('free_asset_limit') ?? _defaults['free_asset_limit'] as int;

  int get freeSignalSlotsPerDay =>
      _rc?.getInt('free_signal_slots_per_day') ??
      _defaults['free_signal_slots_per_day'] as int;

  int get freeSignalAssets =>
      _rc?.getInt('free_signal_assets') ??
      _defaults['free_signal_assets'] as int;

  int get freeCompareSeries =>
      _rc?.getInt('free_compare_series') ??
      _defaults['free_compare_series'] as int;

  int get freePartnerLimit =>
      _rc?.getInt('free_partner_limit') ??
      _defaults['free_partner_limit'] as int;

  int get freeWatchlistLimit =>
      _rc?.getInt('free_watchlist_limit') ??
      _defaults['free_watchlist_limit'] as int;

  int get paywallWatchlistLimit =>
      _rc?.getInt('paywall_watchlist_limit') ??
      _defaults['paywall_watchlist_limit'] as int;

  String get premiumPriceMonthly =>
      _rc?.getString('premium_price_monthly') ??
      _defaults['premium_price_monthly'] as String;

  String get premiumPriceYearly =>
      _rc?.getString('premium_price_yearly') ??
      _defaults['premium_price_yearly'] as String;

  bool get percentileStripEnabled =>
      _rc?.getBool('percentile_strip_enabled') ??
      _defaults['percentile_strip_enabled'] as bool;

  /// Küresel sıralama (yüzdelik dilim, en çok kazandıranlar, solo panel,
  /// benchmark kartı). Ortaklar arası yarış bundan bağımsız.
  bool get globalLeaderboardEnabled =>
      _rc?.getBool('global_leaderboard_enabled') ??
      _defaults['global_leaderboard_enabled'] as bool;

  bool get widgetPromptEnabled =>
      _rc?.getBool('widget_prompt_enabled') ??
      _defaults['widget_prompt_enabled'] as bool;

  bool get pushPromptAfterFirstAsset =>
      _rc?.getBool('push_prompt_after_first_asset') ??
      _defaults['push_prompt_after_first_asset'] as bool;

  bool get realReturnEnabled =>
      _rc?.getBool('real_return_enabled') ??
      _defaults['real_return_enabled'] as bool;

  int get freePriceAlertLimit =>
      _rc?.getInt('free_price_alert_limit') ??
      _defaults['free_price_alert_limit'] as int;

  bool get milestonesEnabled =>
      _rc?.getBool('milestones_enabled') ??
      _defaults['milestones_enabled'] as bool;

  bool get recapEnabled =>
      _rc?.getBool('recap_enabled') ?? _defaults['recap_enabled'] as bool;

  bool get periodSummaryEnabled =>
      _rc?.getBool('period_summary_enabled') ??
      _defaults['period_summary_enabled'] as bool;

  bool get reviewPromptEnabled =>
      _rc?.getBool('review_prompt_enabled') ??
      _defaults['review_prompt_enabled'] as bool;

  bool get reviewPromptSoftGate =>
      _rc?.getBool('review_prompt_soft_gate') ??
      _defaults['review_prompt_soft_gate'] as bool;

  // ── Büyüme özellikleri ─────────────────────────────────────────────────
  bool get demoModeEnabled =>
      _rc?.getBool('demo_mode_enabled') ??
      _defaults['demo_mode_enabled'] as bool;

  bool get lockOfferAfterFirstAsset =>
      _rc?.getBool('lock_offer_after_first_asset') ??
      _defaults['lock_offer_after_first_asset'] as bool;

  bool get fundReportCardEnabled =>
      _rc?.getBool('fund_report_card_enabled') ??
      _defaults['fund_report_card_enabled'] as bool;

  bool get dividendCaptureEnabled =>
      _rc?.getBool('dividend_capture_enabled') ??
      _defaults['dividend_capture_enabled'] as bool;

  bool get ipoCalendarEnabled =>
      _rc?.getBool('ipo_calendar_enabled') ??
      _defaults['ipo_calendar_enabled'] as bool;

  /// Kilit ekranının uygulama kapalıyken dakikalık tazelenmesi — bkz.
  /// `_defaults['canli_etkinlik_dakikalik']`.
  bool get canliEtkinlikDakikalik =>
      _rc?.getBool('canli_etkinlik_dakikalik') ??
      _defaults['canli_etkinlik_dakikalik'] as bool;

  /// Hafta sonu GÜNLÜK şeklinin yurt içi kayıttan çizilmesi — bkz.
  /// `_defaults['hafta_sonu_yurt_ici_seri']`.
  bool get haftaSonuYurtIciSeri =>
      _rc?.getBool('hafta_sonu_yurt_ici_seri') ??
      _defaults['hafta_sonu_yurt_ici_seri'] as bool;

  /// Fon sayfasında para akışı kartı (0106). Gerekçe `_defaults`'ta.
  bool get balinaRadariAcik =>
      _yerelVeyaTest('balina_radari_acik') || premiumOzellikleriGorunur;

  /// Dövizli satışta satış günü kuru (0111). Gerekçe `_defaults`'ta.
  bool get satisGunuKuru => _bayrak('satis_gunu_kuru');

  /// Aylık birikim serisi. Gerekçe `_defaults`'ta.
  bool get birikimSerisi => _bayrak('birikim_serisi');

  /// Eurobond türü. Gerekçe `_defaults`'ta.
  bool get eurobond => _bayrak('eurobond');

  /// Kayıt hunisinin sunucuya gönderimi (0097). Gerekçe `_defaults`'ta.
  bool get kayitHunisi => _bayrak('kayit_hunisi');

  /// Tür SEÇENEK olarak sunulsun mu (ekleme çipi, filtre, sinyal ayarı)?
  ///
  /// Bayrağa bağlı türlerin tek kapısı: her yüzey kendi `if`'ini yazarsa
  /// biri unutulur ve bayrak kapalıyken tür sızar. Kayıtlı veriyi
  /// göstermek bu kapıya TAKILMAZ — kullanıcının varlığı gizlenmez.
  bool turSecenegi(AssetType t) => t != AssetType.eurobond || eurobond;

  /// Varlık başlığı uçuşu. Gerekçe `_defaults`'ta.
  bool get varlikHeroGecisi => _bayrak('varlik_hero_gecisi');

  /// Sadeleştirme 2 bayrakları. Gerekçeler `_defaults`'ta.
  bool get donemHafizasi => _bayrak('donem_hafizasi');
  bool get performansTekAkis => _bayrak('performans_tek_akis');
  bool get portfoyDagilimCubugu => _bayrak('portfoy_dagilim_cubugu');
  bool get varlikDetayKatmanli => _bayrak('varlik_detay_katmanli');
  bool get sinyalOnAyar => _bayrak('sinyal_on_ayar');
  bool get raporlarKapisi => _bayrak('raporlar_kapisi');
  bool get genelArama => _bayrak('genel_arama');

  /// Kart desteli paywall. Gerekçe `_defaults`'ta.
  bool get paywallDeste => _bayrak('paywall_deste');

  /// Ekstre tanılama iskeleti düğmesi. Gerekçe `_defaults`'ta.
  bool get ekstreTanilama => _bayrak('ekstre_tanilama');

  /// Ekstre hareketlerinden gerçek alış. Gerekçe `_defaults`'ta.
  bool get ekstreHareketleri => _bayrak('ekstre_hareketleri');

  /// Ekstre AI sütun eşleme. Gerekçe `_defaults`'ta.
  bool get ekstreAiEsleme =>
      _yerelVeyaTest('ekstre_ai_esleme') || premiumOzellikleriGorunur;

  /// ABD hissesi ekleme/arama. Gerekçe `_defaults`'ta.
  bool get abdHisse => _bayrak('abd_hisse');

  /// Varlık ekranında Masraflar kartı. Gerekçe `_defaults`'ta.
  bool get varlikMasraflari => _bayrak('varlik_masraflari');

  /// Varlık Ekle'de arama + gruplu tür ızgarası. Gerekçe `_defaults`'ta.
  bool get turSeciciIzgara => _bayrak('tur_secici_izgara');

  /// Göz alıcılık paketleri (tek bayrak). Gerekçe `_defaults`'ta.
  bool get gozAlici => _bayrak('goz_alici');

  /// Temettü stopaj oranı; `null` = bilinmiyor (öneri brüt kalır).
  double? get temettuStopajOrani {
    final v = _rc?.getDouble('temettu_stopaj_orani') ??
        _defaults['temettu_stopaj_orani'] as double;
    return (v >= 0 && v < 1) ? v : null;
  }
}
