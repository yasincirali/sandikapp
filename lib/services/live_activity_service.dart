import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../providers/portfolio_provider.dart';
import '../utils/tr_format.dart';

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

  bool _sessionActive = false;

  /// Son gönderilen içerik — aynı veriyi tekrar tekrar göndermemek için.
  String? _lastPayloadKey;

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

      final payload = _payload(state, hideBalance: hideBalance, now: ts);

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
  }) {
    final isPos = state.gainLoss >= 0;
    final endsAt = sessionEnd(now);
    final updatedAt = DateFormat('HH:mm', 'tr_TR').format(now);

    if (hideBalance) {
      // Tutar HİÇ üretilmez — maskelenmiş metin bile gerçek rakamı
      // taşımaz. Yön de sabitlenir: `isPositive` üstünden kâr/zarar
      // durumu sızmasın.
      return {
        'totalText': '••••••',
        'changeText': '••••••',
        'changePctText': '••',
        'isPositive': true,
        'isHidden': true,
        'updatedAtText': updatedAt,
        'sessionEndsAtMs': endsAt.millisecondsSinceEpoch,
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
