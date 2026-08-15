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

  /// `live_activity_sessions.summary` içeriğinin ANLAM sürümü.
  ///
  /// Alan adları aynı kalırken anlamları değiştiği için gerekli:
  ///   * **v1** — `changeText`/`changePctText` ÖMÜRLÜK getiriydi
  ///     (varlığın alındığı günden bugüne, temettü dahil).
  ///   * **v2** — günlük değişim (gün içi serinin ilk ve son noktası).
  ///
  /// Sunucu damgasız ya da eski damgalı satırı push ETMEZ: aksi halde
  /// uygulaması güncellenmiş bir kullanıcı, DB'de duran eski özet
  /// yüzünden kilit ekranında ömürlük getiriyi "Bugün" diye görmeye
  /// devam eder. Anlamı değişen her alanda bu sayı ARTIRILMALIDIR.
  static const summarySchemaVersion = 2;

  /// Kullanıcıya görünen seans adı.
  static const _sessionName = 'Piyasa Seansı';

  /// Varsayılan pencere — BIST işlem saatleri (dakika cinsinden).
  static const defaultStartMinute = 10 * 60; // 10:00
  static const defaultEndMinute = 18 * 60 + 10; // 18:10

  /// BIST piyasa saatleri — "Piyasa kapalı" etiketi bu aralığa bakar.
  ///
  /// Kullanıcının seçtiği GÖSTERİM penceresinden ayrıdır: kullanıcı
  /// 7/24 gösterim seçse bile gece fiyat değişmez ve banner bunu
  /// söylemelidir, yoksa donuk rakam "bozuk" gibi görünür.
  static const _marketOpenMinute = 10 * 60;
  static const _marketCloseMinute = 18 * 60 + 10;

  /// Apple'ın Live Activity oturum limiti.
  ///
  /// Sistem 8 saat sonra oturumu ZORLA kapatır. Kullanıcı daha geniş bir
  /// pencere seçerse oturum bu süreyle sınırlanır ve uygulama her
  /// açıldığında yenilenir. Aşılamaz — Apple'ın kuralı.
  static const _maxSessionDuration = Duration(hours: 8);

  /// Kullanıcının seçtiği gösterim penceresi (dakika, gün başından ofset).
  ///
  /// `main.dart` her senkronda tercihten günceller; servis Riverpod'a
  /// bağlı olmadığı için (singleton) provider'ı kendisi okuyamaz.
  int startMinute = defaultStartMinute;
  int endMinute = defaultEndMinute;

  /// Hafta sonu da gösterilsin mi? Varsayılan AÇIK.
  ///
  /// Hafta sonu BIST kapalıdır ama bu yüzeyi gizlemek için sebep değil:
  /// banner "Piyasa kapalı" etiketiyle rakamın neden sabit olduğunu
  /// zaten söylüyor. Kullanıcı hafta sonu da portföyünü görebilmeli.
  bool includeWeekend = true;

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

  /// Gün içi serinin HAM (TRY) uçları — günlük kâr/zarar bunlardan çıkar.
  ///
  /// Normalize seri (0…1) yalnızca şekli taşır; tutar hesabı için ham
  /// değerler gerekir. Sparkline ile AYNI çağrıdan doldurulur ki grafik
  /// ile rakam asla ayrışmasın: kullanıcı çizginin başladığı ve bittiği
  /// yeri görüp aradaki farkı rakamda okur.
  double? _dayOpenTRY;
  double? _dayLastTRY;

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
    _dayOpenTRY = null;
    _dayLastTRY = null;
    // Pencere ayarları da sıfırlanır: singleton olduğu için bir testin
    // seçtiği saat aralığı sonrakine taşar ve sessizce yanlış sonuç verir.
    startMinute = defaultStartMinute;
    endMinute = defaultEndMinute;
    includeWeekend = true;
    showAmountsOnLockScreen = false;
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
            // `dateText` BURAYA yazılmaz: push anında sunucu kendi
            // üretir. İstemcinin yazdığı tarih gece yarısını geçen bir
            // oturumda eskimiş olur ve kilit ekranı dünün tarihini
            // gösterirdi — `updatedAtText` ile aynı gerekçe.
            'isMarketOpen': payload['isMarketOpen'],
            // Özetin hangi ANLAM sürümüyle yazıldığı.
            //
            // v1'de `changeText` ÖMÜRLÜK getiriydi; v2'de günlük değişim.
            // İki sürüm aynı alan adını farklı anlamda kullanıyor, bu
            // yüzden sunucu ayırt edebilmeli: damgasız bir satır eski
            // uygulamadan kalmadır ve push'lanırsa kullanıcı kilit
            // ekranında yine ömürlük getiriyi "Bugün" diye görür.
            'schema': summarySchemaVersion,
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
        // Ham uçlar da BURADA saklanır: grafik ile günlük kâr/zarar
        // rakamı aynı seriden çıksın, iki kaynak ayrışmasın.
        final values = _dayValues(series, now, state.totalValue);
        _dayOpenTRY = values.isEmpty ? null : values.first;
        _sparkline = _normalize(values);
      } catch (e) {
        if (kDebugMode) debugPrint('Sparkline çekilemedi: $e');
      }
    }

    // Serinin UCU her senkronda canlı toplama oturur — seri 5 dakikada
    // bir tazelense de günlük rakam fiyat tick'iyle birlikte hareket
    // etmeli. Aksi halde kilit ekranı 5 dakikalık basamaklarla güncellenir
    // ve uygulama ile kilit ekranı aynı anda farklı rakam gösterir.
    if (_dayOpenTRY != null && state.totalValue > 0) {
      _dayLastTRY = state.totalValue;
    }

    return _sparkline ?? const [];
  }

  /// Gün içi seriyi uygulamanın GÜNLÜK grafiğiyle birebir aynı kurallarla
  /// ham (TRY) değer listesine indirger.
  ///
  /// Kurallar `portfolio_performance_screen._convertHistoryToSegments`
  /// (intraday dalı) ile aynıdır ve aynı olmak ZORUNDADIR — kilit ekranıyla
  /// uygulama farklı bir çizgi gösterirse kullanıcı hangisine güveneceğini
  /// bilemez:
  ///   1. Gelecekteki slotlar atılır (`ts > now`). Kaynak 24 saatlik grid
  ///      üretir; günün geri kalanı henüz olmamıştır.
  ///   2. `y <= 0` slotlar atlanır — borsa açılmadan önceki boş slotlar.
  ///      Bunlar bırakılırsa normalize edilen aralık 0'dan başlar ve
  ///      gerçek gün içi hareket düz bir çizgiye ezilir. (Kilit ekranındaki
  ///      grafiğin "hep aynı" görünmesinin sebebi buydu.)
  ///   3. Son nokta canlı toplama sabitlenir — grafiğin ucu her zaman
  ///      "şu andaki portföy değeri" olmalı.
  @visibleForTesting
  static List<double> dayValues(
    Map<int, double> series,
    DateTime now,
    double currentTotal,
  ) =>
      _dayValues(series, now, currentTotal);

  static List<double> _dayValues(
    Map<int, double> series,
    DateTime now,
    double currentTotal,
  ) {
    if (series.isEmpty) return const [];
    final nowMs = now.millisecondsSinceEpoch;
    final keys = series.keys.toList()..sort();

    final values = <double>[];
    for (final k in keys) {
      if (k > nowMs) break;
      final v = series[k]!;
      if (v <= 0) continue;
      values.add(v);
    }
    if (values.isEmpty) return const [];

    // Grafiğin ucu canlı toplama oturur. Ekrandaki grafik bunu
    // `currentTotalOverride` ile yapıyor; burada da aynısı yapılmazsa
    // kilit ekranı son 5 dakikalık slotta donmuş görünür.
    if (currentTotal > 0) values[values.length - 1] = currentTotal;

    return values;
  }

  /// Ham TRY serisini 0…1 aralığına indirger — bkz. gizlilik notu.
  static List<double> _normalize(List<double> values) {
    if (values.length < 2) return const [];

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

  /// [now] anında Live Activity GÖSTERİLMELİ mi?
  ///
  /// Kullanıcının seçtiği pencereye bakar — piyasa saatlerine değil.
  /// Gece de gösterim seçilebilir; o durumda banner "Piyasa kapalı"
  /// etiketiyle son kapanışı gösterir (bkz. [isMarketOpen]).
  ///
  /// **Gece aşan pencere desteklenir:** başlangıç > bitiş ise (ör.
  /// 22:00–06:00) aralık gece yarısını sarar. Naif bir `start <= x < end`
  /// karşılaştırması böyle bir pencerede HİÇBİR ZAMAN doğru olmazdı.
  ///
  /// Resmî tatiller BURADA bilinmez — takvim gerektirir ve yanlış bir
  /// tatil listesi, listesizlikten kötüdür. (Bkz. TECHNICAL_DEBT.md)
  bool isWithinWindow(DateTime now) {
    if (!includeWeekend &&
        (now.weekday == DateTime.saturday ||
            now.weekday == DateTime.sunday)) {
      return false;
    }

    final mins = now.hour * 60 + now.minute;

    // Tam gün (7/24) — başlangıç ve bitiş aynıysa kullanıcı sınır
    // koymamış demektir.
    if (startMinute == endMinute) return true;

    if (startMinute < endMinute) {
      return mins >= startMinute && mins < endMinute;
    }
    // Gece yarısını saran pencere: 22:00–06:00 gibi.
    return mins >= startMinute || mins < endMinute;
  }

  /// BIST işlem saatleri içinde miyiz? Fiyatların gerçekten hareket
  /// ettiği aralık.
  ///
  /// [isWithinWindow]'dan AYRI: kullanıcı 7/24 gösterim seçse bile gece
  /// fiyat değişmez. Banner bunu söylemezse donuk rakam "bozuk" görünür.
  @visibleForTesting
  static bool isMarketOpen(DateTime now) {
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final mins = now.hour * 60 + now.minute;
    return mins >= _marketOpenMinute && mins < _marketCloseMinute;
  }

  /// Oturumun bitiş anı — Live Activity'nin `staleDate`'i.
  ///
  /// İki sınırın ERKEN olanı:
  ///   * kullanıcının seçtiği pencerenin bitişi,
  ///   * Apple'ın 8 saatlik oturum limiti.
  ///
  /// Limit aşılırsa sistem oturumu zaten kapatır; `staleDate`'i ondan
  /// sonraya koymak kullanıcıya "hâlâ canlı" yanılsaması verirdi.
  DateTime sessionEnd(DateTime now) {
    final hardLimit = now.add(_maxSessionDuration);

    // 7/24 pencerede takvim sınırı yok; yalnızca Apple limiti geçerli.
    if (startMinute == endMinute) return hardLimit;

    var end = DateTime(now.year, now.month, now.day)
        .add(Duration(minutes: endMinute));
    // Bitiş geçmişte kaldıysa (gece aşan pencere) yarına taşı.
    if (!end.isAfter(now)) end = end.add(const Duration(days: 1));

    return end.isBefore(hardLimit) ? end : hardLimit;
  }

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

      if (!isWithinWindow(ts)) {
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
      final unchanged = _sessionActive && key == _lastPayloadKey;

      // Özeti sunucuya yaz — push döngüsü (cron, 5 dk) bunu okuyup APNs'e
      // gönderir. Böylece uygulama kapalıyken de kilit ekranı güncellenir.
      //
      // **ActivityKit çağrısından ÖNCE ve ONDAN BAĞIMSIZ yazılır.** Eskiden
      // yalnızca `ok == true` iken yazılıyordu ve iki durumda sessizce
      // bayat kalıyordu:
      //   * Oturum ölmüşse (Apple'ın 8 saat sınırı) `_invoke` false döner
      //     ve özet HİÇ yazılmazdı — sunucu sonsuza kadar eski rakamı
      //     push'lardı.
      //   * Erken çıkışta (aşağıdaki `unchanged`) da yazılmazdı; oysa
      //     ekrandaki metin aynı olsa bile DB'deki kayıt eski SÜRÜMDEN
      //     kalma olabilir. Ömürlük getiriyi günlük diye gösteren hata
      //     tam olarak böyle hayatta kaldı: uygulama güncellendi ama
      //     kilit ekranı eski özetten beslenmeye devam etti.
      //
      // `_writeSummary` kendi içinde zaten tekrarı eliyor; buradan her
      // senkronda çağırmak fazladan DB turu açmaz.
      //
      // `await` EDİLMEZ: Live Activity ikincil bir yüzey, DB turu
      // uygulamanın akışını bekletmemeli.
      unawaited(_writeSummary(payload).catchError((Object e) {
        if (kDebugMode) debugPrint('Özet yazılamadı: $e');
      }));

      if (unchanged) return;

      final ok = await _invoke(
        _sessionActive ? 'update' : 'start',
        {...payload, 'sessionName': _sessionName},
      );

      if (ok) {
        _sessionActive = true;
        _lastPayloadKey = key;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LiveActivity sync failed: $e');
    }
  }

  /// Bugünün kâr/zararı — tutar (TRY) ve oran (%).
  ///
  /// **Neden `state.gainLoss` DEĞİL:** o alan varlığın alındığı günden
  /// bugüne TÜM getiridir (temettü dahil). Kilit ekranındaki etiketler
  /// "Bugün" / "Bugünkü Net Kazanç" / "Günlük" diyor; oraya ömürlük
  /// getiriyi basmak doğrudan yanlış bilgidir — kullanıcı %40'lık toplam
  /// kazancı günlük hareket sanır.
  ///
  /// Gün içi serinin ilk ve son noktası kullanılır; uygulamanın "Bugünkü
  /// değişim" kartıyla ([_buildPeriodChangeCard]) aynı mantık: son − ilk.
  /// Seri yoksa (veri çekilemedi) `null` döner ve çağıran taraf yüzeyi
  /// uydurma rakamla doldurmaz.
  ({double amount, double pct})? _todayChange() {
    final open = _dayOpenTRY;
    final last = _dayLastTRY;
    if (open == null || last == null || open <= 0) return null;
    final amount = last - open;
    return (amount: amount, pct: amount / open * 100);
  }

  /// Kilit ekranına gidecek özet. Gizlilik kuralı burada uygulanır.
  Map<String, dynamic> _payload(
    PortfolioState state, {
    required bool hideBalance,
    required DateTime now,
    List<double> sparkline = const [],
  }) {
    final today = _todayChange();
    // Gün içi seri yoksa yön bilgisi de yok — nötr (pozitif) varsayılır,
    // aşağıda tutar/oran zaten "—" olarak gider.
    final isPos = (today?.amount ?? 0) >= 0;
    final endsAt = sessionEnd(now);
    final updatedAt = DateFormat('HH:mm', 'tr_TR').format(now);
    // Tarih kilit ekranında AÇIKÇA yazılır. Live Activity saatlerce
    // durabilir ve gece yarısını geçebilir; yalnızca "14:32" gören
    // kullanıcı hangi güne ait olduğunu bilemez.
    final dateText = DateFormat('d MMMM EEEE', 'tr_TR').format(now);

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
        'dateText': dateText,
        'sessionEndsAtMs': endsAt.millisecondsSinceEpoch,
        'sparkline': const <double>[],
        'showAmounts': false,
        'isMarketOpen': isMarketOpen(now),
      };
    }

    return {
      // Türkçe biçim TEK yerde üretilir (tr_format) ve hazır metin olarak
      // gider; Swift tarafında ikinci bir biçimlendirici tutulmaz.
      'totalText': fmtTRY(state.totalValue, digits: 2),
      // GÜNLÜK değişim — ömürlük getiri değil. Seri yoksa uydurma rakam
      // yerine "—" gider; kilit ekranında yanlış sayı, sayısızlıktan kötü.
      'changeText': today == null
          ? '—'
          : '${isPos ? '+' : '-'}${fmtTRY(today.amount.abs(), digits: 2)}',
      'changePctText':
          today == null ? '—' : fmtPct(today.pct.abs(), digits: 2),
      'isPositive': isPos,
      'isHidden': false,
      'updatedAtText': updatedAt,
      'dateText': dateText,
      'sessionEndsAtMs': endsAt.millisecondsSinceEpoch,
      // Normalize (0…1) — ham tutar taşımaz, yalnızca günün şekli.
      'sparkline': sparkline,
      'showAmounts': showAmountsOnLockScreen,
      // Piyasa kapalıysa banner "Piyasa kapalı" der; kullanıcı rakamın
      // neden değişmediğini bilir. Gösterim penceresinden AYRI bir
      // kavram: 7/24 gösterim seçilse bile gece fiyat hareket etmez.
      'isMarketOpen': isMarketOpen(now),
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
