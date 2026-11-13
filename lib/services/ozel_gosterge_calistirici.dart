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

/// Açık bir göstergenin bu grafikte neden çizilmediği. Liste satırında tek
/// nötr satır olarak söylenir (2026-11-13: çip "2 açık" deyip tek çizgi
/// çizilince kullanıcı nedenini bilmiyordu). Yalnız çalıştırıcının GERÇEKTEN
/// ayırt edebildiği nedenler; gerisi [genel].
enum OzelAtlamaNedeni {
  /// Betik `volume` kullanıyor, seride hacim yok (fon, endeks, parite) ve
  /// hiçbir şey çizilmedi.
  hacimYok,

  /// Betik açılış/yüksek/düşük kullanıyor, seride yok (gerçek mumu olmayan
  /// varlık: fon, BES) ve hiçbir şey çizilmedi.
  ohlcYok,

  /// İşlem bütçesi aşıldı (`BetikHatasi.agir`): daha kısa aralık daha az
  /// çubuk demek, kullanıcının elindeki tek düğme bu.
  agir,

  /// Başka çalışma hatası ya da betik çalıştı ama çizecek bir şey çıkmadı.
  genel,
}

/// Çalıştırmanın raporu: çizilenler ve atlananlar (gösterge kimliği →
/// neden). Çipteki sayı [cizilen]'in uzunluğudur — açık olanların değil.
typedef OzelCalistirma = ({
  List<OzelSonuc> cizilen,
  Map<String, OzelAtlamaNedeni> atlanan,
});

/// Kod + veri parmak izi → atlama nedeni. Bütçeyi aşan betik eskiden her
/// build'de (crosshair, zoom) 40 milyon işlemi yeniden yakıp atlanıyordu;
/// başarılı sonuç gibi o da saklanır.
final Map<String, OzelAtlamaNedeni> _atlamaOnbellegi = {};

/// Açık göstergeleri çalıştırır; yalnız çizilenleri döndürür (bkz.
/// [ozelGostergeleriCalistirRapor]).
List<OzelSonuc> ozelGostergeleriCalistir(
        List<OzelGosterge> acik, BetikVerisi veri) =>
    ozelGostergeleriCalistirRapor(acik, veri).cizilen;

/// Açık göstergeleri çalıştırır. Çalışma hatası (bütçe aşımı) ya da boş
/// sonuç (seride olmayan veriyi isteyen betik) o göstergeyi atlar ve nedeni
/// [OzelCalistirma.atlanan]'a yazılır; düzenleyici aynı hatayı satırıyla
/// gösterir. Sonuç kod + veri parmak izine göre saklanır: Pine betiği çubuk
/// çubuk çalışır ve her build'de (crosshair, zoom) yeniden koşmasın.
/// Göstergeler sayfası da aynı veriyle çağırır; önbellekten okur.
OzelCalistirma ozelGostergeleriCalistirRapor(
    List<OzelGosterge> acik, BetikVerisi veri) {
  if (acik.isEmpty || veri.uzunluk == 0) {
    return (cizilen: const [], atlanan: const {});
  }
  final iz = Object.hash(veri.uzunluk, veri.x.first, veri.x.last,
      veri.kapanis.last, veri.kapanis[veri.uzunluk ~/ 2]);
  final out = <OzelSonuc>[];
  final atlanan = <String, OzelAtlamaNedeni>{};
  for (final g in acik) {
    final d = derlenmisBetik(g.kod);
    if (d == null) continue; // derlenmeyen zaten "Hatalı, düzenle" der
    final anahtar = '${g.kod.hashCode}|$iz';
    final eskiNeden = _atlamaOnbellegi[anahtar];
    if (eskiNeden != null) {
      atlanan[g.id] = eskiNeden;
      continue;
    }
    var s = _sonucOnbellegi[anahtar];
    if (s == null) {
      try {
        s = d.calistir(veri);
        if (_sonucOnbellegi.length > 32) _sonucOnbellegi.clear();
        _sonucOnbellegi[anahtar] = s;
      } on BetikHatasi catch (e) {
        _atlamaYaz(
            anahtar,
            atlanan[g.id] =
                e.agir ? OzelAtlamaNedeni.agir : OzelAtlamaNedeni.genel);
        continue;
      }
    }
    if (s.bos) {
      // Eksik veri çizgileri `na` bırakır; çizilen hiçbir şey yoksa çipte
      // sayılmaz, satırda nedeni yazılır. Bir kısmı çizildiyse sayılır
      // (düzenleyici `ozgEksikVeri` notunu zaten düşer).
      _atlamaYaz(
          anahtar,
          atlanan[g.id] = s.eksikVeri.contains('hacim')
              ? OzelAtlamaNedeni.hacimYok
              : s.eksikVeri.isNotEmpty
                  ? OzelAtlamaNedeni.ohlcYok
                  : OzelAtlamaNedeni.genel);
      continue;
    }
    out.add((g: g, s: s, v: veri));
  }
  return (cizilen: out, atlanan: atlanan);
}

void _atlamaYaz(String anahtar, OzelAtlamaNedeni neden) {
  if (_atlamaOnbellegi.length > 32) _atlamaOnbellegi.clear();
  _atlamaOnbellegi[anahtar] = neden;
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
