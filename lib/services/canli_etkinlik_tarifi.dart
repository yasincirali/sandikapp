import '../models/asset.dart';
import '../models/asset_type.dart';
import '../providers/portfolio_provider.dart';
import '../utils/tr_format.dart';
import 'daily_summary.dart';
import 'fiyat_kaynagi.dart';
import 'para_agirlikli_getiri.dart';

/// Uygulama KAPALIYKEN kilit ekranının dakikada bir tazelenmesi için
/// "tarif" — sunucunun Performans GÜNLÜK rakamını ileri taşıyabilmesine
/// yetecek en küçük veri.
///
/// ## Neden (kullanıcı kararı 2026-10-03: "Canlı aktiviteler her zaman
/// 1 dk'da bir performans günlükle eş olmalı")
/// Uygulama açıkken kilit ekranı Performans GÜNLÜK ile aynı hesaptan
/// ([DailySummary.from]) beslenir. Uygulama arkaya alınınca iOS süreci
/// askıya alır ve kilit ekranını yalnızca sunucu push'u tazeler. Sunucu
/// ise yalnızca istemcinin SON yazdığı metni 5 dakikada bir yeniden
/// basıyordu: rakam donuyor, yalnızca "Canlı 14:32" saati ilerliyordu.
/// Kullanıcı uygulamayı açınca Performans başka, kilit ekranı başka bir
/// sayı gösteriyordu.
///
/// ## Neden sunucu portföyü baştan HESAPLAMIYOR
/// `push-live-activity`'nin eski kararı geçerli: değerleme (lot toplama,
/// sahip sınırı, altın kalibrasyonu, ölçek hafızası) istemcide yaşar ve
/// sunucuda ikinci bir kopya ayrışır. Tarif bu yüzden MUTLAK değeri değil,
/// istemcinin hesapladığı değerin PARÇALARINI ve her parçanın hangi
/// kotasyona bağlı olduğunu taşır. Sunucu yalnızca ORAN uygular:
///
/// ```
///   parça_yeni = parça × (kotasyon_yeni / kotasyon_eski) × (kur_yeni / kur_eski)
/// ```
///
/// Bu, `ownerScopedTotalValue`'nun `toTRY(miktar × fiyat, para birimi)`
/// formülünün birebir oranıdır: miktar ve sahip sınırı değişmez, yalnızca
/// fiyat ve kur oynar. Kotasyon alınamazsa parça SABİT kalır (uydurma yok,
/// `fiyat_kaynagi.dart` sözleşmesi 3). Kaynaklar sunucuda istemciyle aynı
/// (`_shared/live_prices.ts`: altın + döviz truncgil, kripto `kripto_fiyat`,
/// geri kalan Yahoo); istemcinin fiyatı yedek kaynaktan geldiyse bile ölçek
/// hafızası onu birincil ölçeğe taşımıştır, oran aynı ölçekte kalır.
///
/// Gün içi değişim, yüzde ve grafik ucu sunucuda [DailySummary.from] ile
/// AYNI kurallarla kurulur (`_shared/canli_etkinlik.ts`); iki tarafı
/// `supabase/tests/canli_etkinlik_parite.json` kilitler.
abstract final class CanliEtkinlikTarifi {
  const CanliEtkinlikTarifi._();

  /// Tarif biçiminin sürümü — sunucu tanımadığı sürümü İLERİ TAŞIMAZ,
  /// istemcinin yazdığı metni olduğu gibi basar (bugünkü davranış).
  static const surum = 1;

  /// Gün içinde kotasyonu oynayan ve sunucunun istemciyle AYNI kaynaktan
  /// okuyabildiği türler.
  ///
  /// Dışarıda kalanlar sabit parçaya girer, bilinçli olarak:
  ///   * fon — TEFAS günde bir NAV verir; gün içi oran hep 1 olurdu ve her
  ///     dakika fon başına TEFAS'a istek atmak boşa yük.
  ///   * mevduat / BES — fiyat sözleşmeden hesaplanır, kotasyon yok.
  ///   * diğer — elle girilen değer.
  static const oynayanTurler = {
    AssetType.hisse,
    AssetType.doviz,
    AssetType.altin,
    AssetType.emtia,
    AssetType.kripto,
  };

  /// Para birimi → kotasyon sembolü (`PortfolioState.toTRY` ile aynı üçlü;
  /// fiyat turu bu sembollerle çeker, `PortfolioNotifier.refreshPrices`).
  static const kurSembolleri = {
    'USD': FiyatKaynagi.usdTry,
    'EUR': 'EURTRY=X',
    'GBP': 'GBPTRY=X',
  };

  /// [ozet] için tarifi kurar; ileri taşınamayacak durumda `null`.
  ///
  /// `null` dönen her dalda sunucu eski davranışa düşer (yazılı metni
  /// basar) — yanlış rakamı ileri taşımaktansa donuk ama doğru rakam:
  ///   * değişim ölçülemediyse ([DailySummary.hasChange] yanlış),
  ///   * çizilen seans BUGÜN değilse (hafta sonu Cuma'nın eğrisi): uygulama
  ///     da o günün ucunu canlı toplama bağlamaz, ileri taşınacak bir şey
  ///     yok,
  ///   * grafiğin ucu canlı toplama bağlanmadıysa (fiyat bilinmiyor).
  static Map<String, Object?>? kur({
    required PortfolioState state,
    required DailySummary ozet,
    required Map<int, double> series,
    required DateTime now,
    DateTime? seansGunu,
  }) {
    if (!ozet.hasChange || ozet.totalTRY <= 0) return null;
    final cizilenGun = seansGunu ??
        DailySummary.cizilenGunFromSeries(series) ??
        dayKey(now);
    if (dayKey(cizilenGun) != dayKey(now)) return null;

    final acilisMs = DailySummary.acilisDamgasi(series, now);
    if (acilisMs == null) return null;

    // Canlı uçtan ÖNCEKİ ham seri ve son slotun damgası. Sunucu canlı ucu
    // [DailySummary.dayValues] ile aynı kuralla kendisi koyar (son slot
    // 5 dk'dan tazeyse ezer, değilse ekler); bunun için ucun EZİLMEDEN
    // önceki hâli ve son slotun zamanı gerekir.
    final nowMs = now.millisecondsSinceEpoch;
    final keys = series.keys.toList()..sort();
    final seri = <double>[];
    var sonSlotMs = 0;
    for (final k in keys) {
      if (k > nowMs) break;
      final v = series[k]!;
      if (v <= 0 && seri.isEmpty) continue;
      seri.add(v < 0 ? 0 : v);
      sonSlotMs = k;
    }
    if (seri.isEmpty) return null;
    // Uç canlı toplama bağlı değilse tarif tutarsız olur.
    if ((ozet.sparkline.last - ozet.totalTRY).abs() > 0.005) return null;

    // Nakit akışları — [DailySummary.gunIciGetiriPct] ile AYNI küme ve
    // tutar kuralı. Ağırlık sunucuda push anına göre yeniden hesaplanır.
    final esikMs = acilisMs + DailySummary.gunIciSlot.inMilliseconds;
    final bitisMs = DateTime(now.year, now.month, now.day, 23, 59, 59)
        .millisecondsSinceEpoch;
    final akislar = <Map<String, Object?>>[];
    for (final a in state.assets) {
      final ms = a.addedDate.millisecondsSinceEpoch;
      if (ms < esikMs || ms > bitisMs) continue;
      final f = gunlukAkis(a);
      if (f == 0) continue;
      akislar.add({'f': f, 'ms': ms});
    }

    final parcalar = <Map<String, Object?>>[];
    var parcaToplami = 0.0;
    for (final g in _gruplar(state.assets).entries) {
      // Temsil lot'u fiyatı BİLİNEN olmalı: yeni eklenmiş lot henüz fiyat
      // turunu görmemiş olabilir. Hiçbiri fiyatlı değilse grup (son bilinen
      // kotasyonla değerlenmiş olsa da) sabit parçada kalır.
      final lot = g.value.where((a) => a.currentPrice > 0).firstOrNull;
      if (lot == null) continue;
      final fiyat = lot.currentPrice;
      final d = DailySummary.kapsamToplami(state, g.value);
      if (d == 0) continue;
      final kur = kurSembolleri[lot.currency.trim().toUpperCase()];
      final kurDegeri = kur == null ? null : _kur(state, kur);
      // Kur bilinmiyorsa parça ileri taşınamaz (oranın yarısı eksik).
      if (kur != null && (kurDegeri == null || kurDegeri <= 0)) continue;
      parcalar.add({
        's': lot.ticker.trim().toUpperCase(),
        'd': d,
        'p': fiyat,
        if (kur != null) 'k': kur,
        if (kur != null) 'kf': kurDegeri,
      });
      parcaToplami += d;
    }

    return {
      'v': surum,
      'gun': _gunMetni(now),
      'yazildiMs': nowMs,
      'toplam': ozet.totalTRY,
      // Sabit parça farkı yutar: Σ parça + sabit = toplam, birebir.
      'sabit': ozet.totalTRY - parcaToplami,
      'parcalar': parcalar,
      'acilisMs': acilisMs,
      'akislar': akislar,
      'seri': seri,
      'sonSlotMs': sonSlotMs,
    };
  }

  /// Oynayan türdeki lot'lar, kotasyon sembolü + para birimine göre.
  ///
  /// Grup ham DEFTERDİR (alım + satış): [DailySummary.kapsamToplami] net
  /// pozisyonu ve sahip sınırını kendisi kurar. Elle fiyatlı lot dışarıda —
  /// fiyat turu ona dokunmuyor (`PortfolioNotifier.refreshPrices`).
  static Map<String, List<Asset>> _gruplar(List<Asset> lotlar) {
    final out = <String, List<Asset>>{};
    for (final a in lotlar) {
      if (!a.isActive || a.isManualPrice) continue;
      if (!oynayanTurler.contains(a.type)) continue;
      final s = a.ticker.trim().toUpperCase();
      if (s.isEmpty || s.startsWith('TEFAS:')) continue;
      out.putIfAbsent('$s|${a.currency.trim().toUpperCase()}', () => [])
          .add(a);
    }
    return out;
  }

  static double? _kur(PortfolioState s, String sembol) => switch (sembol) {
        FiyatKaynagi.usdTry => s.usdTry,
        'EURTRY=X' => s.eurTry,
        'GBPTRY=X' => s.gbpTry,
        _ => null,
      };

  static String _gunMetni(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}
