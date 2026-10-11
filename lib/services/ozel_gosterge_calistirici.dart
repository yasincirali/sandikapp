import '../models/ohlc.dart';
import '../models/ozel_gosterge.dart';
import 'gosterge_betigi/betik.dart';

/// Kullanıcı göstergelerini (Pine betiği) grafiğin verisinde çalıştırır —
/// varlık detayı ve varlık sayfası (aramadan, takipten) AYNI derleyici
/// önbelleğini ve AYNI sonuç önbelleğini kullanır.
///
/// İlk sürümde (#160) bu kod varlık detayının part'ındaydı
/// (`asset_detail/ozel_gostergeler.dart`); yasin'in üç ekran tutarlılığı
/// isteğiyle (2026-10-10 gece) varlık sayfası da `ƒx` taşıyınca ortak yere
/// alındı. Çizim `widgets/gosterge_cizimi.dart`'ta.

/// Kod → derlenmiş betik ya da hatası. Her zoom/fiyat turunda yeniden
/// ayrıştırmamak için; kod metni anahtar olduğu için düzenleme kendiliğinden
/// yeni kayıt açar. Sınırlı: 20 gösterge × birkaç sürüm.
final Map<String, Object> _betikOnbellegi = {};

/// Kod + veri parmak izi → sonuç (bkz. [ozelGostergeleriCalistir]).
final Map<String, BetikSonucu> _sonucOnbellegi = {};

/// [kod] derlenebiliyorsa derlenmiş betik, değilse null.
DerlenmisBetik? derlenmisBetik(String kod) {
  final v = _betikOnbellegi[kod] ??= () {
    if (_betikOnbellegi.length > 64) _betikOnbellegi.clear();
    try {
      return GostergeBetigi.derle(kod);
    } on BetikHatasi catch (e) {
      return e;
    }
  }();
  return v is DerlenmisBetik ? v : null;
}

/// Gerçek mumda ısınma: EMA200'ün dönem başında da çizilmesi için.
const int betikIsinmaCubugu = 200;

/// Bir göstergenin sonucu ve çalıştığı veri.
typedef OzelSonuc = ({OzelGosterge g, BetikSonucu s, BetikVerisi v});

/// Grafikte açık ve derlenebilen göstergeler.
List<OzelGosterge> grafiktekiGostergeler(List<OzelGosterge> liste) => [
      for (final g in liste)
        if (g.grafikte && derlenmisBetik(g.kod) != null) g
    ];

/// Açık göstergeleri çalıştırır. Çalışma hatası (bütçe aşımı) o
/// göstergeyi atlar; düzenleyici aynı hatayı satırıyla gösterir.
/// Sonuç kod + veri parmak izine göre saklanır: Pine betiği çubuk çubuk
/// çalışır ve her build'de (crosshair, zoom) yeniden koşmasın.
List<OzelSonuc> ozelGostergeleriCalistir(
    List<OzelGosterge> acik, BetikVerisi veri) {
  if (acik.isEmpty || veri.uzunluk == 0) return const [];
  final iz = Object.hash(veri.uzunluk, veri.x.first, veri.x.last,
      veri.kapanis.last, veri.kapanis[veri.uzunluk ~/ 2]);
  final out = <OzelSonuc>[];
  for (final g in acik) {
    final d = derlenmisBetik(g.kod);
    if (d == null) continue;
    final anahtar = '${g.kod.hashCode}|$iz';
    final hazir = _sonucOnbellegi[anahtar];
    if (hazir != null) {
      out.add((g: g, s: hazir, v: veri));
      continue;
    }
    try {
      final s = d.calistir(veri);
      if (_sonucOnbellegi.length > 32) _sonucOnbellegi.clear();
      _sonucOnbellegi[anahtar] = s;
      out.add((g: g, s: s, v: veri));
    } on BetikHatasi {
      continue;
    }
  }
  return out;
}

/// Gerçek mumdan betik girdisi. [x] mumların grafikteki ortası (grafikteki
/// mumla aynı yer), `time` mumun açılış anı (Pine'daki gibi). Hacmi olmayan
/// barda (endeks, parite) `volume` `na`.
BetikVerisi betikVerisiMumdan(List<OhlcBar> barlar, MumAraligi aralik,
        {required List<double> x, required String sembol}) =>
    BetikVerisi(
      x: x,
      zaman: [for (final b in barlar) b.t.toDouble()],
      acilis: [for (final b in barlar) b.acilis],
      yuksek: [for (final b in barlar) b.enYuksek],
      dusuk: [for (final b in barlar) b.enDusuk],
      kapanis: [for (final b in barlar) b.kapanis],
      hacim: [for (final b in barlar) b.hacim ?? double.nan],
      zamanDilimi: aralik.pineDilimi,
      sembol: sembol,
    );
