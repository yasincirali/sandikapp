import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
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

    // Free tier varlık limiti. Launch'ta 20 ile başla, engagement düşükse
    // gerçek ürün konumlanmasına göre azalt.
    'free_asset_limit': 20,

    // Takip listesi limiti. Portföy limitinden AYRI ve paywall kapalıyken
    // de geçerli (kullanıcı kararı 2026-09-25: "şimdilik 7, ilerde paywall'la
    // artırılır"). Sunucuya yazılmadan önce istemcide kontrol edilir.
    'free_watchlist_limit': 7,

    // NOT: `paywall_variant` kaldırıldı (2026-10-04, sadeleştirme C) — hiçbir
    // kod okumuyordu; paywall tek tasarımla çiziliyor. A/B testi yazılınca
    // bayrak getter'ıyla birlikte geri eklenir.

    // Aylık fiyat gösterimi (paywall'da lokalize göstermek için).
    'premium_price_monthly': '49₺/ay',
    'premium_price_yearly': '349₺/yıl',

    // NOT: `free_signal_slots_per_day` kaldırıldı (2026-10-04, sadeleştirme
    // C) — ne istemci ne sunucu okuyordu; sinyal slot'u bugün herkese aynı.
    // Premium planı ücretsiz kullanıcıya slot kapısı koyacak: kapı yazılınca
    // bayrak (varsayılan 1 = yalnız sabah, Premium 2) geri eklenir.

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

  bool _bayrak(String anahtar) =>
      testAcik.contains(anahtar) ||
      _yerelAcik.contains(anahtar) ||
      (_rc?.getBool(anahtar) ?? _defaults[anahtar] as bool);

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
          await _rc!.activate();
          _sunucuyaBildir();
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
  bool get paywallEnabled =>
      _rc?.getBool('paywall_enabled') ?? _defaults['paywall_enabled'] as bool;

  bool get premiumEnabled =>
      _rc?.getBool('premium_enabled') ?? _defaults['premium_enabled'] as bool;

  int get freeAssetLimit =>
      _rc?.getInt('free_asset_limit') ?? _defaults['free_asset_limit'] as int;

  int get freeWatchlistLimit =>
      _rc?.getInt('free_watchlist_limit') ??
      _defaults['free_watchlist_limit'] as int;

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
  bool get balinaRadariAcik => _bayrak('balina_radari_acik');

  /// Dövizli satışta satış günü kuru (0111). Gerekçe `_defaults`'ta.
  bool get satisGunuKuru => _bayrak('satis_gunu_kuru');

  /// Temettü stopaj oranı; `null` = bilinmiyor (öneri brüt kalır).
  double? get temettuStopajOrani {
    final v = _rc?.getDouble('temettu_stopaj_orani') ??
        _defaults['temettu_stopaj_orani'] as double;
    return (v >= 0 && v < 1) ? v : null;
  }
}
