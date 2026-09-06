import 'package:supabase_flutter/supabase_flutter.dart';

/// TÜFE endeksi ve reel getiri hesabı.
///
/// **Neden bu servis var:** Türk tasarrufçusunun sorusu "kaç kazandım" değil
/// "eridim mi?". Nominal getiri o soruya cevap vermiyor — %40 kazanan bir
/// portföy, %50 enflasyonda alım gücü kaybetmiştir.
///
/// **Veri yoksa özellik yoktur.** `inflation_index` tablosu boş doğar ve
/// endeks değerleri uydurulmaz: yanlış bir TÜFE portföy getirisini olduğundan
/// iyi ya da kötü gösterir, kullanıcı bunu TÜİK'in açıkladığı rakamla
/// karşılaştırır ve uygulamaya güvenmeyi bırakır. Tablo boşken bütün
/// hesaplar `null` döner ve çağıran taraf hiçbir şey çizmez.
class InflationService {
  InflationService._();
  static final InflationService instance = InflationService._();

  /// period (ayın ilk günü) → endeks değeri.
  Map<DateTime, double>? _endeks;
  DateTime? _cekildi;

  /// Endeks ayda bir değişir; gün içinde tekrar sorulması anlamsız.
  static const _cacheTtl = Duration(hours: 12);

  /// Testler için enjeksiyon — üretimde Supabase'den okunur.
  void seedForTest(Map<DateTime, double> endeks) {
    _endeks = endeks;
    _cekildi = DateTime.now();
  }

  void resetForTest() {
    _endeks = null;
    _cekildi = null;
  }

  Future<Map<DateTime, double>> _yukle() async {
    final taze = _cekildi != null &&
        DateTime.now().difference(_cekildi!) < _cacheTtl &&
        _endeks != null;
    if (taze) return _endeks!;

    try {
      final rows = await Supabase.instance.client
          .from('inflation_index')
          .select('period, tufe_index')
          .order('period', ascending: true);

      final out = <DateTime, double>{};
      for (final row in rows as List) {
        final p = DateTime.tryParse(row['period']?.toString() ?? '');
        final v = (row['tufe_index'] as num?)?.toDouble();
        if (p == null || v == null || v <= 0) continue;
        out[ayBasi(p)] = v;
      }
      _endeks = out;
      _cekildi = DateTime.now();
      return out;
    } catch (_) {
      // Sessizce boş dön — reel getiri ikincil bir gösterge, ana ekranı
      // düşürmemeli. Bir sonraki açılışta yeniden denenir.
      return _endeks ?? const {};
    }
  }

  /// Bir tarihi ayın ilk gününe indirger (tablo anahtarıyla aynı biçim).
  static DateTime ayBasi(DateTime t) => DateTime(t.year, t.month, 1);

  /// [from] ile [to] arasındaki TÜFE değişimi, yüzde olarak.
  ///
  /// İki uçtan biri için endeks yoksa `null` döner — eksik veriyle yapılan
  /// tahmin, hesap yapmamaktan kötüdür.
  ///
  /// Endeks DEĞERİ üzerinden tek bölmeyle hesaplanır; aylık yüzdeleri
  /// birbiriyle çarpmak her ay bir yuvarlama hatası eklerdi.
  static double? changePct(
    Map<DateTime, double> endeks,
    DateTime from,
    DateTime to,
  ) {
    final ilk = endeks[ayBasi(from)];
    final son = endeks[ayBasi(to)];
    if (ilk == null || son == null || ilk <= 0) return null;
    return (son / ilk - 1) * 100;
  }

  /// Nominal getirinin enflasyonu kaç PUAN geçtiği.
  ///
  /// Kullanıcıya gösterilen sayı budur: "TÜFE'yi 6,4 puan geçti".
  /// Bileşik reel getiri ((1+n)/(1+e)-1) matematiksel olarak daha doğrudur
  /// ama gündelik dilde "puan farkı" okunuyor ve iki sayı da aynı yönü
  /// verir. Farkın büyüdüğü uçlarda ([realReturnPct]) ayrıca sunulur.
  static double spreadPoints(double nominalPct, double inflationPct) =>
      nominalPct - inflationPct;

  /// Bileşik reel getiri: (1+n)/(1+e) - 1, yüzde olarak.
  static double realReturnPct(double nominalPct, double inflationPct) {
    final payda = 1 + inflationPct / 100;
    if (payda <= 0) return double.nan; // -%100 enflasyon tanımsız
    return ((1 + nominalPct / 100) / payda - 1) * 100;
  }

  /// Son [gun] gün için TÜFE değişimi. Endeks eksikse `null`.
  ///
  /// Uçlar AY BAŞINA yuvarlandığı için gün sayısı yaklaşıktır; TÜİK aylık
  /// yayımladığından bundan daha ince bir çözünürlük mümkün değil.
  Future<double?> inflationForPeriod(int gun, {DateTime? now}) async {
    final endeks = await _yukle();
    if (endeks.isEmpty) return null;
    final bugun = now ?? DateTime.now();

    // Son AÇIKLANMIŞ ay: TÜİK bir ayın verisini ertesi ayın 3'ünde
    // yayımlar, yani içinde bulunulan ay tabloda henüz yoktur.
    final sonAy = endeks.keys.reduce((a, b) => a.isAfter(b) ? a : b);
    final baslangic = ayBasi(bugun.subtract(Duration(days: gun)));
    return changePct(endeks, baslangic, sonAy);
  }
}
