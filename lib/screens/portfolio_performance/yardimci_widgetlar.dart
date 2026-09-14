part of '../portfolio_performance_screen.dart';

/// Küçük yardımcı widget'lar: hacim çubuğu modeli, gün içi not, grafik yer
/// tutucu, lider tablosu çipi. `portfolio_performance_screen.dart`'ın part'ı.
class _VolumeBar {
  final double x;
  final double buy;
  final double sell;
  const _VolumeBar({required this.x, required this.buy, required this.sell});
  double get total => buy + sell;
}

/// Seçili dönem ve sekmeye göre HER VARLIK TÜRÜNÜN — ve açıldığında o türün
/// içindeki HER ÜRÜNÜN — dönem değişimi.
///
/// ## Değişmez: satırların toplamı üst kartı TUTAR
/// Üstteki değişim kartı portföyün toplamını verir; bu kart onu önce türlere,
/// tür açıldığında ürünlere ayırır. Üç seviye de **aynı seriden** okur:
///
///   üst kart     → `segments` (historyMap → _convertHistoryToSegments)
///   tür satırı   → `breakdown.byType[t]`
///   ürün satırı  → `breakdown.byPosition[k]`
///
/// `HistoryService.getPortfolioHistoryBreakdownAtResolution` üçünü de TEK
/// döngüde üretir, yani `Σ ürün == tür` ve `Σ tür == toplam` yapısal olarak
/// doğrudur.
///
/// **Bug geçmişi (2026-09-01).** Bu kart eskiden tür başına AYRI bir
/// `getPortfolioHistory(assets, periodDays)` çağırıyordu. O yol üst karttan
/// beş noktada ayrışıyordu ve toplamlar hiçbir zaman tutmuyordu:
///   1. üst kartın son noktası canlı toplamla eziliyor (`currentTotalOverride`),
///      dökümde böyle bir override yoktu;
///   2. üst kart seriyi ilk alım gününe kırpıyor (`firstAssetMidnight`),
///      döküm dönem başından başlıyordu;
///   3. üst kart `effectiveStart` penceresini, döküm ham `periodDays`
///      penceresini kullanıyordu;
///   4. mevduat dökümden tamamen çıkarılmıştı ama üst kartın toplamındaydı;
///   5. dönem başı değeri 0 olan tür (dönem içinde ilk kez alınan varlık)
///      sessizce düşürülüyordu.
/// Hepsi tek kökten geliyordu: iki kart iki farklı veri kaynağı kullanıyordu.
/// Çözüm tek kaynağa indirgemek oldu — yamalarla hizalamak değil.
///
/// ## Formül
/// Her seviyede aynı: tutar `son − ilk`, oran `(son − ilk) / ilk`.
///
/// ## Her varlık KENDİ kategorisinde — sentetik satır yok
/// Sentetik bir "Diğer" satırı **kullanılmaz** (kullanıcı kararı, 2026-09-01).
/// İki sebeple:
///   1. `AssetType.diger` zaten gerçek bir kategori ("Diğer", mor). Sentetik
///      bir satıra aynı adı vermek, biri gerçek biri hesap artığı iki satır
///      üretir ve doğrudan yanlış bilgi verirdi.
///   2. Kategorisiz bakiye diye bir şey yok: `mevduat` ve `diger` dahil her
///      varlık `currentPrice` dalından değer alır ve kendi türüne yazılır.
///
/// Üst kartla tür serileri arasındaki küçük fark (üst kartın son noktası
/// canlı toplamla ezilir, seriler ham gelir) gerçek bir kategori değil, aynı
/// varlıkların birkaç dakikalık fiyat farkıdır — `_calibrate` onu türlerin
/// ağırlığınca dağıtır. `Σ satır == üst kart` yine korunur.
/// "Bu türün gün içi verisi alınamadı" notu.
///
/// ## Neden var
/// Gün içi fiyatı çekilemeyen bir varlık grafikte KAYBOLMAZ — son bilinen
/// fiyatıyla gün boyu sabit çizilir (bkz. `assetSeedTRY`). Bu doğru
/// davranış: varlığı grafikten düşürmek portföyü olduğundan küçük
/// gösterirdi. Ama sessiz kaldığında kullanıcı düz çizgiyi "piyasa durgun"
/// diye okuyor ve uygulamanın bozuk olup olmadığını anlayamıyor —
/// kullanıcı bunu doğrudan sordu: "altın değeri mi alınamıyor acaba".
///
/// Not yalnızca gün içi fiyatı OLMASI GEREKEN türler için çıkar; fon
/// (TEFAS gün içi NAV yayınlamaz), vadeli mevduat ve "diğer" için asla.
class _GunIciVeriYokNotu extends StatelessWidget {
  const _GunIciVeriYokNotu({required this.turler});

  final Set<AssetType> turler;

  @override
  Widget build(BuildContext context) {
    // Sıra deterministik olsun — küme sırası tur başına değişebilir ve
    // aynı ekran her build'de farklı okunurdu.
    final adlar = (turler.map((t) => t.label).toList()..sort()).join(', ');
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: SandikSpace.md, vertical: 12),
      decoration: context.surfaceCard(radius: SandikRadius.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: context.c.text58),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$adlar için gün içi fiyat verisi alınamadı. Bu varlıklar '
              'grafikte son bilinen fiyatlarıyla SABİT çizildi — çizginin '
              'düz olması piyasanın durgun olduğu anlamına gelmez.',
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grafik alanının "çizilecek bir şey yok" hâli.
///
/// Spinner bir SÖZDÜR: "bekle, veri geliyor". Gelmeyecekse o söz tutulmaz.
/// Portföyde bulunmayan bir tür seçildiğinde `HistoryService` boş varlık
/// listesine boş seri döndürür; ekran eskiden burada da spinner çizip
/// sonsuza kadar döndürüyordu. Beklenecek bir şey yoksa sebebini söyle.
class _ChartPlaceholder extends StatelessWidget {
  const _ChartPlaceholder({
    required this.icon,
    required this.title,
    required this.message,
    this.iconColor,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Tür rengi — boş durum bile seçili çipin kimliğini taşısın.
  final Color? iconColor;

  /// Yalnızca "veri alınamadı" hâlinde verilir; gerçek boş durumda tekrar
  /// denenecek bir şey yok.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(SandikSpace.md),
              decoration: BoxDecoration(
                color:
                    (iconColor ?? context.c.amberFill).withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child:
                  Icon(icon, size: 28, color: iconColor ?? context.c.amberText),
            ),
            const SizedBox(height: SandikSpace.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.t.titleMedium?.copyWith(
                color: context.c.text90,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: SandikSpace.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: SandikSpace.md),
              SandikTappable(
                onTap: onRetry,
                haptic: SandikHaptic.medium,
                semanticLabel: 'Tekrar dene',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SandikSpace.lg,
                    vertical: SandikSpace.sm,
                  ),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.12),
                    borderRadius: SandikRadius.mdAll,
                    border: Border.all(
                      color: context.c.amberFill.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    'Tekrar Dene',
                    style: context.t.bodyMedium?.copyWith(
                      color: context.c.amberText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Yarış (leaderboard) ekranını açan küçük ikon buton — grafik container
/// üstünde, fullscreen chip'inin solunda. Opt-in ve partner varsa gösterilir.
class _LeaderboardChip extends StatelessWidget {
  final VoidCallback onTap;
  const _LeaderboardChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: context.c.amberFill.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border:
                Border.all(color: context.c.amberFill.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_rounded,
                  size: 13, color: context.c.amberText),
              const SizedBox(width: 4),
              Text(
                'YARIŞ',
                style: context.t.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.c.amberText,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
