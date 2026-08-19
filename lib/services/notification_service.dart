import 'package:flutter/material.dart'
    show Color, GlobalKey, NavigatorState;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/asset.dart';
import '../models/position.dart' show positionKey;
import '../models/technical_signal.dart';
import '../providers/portfolio_provider.dart';
import '../screens/partnership_requests_screen.dart';
import '../screens/performance_screen.dart';
import '../theme/sandik.dart' show adaptiveRoute, Sandik;

const _kSignalNotificationsKey = 'pref_signal_notifications';
const _kPartnerNotificationsKey = 'pref_partner_notifications';

Future<bool> _prefEnabled(String key) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? true; // default açık
  } catch (_) {
    return true;
  }
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  static const partnerInviteType = 'partner_invite';
  static const signalAnalyzeRequestType = 'signal_analyze_request';

  /// Sunucudan gelen hazır sinyal bildirimi (analyze-signals edge function
  /// → FCM `data.type`). Uygulama ÖN PLANDAYKEN Android `notification`
  /// payload'ını sistem göstermez; bu tipi görünce bildirimi biz basarız.
  static const signalAlertType = 'signal_alert';
  static const _partnerInvitePayloadPrefix = 'partner_invite:';
  static const _signalPayloadPrefix = 'signal_alert:';

  /// Navigator/portföy hazır değilken yeniden deneme aralığı.
  ///
  /// Bildirime uygulama KAPALIYKEN dokunulduğunda hedef ekran hemen
  /// açılamaz: navigator henüz kurulmamış, portföy henüz yüklenmemiş olur.
  /// Bu bir animasyon süresi değildir — kısa tutulur ki soğuk açılışta
  /// yönlendirme gecikmiş hissettirmesin.
  static const _yenidenDenemeAraligi = Duration(milliseconds: 300);

  /// Yeniden deneme üst sınırı — 20 × 300ms ≈ 6 sn. Sonsuz döngü olmaz;
  /// bu süre içinde açılamazsa kullanıcı zaten uygulamanın açıldığını görür.
  static const _yenidenDenemeSiniri = 20;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  GlobalKey<NavigatorState>? _navigatorKey;

  Future<void> init({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (navigatorKey != null) {
      _navigatorKey = navigatorKey;
    }
    if (_initialized) return;

    // Durum çubuğu ikonu beyaz siluet + şeffaf zemin olmalı; Android yalnızca
    // alfa kanalını kullanır. `@mipmap/ic_launcher` renkli olduğu için düz
    // beyaz kare olarak görünüyordu.
    const android = AndroidInitializationSettings('ic_stat_sandik');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: darwin);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationPayload(response.payload);
      },
    );

    // Android 8+ (API 26): bildirim kanalı ÖNCEDEN oluşturulmalı.
    //
    // Sunucudan gelen push `channel_id: signal_channel` taşıyor. Kanal
    // yoksa Android mesajı sessizce düşürür — FCM "başarılı" der, cihaz
    // mesajı alır, ama kullanıcı hiçbir şey görmez. Tam olarak bu yaşandı:
    // `sent: 1, failed: 0` dönerken bildirim gölgesi boş kaldı.
    //
    // Local bildirimler kanalı ilk gösterimde kendiliğinden yaratır; uzak
    // (FCM) bildirimler yaratmaz. Bu yüzden burada açıkça kuruyoruz.
    await _createAndroidChannels();

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();

    _initialized = true;

    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchPayload != null) {
      Future<void>.microtask(() => _handleNotificationPayload(launchPayload));
    }
  }

  /// Android bildirim kanallarını oluşturur (API 26+).
  ///
  /// Kanal id'leri sunucu tarafıyla eşleşmek ZORUNDA:
  /// `supabase/functions/analyze-signals/index.ts` → `channel_id`.
  /// Biri değişirse diğeri de değişmeli, aksi halde uzak bildirimler
  /// sessizce düşer.
  Future<void> _createAndroidChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return; // iOS/diğer platform — kanal kavramı yok

    // Teknik sinyal bildirimleri (sunucudan FCM ile gelir).
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'signal_channel',
        'Teknik Sinyal Bildirimleri',
        description: 'Portföyünüzdeki varlıklar için trend bildirimleri',
        importance: Importance.high,
      ),
    );

    // Ortaklık davetleri.
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'partner_invite_channel',
        'Ortaklik Bildirimleri',
        description: 'Yeni ortaklik onay istekleri',
        importance: Importance.max,
      ),
    );
  }

  /// Bildirim iznini kullanıcıya sor. Onboarding tamamlandıktan sonra çağır.
  Future<void> requestPermission() async {
    if (!_initialized) await init();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> sendSignalNotification({
    required String assetName,
    required String ticker,
    required SignalType signal,
    required int buyCount,
    required int sellCount,
  }) async {
    if (!await _prefEnabled(_kSignalNotificationsKey)) return;
    if (!_initialized) await init();

    final m = buildSignalMessage(
      assetName: assetName,
      ticker: ticker,
      signal: signal,
      buyCount: buyCount,
      sellCount: sellCount,
    );
    final title = m.title;
    final body = m.body;

    final androidDetails = AndroidNotificationDetails(
      'signal_channel',
      'Teknik Sinyal Bildirimleri',
      channelDescription: 'AL/SAT teknik analiz sinyalleri',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_sandik',
      // Vurgu rengi: ikonu ve uygulama adını tonlar. `colorized` KULLANMA —
      // o bildirimin tüm arka planını boyar (medya bildirimi görünümü).
      //
      // ÜÇ durum ayrı: nötr'de eskiden `danger` (kırmızı) basılıyordu ve
      // "yön belirsiz" bildirimi düşüş uyarısı gibi görünüyordu. Renk tek
      // başına anlam taşımaz — yön ayrıca ▲▼◆ ile de veriliyor.
      color: switch (signal) {
        SignalType.buy => const Color(0xFF3DB77F),
        SignalType.sell => const Color(0xFFFF6B52),
        _ => Sandik.amber,
      },
      ticker: ticker,
      styleInformation: BigTextStyleInformation(body),
    );

    await _plugin.show(
      assetName.hashCode,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  /// Sinyal bildiriminin başlık + gövdesi — İSTEMCİ ve SUNUCU aynı dili
  /// konuşmalı.
  ///
  /// Sunucudaki eşi: `analyze-signals/index.ts` → `buildMessage`. İkisi
  /// ayrışırsa kullanıcı, push'un nereden geldiğine göre farklı biçimde
  /// bildirim alır (cron → sunucu metni, uygulama içi analiz → bu metin).
  ///
  /// **Tasarım kararları:**
  ///   * Yön OKU başlıkta en solda (▲ ▼ ◆) — kilit ekranında bildirimler
  ///     yığılır ve kullanıcı önce sol kenarı tarar. Emoji yerine geometrik
  ///     şekil: finansal ciddiyeti korur, her yazı tipinde aynı görünür.
  ///   * Kısa ETİKET (ticker) kullanılır; fon adları başlığa sığmaz ve
  ///     işletim sistemi ortadan keserek ayırt edici kısmı yok eder.
  ///   * Güven yüzdesi gövdede AÇIKÇA verilir — "çoğunluğu yukarı yönlü"
  ///     ifadesi 4/6 ile 6/6 arasındaki farkı gizliyordu.
  ///   * Yasal ibare her durumda korunur.
  static ({String title, String body}) buildSignalMessage({
    required String assetName,
    required String ticker,
    required SignalType signal,
    required int buyCount,
    required int sellCount,
  }) {
    const disclaimer = 'Yatırım tavsiyesi değildir.';
    final etiket = shortAssetLabel(assetName, ticker);
    final total = buyCount + sellCount;

    if (signal == SignalType.neutral) {
      return (
        title: '◆ $etiket · yön belirsiz',
        body: 'Göstergeler bölünmüş: $buyCount yukarı, $sellCount aşağı. '
            '$disclaimer',
      );
    }

    final isBuy = signal == SignalType.buy;
    final lehte = isBuy ? buyCount : sellCount;
    final yuzde = total > 0 ? ((lehte / total) * 100).round() : 0;

    return (
      title: isBuy ? '▲ $etiket · yukarı yönlü' : '▼ $etiket · aşağı yönlü',
      body: '$lehte/$total gösterge ${isBuy ? 'yukarı' : 'aşağı'} · '
          'güven %$yuzde. $disclaimer',
    );
  }

  /// Başlıkta kullanılacak kısa varlık etiketi.
  ///
  /// Sunucudaki eşi: `analyze-signals/index.ts` → `shortLabel`.
  ///   `TEFAS:AFO` → `AFO`      (fon kodu)
  ///   `AGHOL.IS`  → `AGHOL`    (BIST kodu)
  ///   `EURTRY=X`  → adına düş  (kur çifti; "Euro" kullanıcıya daha anlamlı)
  static String shortAssetLabel(String assetName, String ticker) {
    final t = ticker.trim();
    if (t.isEmpty || t.endsWith('=X')) return assetName;

    final sade = t.contains(':')
        ? t.split(':').last
        : t.replaceAll(RegExp(r'\.IS$', caseSensitive: false), '');

    return sade.length >= 2 ? sade : assetName;
  }

  Future<void> showPartnerInviteNotification({
    required String inviteId,
    required String requesterName,
  }) async {
    if (!await _prefEnabled(_kPartnerNotificationsKey)) return;
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'partner_invite_channel',
      'Ortaklik Bildirimleri',
      channelDescription: 'Yeni ortaklik onay istekleri',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'ic_stat_sandik',
      color: Sandik.amber, // marka amber
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _plugin.show(
      inviteId.hashCode,
      'Yeni ortaklik istegi',
      '$requesterName ortaklik kodunuzu girdi.',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: '$_partnerInvitePayloadPrefix$inviteId',
    );
  }

  /// Sunucudan gelen teknik sinyal bildirimini gösterir.
  ///
  /// Yalnızca uygulama ÖN PLANDAYKEN çağrılır. Arka planda/kapalıyken FCM
  /// `notification` payload'ını Android'in kendisi gösterir; oraya ikinci
  /// bir bildirim basmak çift gösterime yol açar.
  ///
  /// Kanal `signal_channel` — sunucudaki `channel_id` ile aynı olmak
  /// zorunda (bkz. `_createAndroidChannels`).
  Future<void> showSignalNotification({
    required String title,
    required String body,
    required String assetId,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'signal_channel',
      'Teknik Sinyal Bildirimleri',
      channelDescription: 'Portföyünüzdeki varlıklar için trend bildirimleri',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_sandik',
      color: Sandik.amber, // marka amber
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _plugin.show(
      assetId.hashCode,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      // PAYLOAD ŞART: bu alan boş bırakılmıştı, bu yüzden ön planda basılan
      // bildirime dokunmak hiçbir şey yapmıyordu. Tıklama bilgisiz kalıyordu
      // — hangi varlığa ait olduğu kayboluyordu.
      payload: assetId.isEmpty ? null : '$_signalPayloadPrefix$assetId',
    );
  }

  void handleRemoteMessageData(Map<String, dynamic> data) {
    final type = data['type']?.toString();

    // Sinyal bildirimine dokunulduğunda o varlığın performans ekranı açılır
    // (grafiğin altında teknik sinyal paneli var — kullanıcının bildirimden
    // sonra görmek istediği yer orasıdır).
    //
    // Bu dal EKSİKTİ: yalnızca `partnerInviteType` ele alınıyordu, sinyal
    // bildirimine dokunmak uygulamayı açıp ana ekranda bırakıyordu.
    if (type == signalAlertType) {
      final assetId = data['asset_id']?.toString();
      if (assetId == null || assetId.isEmpty) return;
      _openAssetPerformance(assetId);
      return;
    }

    if (type != partnerInviteType) return;

    final inviteId = data['invite_id']?.toString();
    if (inviteId == null || inviteId.isEmpty) return;
    _openPartnerInvite(inviteId);
  }

  void _handleNotificationPayload(String? payload) {
    if (payload == null) return;

    if (payload.startsWith(_signalPayloadPrefix)) {
      final assetId = payload.substring(_signalPayloadPrefix.length);
      if (assetId.isNotEmpty) _openAssetPerformance(assetId);
      return;
    }

    if (!payload.startsWith(_partnerInvitePayloadPrefix)) return;

    final inviteId = payload.substring(_partnerInvitePayloadPrefix.length);
    _openPartnerInvite(inviteId);
  }

  void _openPartnerInvite(String inviteId) {
    final navigator = _navigatorKey?.currentState;
    final context = navigator?.overlay?.context;
    if (navigator == null || context == null) {
      Future<void>.delayed(
        _yenidenDenemeAraligi,
        () => _openPartnerInvite(inviteId),
      );
      return;
    }

    navigator.push(
      adaptiveRoute(
        builder: (_) => PartnershipRequestsScreen(
          highlightInviteId: inviteId,
        ),
      ),
    );
  }

  /// Sinyal bildiriminden varlığın performans ekranına gider.
  ///
  /// [PerformanceScreen] grafiğin ALTINDA teknik sinyal panelini gösterir —
  /// bildirimdeki "4/6 gösterge yukarı" özetinin dayanağı orada açılır.
  ///
  /// Varlık `id` üzerinden provider'dan çözülür; bildirim yalnızca `asset_id`
  /// taşır (ad ve fiyat push anında eskimiş olabilir, taşımanın anlamı yok).
  ///
  /// [deneme] yeniden deneme sayacıdır: bildirime uygulama KAPALIYKEN
  /// dokunulduğunda portföy henüz yüklenmemiş olur ve varlık bulunamaz.
  /// Sonsuz döngü olmaması için sınırlıdır — bulunamazsa sessizce vazgeçilir
  /// (kullanıcı uygulamanın açıldığını zaten görür).
  void _openAssetPerformance(String assetId, {int deneme = 0}) {
    final navigator = _navigatorKey?.currentState;
    final context = navigator?.overlay?.context;

    if (navigator == null || context == null) {
      if (deneme >= _yenidenDenemeSiniri) return;
      Future<void>.delayed(
        _yenidenDenemeAraligi,
        () => _openAssetPerformance(assetId, deneme: deneme + 1),
      );
      return;
    }

    final container = ProviderScope.containerOf(context, listen: false);
    final assets = container.read(portfolioProvider).valueOrNull?.assets;

    // Portföy henüz gelmediyse bekle — uygulama soğuk açılışta bildirimden
    // geliyorsa veri birkaç saniye sonra düşer.
    if (assets == null || assets.isEmpty) {
      if (deneme >= _yenidenDenemeSiniri) return;
      Future<void>.delayed(
        _yenidenDenemeAraligi,
        () => _openAssetPerformance(assetId, deneme: deneme + 1),
      );
      return;
    }

    Asset? asset;
    for (final a in assets) {
      if (a.id == assetId) {
        asset = a;
        break;
      }
    }

    // Varlık silinmiş olabilir (bildirim gönderildikten sonra). Sessiz
    // geçmek doğru: olmayan bir varlık için boş ekran açmak yanıltıcı olur.
    if (asset == null) return;

    // Aynı pozisyonun tüm lot'ları — grafik üstündeki işlem marker'ları için.
    // `positionKey` sahip taşımaz; ortak lot'ları AYRI tutulur.
    final anahtar = positionKey(asset);
    final lots = assets.where((a) => positionKey(a) == anahtar).toList();

    navigator.push(
      adaptiveRoute(
        builder: (_) => PerformanceScreen(
          asset: asset!,
          showBackButton: true,
          lots: lots,
        ),
      ),
    );
  }
}
