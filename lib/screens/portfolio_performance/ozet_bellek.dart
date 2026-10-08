part of '../portfolio_performance_screen.dart';

/// Özet sekmesinin ekran ömrü boyunca tuttuğu sonuç belleği.
///
/// ## Neden (kullanıcı bildirimi 2026-10-02: "Performansta grafikten
/// özete geçerken ekran flick oluyor; Özet'teyken diğer filtrelere de
/// tıklayınca titreme oluyor")
/// Özet'in iki asenkron katmanı vardı ve ikisi de her kurulumda SIFIRDAN
/// başlıyordu:
///
///   1. `_OzetSerisi` anahtarı dönem/kapsam ile değişir → yeni State,
///      `_seri == null` → iskelet (iki kısa kart) → seri gelince tam özet.
///      Grafik → Özet geçişinde de yeni kurulur. Seri `HistoryService`
///      önbelleğinden gelse bile `await` en az bir kare iskelet çizdiriyordu;
///      liste iki kısa karta çöküp yeniden uzuyordu.
///   2. `_OzetYanVeri` (TÜFE, reel getiri, köprü, 1Y bağlamı, sağlık)
///      `_OzetSerisi`'nin İÇİNDE yeni doğar → kartlar özetten SONRA tek tek
///      belirip alttakileri itiyordu.
///
/// Aynı dönem-kapsam ikinci kez açıldığında elde olan sonuç tekrar
/// beklenmesin diye buradan, EŞZAMANLI okunur. İlk açılışta ise Özet
/// görünürken öteki dönemler arkada ısıtılır ([isit]); dönem dokunuşu
/// çoğunlukla hazır veriye düşer.
///
/// ## Neden yanlış sayı göstermez
/// Anahtar seriyi belirleyen HER girdiyi taşır (kapsam, tür, dönem,
/// simülasyon, yenileme sayacı ve lot imzası: kimlik + miktar + tarih). Lot
/// düzenlenince anahtar değişir; başka bir kapsamın/dönemin sonucu asla
/// okunmaz — "iskelet, yanlış sayıdan iyidir" kuralı (`_ozetSekmesi` notu)
/// korunur. Bellekteki sonuç [tazelik]ten eskiyse yine gösterilir ama
/// arkada yeniden ölçülür (Grafik'in 30 sn'lik tikiyle aynı tazelik dili:
/// aynı dönemin biraz eski ölçümü, başka dönemin rakamı değil). Canlı sağ
/// uç zaten bellekten değil `portfolioProvider`'dan okunur (`canliSon`).
class _OzetBellek {
  /// Bundan eski girdi gösterilir ama arkada tazelenir. `HistoryService`
  /// sembol önbelleğinin tavanı 15 dk; 1 dk, ölçümün o önbellekle hep
  /// aynı kalmasını sağlar.
  static const tazelik = Duration(minutes: 1);

  /// Dönem (7) × kapsam × tür birikebilir; üstü en eskiden atılır.
  static const azami = 32;

  /// BOŞ seri saklanmaz (ağ yok): sonraki açılış yeniden dener, boş özet
  /// "veri" sayılmaz.
  final seriler = SonucBellegi<PortfolioHistoryBreakdown>(
    tazelik: tazelik,
    azami: azami,
    saklanir: (bd) => bd.total.isNotEmpty,
  );

  final yanVeriler = SonucBellegi<_YanVeri>(tazelik: tazelik, azami: azami);

  /// Yüzdelik dilim (6A şeridi) — RPC ve analitik olayı State'te kalır,
  /// yalnızca sonuç saklanır: 6A'ya dönen kullanıcı şeridi beklemeden görür.
  final dilimler = <String, PercentileBucket>{};

  /// En son ısıtılan küme — her `build`'de aynı ısıtma yeniden kurulmasın.
  String? _isitilan;

  /// "Başka yere koysaydın" kartının kıyas serilerini ısıtan abonelikler.
  /// Kart Özet'te iskeletle doğup sonradan doluyordu (aynı titreme).
  /// Abonelik yalnız İLK sonuç gelene kadar tutulur; sonra kapatılır ve
  /// sağlayıcının kendi 15 dk'lık ömrü geçerli olur (`kiyasSerileriProvider`
  /// notu) — ekran ömrü boyunca tutmak seriyi hiç tazelenmez yapardı.
  final _kiyasAbonelikleri =
      <SummaryPeriod, ProviderSubscription<AsyncValue<Object?>>>{};

  void kiyasIsit(WidgetRef ref, SummaryPeriod p) {
    if (p.intraday || _kiyasAbonelikleri.containsKey(p)) return;
    late final ProviderSubscription<AsyncValue<Object?>> abone;
    var bitti = false;
    abone = ref.listenManual<AsyncValue<Object?>>(
      kiyasSerileriProvider(p),
      (_, sonraki) {
        if (sonraki.isLoading) return;
        bitti = true;
        _kiyasAbonelikleri.remove(p)?.close();
      },
      fireImmediately: true,
    );
    if (bitti) {
      abone.close(); // zaten hazırdı
    } else {
      _kiyasAbonelikleri[p] = abone;
    }
  }

  /// Ekran kapanırken: bekleyen ısıtma abonelikleri bırakılır.
  void kapat() {
    for (final a in _kiyasAbonelikleri.values) {
      a.close();
    }
    _kiyasAbonelikleri.clear();
    _isitilan = null;
  }

  /// Lot imzası — anahtarın "hangi defter" parçası. Yalnız kimlik yetmez:
  /// miktarı düzeltilen lot aynı kimliği taşır ve eski seri okunurdu.
  static String imza(List<Asset> lotlar) => [
        for (final a in lotlar)
          '${a.id}:${a.quantity}:${a.addedDate.millisecondsSinceEpoch}'
              ':${a.isBuy ? 'b' : 's'}',
      ].join(',');

  /// Görünür dönemin ve (Özet açıksa) öteki dönemlerin serisini + yan
  /// verisini arkada hazırlar. SIRAYLA: altı dönemi birden başlatmak
  /// sembol isteklerini ve hesabı aynı kareye yığar.
  ///
  /// Ağ maliyeti küçük: sembol serileri çözünürlük başına tek kez iner
  /// (`_tierCache` anahtarı aralık taşımaz) ve altı dönem üç çözünürlüğe
  /// düşer (1H saatlik; 1A/3A günlük; 6A/1Y/5Y haftalık). Grafik
  /// sekmesinde yalnızca görünür dönem ısıtılır — Özet'e ilk geçiş
  /// iskeletsiz olsun diye; öteki dönemler kullanıcı Özet'e gelince.
  void isit({
    required String kume,
    required List<SummaryPeriod> donemler,
    required String Function(SummaryPeriod) seriAnahtari,
    required Future<PortfolioHistoryBreakdown> Function(SummaryPeriod) seriCek,
    required String Function(SummaryPeriod) yanAnahtari,
    required Future<_YanVeri> Function(SummaryPeriod) yanCek,
    required void Function(SummaryPeriod) kiyasCek,
  }) {
    if (_isitilan == kume) return;
    _isitilan = kume;
    // Kare sonrası: build içinden çağrılır; hesabın eşzamanlı kısmı bu
    // kareye binmesin. (`Future(...)` değil — sıfır süreli bir Timer
    // bırakır, test bağlayıcısı onu bekleyen zamanlayıcı sayar.)
    WidgetsBinding.instance.addPostFrameCallback((_) => _isitDongusu(
          kume: kume,
          donemler: donemler,
          seriAnahtari: seriAnahtari,
          seriCek: seriCek,
          yanAnahtari: yanAnahtari,
          yanCek: yanCek,
          kiyasCek: kiyasCek,
        ));
  }

  Future<void> _isitDongusu({
    required String kume,
    required List<SummaryPeriod> donemler,
    required String Function(SummaryPeriod) seriAnahtari,
    required Future<PortfolioHistoryBreakdown> Function(SummaryPeriod) seriCek,
    required String Function(SummaryPeriod) yanAnahtari,
    required Future<_YanVeri> Function(SummaryPeriod) yanCek,
    required void Function(SummaryPeriod) kiyasCek,
  }) async {
    for (final p in donemler) {
      if (_isitilan != kume) return; // kapsam/tür değişti: eski küme bırakılır
      try {
        kiyasCek(p);
        // GÜNLÜK'ün serisi gün içi katmandan gelir (`_OzetSerisi` notu);
        // yalnız yan verisi ısıtılır.
        final sk = seriAnahtari(p);
        if (!p.intraday && !seriler.taze(sk)) {
          await seriler.yukle(sk, () => seriCek(p));
        }
        // Await sonrası yeniden bak: ekran kapanmış ya da küme değişmiş
        // olabilir (kapalı ekranın `ref`'i okunamaz).
        if (_isitilan != kume) return;
        final yk = yanAnahtari(p);
        if (!yanVeriler.taze(yk)) await yanVeriler.yukle(yk, () => yanCek(p));
      } catch (e, st) {
        // Isıtma ikincil: ekran kendi isteğini yine atar. Sessiz değil.
        CrashReporter.report(e, st, reason: 'OzetBellek.isit');
      }
    }
  }

  /// Kullanıcı yenilemesi: bellekteki her şey bırakılır.
  void temizle() {
    seriler.temizle();
    yanVeriler.temizle();
    dilimler.clear();
    _isitilan = null;
  }
}

/// Özet'in kanonik serisi — `_OzetSerisi` ve ısıtma AYNI isteği atar.
///
/// Pencere `PeriodSummaryService.pencere`, çözünürlük `pickForSpan(period.days)`
/// — gerekçe `_OzetSerisi` notunda.
Future<PortfolioHistoryBreakdown> _ozetSerisiniCek(
  SummaryPeriod period,
  List<Asset> chartAssets,
  bool simulate,
) {
  final p = PeriodSummaryService.pencere(period, DateTime.now());
  return HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
    assets: chartAssets,
    from: p.start,
    to: p.end,
    tier: ResolutionTierMeta.pickForSpan(period.days.toDouble()),
    simulate: simulate,
  );
}

/// Ekran tarafı: bellek anahtarları ve ısıtma tetiği.
extension _OzetBellekKullanimi on _PortfolioPerformanceScreenState {
  /// Anahtarın dönem dışındaki parçası: kapsam, tür, simülasyon, yenileme.
  String get _ozetKapsami =>
      '$_view|${_typeFilter?.name}|$_simulate|$_ozetYenileme';

  String _ozetSeriAnahtari(SummaryPeriod p, List<Asset> chartAssets) =>
      'seri|${p.name}|$_ozetKapsami|${_OzetBellek.imza(chartAssets)}';

  String _ozetYanAnahtari(SummaryPeriod p, List<Asset> lotlar) =>
      'yan|${p.name}|$_ozetKapsami|${_OzetBellek.imza(lotlar)}';

  /// Grafik sekmesinde yalnızca görünür dönemi, Özet'te önce görünür
  /// dönemi sonra ötekileri ısıtır (gerekçe `_OzetBellek.isit`).
  void _ozetiIsit({
    required List<Asset> chartAssets,
    required List<Asset> targetAssets,
  }) {
    if (chartAssets.isEmpty) return;
    final gorunur = SummaryPeriod.fromIndex(_selectedPeriodIdx);
    final donemler = _ozetSekmesi
        ? [gorunur, ...SummaryPeriod.values.where((p) => p != gorunur)]
        : [gorunur];
    final simulate = _simulate;
    final seriImza = _OzetBellek.imza(chartAssets);
    final lotImza = _OzetBellek.imza(targetAssets);
    _ozetBellek.isit(
      kume: '$_ozetSekmesi|${gorunur.name}|$_ozetKapsami|$seriImza|$lotImza',
      donemler: donemler,
      seriAnahtari: (p) => _ozetSeriAnahtari(p, chartAssets),
      seriCek: (p) => _ozetSerisiniCek(p, chartAssets, simulate),
      yanAnahtari: (p) => _ozetYanAnahtari(p, targetAssets),
      kiyasCek: (p) => _ozetBellek.kiyasIsit(ref, p),
      yanCek: (p) => _yanVeriYukle(
        period: p,
        assets: targetAssets,
        pState: ref.read(portfolioProvider).valueOrNull,
      ),
    );
  }
}
