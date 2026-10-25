import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/asset.dart';
import '../services/history_service.dart';

/// Zoom-aware grafik veri controller'ı.
///
/// Grafik viewport'u değiştiğinde çağıran `updateViewport(from, to)` diyerek
/// controller'a bildirir. Controller uygun `ResolutionTier`'ı seçer, debounce
/// eder ve yeni veri yüklenince notify eder. Eski veri set'i yeni geldiğinde
/// silinene kadar ekranda kalır — flicker olmaz.
class ZoomDataController extends ChangeNotifier {
  ZoomDataController({
    required this.assets,
    required this.initialFrom,
    required this.initialTo,
    this.simulate = false,
    Map<int, double> seedData = const {},
    ResolutionTier? manualTier,
    this.eldekiSeri,
    this.tazeKaydet,
  }) {
    _from = initialFrom;
    _to = initialTo;
    _manualTier = manualTier;
    _tier = _cozunurluk();
    // Filtre değişiminde önceki controller'ın verisi tohum olarak gelir.
    // Yeni seri hazır olana kadar ekranda soluk şekilde eski grafik durur;
    // böylece "veri yok" hâli oluşmaz ve tam sayfa spinner'a düşülmez.
    // Bu veri BAŞKA bir filtreye ait — sadece geçici görsel süreklilik
    // içindir, ilk gerçek sonuç geldiğinde tamamen değişir.
    _data = seedData;
    _recomputeDataBounds();
    _stale = seedData.isNotEmpty;
    // İlk yüklemeyi tetikle
    _reload(immediate: true);
    // Önce eski seri: taze hesapla AYNI ANDA, yalnız tohum yoksa (soğuk
    // açılış). Tohum varsa ekranda zaten bir ara kare var.
    final eldeki = eldekiSeri;
    if (eldeki != null && seedData.isEmpty) _eldekiyiGoster(eldeki);
  }

  /// Önce-eski-seri (Ar-Ge 2026-10-25 §4): diskteki son portföy serisi.
  ///
  /// Çağıran (Performans ekranı) yalnız AYNI lot defterinin, aynı kapsam ve
  /// dönemin, tazelik sınırı içindeki serisini döndürür
  /// (`PortfoySeriDepo`); burada yalnız gösterim kuralı var: taze sonuç
  /// henüz gelmediyse soluk ([stale]) çizilir, gelince yerini alır.
  final Future<({Map<int, double> seri, DateTime zaman})?> Function()?
      eldekiSeri;

  /// Taze ve TAM ölçülmüş (bileşenlerin hiçbiri son iyi kopyadan değil)
  /// ilk pencere sonucu — çağıran diske yazar. Zoom/kaydırma ya da elle
  /// bar seçimiyle gelen sonuç yazılmaz: soğuk açılışın penceresi değildir.
  final void Function(Map<int, double> seri)? tazeKaydet;

  /// Ekrandaki veri disk kopyasından mı (taze sonuç gelmedi ya da düştü)?
  bool _diskten = false;
  DateTime? _diskZamani;

  /// Gösterilen seri ağdan TAZE değil, şu anda ölçülmüş de değil: taze çekim
  /// düştü ve seri ya diskteki portföy kopyasından ya da bileşenlerin son iyi
  /// kopyalarından kuruldu. Doluysa ekran net çizer ve altında "Son
  /// güncelleme: …" yazar (`SeriSonGuncelleme`) — sonsuza dek soluk kalmaz,
  /// eski veri de bugünkü sanılmaz.
  DateTime? _sonGuncelleme;
  DateTime? get sonGuncelleme => _sonGuncelleme;

  Future<void> _eldekiyiGoster(
      Future<({Map<int, double> seri, DateTime zaman})?> Function()
          yukle) async {
    final ilkIstek = _requestSeq;
    final ({Map<int, double> seri, DateTime zaman})? e;
    try {
      e = await yukle();
    } catch (_) {
      return; // eski seri ikincil: ekran taze hesabı bekler
    }
    // Taze sonuç önce geldiyse, viewport değiştiyse ya da ekran kapandıysa
    // eski kopya yok sayılır.
    if (e == null ||
        e.seri.length < 2 ||
        _disposed ||
        _settled ||
        _requestSeq != ilkIstek ||
        _data.isNotEmpty) {
      return;
    }
    _data = e.seri;
    _breakdown = const PortfolioHistoryBreakdown.empty();
    _recomputeDataBounds();
    _stale = true;
    _diskten = true;
    _diskZamani = e.zaman;
    notifyListeners();
  }

  final List<Asset> assets;
  final DateTime initialFrom;
  final DateTime initialTo;
  final bool simulate;

  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  ResolutionTier _tier = ResolutionTier.daily;

  /// Kullanıcının seçtiği bar. `null` ise çözünürlük viewport genişliğinden
  /// otomatik türetilir (eski davranış, hiç değişmedi).
  ///
  /// Seçim yapılmışsa zoom bunu GERİ ALAMAZ: kullanıcı 15dk seçip pinch
  /// yaptığında grafiğin sessizce 5dk'ya düşmesi, açıkça verilmiş bir kararı
  /// ezmek olurdu. Çağıran bu değeri [ChartIntervalPolicy.uyarla]'dan
  /// geçirmiş olmalı — controller dönemi bilmez, geçerliliği doğrulayamaz.
  ResolutionTier? _manualTier;

  /// Şu an geçerli çözünürlük: elle seçim varsa o, yoksa viewport'tan.
  ResolutionTier _cozunurluk() =>
      _manualTier ?? ResolutionTierMeta.pickForSpan(_spanDays());

  Map<int, double> _data = const {};
  /// `_data` ile AYNI istekten gelen tür/pozisyon dağılımı.
  ///
  /// Tür dökümü kartı eskiden kendi `getPortfolioHistory` çağrısını yapıyordu;
  /// farklı pencere ve tier kullandığı için türlerin toplamı grafiğin
  /// toplamını tutmuyordu. Artık ikisi tek yanıttan besleniyor.
  PortfolioHistoryBreakdown _breakdown =
      const PortfolioHistoryBreakdown.empty();
  bool _loading = false;
  /// En az bir istek SONUÇLANDI mı (başarıyla ya da hatayla)?
  ///
  /// "Veri yok" iki farklı şeyi anlatabilir: henüz gelmedi (spinner doğru)
  /// veya geldi ve boştu (spinner SONSUZA KADAR döner — bekleyecek bir şey
  /// yok). Ekran bu bayrakla ikisini ayırır.
  bool _settled = false;
  /// `_data` başka bir filtreden devralınan tohum veri mi? Doğruysa grafik
  /// gösterilir ama "bu henüz seçtiğin filtrenin verisi değil" diye soluk
  /// çizilir ve sayısal özetler (toplam/PnL) buna göre gizlenebilir.
  bool _stale = false;
  int _requestSeq = 0;
  Timer? _debounce;
  // Yükleme durumunu geciktiren timer — dispose'da iptal edilmeli, aksi
  // halde widget ağaçtan kalktıktan sonra notifyListeners() çağırıp
  // "disposed ChangeNotifier" hatası fırlatır.
  Timer? _graceTimer;
  bool _disposed = false;

  Map<int, double> get data => _data;

  /// `data` ile aynı istekten gelen tür/pozisyon dağılımı — tür dökümü kartı
  /// bunu kullanır. Tohum (seed) veride dağılım YOKTUR: tohum başka bir
  /// filtreye aittir ve dağılımı bu filtrenin toplamını tutmaz.
  PortfolioHistoryBreakdown get breakdown => _breakdown;
  bool get loading => _loading;

  /// İlk istek sonuçlandı mı. `!loading && settled && data.isEmpty` →
  /// gerçekten veri yok; spinner yerine boş/hata durumu gösterilmeli.
  bool get settled => _settled;

  /// Ekrandaki veri devralınan tohum mu (henüz bu filtrenin gerçek sonucu
  /// gelmedi mi)?
  bool get stale => _stale;
  ResolutionTier get tier => _tier;
  DateTime get from => _from;
  DateTime get to => _to;

  double _spanDays() =>
      _to.difference(_from).inMinutes / (60.0 * 24.0);

  /// Chart viewport değiştiğinde çağır. [from]/[to] gerçek tarih değerleri.
  /// Debounce 220ms — pinch/pan sırasında spam istek atmaz.
  void updateViewport(DateTime from, DateTime to) {
    _from = from;
    _to = to;
    final newTier = _cozunurluk();
    // Tier değişmediyse ve _data zaten viewport'u kapsıyorsa reload etme —
    // pan sırasında Y-fit içinde gezmek yeni istek gerektirmez.
    if (newTier == _tier && _dataCoversViewport()) {
      notifyListeners();
      return;
    }
    _tier = newTier;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      _reload();
    });
  }

  // `_data`nın min/max zaman damgası. Her viewport değişiminde tüm
  // anahtarları sıralamak (pan sırasında saniyede onlarca kez) gereksizdi —
  // veri değişmediği sürece sınırlar da değişmez. `_data` her atandığında
  // bir kez hesaplanır.
  int _dataMinTs = 0;
  int _dataMaxTs = -1;

  void _recomputeDataBounds() {
    if (_data.isEmpty) {
      _dataMinTs = 0;
      _dataMaxTs = -1;
      return;
    }
    int lo = _data.keys.first;
    int hi = lo;
    for (final k in _data.keys) {
      if (k < lo) lo = k;
      if (k > hi) hi = k;
    }
    _dataMinTs = lo;
    _dataMaxTs = hi;
  }

  bool _dataCoversViewport() {
    if (_data.isEmpty) return false;
    return _dataMinTs <= _from.millisecondsSinceEpoch &&
        _dataMaxTs >= _to.millisecondsSinceEpoch - 60 * 1000;
  }

  Future<void> _reload({bool immediate = false}) async {
    final mySeq = ++_requestSeq;
    // `_loading`i HEMEN true yapıp notify etmiyoruz. Fiyat serileri
    // `HistoryService._tierCache` içinde önbelleklendiği için istek çoğu
    // zaman aynı karede (mikro-görev) döner; önce "yükleniyor" yayınlamak
    // görünür bir spinner çakması üretiyordu. Bunun yerine kısa bir gecikme
    // sonrası hâlâ bitmediyse yükleme durumunu duyuruyoruz.
    _graceTimer?.cancel();
    final graceTimer = Timer(const Duration(milliseconds: 120), () {
      if (_disposed || mySeq != _requestSeq) return;
      if (!_loading) {
        _loading = true;
        notifyListeners();
      }
    });
    _graceTimer = graceTimer;
    // İlk pencere mi (soğuk açılışın kaydedilebilir sonucu)?
    final ilkPencere = _manualTier == null &&
        _from == initialFrom &&
        _to == initialTo;
    try {
      // `tazelikle`: hesap birebir aynı; yalnız bileşenlerden biri son iyi
      // kopyadan geldiyse (ağ düştü) ölçüldüğü anı söyler.
      final r = await HistoryService.tazelikle(() => HistoryService.instance
          .getPortfolioHistoryBreakdownAtResolution(
            assets: assets,
            from: _from,
            to: _to,
            tier: _tier,
            simulate: simulate,
          ));
      final result = r.sonuc;
      // Sıra numarası eşleşmezse (viewport arada değişti) bu sonucu at.
      if (mySeq != _requestSeq) return;
      if (_diskten && (result.total.length < 2 || r.bosBilesen)) {
        // Taze hesap boş döndü ya da bir bileşeni HİÇ gelmedi (ağ düştü,
        // son iyi kopyası da yok): motor o bileşeni `currentPrice`
        // tohumuyla DÜZ çizer — ölçülmüş disk kopyasını düz çizgiyle ezmek
        // tam da "grafik düz çizgiye döndü" şikâyetiydi (2026-10-03). Disk
        // kopyası kalır, artık NET ve altında ne zaman ölçüldüğü yazılır.
        // Varlık sayfasıyla aynı davranış.
        _stale = false;
        _sonGuncelleme = _diskZamani;
        return;
      }
      _data = result.total;
      // Toplam ve dağılım DAİMA birlikte atanır — ayrı atanırsa bir kare
      // boyunca eski dağılım yeni toplamla eşleşir ve tür dökümü tutmaz.
      _breakdown = result;
      _recomputeDataBounds();
      _stale = false;
      _diskten = false;
      _sonGuncelleme = result.total.isEmpty ? null : r.bayatZaman;
      final kaydet = tazeKaydet;
      // Yalnız TAM ölçüm yazılır: bileşenlerden biri son iyi kopyadan
      // (bayat) ya da hiç gelmediyse (düz tohum) kayıt yapılmaz — disk
      // kopyası "o gün bu defterle ölçülen seri" olarak kalsın.
      if (kaydet != null &&
          ilkPencere &&
          r.bayatZaman == null &&
          !r.bosBilesen &&
          result.total.length >= 2) {
        kaydet(result.total);
      }
    } catch (_) {
      // sessizce yok say — eski veri ekranda kalır. Disk kopyasıysa net
      // çizilir, "son güncelleme" ile (yukarıdaki boş sonuçla aynı karar).
      if (mySeq == _requestSeq && _diskten) {
        _stale = false;
        _sonGuncelleme = _diskZamani;
      }
    } finally {
      graceTimer.cancel();
      // `await`ten sonra buradayız — controller bu arada dispose edilmiş
      // olabilir (filtre değişiminde eski controller atılıyor). Dispose
      // sonrası notifyListeners() exception fırlatır.
      if (!_disposed && mySeq == _requestSeq) {
        _loading = false;
        _settled = true;
        // Grace timer "yükleniyor" duyurmuş olsa da olmasa da tek notify
        // yeterli: ya spinner'ı kapatır ya da yeni veriyi yayınlar.
        notifyListeners();
      }
    }
  }

  /// Kullanıcı bar aralığını değiştirdi.
  ///
  /// [tier] `null` verilirse elle seçim KALDIRILIR ve çözünürlük yeniden
  /// viewport'tan türetilmeye başlar.
  ///
  /// Debounce YOK: pinch/pan sırasında saniyede onlarca kez tetiklenen
  /// `updateViewport`'un aksine bu, tek bir bilinçli dokunuş. Beklemek
  /// yalnızca gecikme hissi yaratırdı.
  void setManualTier(ResolutionTier? tier) {
    if (_manualTier == tier) return;
    _manualTier = tier;
    final yeni = _cozunurluk();
    if (yeni == _tier) {
      // Çözünürlük fiilen değişmedi (örn. otomatik zaten aynı tier'ı
      // seçiyordu) — ağa çıkmaya gerek yok, ama seçim durumu değiştiği
      // için dinleyiciler haberdar edilmeli (seçici kendini boyar).
      notifyListeners();
      return;
    }
    _tier = yeni;
    _debounce?.cancel();
    _reload(immediate: true);
  }

  /// Kullanıcının seçtiği bar; `null` ise otomatik.
  ResolutionTier? get manualTier => _manualTier;

  /// Veriyi elle tazele — "veri alınamadı" durumundaki tekrar dene butonu
  /// bunu çağırır. Debounce'u atlar; kullanıcı zaten bilinçli tetikledi.
  void reload() => _reload(immediate: true);

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _graceTimer?.cancel();
    super.dispose();
  }
}
