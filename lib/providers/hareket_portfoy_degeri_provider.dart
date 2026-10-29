import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/gorunum_kapsami.dart';
import '../models/position.dart';
import '../services/daily_summary.dart';
import '../services/history_service.dart';
import '../services/portfoy_seri_depo.dart';
import '../services/price_service.dart';
import 'portfolio_provider.dart';
import 'portfoy_provider.dart';

/// Hareket listesinin kapsamı: kişi (`''` Ben, ortak kimliği, `null`
/// Birlikte) + portföy seçimi. Kayıt (record) değer eşitliği taşır; aynı
/// kapsamı soran iki ekran aynı sağlayıcı örneğini paylaşır.
typedef HareketKapsami = ({String? kisi, String portfoy});

/// Performans grafiğinin seri girdisi — SAHİP BAŞINA ve TEK KAYNAK.
///
/// ## Neden burada ve Performans da bunu çağırıyor (2026-10-29)
/// Hareket satırının "Portföy önce → sonra" değeri Performans'ın gösterdiği
/// sayıyla birebir aynı olmalı (yasin: "tutarsızlık olmamalı"). Aynı sayı
/// ancak motorun AYNI girdiyle (aynı lotlar, aynı sıra — toplama sırası
/// kayan noktada son haneyi değiştirir) çağrılmasıyla çıkar. Süzgeç eskiden
/// Performans ekranının build'inde satır içiydi; ikinci bir kopya yazılsaydı
/// ilk değişiklikte iki yüzey ayrışırdı ("iki merdiven" hata sınıfı).
///
/// Kural: süren lot ([Asset.isActive]), isteğe bağlı tür süzgeci ve
/// [FiyatKaynagi.seriyeGirer]. Simülasyon bu yoldan geçmez (Performans
/// onu ayrıca kurar; hareket değeri gerçek geçmişi anlatır).
List<List<Asset>> performansSeriDefterleri(
  Iterable<List<Asset>> sahipDefterleri, {
  bool Function(Asset)? suzgec,
}) =>
    [
      for (final lots in sahipDefterleri)
        [
          for (final a in lots)
            if (a.isActive &&
                (suzgec?.call(a) ?? true) &&
                FiyatKaynagi.seriyeGirer(a))
              a,
        ],
    ];

/// Hareket değeri için seri penceresi (gün). Performans'ın GÜNLÜK katmanda
/// çizdiği en uzun dönem 3A (`pickForSpan` < 180 gün → günlük); daha eskisi
/// haftalık çizilir, o günün noktası grafikte yoktur. Pencere dışındaki
/// eski işlemler yalnız miktarı yazar — uzun geçmişi yalnız bunun için
/// çekmeyiz (yasin: performans).
const hareketDegerPencereGun = 92;

/// Kapsamın sahip başına HAM defterleri — Performans'la aynı çağrı
/// (`kapsamSahipDefterleri`, tür süzgeci yok: değer kapsamın tamamıdır).
///
/// "Ben"de ortak verisi İZLENMEZ: ortağı olmayan kullanıcıda
/// `allPartnerAssetsProvider`'ı uyandırmak boşuna ağ isteği olurdu.
final _kapsamDefterleriProvider = Provider.autoDispose
    .family<List<List<Asset>>, HareketKapsami>((ref, k) {
  final benim = ref.watch(portfolioProvider).valueOrNull?.assets ?? const [];
  final ortaklar = k.kisi == ''
      ? const <String, List<Asset>>{}
      : ref.watch(allPartnerAssetsProvider).valueOrNull ??
          const <String, List<Asset>>{};
  final bilinen = k.portfoy == PortfoySecimi.tumu
      ? const <String>{}
      : ref.watch(portfoyKapsamiProvider).bilinen;
  return kapsamSahipDefterleri(
    kisi: k.kisi,
    benim: benim,
    ortaklar: ortaklar,
    portfoy: k.portfoy,
    bilinenPortfoyler: bilinen,
  );
});

/// Seri girdisi + defter parmak izi. Fiyat turu her tikte yeni [Asset]
/// nesneleri üretir; seri yalnız [imza] değişince (lot eklendi/satıldı/
/// silindi/düzenlendi, bir varlık seriye girdi/çıktı) yeniden hesaplanır.
/// İz `PortfoySeriDepo.imza` — Performans'ın disk kopyasıyla aynı tanım;
/// `currentPrice` taşımaz.
final _seriGirdisiProvider = Provider.autoDispose.family<
    ({List<List<Asset>> defterler, List<Asset> varliklar, String imza}),
    HareketKapsami>((ref, k) {
  final defterler = performansSeriDefterleri(
      ref.watch(_kapsamDefterleriProvider(k)));
  final varliklar = [for (final l in defterler) ...l];
  return (
    defterler: defterler,
    varliklar: varliklar,
    imza: PortfoySeriDepo.imza(const [], varliklar),
  );
});

/// Performans ekranının ŞU AN çizdiği günlük seri, kapsam başına.
///
/// ## Neden (E2E, 2026-10-29)
/// Satırlar seriyi defter değişince bir kez hesaplıyordu; Performans ise
/// geçmişi canlı kura ve altın kotasyonuna hizalayarak (`kurSerisiniHizala`,
/// `altinKalibrasyonHaritasi`) kendi zamanında yeniden hesaplıyor. Dakikalar
/// sonra satır ₺931.267, Performans ₺931.288 diyordu (altın hareketinde
/// binlerce ₺). İki hesap aynı motoru çağırsa da AYNI ANDA çağırmadıkça
/// ayrışır. Çözüm: Performans günlük seriyi çizdiği an buraya yayınlar,
/// satırlar o noktalar için BU örneği okur — iki yüzey aynı sayı nesnesini
/// gösterir. Performans o kapsamda günlük seri çizmiyorsa (başka dönem, tür
/// süzgeci, simülasyon, ekran hiç açılmadı) satırlar kendi seriyle döner
/// ([hareketGunlukSeriProvider]); Performans açıldığında o seri bu
/// yayınla yer değiştirir.
///
/// `ChangeNotifier` (sağlayıcı değil): Performans ekranı `dispose`
/// sırasında da yayını geri çekebilmeli; orada `ref` güvenli değil. Bildirim
/// mikro göreve ertelenir — ekran build/dispose karesinde sağlayıcı
/// geçersizlenmesin.
class PerformansSeriYayini extends ChangeNotifier {
  PerformansSeriYayini._();
  static final instance = PerformansSeriYayini._();

  final Map<HareketKapsami, Map<int, double>> _seriler = {};
  bool _bildirimBekliyor = false;

  Map<int, double>? seri(HareketKapsami k) => _seriler[k];

  /// [seri] `null` → kapsamın yayını geri çekilir.
  void yayinla(HareketKapsami k, Map<int, double>? seri) {
    if (identical(_seriler[k], seri)) return;
    if (seri == null) {
      _seriler.remove(k);
    } else {
      _seriler[k] = seri;
    }
    if (_bildirimBekliyor) return;
    _bildirimBekliyor = true;
    scheduleMicrotask(() {
      _bildirimBekliyor = false;
      notifyListeners();
    });
  }

  @visibleForTesting
  void temizle() => _seriler.clear();
}

/// Ekranın kapsamını yayın anahtarına çevirir: portföy süzgeci yalnız "Ben"de
/// uygulanır (`kapsamSahipDefterleri`); ortak/Birlikte'de anahtar "Tümü" ki
/// Performans ve hareket listesi aynı kümeyi aynı anahtarla bulsun.
HareketKapsami hareketKapsami({required String? kisi, required String portfoy}) =>
    (kisi: kisi, portfoy: kisi == '' ? portfoy : PortfoySecimi.tumu);

final _performansYayiniProvider = Provider.autoDispose
    .family<Map<int, double>?, HareketKapsami>((ref, k) {
  final y = PerformansSeriYayini.instance;
  void degisti() => ref.invalidateSelf();
  y.addListener(degisti);
  ref.onDispose(() => y.removeListener(degisti));
  return y.seri(k);
});

/// Kapsamın GÜNLÜK portföy serisi (TRY) — Performans'ın günlük katmanda
/// çağırdığı motorun kendisi (`getPortfolioHistoryAtResolution`, aynı
/// girdi, `simulate: false`). Fiyat serileri `HistoryService` katman
/// önbelleğinden gelir: Performans 1A/3A açıldıysa ağ isteği yok; açılmadıysa
/// aynı yükleyici bir kez, arka planda çalışır.
///
/// İlk kareyi bekletmez: hesap bir olay döngüsü turu sonra başlar, liste o
/// arada miktarlarla çizilmiş olur; değerler seri gelince dolar.
///
/// ## Canlı kotasyonla tazelenir (E2E, 2026-10-29)
/// Motor geçmişi canlı kura/altına hizalar; girdi (lot `currentPrice`,
/// `HistoryService.canliKur`) her fiyat turunda değişir. Defter izi
/// değişmeden de fiyat turundan sonra seri yeniden hesaplanır — en çok
/// [tazelemeAraligi]'nda bir, zamanlayıcıyla (kare dışında); hesap
/// sürerken eski seri ekranda kalır (boşalıp dolmaz). Defter değişince
/// ise eski seri hemen bırakılır: yeni defterle karıştırılmaz.
class HareketGunlukSeriNotifier
    extends AutoDisposeFamilyAsyncNotifier<Map<int, double>, HareketKapsami> {
  /// İki tazeleme arası en kısa süre. Fiyat turu (saniyeler) kadar sık
  /// hesap gereksiz; ekranda bir tazeleme gecikmesi kadar fark kalabilir.
  @visibleForTesting
  static Duration tazelemeAraligi = const Duration(seconds: 5);

  Timer? _zamanlayici;
  DateTime? _sonHesap;
  int _kusak = 0;

  @override
  Future<Map<int, double>> build(HareketKapsami arg) async {
    // Yalnız iz İZLENİR (defter değişimi → yeniden kurulum); fiyat turu
    // `listen` ile tazeleme planlar.
    ref.watch(_seriGirdisiProvider(arg).select((g) => g.imza));
    ref.listen(portfolioProvider, (_, __) => _planla());
    if (arg.kisi != '') ref.listen(allPartnerAssetsProvider, (_, __) => _planla());
    ref.onDispose(() => _zamanlayici?.cancel());
    final kusak = ++_kusak;
    await Future<void>(() {});
    final seri = await _hesapla();
    if (kusak == _kusak) _sonHesap = DateTime.now();
    return seri;
  }

  Future<Map<int, double>> _hesapla() {
    final varliklar = ref.read(_seriGirdisiProvider(arg)).varliklar;
    if (varliklar.isEmpty) return Future.value(const {});
    final simdi = DateTime.now();
    return HistoryService.instance.getPortfolioHistoryAtResolution(
      assets: varliklar,
      from: simdi.subtract(const Duration(days: hareketDegerPencereGun)),
      to: simdi,
      tier: ResolutionTier.daily,
    );
  }

  void _planla() {
    if (_zamanlayici?.isActive ?? false) return;
    final son = _sonHesap;
    final gecen = son == null ? tazelemeAraligi : DateTime.now().difference(son);
    final bekle = gecen >= tazelemeAraligi ? Duration.zero : tazelemeAraligi - gecen;
    _zamanlayici = Timer(bekle, _tazele);
  }

  Future<void> _tazele() async {
    if (!state.hasValue || state.isLoading) {
      // İlk hesap sürüyor ve girdiyi başta okudu; bu fiyat turu onda yok.
      // Bir aralık sonra yeniden dene.
      _zamanlayici = Timer(tazelemeAraligi, _tazele);
      return;
    }
    final kusak = _kusak;
    final seri = await _hesapla();
    // Arada defter değiştiyse (build yeniden koştu) bu sonuç eski deftere
    // ait; atılır.
    if (kusak != _kusak) return;
    _sonHesap = DateTime.now();
    state = AsyncData(seri);
  }
}

final hareketGunlukSeriProvider = AsyncNotifierProvider.autoDispose
    .family<HareketGunlukSeriNotifier, Map<int, double>, HareketKapsami>(
        HareketGunlukSeriNotifier.new);

/// Lot kimliği → "Portföy önce → sonra" (TRY). Satır O(1) okur; harita
/// (defter, seri, yayın, canlı toplam) değişince bir kez kurulur — build
/// içinde satır başına hesap yok. Seri yüklenirken ya da hata verdiyse BOŞ:
/// satırlar miktarla çizilir, eski seriyle yeni defter karıştırılmaz.
///
/// Nokta önceliği: Performans'ın yayınladığı seri (ekranda çizilen örnek)
/// > kendi seri. Canlı uç her iki durumda Performans'ın `currentTotalOverride`
/// hesabıyla aynı.
final hareketPortfoyDegerleriProvider = Provider.autoDispose
    .family<Map<String, ({double once, double sonra})>, HareketKapsami>(
        (ref, k) {
  final seri = ref.watch(hareketGunlukSeriProvider(k));
  if (seri.isLoading || !seri.hasValue) return const {};
  final pState = ref.watch(portfolioProvider).valueOrNull;
  if (pState == null) return const {};
  final g = ref.watch(_seriGirdisiProvider(k));
  final yayin = ref.watch(_performansYayiniProvider(k));
  final noktalar = yayin == null
      ? seri.requireValue
      : <int, double>{...seri.requireValue, ...yayin};
  // Grafiğin canlı ucu — Performans `_buildChartWithData`'daki hesabın
  // aynısı (aynı süzülmüş sahip defterleri, aynı `sonFiyat`).
  final canli = ownerScopedTotalValue(g.defterler,
      toTRY: pState.toTRY, sonFiyat: PriceService.instance.sonBilinenFiyat);
  final canliUc =
      (canli > 0 || DailySummary.acikPozisyonYok(g.varliklar)) ? canli : null;
  return hareketPortfoyDegerleri(
    seriGirdisi: g.varliklar,
    gunlukSeri: noktalar,
    canliToplam: canliUc,
    simdi: DateTime.now(),
    toTRY: pState.toTRY,
  );
});
