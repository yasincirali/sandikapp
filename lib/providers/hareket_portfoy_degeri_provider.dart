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

/// Kapsamın GÜNLÜK portföy serisi (TRY) — Performans'ın günlük katmanda
/// çağırdığı motorun kendisi (`getPortfolioHistoryAtResolution`, aynı
/// girdi, `simulate: false`). Fiyat serileri `HistoryService` katman
/// önbelleğinden gelir: Performans 1A/3A açıldıysa ağ isteği yok; açılmadıysa
/// aynı yükleyici bir kez, arka planda çalışır.
///
/// İlk kareyi bekletmez: hesap bir olay döngüsü turu sonra başlar, liste o
/// arada miktarlarla çizilmiş olur; değerler seri gelince dolar.
final hareketGunlukSeriProvider = FutureProvider.autoDispose
    .family<Map<int, double>, HareketKapsami>((ref, k) async {
  // Yalnız iz izlenir: fiyat tiki seriyi yeniden hesaplatmaz.
  ref.watch(_seriGirdisiProvider(k).select((g) => g.imza));
  final varliklar = ref.read(_seriGirdisiProvider(k)).varliklar;
  if (varliklar.isEmpty) return const {};
  await Future<void>(() {});
  final simdi = DateTime.now();
  return HistoryService.instance.getPortfolioHistoryAtResolution(
    assets: varliklar,
    from: simdi.subtract(const Duration(days: hareketDegerPencereGun)),
    to: simdi,
    tier: ResolutionTier.daily,
  );
});

/// Lot kimliği → "Portföy önce → sonra" (TRY). Satır O(1) okur; harita
/// (defter, seri, canlı toplam) değişince bir kez kurulur — build içinde
/// satır başına hesap yok. Seri yüklenirken ya da hata verdiyse BOŞ:
/// satırlar miktarla çizilir, eski seriyle yeni defter karıştırılmaz.
final hareketPortfoyDegerleriProvider = Provider.autoDispose
    .family<Map<String, ({double once, double sonra})>, HareketKapsami>(
        (ref, k) {
  final seri = ref.watch(hareketGunlukSeriProvider(k));
  if (seri.isLoading || !seri.hasValue) return const {};
  final pState = ref.watch(portfolioProvider).valueOrNull;
  if (pState == null) return const {};
  final g = ref.watch(_seriGirdisiProvider(k));
  // Grafiğin canlı ucu — Performans `_buildChartWithData`'daki hesabın
  // aynısı (aynı süzülmüş sahip defterleri, aynı `sonFiyat`).
  final canli = ownerScopedTotalValue(g.defterler,
      toTRY: pState.toTRY, sonFiyat: PriceService.instance.sonBilinenFiyat);
  final canliUc =
      (canli > 0 || DailySummary.acikPozisyonYok(g.varliklar)) ? canli : null;
  return hareketPortfoyDegerleri(
    seriGirdisi: g.varliklar,
    gunlukSeri: seri.requireValue,
    canliToplam: canliUc,
    simdi: DateTime.now(),
    toTRY: pState.toTRY,
  );
});
