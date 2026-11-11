import 'package:fl_chart/fl_chart.dart' show FlSpot;

/// Fiyatın ortalama maliyeti hangi yönde kestiği.
enum MaliyetKesisimi { yukari, asagi }

/// Fiyat serisinin ortalama maliyeti kestiği noktalar (2026-11-11):
/// X → yön. Varlık sayfası grafiğinde imleç bu günlere gelince hafif
/// titreşim + "Maliyetinin üstüne çıktı / altına indi" satırı.
///
/// Neden: dönem zirvesi/dibi titreşimi (`donemUclariX`) "en yüksek burada"
/// anını yakalatıyor; kişinin kendi parası için asıl an kâra/zarara geçtiği
/// gün. Bunu ancak maliyet çizgisiyle fiyatın kesiştiği yer söyler.
///
/// Kurallar:
/// - [maliyet] yoksa (≤0 dahil) ya da pozisyon kapalıysa ([acik] false)
///   boş: kapanmış pozisyonun "maliyeti" bugünün sorusu değil.
/// - Kesişim X'i yeni tarafa geçilen **ilk noktadır** (o günün kapanışı
///   maliyetin öbür yanında); imleç zaten noktalara oturduğu için ara
///   değer (iki nokta arası) yazılmaz.
/// - Tam maliyete eşit nokta taraf sayılmaz: önceki taraf sürer. Yoksa
///   maliyete değip dönen fiyat iki sahte kesişim üretirdi.
/// - **Gürültü sınırı:** son raporlanan kesişimden [minAralik] (X biriminde;
///   günlük seride gün) içinde gelen kesişimler atlanır — maliyet
///   etrafında testere gibi giden fiyatta her gün titreşim yorucu olur,
///   ilk geçiş asıl haberdir. Atlanan gün etiketsiz kalır; raporlanan
///   satır yalnız O GÜNÜ anlatır ("çıktı/indi"), bugünü değil, yani
///   sonraki ters geçiş atlansa da yazılan cümle yanlış olmaz.
Map<double, MaliyetKesisimi> maliyetKesisimleri(
  List<FlSpot> spots, {
  required double? maliyet,
  required bool acik,
  double minAralik = 7,
}) {
  final m = maliyet;
  if (m == null || m <= 0 || !acik || spots.length < 2) return const {};
  final out = <double, MaliyetKesisimi>{};
  int? taraf; // +1 üstte, -1 altta
  double? sonX;
  for (final s in spots) {
    final t = s.y > m ? 1 : (s.y < m ? -1 : 0);
    if (t == 0) continue;
    if (taraf != null && t != taraf) {
      if (sonX == null || s.x - sonX >= minAralik) {
        out[s.x] = t > 0 ? MaliyetKesisimi.yukari : MaliyetKesisimi.asagi;
        sonX = s.x;
      }
    }
    taraf = t;
  }
  return out;
}
