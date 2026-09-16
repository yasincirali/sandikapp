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

  /// Ay başı → endeks değeri, artan tarih sırasında değil, Map olarak.
  ///
  /// Karşılaştırma ekranı TÜFE'yi portföyle aynı yüzde düzleminde BASAMAKLI
  /// çizer (`TufeSeries`). Değer AYLIK yayımlanır; ara günler için
  /// interpolasyon yapılmaz — TÜİK'in açıklamadığı bir sayı üretmek olurdu.
  Future<Map<DateTime, double>> indexSeries() => _yukle();

  /// Endeksi bir karşılaştırma penceresine oturtur: `<zaman damgası, endeks>`.
  ///
  /// Kural (2026-09-14 incelemesiyle düzeltildi):
  /// - Pencere içinde hiç açıklama yoksa BOŞ döner — aylık bir göstergeyi
  ///   haftalık pencerede çizmek anlamsız; satır "yeterli veri yok" der.
  /// - Pencere başındaki nokta, o an YÜRÜRLÜKTE olan endekstir (pencereden
  ///   önce açıklanmış son ay), damgası pencere başına çakılır. Eskiden
  ///   yalnızca pencere içindeki aylar alınıyordu: 1A'da tek ay + taşınan
  ///   nokta = iki EŞİT değer, yani düz %0 çizgisi. Kullanıcı "bir ayda
  ///   enflasyon sıfır" diye okuyordu.
  /// - Son açıklanan ay [simdi]'ye kadar sabit taşınır; ara gün üretilmez.
  static Map<int, double> pencereSerisi(
    Map<DateTime, double> endeks,
    DateTime simdi,
    int days,
  ) {
    if (endeks.isEmpty) return const {};
    final baslangic = simdi.subtract(Duration(days: days));
    final aylar = endeks.keys.where((a) => !a.isBefore(baslangic)).toList()
      ..sort();
    if (aylar.isEmpty) return const {};

    final out = <int, double>{};
    final oncekiler = endeks.keys.where((a) => a.isBefore(baslangic)).toList()
      ..sort();
    if (oncekiler.isNotEmpty) {
      out[baslangic.millisecondsSinceEpoch] = endeks[oncekiler.last]!;
    }
    for (final a in aylar) {
      out[a.millisecondsSinceEpoch] = endeks[a]!;
    }
    final sonAy = aylar.last;
    if (simdi.isAfter(sonAy)) {
      out[simdi.millisecondsSinceEpoch] = endeks[sonAy]!;
    }
    return out;
  }

  /// Endeks tablosunda hiç satır var mı?
  ///
  /// Çoğu çağıran [isStale] istiyor: boş tablo ile DURMUŞ seri kullanıcı
  /// açısından aynı sonucu doğurur (reel getiri hesaplanamaz) ve `isStale`
  /// ikisini birden kapsar. Bu metot ayrımın kendisi gerektiğinde —
  /// teşhiste — duruyor.
  Future<bool> hasIndexData() async => (await _yukle()).isNotEmpty;

  /// Endeksin BAYAT sayıldığı eşik (ay).
  ///
  /// TÜİK bir ayın verisini ertesi ayın 3'ünde yayımlar, yani normalde son
  /// satır en fazla bir ay geridedir. İki ay tolerans, gecikmeli yayın ya
  /// da çekim turunun bir ayı kaçırması için pay bırakır.
  ///
  /// **Neden bir eşik gerekiyor.** Ölçüldü (2026-09-14): TÜİK Ocak 2026'da
  /// baz yılını 2003=100'den 2025=100'e çevirdi ve eski `TP.FG.J0` serisi o
  /// ayda SONA ERDİ. Tablo dolu görünüyordu (29 satır) ama son satır sekiz
  /// ay eskiydi. Bu kapı olmasaydı ekran "son 1 yılın enflasyonu" diye
  /// Şubat 2025 – Ocak 2026 aralığını gösterir, kullanıcı bunu TÜİK'in
  /// açıkladığı güncel rakamla karşılaştırır ve tutmadığını görürdü.
  ///
  /// Bayat veriyle hesap yapmamak, `changePct`'in eksik uçta `null`
  /// dönmesiyle aynı disiplin: yanlış bir sayı, hiç sayı olmamasından
  /// kötüdür.
  static const bayatlikEsigiAy = 2;

  /// Endeksin son satırı bayat mı? Tablo boşsa da `true`.
  Future<bool> isStale({DateTime? now}) async {
    final endeks = await _yukle();
    if (endeks.isEmpty) return true;
    final bugun = now ?? DateTime.now();
    final sonAy = endeks.keys.reduce((a, b) => a.isAfter(b) ? a : b);
    final gecenAy =
        (bugun.year - sonAy.year) * 12 + (bugun.month - sonAy.month);
    return gecenAy > bayatlikEsigiAy;
  }

  /// Endeksin son satırının ayı — teşhis ve "veri şu tarihe kadar" notu
  /// için. Tablo boşsa `null`.
  Future<DateTime?> latestPeriod() async {
    final endeks = await _yukle();
    if (endeks.isEmpty) return null;
    return endeks.keys.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Gün sayısını AY sayısına çevirir.
  ///
  /// 365 gün → 12 ay, 180 → 6, 30 → 1. Yuvarlama en yakına yapılır:
  /// çağıranlar takvim dönemlerini gün cinsinden ifade ediyor
  /// (`SummaryPeriod.days`) ve 365/30 = 12,17 gibi bir artık, aşağı
  /// yuvarlansa pencereyi bir ay kısaltırdı.
  static int aySayisi(int gun) {
    final ay = (gun / 30.44).round();
    return ay < 1 ? 1 : ay;
  }

  /// Son [gun] gün için TÜFE değişimi. Endeks eksik ya da BAYATSA `null`.
  ///
  /// **Pencere SON AÇIKLANMIŞ AYDAN geriye sayılır, bugünden değil.**
  /// Ölçüldü (2026-09-14): bugünden 365 gün geriye gidip ay başına
  /// yuvarlamak 2025-09-01 veriyordu; son açıklanmış ay 2026-08 olduğu
  /// için aralık 11 AY oluyordu ve ana ekran şeridi TÜFE'yi %27 diye
  /// yazıyordu — TÜİK'in açıkladığı yıllık %31,51 yerine. Kullanıcı iki
  /// sayıyı karşılaştırıp uygulamaya güvenmeyi bırakır.
  ///
  /// Doğrusu: 365 gün = 12 ay ve 12 ay geriye sayılacak uç, bugünün ayı
  /// değil son açıklanmış aydır. TÜİK "yıllık enflasyon"u da böyle kurar
  /// (Ağustos 2025 → Ağustos 2026).
  Future<double?> inflationForPeriod(int gun, {DateTime? now}) async =>
      (await pencere(gun, now: now))?.pct;

  /// TÜFE değişimi ve ÖLÇÜLDÜĞÜ pencere birlikte.
  ///
  /// **Neden yüzde tek başına yetmiyor (2026-09-16).** Ölçüldü: nominal
  /// getiri bugünden geriye sayılıyordu (`donemBaslangici(now, 12)` →
  /// 2025-09-16 … 2026-09-16), TÜFE ise son açıklanmış aydan
  /// (2025-08-01 … 2026-08-01). İki sayı aynı satırda "nominal − TÜFE"
  /// diye çıkarılıyordu ama FARKLI zaman dilimlerine aitti: 1Y'de ~1,5 ay
  /// kayma, 1A'da pencereler HİÇ KESİŞMİYORDU (portföyün 16 Ağustos–16
  /// Eylül getirisi Temmuz enflasyonuyla kıyaslanıyordu).
  ///
  /// TÜFE ucunun son açıklanmış ay olması DOĞRU ve korunuyor — TÜİK'in
  /// "yıllık enflasyon"u böyle kurulur ve kullanıcı rakamı oradan
  /// doğruluyor. Düzeltme ters yönde: nominal getiri bu pencereye
  /// hizalanır. Bunun için çağıranın uçları BİLMESİ gerekiyor, yüzdeyi
  /// değil — [InflationWindow] onları taşır.
  ///
  /// [ilkAy] ve [sonAy] endeks tablosunun anahtarlarıdır (ayın 1'i).
  /// Portföy serisi için anlamlı uçlar [seriBaslangici] ve [seriBitisi]:
  /// endeks bir AYIN ortalama seviyesini değil, o ayın ölçümünü taşır ve
  /// TÜİK karşılaştırması "Ağustos → Ağustos" olduğu için portföy penceresi
  /// de ilk ayın SONUNDAN son ayın SONUNA kurulur.
  Future<InflationWindow?> pencere(int gun, {DateTime? now}) async {
    final endeks = await _yukle();
    if (endeks.isEmpty) return null;
    final bugun = now ?? DateTime.now();

    // Son AÇIKLANMIŞ ay: TÜİK bir ayın verisini ertesi ayın 3'ünde
    // yayımlar, yani içinde bulunulan ay tabloda henüz yoktur.
    final sonAy = endeks.keys.reduce((a, b) => a.isAfter(b) ? a : b);

    // Bayatlık kapısı ([bayatlikEsigiAy] notuna bakın): seri durmuşsa
    // pencere sessizce geriye kayar ve gösterilen sayı kullanıcının TÜİK'te
    // gördüğüyle tutmaz.
    final gecenAy =
        (bugun.year - sonAy.year) * 12 + (bugun.month - sonAy.month);
    if (gecenAy > bayatlikEsigiAy) return null;

    // Uç, son açıklanmış aydan geriye sayılır (yukarıdaki nota bakın).
    final ilkAy = DateTime(sonAy.year, sonAy.month - aySayisi(gun), 1);
    final pct = changePct(endeks, ilkAy, sonAy);
    if (pct == null) return null;
    return InflationWindow(ilkAy: ilkAy, sonAy: sonAy, pct: pct);
  }

  /// Son açıklanmış ayın AYLIK TÜFE değişimi (bir önceki aya göre).
  ///
  /// Aylık özetin sorusu yıllıktan farklı: "bu ay eridim mi". Yıllık TÜFE
  /// bir aylık pencereye uygulanınca portföyü haksız yere kötü gösterir —
  /// %31,5'lik yıllık enflasyonu bir ayın getirisinden düşmek, o ayı
  /// otomatik olarak kayıp yazar.
  ///
  /// Ardışık iki ay gerekir; biri eksikse `null` (eksik veriyle tahmin
  /// yürütmeme disiplini, bkz. [changePct]). Bayatlık kapısı burada da
  /// geçerli.
  Future<double?> monthlyInflation({DateTime? now}) async {
    final endeks = await _yukle();
    if (endeks.isEmpty) return null;
    final bugun = now ?? DateTime.now();

    final sonAy = endeks.keys.reduce((a, b) => a.isAfter(b) ? a : b);
    final gecenAy =
        (bugun.year - sonAy.year) * 12 + (bugun.month - sonAy.month);
    if (gecenAy > bayatlikEsigiAy) return null;

    final oncekiAy = DateTime(sonAy.year, sonAy.month - 1, 1);
    return changePct(endeks, oncekiAy, sonAy);
  }
}

/// Bir TÜFE ölçümü ve ÖLÇÜLDÜĞÜ pencere.
///
/// **Neden uçlar taşınıyor (2026-09-16).** Yüzde tek başına gönderildiğinde
/// çağıran onu kendi penceresiyle kıyaslıyordu ve iki pencere tutmuyordu
/// (bkz. `InflationService.pencere`). Uçlar sayının YANINDA yolculuk edince
/// nominal getiri aynı aralığa kurulabiliyor ve ekran tarih aralığını
/// yazabiliyor — kullanıcı "hangi tarihler arası" sorusunu sorabilmeli,
/// yoksa rakam kara kutu olur.
class InflationWindow {
  const InflationWindow({
    required this.ilkAy,
    required this.sonAy,
    required this.pct,
  });

  /// Pencerenin ilk ayı (endeks anahtarı — ayın 1'i). Bu ayın ENDEKSİ taban
  /// alınır, yani karşılaştırma bu ayın SONUNDAN başlar ([seriBaslangici]).
  final DateTime ilkAy;

  /// Pencerenin son ayı — son açıklanmış TÜFE ayı.
  final DateTime sonAy;

  /// [ilkAy] → [sonAy] TÜFE değişimi (yüzde).
  final double pct;

  /// Portföy serisinin başlangıcı: [ilkAy]'ın SON günü.
  ///
  /// Endeks bir ayın ölçümüdür, ayın ortalaması değil. TÜİK "Ağustos 2025 →
  /// Ağustos 2026" derken iki ÖLÇÜM noktasını kıyaslar; portföyün de aynı
  /// iki noktada değerlenmesi gerekir. Ayın 1'ini almak pencereyi bir ay
  /// uzatır ve farkı sistematik olarak bozardı.
  DateTime get seriBaslangici => DateTime(ilkAy.year, ilkAy.month + 1, 0);

  /// Portföy serisinin bitişi: [sonAy]'ın SON günü ([seriBaslangici] ile
  /// aynı gerekçe).
  DateTime get seriBitisi => DateTime(sonAy.year, sonAy.month + 1, 0);

  /// Pencere kaç ay sayıyor — ekranın "12 aylık" gibi bir etiket yazması
  /// ve testlerin uzunluğu doğrulaması için.
  int get ayAdedi =>
      (sonAy.year - ilkAy.year) * 12 + (sonAy.month - ilkAy.month);
}
