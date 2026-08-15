import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../providers/portfolio_provider.dart';
import '../utils/tr_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'history_service.dart';

/// iOS Live Activity — kilit ekranı + Dynamic Island "piyasa seansı" yüzeyi.
///
/// ## Neden OLAY tabanlı (sürekli açık değil)
/// Live Activity'yi Apple **başı ve sonu olan** olaylar için tasarladı:
/// kargo, maç, yolculuk. Sürekli açık duran bir portföy takibi hem
/// App Review'da reddedilebilir hem de sistem tarafından 8 saat sonra
/// zaten sonlandırılır — kullanıcı "widget'ım kayboldu" der.
///
/// Bu yüzden yüzey bir **seansa** bağlanır: borsa açılışında başlar,
/// kapanışında biter. Böylece:
///   * Apple'ın beklediği "canlı olay" kalıbına oturur,
///   * 8 saatlik sistem limiti seans süresinden uzun olduğu için hiç
///     devreye girmez (bkz. [_sessionEnd] hesabı),
///   * seans dışında pil ve kota harcanmaz.
///
/// [HomeWidgetService] ise TAM TERSİ bir yüzeydir: ana ekranda 7/24 durur,
/// seans kavramı yoktur. İkisi birbirinin yerine geçmez, tamamlar.
///
/// ## Gizlilik değişmezi
/// Kilit ekranı, telefon açılmadan görülebilen bir yüzeydir — buradaki
/// kural [HomeWidgetService]'inkinden daha sıkıdır. Yalnızca ÖZET gönderilir;
/// varlık listesi, ticker, adet, kullanıcı kimliği ASLA gitmez. Kullanıcı
/// bakiyeyi gizlediyse tutar hiç üretilmez — maskeleme sunumda değil
/// KAYNAKTA yapılır ki rakam cihazın o yüzeyine hiç ulaşmasın.
///
/// Oturum kapanışında [endAll] çağrılmalıdır; aksi halde çıkan kullanıcının
/// bakiyesi kilit ekranında asılı kalır.
class LiveActivityService {
  LiveActivityService._();
  static final instance = LiveActivityService._();

  /// Native taraftaki `LiveActivityChannel.name` ile birebir aynı olmalı.
  static const _channel = MethodChannel('com.sandik.app/live_activity');

  /// Kullanıcıya görünen seans adı.
  static const _sessionName = 'Piyasa Seansı';

  /// BIST işlem saatleri (Türkiye saati). Seans bu aralıkta "açık" sayılır.
  ///
  /// Kapanış 18:10 — kapanış seansı dahil. Süre 8s 10dk; Apple'ın 8 saatlik
  /// Live Activity limitine yakın ama kullanıcı uygulamayı gün içinde
  /// açtığında oturum tazelendiği için pratikte sorun olmaz.
  static const _openHour = 10;
  static const _openMinute = 0;
  static const _closeHour = 18;
  static const _closeMinute = 10;

  /// Supabase istemcisi — `auth_service` ile aynı desen.
  SupabaseClient get _db => Supabase.instance.client;

  bool _sessionActive = false;

  /// Son gönderilen içerik — aynı veriyi tekrar tekrar göndermemek için.
  String? _lastPayloadKey;

  /// Native taraftan gelen push token dinleyicisi kuruldu mu?
  bool _tokenListenerReady = false;

  /// Son yazılan özet — sunucu bunu push'lar. Aynı özeti tekrar tekrar
  /// yazmamak için tutulur (her fiyat tick'inde DB turu atmak israf).
  String? _lastSummaryKey;

  /// Gün içi seri — sparkline için. `updateWithChart` deseniyle aynı
  /// gerekçe: her tick'te ağ turu atmak pahalı, seri önbelleklenir.
  List<double>? _sparkline;
  DateTime? _sparklineAt;

  /// Sparkline en sık bu aralıkta tazelenir.
  ///
  /// 5 dakika, push döngüsünün (`0033_live_activity_cron.sql`) periyoduyla
  /// hizalı: daha sık çekmek push'a yansımayacağı için boşuna olur.
  static const _sparkMinInterval = Duration(minutes: 5);

  /// Kilit ekranında tutar gösterilsin mi? (kullanıcı tercihi)
  ///
  /// **iOS kilitli/açık ayrımı VERMEZ** — ActivityKit'te böyle bir sinyal
  /// yok, aynı içerik iki durumda da render edilir. Bu yüzden "kilitliyken
  /// gizle" davranışı teknik olarak kurulamaz; yerine kullanıcı tercihi
  /// taşınır. Varsayılan KAPALI: gizlilik kararlarında güvenli taraf.
  bool showAmountsOnLockScreen = false;

  /// Platform desteği + kullanıcı izni.
  ///
  /// Android'de kanal hiç kayıtlı değildir; [MissingPluginException] beklenen
  /// durumdur ve `false` olarak yorumlanır.
  ///
  /// **Sonuç ÖNBELLEĞE ALINMAZ.** İlk bakışta her senkronda platform kanalına
  /// gitmek israf gibi görünür ama `areActivitiesEnabled` kullanıcı tercihidir:
  /// Ayarlar'dan Live Activity'yi kapatıp açabilir. Önbelleğe alınsaydı izni
  /// sonradan veren kullanıcı, uygulamayı tamamen yeniden başlatana kadar
  /// kilit ekranında hiçbir şey göremezdi. Çağrı zaten ucuz bir yerel
  /// sorgudur (ağ turu yok).
  Future<bool> _isSupported() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('LiveActivity isSupported failed: $e');
      return false;
    }
  }

  /// Süreç içi durumu sıfırlar.
  ///
  /// Testler arasında ve kullanıcı değişiminde çağrılır: singleton olduğu
  /// için `_sessionActive` aksi halde önceki oturumdan taşar ve servis
  /// hiç açılmamış bir oturuma `update` göndermeye çalışır.
  @visibleForTesting
  void resetForTest() {
    _sessionActive = false;
    _lastPayloadKey = null;
    _lastSummaryKey = null;
    _sparkline = null;
    _sparklineAt = null;
  }

  /// Native taraftan gelen push token'ını dinlemeye başlar.
  ///
  /// **Neden dinleyici, tek seferlik okuma değil:** token oturum açıldıktan
  /// SONRA asenkron gelir (`start` çoktan dönmüştür) ve oturum boyunca
  /// yenilenebilir. Kaçırılan bir yenileme, sunucunun ölü token'a push
  /// atmasına ve kilit ekranının sessizce donmasına yol açar.
  void _ensureTokenListener() {
    if (_tokenListenerReady) return;
    _tokenListenerReady = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onPushToken') return null;
      try {
        final args = (call.arguments as Map).cast<String, Object?>();
        final token = args['token'] as String?;
        final activityId = args['activityId'] as String?;
        if (token == null || activityId == null) return null;
        await _registerToken(token, activityId);
      } catch (e) {
        if (kDebugMode) debugPrint('Push token kaydı başarısız: $e');
      }
      return null;
    });
  }

  /// Push token'ını sunucuya yazar — cron döngüsünün hedefi.
  Future<void> _registerToken(String token, String activityId) async {
    final user = _db.auth.currentUser;
    if (user == null) return;

    await _db.from('live_activity_sessions').upsert({
      'token': token,
      'user_id': user.id,
      'activity_id': activityId,
      'expires_at': sessionEnd(DateTime.now()).toIso8601String(),
      'show_amounts': showAmountsOnLockScreen,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Portföy özetini sunucuya yazar; push döngüsü bunu okur.
  ///
  /// **Neden sunucu hesaplamıyor:** portföy değeri lot toplama + döviz
  /// çevrimi + altın dönüşümü ister ve bunların tamamı `HistoryService`
  /// içinde yaşıyor. Sunucuda ikinci bir implementasyon iki kopyanın
  /// ayrışması demekti — kullanıcı uygulamada bir rakam, kilit ekranında
  /// başka bir rakam görürdü.
  Future<void> _writeSummary(Map<String, dynamic> payload) async {
    final user = _db.auth.currentUser;
    if (user == null) return;

    // Aynı özeti tekrar yazma — her fiyat tick'inde DB turu atmak israf.
    final key = '${payload['totalText']}|${payload['changeText']}'
        '|${payload['changePctText']}';
    if (key == _lastSummaryKey) return;

    await _db
        .from('live_activity_sessions')
        .update({
          'summary': {
            'totalText': payload['totalText'],
            'changeText': payload['changeText'],
            'changePctText': payload['changePctText'],
            'isPositive': payload['isPositive'],
            'sparkline': payload['sparkline'],
          },
          'show_amounts': showAmountsOnLockScreen,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('user_id', user.id);

    _lastSummaryKey = key;
  }

  /// Gün içi seriyi 0…1 aralığına normalize eder.
  ///
  /// **Neden normalize:** kilit ekranı telefonu açmadan görülebilir. Ham TL
  /// değerleri göndermek, tutar gizliyken bile portföy büyüklüğünü grafik
  /// ekseninden okunabilir kılardı. Normalize seri yalnızca ŞEKLİ taşır.
  ///
  /// Nokta sayısı sınırlanır: kilit ekranındaki grafik ~130pt genişlikte,
  /// 40'tan fazla nokta görsel olarak ayırt edilemez ve push gövdesini
  /// (APNs 4KB sınırı) şişirir.
  Future<List<double>> _buildSparkline(PortfolioState state) async {
    final now = DateTime.now();
    final due = _sparklineAt == null ||
        now.difference(_sparklineAt!) >= _sparkMinInterval;

    if (due) {
      try {
        _sparklineAt = now;
        final series = await HistoryService.instance
            .getPortfolioHistoryHourly(state.activeAssets, 24);
        _sparkline = _normalize(series);
      } catch (e) {
        if (kDebugMode) debugPrint('Sparkline çekilemedi: $e');
      }
    }
    return _sparkline ?? const [];
  }

  static List<double> _normalize(Map<int, double> series) {
    if (series.length < 2) return const [];
    final keys = series.keys.toList()..sort();
    final values = [for (final k in keys) series[k]!];

    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final span = (maxV - minV).abs();

    // Düz çizgi (min == max): ortada yatay çiz. Sıfıra bölmeyi de önler.
    if (span < 1e-9) return List.filled(values.length.clamp(2, 40), 0.5);

    // Örnekleme: 40 noktadan fazlasını seyrelt.
    const maxPoints = 40;
    final step = values.length <= maxPoints
        ? 1
        : (values.length / maxPoints).ceil();

    final out = <double>[];
    for (var i = 0; i < values.length; i += step) {
      out.add((values[i] - minV) / span);
    }
    // Son nokta her zaman dahil — grafiğin ucu güncel değeri göstermeli.
    final lastNorm = (values.last - minV) / span;
    if (out.isEmpty || (out.last - lastNorm).abs() > 1e-9) out.add(lastNorm);
    return out;
  }

  /// [now] anında piyasa seansı açık mı?
  ///
  /// Hafta sonu kapalı. Resmî tatiller BURADA bilinmez — takvim gerektirir
  /// ve yanlış bir tatil listesi seansı yanlış günde açmaktan daha kötüdür.
  /// Tatilde açılan bir seans zararsızdır: fiyat değişmez, banner sabit
  /// rakam gösterir ve akşam kapanır. (Bkz. TECHNICAL_DEBT.md)
  @visibleForTesting
  static bool isMarketOpen(DateTime now) {
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final open = DateTime(now.year, now.month, now.day, _openHour, _openMinute);
    final close =
        DateTime(now.year, now.month, now.day, _closeHour, _closeMinute);
    return !now.isBefore(open) && now.isBefore(close);
  }

  /// Seansın o günkü bitiş anı — Live Activity'nin `staleDate`'i.
  @visibleForTesting
  static DateTime sessionEnd(DateTime now) =>
      DateTime(now.year, now.month, now.day, _closeHour, _closeMinute);

  /// Portföy her değiştiğinde çağrılır. Seans durumuna göre oturumu
  /// başlatır, tazeler veya kapatır.
  ///
  /// Sessizce başarısız olur: Live Activity ikincil bir yüzeydir ve bir
  /// hata uygulamanın akışını bozmamalıdır.
  Future<void> sync(
    PortfolioState state, {
    required bool hideBalance,
    DateTime? now,
  }) async {
    try {
      if (!await _isSupported()) return;
      _ensureTokenListener();

      final ts = now ?? DateTime.now();

      if (!isMarketOpen(ts)) {
        // Seans kapandı: oturumu bitir. `immediate: false` — kullanıcı
        // kapanış rakamını kısa süre daha görebilsin.
        if (_sessionActive) {
          await _invoke('end', {
            ..._payload(state, hideBalance: hideBalance, now: ts),
            'immediate': false,
          });
          _sessionActive = false;
          _lastPayloadKey = null;
        }
        return;
      }

      // Sparkline seansta 5 dakikada bir tazelenir (push periyoduyla
      // hizalı); aradaki çağrılar önbellekten okur.
      final spark =
          hideBalance ? const <double>[] : await _buildSparkline(state);

      final payload = _payload(
        state,
        hideBalance: hideBalance,
        now: ts,
        sparkline: spark,
      );

      // Aynı içerik tekrar gönderilmez.
      //
      // Portföy state'i her fiyat tick'inde yayınlanıyor ama görünen metin
      // çoğu zaman aynı kalıyor (ör. kuruş altı değişim). ActivityKit'e
      // gereksiz `update` göndermek pil yakar ve sistem tarafından
      // kısıtlanmaya (throttle) yol açar.
      final key = '${payload['totalText']}|${payload['changeText']}'
          '|${payload['isPositive']}|${payload['isHidden']}';
      if (_sessionActive && key == _lastPayloadKey) return;

      final ok = await _invoke(
        _sessionActive ? 'update' : 'start',
        {...payload, 'sessionName': _sessionName},
      );

      if (ok) {
        _sessionActive = true;
        _lastPayloadKey = key;

        // Özeti sunucuya yaz — push döngüsü (cron, 5 dk) bunu okuyup
        // APNs'e gönderir. Böylece uygulama kapalıyken de kilit ekranı
        // güncellenir. `await` EDİLMEZ: Live Activity ikincil bir yüzey,
        // DB turu uygulamanın akışını bekletmemeli.
        unawaited(_writeSummary(payload).catchError((Object e) {
          if (kDebugMode) debugPrint('Özet yazılamadı: $e');
        }));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LiveActivity sync failed: $e');
    }
  }

  /// Kilit ekranına gidecek özet. Gizlilik kuralı burada uygulanır.
  Map<String, dynamic> _payload(
    PortfolioState state, {
    required bool hideBalance,
    required DateTime now,
    List<double> sparkline = const [],
  }) {
    final isPos = state.gainLoss >= 0;
    final endsAt = sessionEnd(now);
    final updatedAt = DateFormat('HH:mm', 'tr_TR').format(now);

    if (hideBalance) {
      // Tutar HİÇ üretilmez — maskelenmiş metin bile gerçek rakamı
      // taşımaz. Yön de sabitlenir: `isPositive` üstünden kâr/zarar
      // durumu sızmasın. Grafik de gitmez: şekli bile bir sinyaldir.
      return {
        'totalText': '••••••',
        'changeText': '••••••',
        'changePctText': '••',
        'isPositive': true,
        'isHidden': true,
        'updatedAtText': updatedAt,
        'sessionEndsAtMs': endsAt.millisecondsSinceEpoch,
        'sparkline': const <double>[],
        'showAmounts': false,
      };
    }

    return {
      // Türkçe biçim TEK yerde üretilir (tr_format) ve hazır metin olarak
      // gider; Swift tarafında ikinci bir biçimlendirici tutulmaz.
      'totalText': fmtTRY(state.totalValue, digits: 2),
      'changeText':
          '${isPos ? '+' : '-'}${fmtTRY(state.gainLoss.abs(), digits: 2)}',
      'changePctText': fmtPct(state.gainLossPercentage.abs(), digits: 2),
      'isPositive': isPos,
      'isHidden': false,
      'updatedAtText': updatedAt,
      'sessionEndsAtMs': endsAt.millisecondsSinceEpoch,
      // Normalize (0…1) — ham tutar taşımaz, yalnızca günün şekli.
      'sparkline': sparkline,
      'showAmounts': showAmountsOnLockScreen,
    };
  }

  /// Oturum kapanışında / çıkışta çağrılır — banner kilit ekranından
  /// DERHAL kalkar.
  Future<void> endAll() async {
    try {
      _sessionActive = false;
      _lastPayloadKey = null;
      if (!await _isSupported()) return;
      await _invoke('endAll', const {});
    } catch (e) {
      if (kDebugMode) debugPrint('LiveActivity endAll failed: $e');
    }
  }

  Future<bool> _invoke(String method, Map<String, dynamic> args) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
