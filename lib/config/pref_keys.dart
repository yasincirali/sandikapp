/// SharedPreferences anahtarları — TEK KAYIT.
///
/// 2026-09 denetimi: `pref_signal_notifications` ve `pref_partner_notifications`
/// iki dosyada ayrı ayrı `const` tanımlıydı (`preferences_provider.dart` ve
/// `notification_service.dart`). İki özel sabit, tek string sözleşmesi: biri
/// yeniden adlandırılsa Ayarlar'daki anahtar bildirim yolundan sessizce
/// ayrışacaktı. Buradaki sabitler o sözleşmeyi tek yerde tutar.
///
/// Kapsam dışı ve BİLİNÇLİ olarak burada olmayanlar:
/// - `sandik_*` (home_widget_service): Kotlin/Swift widget koduyla paylaşılan
///   süreçler arası sözleşme; Dart tarafında yeniden adlandırılamaz.
/// - `retention_*` (retention_tracker): kendi içinde kapalı, tek dosya.
/// - Kullanıcı kimliğiyle sonek alan anahtarlar `preferences_provider.dart`
///   içindeki `_userKey()` ile üretilir; burada YALNIZCA taban adı durur.
class PrefKeys {
  PrefKeys._();

  static const themeMode = 'pref_theme_mode'; // 'system' | 'light' | 'dark'
  /// Arayüz dili — 'tr' | 'en' | 'system' (3.20). Cihaz tercihi, kişiye özel değil.
  static const locale = 'pref_locale';

  /// Uygulama içi yazı boyutu — `YaziBoyutu.index` (0 küçük, 1 normal,
  /// 2 büyük, 3 çok büyük). Cihaz tercihi: ekran/göz meselesi, hesaba değil.
  static const yaziBoyutu = 'pref_yazi_boyutu';
  static const signalNotifications = 'pref_signal_notifications';
  static const partnerNotifications = 'pref_partner_notifications';
  static const balanceHidden = 'pref_balance_hidden';

  /// Portföy listesi "Toplam | Bugün" modu (1 Kas 2026). Cihaz tercihi:
  /// bakış alışkanlığı, hesaba değil.
  static const portfoyBugunModu = 'pref_portfoy_bugun_modu';

  /// Toplam kartı kaydırma ipucu (tek seferlik göz kırpma) gösterildi mi.
  static const kaydirmaIpucu = 'pref_kaydirma_ipucu_gosterildi';

  /// Dik grafiğin altındaki "Detaylı grafik için telefonu yan çevir" ipucu
  /// artık gerekmiyor mu: kullanıcı yatay tam ekranı bir kez açtı
  /// (2026-10-29). Cihaz tercihi — jest cihaza ait.
  static const yatayGrafikIpucu = 'pref_yatay_grafik_ipucu_goruldu';
  static const lockScreenAmounts = 'pref_lockscreen_amounts';
  static const liveActivityStartMin = 'pref_live_activity_start_min';
  static const liveActivityEndMin = 'pref_live_activity_end_min';
  static const liveActivityWeekend = 'pref_live_activity_weekend';
  static const premiumUnlocked = 'pref_premium_unlocked';
  static const indicatorsByType = 'pref_indicators_by_type_v1';
  // Gösterge parametreleri (periyot vb.), tür başına JSON (2026-10-10; Premium).
  static const gostergeParametreleri = 'pref_gosterge_parametreleri_v1';
  static const chartOverlayMa20 = 'pref_chart_overlay_ma20';
  static const chartLogScale = 'pref_chart_log_scale';
  // EMA50/EMA200 ve mum (varlık detayı, 2026-10-10; Premium).
  static const chartEma50 = 'pref_chart_ema50';
  static const chartEma200 = 'pref_chart_ema200';
  static const chartCandle = 'pref_chart_candle';

  /// Yatay tam ekran grafikteki çizimler (trend, ışın, yatay, dikdörtgen),
  /// sembol başına JSON (2026-10-23). Cihazda kalır, hesaba yazılmaz:
  /// cihazlar arası eşitleme ayrı (Premium) adım.
  static const grafikCizimleri = 'pref_grafik_cizimleri_v1';

  /// Yatay çizgi → fiyat alarmı bağı (2026-10-29): `{çizimId: {a: alarmId,
  /// p: bağlandığı fiyat}}`. `price_alerts`'e çizim kolonu eklemek eski
  /// build'lerin okuduğu tabloyu değiştirmek olurdu; çizim zaten cihazda
  /// yaşadığı için bağ da cihazda (`CizimDeposu.alarmBaglari`).
  static const grafikCizimAlarmBaglari = 'pref_grafik_cizim_alarm_baglari_v1';
  // `pref_chart_mum_araligi` (mum aralığı, PR #161) 2026-10-10 gece
  // okunmuyor: aralık artık dönemin TradingView varsayılanıyla açılır,
  // seçim oturumluk (`mumAraligiSecimiProvider`). Anahtar başka iş için
  // yeniden KULLANILMAZ (eski kurulumlarda değer duruyor).
  static const leaderboardOptIn = 'pref_leaderboard_opt_in';
  static const biometricLock = 'pref_biometric_lock';

  /// Kilit teklifi bu kullanıcıya SORULDU mu (kabul edilsin ya da edilmesin).
  ///
  /// Teklif bir kez sorulur; reddeden kullanıcıya her açılışta tekrar
  /// sorulmaz — dayatma olmasın. Kişiye özel (`perUser`): aynı telefonda
  /// ikinci hesap kendi kararını verir.
  static const biometricLockOffered = 'pref_biometric_lock_offered';

  /// Baz para birimi — `BaseCurrency.index` (0 TRY, 1 USD, 2 EUR, 3 gram altın).
  static const baseCurrency = 'pref_base_currency';

  /// Yatırımcı seviyesi — `YatirimciSeviyesi.index` (0 başlangıç, 1 orta, 2 ileri).
  static const investorLevel = 'pref_investor_level';
  static const surfaceIsLight = 'pref_surface_is_light';
  static const signalThresholdByType = 'pref_signal_threshold_by_type_v1';
  static const signalNeutralPush = 'pref_signal_neutral_push';
  static const signalFrequencyByType = 'pref_signal_frequency_by_type_v1';
  static const signalHoursByType = 'pref_signal_hours_by_type_v1';

  /// Kullanıcının "Yenilikler"ini en son gördüğü uygulama sürümü ('1.2.0').
  ///
  /// Cihaza özgü ve kasıtlı: sürüm notu KURULU SÜRÜME dairdir, hesaba değil.
  /// Aynı hesapla iki cihaz farklı sürümlerde olabilir; sunucuya yazılsaydı
  /// yeni sürüme geçen cihaz notu görmezdi.
  static const sonGorulenSurumNotu = 'pref_son_gorulen_surum_notu';

  /// `FxRateMigrationService` en son ne zaman koştu (epoch ms). Her açılışta
  /// değil, günde bir kez sorgu atsın diye.
  static const fxMigrationLastRunMs = 'fx_migration_last_run_ms';

  /// Uygulama arkaya alındığı an (ms). Süreç öldürülürse bellekteki
  /// `_backgroundedAt` kaybolurdu ve uzun boşluk kilidi hiç işlemezdi
  /// (2026-09 L2); açılışta buradan okunur. 2026-10-13'ten beri boşluk
  /// oturumu kapatmaz, yalnız kilit açıksa kilitler.
  static const backgroundedAtMs = 'session_backgrounded_at_ms';

  /// Uygulama arkaya alınırken çalışan SÜRÜM (`1.1.6+7`).
  ///
  /// Zaman aşımı kontrolü bunu karşılaştırır: sürüm DEĞİŞTİYSE aradaki
  /// boşluk bir güncellemedir, gerçek bir terk ediş değil (bkz.
  /// `_AuthGateState._readStaleSessionAtLaunch`; 2026-10-13'ten beri iki
  /// sonuç da oturumu korur).
  static const backgroundedAtVersion = 'session_backgrounded_at_version';

  /// `RemotePushService` cihaz kimliği; çıkışta silinir (L14).
  static const pushDeviceId = 'push_device_id';

  /// iOS bildirim izninin en son analytics'e yazılan durumu. Durum yalnızca
  /// DEĞİŞİNCE kaydedilir; yoksa her açılış bir "izin verdi" olayı olurdu.
  static const iosPushPermissionLast = 'ios_push_permission_last';

  /// Varlığı olan kullanıcıya ertelenmiş bildirim izni bir kez soruldu mu
  /// (`NotificationService.varlikliKullaniciyaBirKezSor`).
  static const pushIzniVarlikliSoruldu = 'push_izni_varlikli_soruldu';

  /// Girişten önceki tanıtım (karşılama) görüldü mü — cihaz başına. Bu
  /// cihazda herhangi bir hesapla oturum açılınca da `true` yazılır: mevcut
  /// kullanıcı çıkış yapınca tanıtımı görmesin.
  static const karsilamaGoruldu = 'karsilama_goruldu';

  /// Son bilinen varlık defteri (JSON); kullanıcı kimliği soneklenir.
  static const portfolioCachePrefix = 'portfolio_cache_v1_';

  /// Mağaza değerlendirme istemi (`ReviewPromptService`). Cihaza özgü ve
  /// kasıtlı: mağaza kotası cihaz+hesap başınadır, hesap değişince
  /// sıfırlansaydı aynı telefona ikinci kez sorardık.
  static const reviewDone = 'review_done'; // bool — "Değerlendir" seçildi
  static const reviewLastAskedMs = 'review_last_asked_ms'; // int
  static const reviewAskCount = 'review_ask_count'; // int
  static const reviewFeedbackMs = 'review_feedback_ms'; // int — "Sorun var"

  /// Portföy hedefi (TRY, tam sayı; 0 = hedef yok). Kullanıcı kimliği
  /// soneklenir (`perUser`): hedef kişiseldir, aynı cihazdaki başka hesaba
  /// taşınmaz. Ana ekrandaki "Bugün" kartı ilerlemeyi buradan okur.
  static const portfolioGoalTRY = 'portfolio_goal_try';

  /// Çan sayfasının en son açıldığı an (ms epoch; 0 = hiç açılmadı).
  /// Rozet yalnız bundan SONRA gelen aktif bildirimleri "yeni" sayar.
  /// Kişiye özel (`perUser`): A'nın gördüğü, B'nin rozetini düşürmez.
  static const bildirimSonGorulen = 'pref_bildirim_son_gorulen_ms';

  /// Performans "Bugünkü portföyle" (simülasyon) görünümü — Ayarlar ›
  /// Görünüm'deki anahtar (2026-10-04, `performans_ayar_sade`). Kişiye özel
  /// (`perUser`): A'nın görünümü B'nin grafiğini değiştirmez. Modun TEK
  /// kaynağı (bayrak ve ekranın oturum alanı 2026-10-05'te kalktı).
  static const performansBugunkuPortfoy = 'pref_performans_bugunku_portfoy';

  /// Balina Radarı "nasıl okunur" gezintisi görüldü (2026-10-05). Kişiye
  /// özel: aynı telefonda giriş yapan ikinci kullanıcı da bir kez görsün.
  static const radarKocuGoruldu = 'pref_radar_kocu_goruldu';

  /// Haftanın özetinde sakin geçen varlıklar da listelensin mi (Ayarlar ›
  /// Bildirimler). Varsayılan açık: "AFT · Sakin" satırı da bilgidir.
  static const haftaSakinGoster = 'pref_hafta_sakin_goster';

  /// Erken kullanıcı hediyesi sayfası gösterildi (bir kez). Kişiye özel.
  static const premiumHediyeGosterildi = 'pref_premium_hediye_gosterildi';

  /// Hediyenin bittiği bir kez söylendi (kişiye özel; bitiş tarihine
  /// bağlı: yeni hediye = yeni bitiş = yeniden söylenir).
  static const premiumHediyeBittiSoylenen =
      'pref_premium_hediye_bitti_soylenen';

  /// Portföy ve Performans'ta seçili portföy (çoklu portföy, 0133): `''`
  /// Tümü, `ana` Ana, uuid adlandırılmış portföy. Kişiye özel (`perUser`):
  /// portföy kimlikleri hesaba aittir, aynı cihazdaki başka hesapta anlamsız.
  static const seciliPortfoy = 'pref_secili_portfoy';

  /// Ana ekrandaki "N varlıkta bilgi eksik" satırı kapatıldığında o anki
  /// eksiklerin anahtarları (`VeriEksigi.anahtar`). Kişiye özel. Yeni bir
  /// eksik çıkınca satır yeniden görünür; kapatılanlar bir daha sorulmaz.
  static const veriKalitesiKapatilan = 'pref_veri_kalitesi_kapatilan';

  /// Ana ekran özellik önerisi kartı (`ozellik_onerisi.dart`): kapatılan ya
  /// da dokunulan önerilerin anahtarları (`OzellikOnerisi.anahtar`) ve son
  /// kapatmanın zamanı (epoch ms; sıradaki öneri için bekleme). Kişiye özel.
  static const ozellikOnerisiKapatilan = 'pref_ozellik_onerisi_kapatilan';
  static const ozellikOnerisiSonKapatma = 'pref_ozellik_onerisi_son_kapatma';

  /// Yumuşak güncelleme kartı (`guncelleme_karti.dart`): kapatıldığı
  /// önerilen build numarası. Aynı build bir daha sorulmaz; Console'da daha
  /// yeni bir build önerilince kart yeniden görünür. Cihaza özel (sürüm
  /// hesaba değil kuruluma ait).
  static const guncellemeKapatilanBuild = 'pref_guncelleme_kapatilan_build';

  /// Ana sayfa "seni ilgilendiren günler" satırı (`seni_ilgilendiren_gunler.dart`):
  /// kapatılan olayların kimlikleri (`GunOlayi.kimlik`, tarihli). Kişiye özel:
  /// temettü günleri kullanıcının kendi hisselerinden gelir.
  static const gunlerKapatilan = 'pref_gunler_kapatilan';

  /// Takip listesi "benim sıram" (`takip_sirasi.dart`): watchlist satır
  /// kimliklerinin sırası. Yoksa ilk açılışta bugünkü sıradan (değişime göre)
  /// kurulur ve kaydedilir. Kişiye özel: kimlikler hesaba ait. Sunucuda
  /// sıra alanı yok; sıra yalnız bu telefonda.
  static const takipSirasi = 'pref_takip_sirasi';

  /// Takip listesi sıralama seçimi — `TakipSiralama.index` (0 benim sıram,
  /// 1 en çok yükselen, 2 en çok düşen). Kişiye özel.
  static const takipSiralama = 'pref_takip_siralama';

  /// Portföy listesi sıralama seçimi — `PortfoySiralama.kod`
  /// (`deger_azalan`, `kar_azalan`…). Index DEĞİL kod: enum sırası değişince
  /// tercih başka sıralamaya kaymasın. Yoksa / tanınmazsa "Değere göre".
  /// Kişiye özel (çoklu hesapta her hesabın kendi seçimi).
  static const portfoySiralama = 'pref_portfoy_siralama';

  /// Özellik kullanım ölçümünün (`OzellikOlcumu`) tekilleştirme öneki:
  /// `<önek><ozellik kodu>` → son sayıldığı TR günü (`2026-10-25`). Değer
  /// kullanıcı verisi değil, "bugün bu olay gitti mi" işaretidir; silinirse
  /// yalnız o günün olayı ikinci kez gider.
  ///
  /// Cihaza özel, `perUser` DEĞİL ve çıkışta silinmez (2026-10-25 kararı):
  /// tercih değil, `kullaniciyaOzelTercihler` listesine girmez. Aynı gün
  /// aynı telefonda hesap değiştiren kişinin ikinci hesabındaki ilk kullanım
  /// sayılmaz; bu kaybı, her hesaba ayrı anahtar ve çıkış temizliği
  /// karmaşasına değmez görüyoruz (ölçü "kaç kişi kullanıyor", kesin sayım
  /// değil).
  static const ozellikOlcumuPrefix = 'ozellik_olcumu_gun_';
}
