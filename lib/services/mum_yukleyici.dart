import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/ohlc.dart';
import 'crash_reporter.dart';
import 'history_service.dart' show FiyatKaynagi, MumKaynakTuru;
import 'mum_verisi.dart';

/// Bir ekranın gerçek mum isteği — "build sırasında iste, eldekini döndür".
///
/// Varlık detayının `_ohlcBarlari` deseninin ekrandan bağımsız hâli
/// (`asset_detail/grafik_katmanlari.dart`): varlık sayfası ve Karşılaştır
/// aynı kuralla ister (yasin 2026-10-10 gece, üç ekran tutarlı).
///
///  · Build sırasında çağrılır, senkron setState yapmaz; yanıt gelince
///    [onDegisti] çağrılır (çağıran `setState`).
///  · İstek anahtarı zamanla da değişir (gün içi aralıkta dakikada,
///    diğerlerinde on dakikada bir): açık ekran oluşan mumu tazeler, aradaki
///    çağrılar `MumVerisi` önbelleğinden döner.
///  · Boş yanıt eldeki iyi mumları silmez (bayat ama ölçülmüş veri).
///  · Bu aralığın ve pencerenin mumu henüz yoksa null döner: çağıran
///    kapanıştan türetilen muma (ya da çizgiye) düşer — ekran boş kalmaz.
class MumYukleyici {
  MumYukleyici({required this.onDegisti, required this.neden});

  final VoidCallback onDegisti;

  /// Crashlytics'teki `reason` (hangi ekran).
  final String neden;

  bool _kapali = false;
  String? _istenen;

  /// Son istenen anahtarın yanıtı geldi mi (boş da olsa).
  String? _tamamlanan;

  /// Son istek hâlâ yolda mı. Çağıran "henüz yok" ile "hiç gelmeyecek"
  /// (kaynak boş döndü, ağ hatası) arasını ayırır: yoldayken göstergeyi
  /// çizmez (gelince bir kez çizilir), gelmezse çizginin noktalarına düşer.
  /// Eskiden yükleme sırasında çizgiden hesaplanan ortalama çiziliyor,
  /// çubuklar gelince başka bir ortalamaya atlıyordu — "grafik bozulup
  /// tekrar çiziliyor" (yasin 2026-10-11).
  bool get bekliyor => _istenen != null && _tamamlanan != _istenen;
  ({MumAraligi aralik, int basMs, List<OhlcBar> barlar})? _veri;

  /// Ekran kapanınca: gecikmiş yanıt [onDegisti]'yi çağırmaz.
  void kapat() => _kapali = true;

  /// [a]'nın [bas, son] penceresindeki [aralik] mumları; [isinma] mum kadar
  /// önceden başlar (Pine betiğinin ısınması). [gunIci] → pencere bir
  /// takvim günü.
  List<OhlcBar>? mumlar({
    required Asset a,
    required MumAraligi aralik,
    required DateTime bas,
    required DateTime son,
    required double canliBirim,
    required bool gunIci,
    int isinma = 0,
  }) {
    var istekBas = bas;
    if (isinma > 0) {
      // Seansı olan piyasada gün içi mum gece/hafta sonu yoktur: duvar
      // saatinde daha geriye gidilir ki ısınma yine ~[isinma] mum olsun.
      final carpan = aralik.gunIci ? 4 : 1.5;
      istekBas = bas.subtract(
          Duration(minutes: (aralik.dakika * isinma * carpan).round()));
      // Yahoo bu aralıkta geriye ancak [MumAraligi.yahooGecmisGun] verir
      // (1 dk: 8 gün). Isınma bu sınırı aşarsa istek BOŞ döner ve dönemin
      // kendi mumları da kaybolurdu: ısınma sınırda kırpılır, ortalama o
      // zaman dönemin biraz içinden başlar (uydurma yok).
      final sinir = aralik.yahooGecmisGun;
      if (sinir != null &&
          FiyatKaynagi.mumKaynagi(a).tur == MumKaynakTuru.yahoo) {
        final enEski = DateTime.now().subtract(Duration(days: sinir));
        if (istekBas.isBefore(enEski)) {
          istekBas = enEski.isBefore(bas) ? enEski : bas;
        }
      }
    }
    final basMs = istekBas.millisecondsSinceEpoch;
    final adim = aralik.gunIci ? 60000 : 600000;
    final anahtar = '${a.ticker}|${aralik.name}|${bas.millisecondsSinceEpoch}|'
        '$isinma|${DateTime.now().millisecondsSinceEpoch ~/ adim}';
    if (_istenen != anahtar) {
      _istenen = anahtar;
      final pencereSonu = gunIci ? bas.add(const Duration(days: 1)) : son;
      final simdi = DateTime.now();
      final yukleme = MumVerisi.instance
          .mumlar(
            a: a,
            aralik: aralik,
            bas: istekBas,
            son: pencereSonu.isAfter(simdi) ? simdi : pencereSonu,
            canliBirim: canliBirim,
          )
          .then<void>((barlar) {
        if (_kapali || _istenen != anahtar) return;
        _tamamlanan = anahtar;
        if (barlar.isEmpty &&
            _veri?.aralik == aralik &&
            _veri?.basMs == basMs) {
          onDegisti();
          return;
        }
        _veri = (aralik: aralik, basMs: basMs, barlar: barlar);
        onDegisti();
      });
      CrashReporter.arkaPlan(yukleme, reason: neden);
    }
    final o = _veri;
    if (o == null || o.aralik != aralik || o.basMs != basMs) return null;
    return o.barlar.length >= 2 ? o.barlar : null;
  }
}
