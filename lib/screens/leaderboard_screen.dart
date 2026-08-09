import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/leaderboard_service.dart';
import '../theme/sandik.dart';
import '../widgets/custom_loading_indicator.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() =>
      _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  int _periodIdx = 1; // 0=7g, 1=30g, 2=1y

  static const _periods = [
    (label: '7G', days: 7),
    (label: '30G', days: 30),
    (label: '1Y', days: 365),
  ];

  @override
  Widget build(BuildContext context) {
    final optIn = ref.watch(leaderboardOptInProvider);
    final me = ref.watch(authProvider).valueOrNull;
    final activePartners = ref.watch(activePartnersProvider);
    final myAssets = ref.watch(portfolioProvider).valueOrNull?.assets ?? [];
    final partnerAssets =
        ref.watch(allPartnerAssetsProvider).valueOrNull ?? {};
    final pState = ref.watch(portfolioProvider).valueOrNull;

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Yarış',
          style: context.t.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.c.text90),
        ),
        actions: [
          // Yarıştaki getiri ile Performans ekranındaki yüzde farklı
          // formüllerdir (dönemsel + para akışı düzeltmeli vs. toplam
          // maliyete göre). Kullanıcı ikisini yan yana görünce "hangisi
          // doğru?" diye soruyor — açıklama burada.
          IconButton(
            icon: Icon(Icons.info_outline_rounded,
                color: context.c.text58, size: 22),
            tooltip: 'Getiri nasıl hesaplanıyor?',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: context.c.surface1,
              isScrollControlled: true,
              useSafeArea: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const _RoiInfoSheet(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: !optIn
            ? _OptInPrompt(
                onEnable: () => ref
                    .read(leaderboardOptInProvider.notifier)
                    .set(true),
              )
            : Column(
                children: [
                  _PeriodBar(
                    selected: _periodIdx,
                    onChange: (i) => setState(() => _periodIdx = i),
                    periods: _periods
                        .map((p) => p.label)
                        .toList(growable: false),
                  ),
                  Expanded(
                    child: activePartners.isEmpty
                        ? _SoloPanel(
                            me: me,
                            myAssets: myAssets,
                            periodDays: _periods[_periodIdx].days,
                            pnlToTRY: (val, cur) =>
                                pState?.toTRY(val, cur) ?? val,
                          )
                        : _LeaderboardList(
                            me: me,
                            myAssets: myAssets,
                            partners: activePartners,
                            partnerAssets: partnerAssets,
                            periodDays: _periods[_periodIdx].days,
                            pnlToTRY: (val, cur) =>
                                pState?.toTRY(val, cur) ?? val,
                          ),
                  ),
                  _GlobalPercentileTeaser(
                    periodDays: _periods[_periodIdx].days,
                  ),
                  _TopGainersAllocationCard(
                    periodDays: _periods[_periodIdx].days,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Text(
                      activePartners.isEmpty
                          ? 'Getiri seçili döneme göre hesaplanır; para '
                              'giriş/çıkışı hariç tutulur. Sıralamalar ve '
                              'dağılımlar anonimdir — kimlik, miktar ve TL '
                              'bilgisi asla paylaşılmaz.'
                          : 'Ortak sıralaması seçili dönemin getirisidir '
                              '(%) — para giriş/çıkışı hariç. Kimsenin '
                              'varlık listesi görünmez.',
                      style: context.t.labelMedium?.copyWith(
                        letterSpacing: 0,
                        color: context.c.text36,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "Getiri nasıl hesaplanıyor?" açıklaması.
///
/// Yarıştaki ROI ile Performans ekranındaki kâr/zarar yüzdesi kasıtlı olarak
/// FARKLI metriklerdir; kullanıcı ikisini karşılaştırınca hata sanıyor.
/// Formüller:
///   Yarış      → (bugünkü değer − dönem başı değer − net para akışı)
///                / dönem başı değer × 100   [LeaderboardService.computeROI]
///   Performans → (bugünkü değer − toplam maliyet) / toplam maliyet × 100
class _RoiInfoSheet extends StatelessWidget {
  const _RoiInfoSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: context.c.text36,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Getiri nasıl hesaplanıyor?',
              style: context.t.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.c.text90,
              ),
            ),
            const SizedBox(height: 14),
            const _InfoBlock(
              icon: Icons.emoji_events_outlined,
              title: 'Yarıştaki getiri — dönemsel',
              body: 'Seçtiğin dönemin başındaki portföy değerine göre '
                  'hesaplanır. Dönem içinde yatırdığın yeni para ve '
                  'çektiğin tutar sonuçtan düşülür.\n\n'
                  'Böylece sıralama "kim daha çok para yatırdı" değil, '
                  '"kim parasını daha iyi değerlendirdi" sorusunu ölçer.',
            ),
            const SizedBox(height: 12),
            const _InfoBlock(
              icon: Icons.show_chart_rounded,
              title: 'Performans ekranındaki yüzde — toplam',
              body: 'Varlığın bugünkü değerini ödediğin toplam maliyetle '
                  'karşılaştırır. Dönem ayrımı yoktur, ilk aldığın günden '
                  'bugüne kadarki kâr/zararını gösterir.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.c.amberFill.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(
                    color: context.c.amberFill.withValues(alpha: 0.28)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded,
                      size: 18, color: context.c.amberText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'İki sayının farklı olması normaldir — aynı portföyün '
                      'iki ayrı ölçüsüdür. Örnek: bir yıl önce 100.000 ₺\'ye '
                      'alıp bugün 150.000 ₺ olan portföyde Performans +%50 '
                      'gösterir; portföy 30 gün önce 145.000 ₺ ise "30 gün" '
                      'yarışındaki getirin +%3,4\'tür.',
                      style: context.t.bodySmall?.copyWith(
                        color: context.c.text90,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Dönem başına ait fiyat geçmişi bulunamazsa yarış getirisi de '
              'toplam kâr/zarar yöntemine düşer; bu durumda iki sayı aynı '
              'çıkabilir.',
              style: context.t.labelMedium?.copyWith(
                letterSpacing: 0,
                color: context.c.text36,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _InfoBlock({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.c.surface2,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: context.c.amberText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: context.t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.c.text90,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: context.t.bodySmall?.copyWith(
              color: context.c.text58,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptInPrompt extends StatelessWidget {
  final VoidCallback onEnable;
  const _OptInPrompt({required this.onEnable});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events_outlined,
                size: 48, color: context.c.amberText),
            const SizedBox(height: 16),
            Text(
              'Yarış\'a katılmadın',
              style: context.t.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.c.text90,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ortaklarınla getiri sıralamasında yer almak için '
              'katılmayı aç. Sadece kaydolan ortaklar birbirinin '
              'yüzdesini görebilir. Varlıkların ve toplam TRY '
              'değerin asla paylaşılmaz.',
              style: context.t.bodyMedium?.copyWith(
                color: context.c.text58,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onEnable,
              style: FilledButton.styleFrom(
                backgroundColor: context.c.amberFill,
                foregroundColor: context.c.onAmber,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
              ),
              child: const Text('Yarış\'a katıl'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ortağı olmayan opt-in kullanıcı için: kendi ROI'sini hesaplayıp arka
/// planda snapshot yükler (global percentile aktif olsun diye) ve
/// "ortak ekle" CTA'sı gösterir. Global percentile teaser ayrı widget
/// olarak zaten Column'un altında; bu panel sadece solo state için.
class _SoloPanel extends StatefulWidget {
  final AppUser? me;
  final List<Asset> myAssets;
  final int periodDays;
  final double Function(double, String) pnlToTRY;

  const _SoloPanel({
    required this.me,
    required this.myAssets,
    required this.periodDays,
    required this.pnlToTRY,
  });

  @override
  State<_SoloPanel> createState() => _SoloPanelState();
}

class _SoloPanelState extends State<_SoloPanel> {
  double? _myRoi;
  bool _computing = false;
  Timer? _liveTick;
  static const _livePeriod = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _myRoi = widget.me == null
        ? null
        : LeaderboardService.instance.staleROI(
            userId: widget.me!.id,
            periodDays: widget.periodDays,
          );
    _refresh();
    _liveTick = Timer.periodic(_livePeriod, (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _liveTick?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SoloPanel old) {
    super.didUpdateWidget(old);
    if (old.periodDays != widget.periodDays ||
        old.myAssets.length != widget.myAssets.length) {
      _myRoi = widget.me == null
          ? null
          : LeaderboardService.instance.staleROI(
              userId: widget.me!.id,
              periodDays: widget.periodDays,
            );
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final me = widget.me;
    if (me == null) return;
    setState(() => _computing = true);
    final myCurrentTRY = LeaderboardService.instance
        .totalValueTRY(widget.myAssets, widget.pnlToTRY);
    final roi = await LeaderboardService.instance.computeROI(
      assets: widget.myAssets,
      periodDays: widget.periodDays,
      currentValueTRY: myCurrentTRY,
      toTRY: widget.pnlToTRY,
      cacheKey: me.id,
    );
    if (roi != null) {
      // Fire-and-forget snapshot — global percentile için.
      LeaderboardService.instance.uploadRoiSnapshot(
        userId: me.id,
        periodDays: widget.periodDays,
        roiPct: roi,
      );
    }
    if (!mounted) return;
    setState(() {
      _myRoi = roi;
      _computing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SoloRoiCard(roi: _myRoi, computing: _computing),
          const SizedBox(height: 14),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: context.c.surface1,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              border:
                  Border.all(color: context.c.hairline),
            ),
            child: Row(
              children: [
                Icon(Icons.people_outline_rounded,
                    size: 22, color: context.c.amberText),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ortak ekle, aranızda da yarış',
                        style: context.t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.c.text90,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Kimsenin varlık listesi paylaşılmaz — yalnız '
                        'getiri yüzdeleri sıralanır.',
                        style: context.t.bodySmall?.copyWith(
                          color: context.c.text58,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoloRoiCard extends StatelessWidget {
  final double? roi;
  final bool computing;
  const _SoloRoiCard({required this.roi, required this.computing});

  @override
  Widget build(BuildContext context) {
    final r = roi;
    final positive = r != null && r >= 0;
    final color = r == null
        ? context.c.text58
        : (positive ? context.c.gain : context.c.loss);
    final valueText = r == null
        ? (computing ? 'Hesaplanıyor…' : '—')
        : '${positive ? '+' : ''}${r.toStringAsFixed(2)}%';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.18),
            context.c.surface1.withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(SandikRadius.md),
            ),
            child: Icon(
              r == null
                  ? Icons.query_stats_rounded
                  : (positive
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded),
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SENİN GETİRİN',
                  style: context.t.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: context.c.text58,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  valueText,
                  style: context.t.numLarge.copyWith(
                    color: color,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          if (computing)
            const CustomLoadingIndicator(size: 18),
        ],
      ),
    );
  }
}

/// iOS Cupertino-benzeri segmented control. Aktif segment altın gradient
/// pill ile animate ederek kayar. Sade ama net & rekabet duygusu veren.
class _PeriodBar extends StatelessWidget {
  final int selected;
  final void Function(int) onChange;
  final List<String> periods;
  const _PeriodBar({
    required this.selected,
    required this.onChange,
    required this.periods,
  });

  @override
  Widget build(BuildContext context) {
    // Overflow-güvenli tasarım: LayoutBuilder + explicit width yerine
    // Flex-only. Aktif pill de Stack yerine seçili segment'in Container
    // BoxDecoration'ı ile yapılır — yuvarlama gap'i yok.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.c.overlay,
          borderRadius: BorderRadius.circular(SandikRadius.lg),
          border:
              Border.all(color: context.c.hairline),
        ),
        child: Row(
          children: List.generate(periods.length, (i) {
            final active = i == selected;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChange(i),
                child: AnimatedContainer(
                  duration: SandikMotion.of(context, const Duration(milliseconds: 220)),
                  curve: Curves.easeOutCubic,
                  margin: EdgeInsets.symmetric(
                      horizontal: active ? 0 : 2),
                  decoration: BoxDecoration(
                    // Seçili pill bir YÜZEY — dolgu token'ı kullanılır.
                    // (Eskiden `[gold, amberText]` idi; ikisi de metin
                    // token'ı olduğu için light'ta çöküyordu — bkz.
                    // `SandikPalette.amberGradient`.)
                    gradient: active ? context.c.amberGradient : null,
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: context.c.amberFill
                                  .withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: SandikMotion.stateOf(context),
                      curve: SandikMotion.enter,
                      style: context.t.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w800,
                        color:
                            active ? context.c.onAmber : context.c.text58,
                        letterSpacing: 0.6,
                      ),
                      child: Text(periods[i]),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _LeaderboardList extends StatefulWidget {
  final AppUser? me;
  final List<Asset> myAssets;
  final List<AppUser> partners;
  final Map<String, List<Asset>> partnerAssets;
  final int periodDays;
  final double Function(double, String) pnlToTRY;

  const _LeaderboardList({
    required this.me,
    required this.myAssets,
    required this.partners,
    required this.partnerAssets,
    required this.periodDays,
    required this.pnlToTRY,
  });

  @override
  State<_LeaderboardList> createState() => _LeaderboardListState();
}

class _LeaderboardListState extends State<_LeaderboardList> {
  late Future<List<_LeaderboardRow>> _future;
  // Cache'ten hemen okunan stale rows — spinner göstermek yerine
  // ekran anında bu satırlarla açılır; Future dolunca setState ile
  // yenilenir. Kullanıcı "her girdiğimde hesaplanıyor" hissi almaz.
  List<_LeaderboardRow>? _staleRows;
  // "Anlık" hissi için düzenli tick — her tetikte kendi ROI'sini
  // yeniden hesaplayıp upload eder, sonra partner ROI'lerini
  // Supabase'ten tazeler.
  Timer? _liveTick;
  static const _livePeriod = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _staleRows = _readCachedRows();
    _future = _compute();
    _startLiveTick();
  }

  @override
  void didUpdateWidget(covariant _LeaderboardList old) {
    super.didUpdateWidget(old);
    if (old.periodDays != widget.periodDays ||
        old.partners.length != widget.partners.length) {
      _staleRows = _readCachedRows();
      _future = _compute();
    }
  }

  @override
  void dispose() {
    _liveTick?.cancel();
    super.dispose();
  }

  void _startLiveTick() {
    _liveTick?.cancel();
    _liveTick = Timer.periodic(_livePeriod, (_) {
      if (!mounted) return;
      setState(() => _future = _compute());
    });
  }

  /// LeaderboardService cache'inden — TTL geçmiş bile olsa — synchronous
  /// rows üret. Hepsi cache'te varsa gerçek rows kadar iyi; birkaçı yoksa
  /// onlar için `roi: null` gelir ve Future dolunca yerlerine oturur.
  List<_LeaderboardRow>? _readCachedRows() {
    if (widget.me == null) return null;
    final rows = <_LeaderboardRow>[];
    rows.add(_LeaderboardRow(
      userId: widget.me!.id,
      displayName: '${widget.me!.displayName} (sen)',
      isMe: true,
      roi: LeaderboardService.instance.staleROI(
        userId: widget.me!.id,
        periodDays: widget.periodDays,
      ),
    ));
    for (final p in widget.partners) {
      rows.add(_LeaderboardRow(
        userId: p.id,
        displayName: p.displayName,
        isMe: false,
        roi: LeaderboardService.instance.staleROI(
          userId: p.id,
          periodDays: widget.periodDays,
        ),
      ));
    }
    // Hiç cache yoksa (ilk açılış) null döndür — Future beklensin.
    if (rows.every((r) => r.roi == null)) return null;
    rows.sort((a, b) {
      if (a.roi == null && b.roi == null) return 0;
      if (a.roi == null) return 1;
      if (b.roi == null) return -1;
      return b.roi!.compareTo(a.roi!);
    });
    return rows;
  }

  Future<List<_LeaderboardRow>> _compute() async {
    // Kendi ROI'mizi lokal hesapla → Supabase'e upload et → sonra hem
    // kendimizin hem partnerların ROI'sini TEK OTORİTE olan Supabase
    // snapshot tablosundan oku. Böylece iki cihaz her zaman aynı sayıyı
    // görür. Tick her 15 sn'de bu döngüyü tekrar eder → canlı hissi.
    final me = widget.me;
    double? myRoi;
    if (me != null) {
      final myCurrentTRY = LeaderboardService.instance
          .totalValueTRY(widget.myAssets, widget.pnlToTRY);
      myRoi = await LeaderboardService.instance.computeROI(
        assets: widget.myAssets,
        periodDays: widget.periodDays,
        currentValueTRY: myCurrentTRY,
        toTRY: widget.pnlToTRY,
        cacheKey: me.id,
      );
      if (myRoi != null) {
        // Await ETMİYORUZ, snapshot upload + partner fetch paralel gitsin.
        LeaderboardService.instance.uploadRoiSnapshot(
          userId: me.id,
          periodDays: widget.periodDays,
          roiPct: myRoi,
        );
        // Top gainers allocation feature'ı için anonim tür dağılımını da
        // gönder — miktar/TL yok, sadece {tür: %}. RPC k-anonymity + min
        // type_count filtreleri ile agregat gösterir.
        final alloc = LeaderboardService.instance
            .computeAllocation(widget.myAssets, widget.pnlToTRY);
        if (alloc.length >= 2) {
          LeaderboardService.instance.uploadAllocationSnapshot(
            userId: me.id,
            allocation: alloc,
            typeCount: alloc.length,
          );
        }
      }
    }

    final partnerRois = await LeaderboardService.instance
        .fetchPartnerRois(widget.periodDays);

    final rows = <_LeaderboardRow>[];
    if (me != null) {
      rows.add(_LeaderboardRow(
        userId: me.id,
        displayName: '${me.displayName} (sen)',
        isMe: true,
        roi: myRoi,
      ));
    }
    for (final p in widget.partners) {
      final entry = partnerRois[p.id];
      rows.add(_LeaderboardRow(
        userId: p.id,
        displayName: p.displayName,
        isMe: false,
        roi: entry?.roi,
      ));
    }

    rows.sort((a, b) {
      if (a.roi == null && b.roi == null) return 0;
      if (a.roi == null) return 1;
      if (b.roi == null) return -1;
      return b.roi!.compareTo(a.roi!);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_LeaderboardRow>>(
      future: _future,
      builder: (context, snap) {
        final isLoading =
            snap.connectionState == ConnectionState.waiting;
        // Öncelik: fresh Future data > stale cache > spinner
        final rows = snap.data ?? _staleRows;
        if (rows == null) {
          return const CustomLoadingView();
        }
        if (rows.isEmpty) {
          return Center(
            child: Text(
              'Veri hazır değil.',
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
          );
        }
        // Leader ROI + maxAbsRoi — bar normalize için
        final validRois = rows
            .where((r) => r.roi != null)
            .map((r) => r.roi!)
            .toList();
        final leaderRoi = validRois.isEmpty ? null : validRois.first;
        final maxAbsRoi = validRois.isEmpty
            ? null
            : validRois.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);

        return Stack(
          children: [
            ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _LeaderRow(
                row: rows[i],
                rank: i + 1,
                leaderRoi: leaderRoi,
                maxAbsRoi: maxAbsRoi,
              ),
            ),
            // Stale gösterirken üstte ince progress bar — yeni veri
            // geldiğinde otomatik kaybolur, kullanıcıyı bekletmez.
            if (isLoading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 2,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: context.c.amberFill,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LeaderboardRow {
  final String userId;
  final String displayName;
  final bool isMe;
  final double? roi;
  const _LeaderboardRow({
    required this.userId,
    required this.displayName,
    required this.isMe,
    required this.roi,
  });
}

/// Bir satır: rank badge (madalya) + isim + ROI% + hızlı görsel fark barı.
///
/// Rekabet öğeleri:
/// - Lider satırında ince "LİDER" mikro rozet
/// - Sen ve lider değilsen: sağ altta "+X.X arayla 1." teaser
/// - Fark barı: liderin ROI'sine göre normalize edilmiş uzunluk;
///   negatif ROI'ler bar göstermez (shame azaltıcı — sadece rakam)
class _LeaderRow extends StatelessWidget {
  final _LeaderboardRow row;
  final int rank;
  final double? leaderRoi;
  final double? maxAbsRoi; // barı normalize etmek için
  const _LeaderRow({
    required this.row,
    required this.rank,
    required this.leaderRoi,
    required this.maxAbsRoi,
  });

  @override
  Widget build(BuildContext context) {
    final roi = row.roi;
    final positive = roi != null && roi >= 0;
    final roiColor = roi == null
        ? context.c.text36
        : (positive ? context.c.gain : context.c.loss);
    final roiText = roi == null
        ? 'Veri yok'
        : '${positive ? '+' : ''}${roi.toStringAsFixed(1)}%';

    final isLeader = rank == 1 && roi != null;
    final isMe = row.isMe;

    // Sen değilse lider değilsen fark ölçüsü — motive edici teaser
    String? gapTeaser;
    if (isMe && !isLeader && roi != null && leaderRoi != null) {
      final gap = leaderRoi! - roi;
      if (gap > 0.05) {
        gapTeaser = '+${gap.toStringAsFixed(1)}% arayla 1.';
      }
    }

    // Bar oranı: max(|roi|) baz alınır, negatif ROI için bar yok
    final barRatio = (roi != null &&
            roi >= 0 &&
            maxAbsRoi != null &&
            maxAbsRoi! > 0.01)
        ? (roi / maxAbsRoi!).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe
            ? context.c.amberFill.withValues(alpha: 0.10)
            : context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(
          color: isMe
              ? context.c.amberFill.withValues(alpha: 0.55)
              : isLeader
                  ? context.c.gold.withValues(alpha: 0.35)
                  : context.c.overlay,
          width: isLeader && !isMe ? 1.2 : 1.0,
        ),
        boxShadow: isLeader
            ? [
                BoxShadow(
                  color: context.c.gold.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _rankBadge(context),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            row.displayName,
                            style: context.t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.c.text90,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isLeader) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  context.c.gold.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(SandikRadius.sm),
                            ),
                            child: Text(
                              'LİDER',
                              style: context.t.labelSmall?.copyWith(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                color: context.c.gold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (gapTeaser != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        gapTeaser,
                        style: context.t.labelMedium?.copyWith(
                          fontSize: 10.5,
                          letterSpacing: 0,
                          fontWeight: FontWeight.w600,
                          // `amberFill` MARKA DOLGU rengidir (#F5A623) ve
                          // light/dark'ta değişmez — zemin olarak doğru,
                          // METİN olarak değil: light yüzeyde 1.77:1 veriyordu
                          // (AA eşiği 4.5:1), yani cümle neredeyse görünmezdi.
                          // `amberText` tam da bunun için var: aynı marka
                          // ailesinin okunabilir tonu (light'ta 10.98:1).
                          color: context.c.amberText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                roiText,
                style: context.t.numSmall.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: roiColor,
                ),
              ),
            ],
          ),
          if (barRatio > 0) ...[
            const SizedBox(height: 10),
            _DiffBar(ratio: barRatio, color: roiColor),
          ],
        ],
      ),
    );
  }

  Widget _rankBadge(BuildContext context) {
    // 1-3: gradient madalyalar; 4+: sade amber outlined
    if (rank <= 3) {
      // Tonlar [Sandik] madalya token'larından gelir — gradient'in her iki
      // ucunda da koyu rakamın okunabilmesi için kalibre edildi (bkz. token
      // dokümantasyonu). Yerinde renk yazmak o kalibrasyonu bozar.
      final (Color light, Color dark) = switch (rank) {
        1 => (Sandik.medalGold, Sandik.medalGoldDark),
        2 => (Sandik.medalSilver, Sandik.medalSilverDark),
        _ => (Sandik.medalBronze, Sandik.medalBronzeDark),
      };
      return Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [light, dark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: light.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          '$rank',
          style: context.t.numSmall.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: context.c.onAmber.withValues(alpha: 0.85),
          ),
        ),
      );
    }
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.c.overlay,
        shape: BoxShape.circle,
        border: Border.all(
          color: context.c.overlay,
        ),
      ),
      child: Text(
        '$rank',
        style: context.t.numSmall.copyWith(
          fontWeight: FontWeight.w800,
          color: context.c.text58,
        ),
      ),
    );
  }
}

/// Sıralamayı görsel olarak destekleyen mini bar. Liderin barı tam
/// dolu; diğerleri ROI'lerine göre oranlı. Negatif ROI için gösterilmez.
class _DiffBar extends StatelessWidget {
  final double ratio; // 0..1
  final Color color;
  const _DiffBar({required this.ratio, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SandikRadius.sm),
      child: Container(
        height: 4,
        color: context.c.overlay,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: ratio.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.5),
                  color,
                ],
              ),
              borderRadius: BorderRadius.circular(SandikRadius.sm),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tüm Sandık kullanıcıları arasında anonim percentile göstergesi.
/// Backend RPC (get_percentile_bucket) k=20 threshold uyguluyor — yeterli
/// katılımcı yoksa "YAKINDA" placeholder gösterilir, aksi halde gerçek
/// "İlk %X" numarası + toplam katılımcı sayısı.
class _GlobalPercentileTeaser extends StatefulWidget {
  final int periodDays;
  const _GlobalPercentileTeaser({required this.periodDays});

  @override
  State<_GlobalPercentileTeaser> createState() =>
      _GlobalPercentileTeaserState();
}

class _GlobalPercentileTeaserState
    extends State<_GlobalPercentileTeaser> {
  late Future<_BestPercentile?> _future;
  Timer? _liveTick;
  static const _livePeriod = Duration(seconds: 30);

  static const _periods = <({int days, String label})>[
    (days: 7, label: 'haftalık'),
    (days: 30, label: 'aylık'),
    (days: 365, label: 'yıllık'),
  ];

  @override
  void initState() {
    super.initState();
    _future = _computeBest();
    _liveTick = Timer.periodic(_livePeriod, (_) {
      if (!mounted) return;
      setState(() => _future = _computeBest());
    });
  }

  @override
  void dispose() {
    _liveTick?.cancel();
    super.dispose();
  }

  /// 3 periyotta paralel percentile çek → en iyi (düşük percentile = üst)
  /// olanı göster. "Genel havuzda hangi periyotta en üsttesin" hissi
  /// verir; kullanıcı belirli bir periyot seçmeden vitrin görür.
  Future<_BestPercentile?> _computeBest() async {
    final results = await Future.wait(
      _periods.map((p) => LeaderboardService.instance
          .fetchPercentile(p.days)
          .then((data) => data == null
              ? null
              : _BestPercentile(
                  periodLabel: p.label,
                  percentile: data.percentile,
                  total: data.total,
                ))),
    );
    final valid = results.whereType<_BestPercentile>().toList();
    if (valid.isEmpty) return null;
    valid.sort((a, b) => a.percentile.compareTo(b.percentile));
    return valid.first;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: FutureBuilder<_BestPercentile?>(
        future: _future,
        builder: (_, snap) {
          final data = snap.data;
          return _shell(child: _content(data, snap.connectionState));
        },
      ),
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.c.surface2.withValues(alpha: 0.7),
            context.c.surface1.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border:
            Border.all(color: context.c.hairline),
      ),
      child: child,
    );
  }

  Widget _content(_BestPercentile? data, ConnectionState state) {
    // Loading
    if (state == ConnectionState.waiting && data == null) {
      return _row(
        badge: _Badge(text: 'YÜKLENİYOR', color: context.c.text58),
        title: 'Genel Sıralama',
        subtitle: 'Anonim havuz kontrol ediliyor…',
        icon: Icons.public_rounded,
        iconColor: context.c.text58,
      );
    }

    // k-anonymity altında veya yeterli veri yok
    if (data == null) {
      return _row(
        badge: _Badge(text: 'YAKINDA', color: context.c.gain),
        title: 'Genel Sıralama',
        subtitle:
            'Yeterli katılımcı olunca sıran açılacak — anonim, KVKK uyumlu',
        icon: Icons.public_rounded,
        iconColor: context.c.gain,
      );
    }

    // En iyi periyot vitrine — kullanıcı hangi zaman diliminde parlıyorsa.
    final pct = data.percentile;
    final total = data.total;
    final tone = _toneFor(pct);
    final periodCap = _capitalize(data.periodLabel);
    return _row(
      badge: _Badge(
        text: total > 1000
            ? '${(total / 1000).toStringAsFixed(1)}K KİŞİ'
            : '$total KİŞİ',
        color: context.c.text58,
      ),
      title: '$periodCap sıralamada ilk %$pct\'desin',
      subtitle: tone,
      icon: Icons.public_rounded,
      iconColor: pct <= 25 ? context.c.gain : context.c.amberText,
      hero: true,
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _toneFor(int pct) {
    if (pct <= 5) return 'Zirvedeki azınlıktasın 🚀';
    if (pct <= 10) return 'Sandık\'ın en iyi %10\'undasın';
    if (pct <= 25) return 'Ortalamanın çok üstündesin';
    if (pct <= 50) return 'Ortalamanın üstündesin';
    if (pct <= 75) return 'Ortalamaya yakınsın';
    return 'Daha iyisini yapabilirsin — 30G takip et';
  }

  Widget _row({
    required _Badge badge,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    bool hero = false,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(SandikRadius.md),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: context.t.bodyMedium?.copyWith(
                        fontSize: hero ? 14 : 13,
                        fontWeight: FontWeight.w800,
                        color: context.c.text90,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  badge,
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: context.t.bodySmall?.copyWith(
                  color: context.c.text58,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Gainers Allocation kartı — anonim, agregat: "Bu hafta en çok kazanan
// portföyler neyden oluşuyor?" Kimlik, miktar, TL yok — sadece rank + ROI +
// tür yüzdeleri. Marka: gold/amber gradient shell, madalya rank, tür
// renkleri (AssetType.color), horizontal stacked bar + inline legend.
// ─────────────────────────────────────────────────────────────────────────────

class _TopGainersAllocationCard extends StatefulWidget {
  final int periodDays;
  const _TopGainersAllocationCard({required this.periodDays});

  @override
  State<_TopGainersAllocationCard> createState() =>
      _TopGainersAllocationCardState();
}

class _TopGainersAllocationCardState extends State<_TopGainersAllocationCard> {
  late Future<List<TopGainerAllocation>> _future;
  Timer? _liveTick;
  static const _livePeriod = Duration(seconds: 45);
  int _expandedIdx = 0; // seçili rank kartı

  @override
  void initState() {
    super.initState();
    _future = _fetch();
    _liveTick = Timer.periodic(_livePeriod, (_) {
      if (!mounted) return;
      setState(() => _future = _fetch());
    });
  }

  @override
  void didUpdateWidget(covariant _TopGainersAllocationCard old) {
    super.didUpdateWidget(old);
    if (old.periodDays != widget.periodDays) {
      _expandedIdx = 0;
      _future = _fetch();
    }
  }

  @override
  void dispose() {
    _liveTick?.cancel();
    super.dispose();
  }

  Future<List<TopGainerAllocation>> _fetch() =>
      LeaderboardService.instance.fetchTopGainersAllocation(
        periodDays: widget.periodDays,
        topN: 5,
      );

  String get _periodLabel {
    switch (widget.periodDays) {
      case 7:
        return 'HAFTALIK';
      case 30:
        return 'AYLIK';
      default:
        return 'YILLIK';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: FutureBuilder<List<TopGainerAllocation>>(
        future: _future,
        builder: (_, snap) {
          final rows = snap.data ?? const <TopGainerAllocation>[];
          final loading =
              snap.connectionState == ConnectionState.waiting && rows.isEmpty;
          return _shell(child: _content(rows, loading));
        },
      ),
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.c.gold.withValues(alpha: 0.08),
            context.c.surface1.withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.gold.withValues(alpha: 0.18)),
      ),
      child: child,
    );
  }

  Widget _content(List<TopGainerAllocation> rows, bool loading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(rows.length, loading),
        const SizedBox(height: 10),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: CustomLoadingIndicator(size: 18),
            ),
          )
        else if (rows.isEmpty)
          _emptyState(context)
        else
          Column(
            children: [
              _rankStrip(rows),
              const SizedBox(height: 12),
              _AllocationDetail(row: rows[_expandedIdx.clamp(0, rows.length - 1)]),
            ],
          ),
      ],
    );
  }

  Widget _header(int count, bool loading) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: context.c.amberGradient,
            borderRadius: BorderRadius.circular(SandikRadius.sm),
          ),
          // Sabit `Colors.black87` yerine tema token'ı — amber dolgunun
          // üzerine gelen içerik rengi tanımı zaten `onAmber`.
          child: Icon(Icons.emoji_events_rounded,
              color: context.c.onAmber, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Zirvedeki Portföyler',
                style: context.t.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.c.text90,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '${_periodLabel.toLowerCase()} en çok kazananların dağılımı',
                style: context.t.labelMedium?.copyWith(
                  letterSpacing: 0,
                  color: context.c.text58,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: context.c.gold.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(SandikRadius.sm),
          ),
          child: Text(
            'ANONİM',
            style: context.t.labelSmall?.copyWith(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: context.c.gold,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        'Yeterli katılımcı olunca zirve portföyler burada görünecek. '
        'Anonim havuz oluşuyor…',
        style: context.t.bodySmall?.copyWith(
          color: context.c.text58,
          height: 1.35,
        ),
      ),
    );
  }

  /// Yatay rank chip'leri: 1-5, tıklanınca alt detay değişir.
  Widget _rankStrip(List<TopGainerAllocation> rows) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final r = rows[i];
          final selected = i == _expandedIdx;
          final positive = r.roiPct >= 0;
          final roiColor = positive ? context.c.gain : context.c.loss;
          return GestureDetector(
            onTap: () => setState(() => _expandedIdx = i),
            child: AnimatedContainer(
              duration: SandikMotion.stateOf(context),
              curve: SandikMotion.enter,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? context.c.gold.withValues(alpha: 0.16)
                    : context.c.overlay,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(
                  color: selected
                      ? context.c.gold.withValues(alpha: 0.55)
                      : context.c.overlay,
                  width: selected ? 1.2 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _rankMedal(context, r.rank),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${r.rank}. portföy',
                        style: context.t.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.c.text58,
                          letterSpacing: 0.4,
                        ),
                      ),
                      Text(
                        '${positive ? '+' : ''}${r.roiPct.toStringAsFixed(1)}%',
                        style: context.t.numSmall.copyWith(
                          fontWeight: FontWeight.w800,
                          color: roiColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _rankMedal(BuildContext context, int rank) {
    // Bkz. `_rankBadge` — aynı kalibre edilmiş token seti.
    final (light, dark) = switch (rank) {
      1 => (Sandik.medalGold, Sandik.medalGoldDark),
      2 => (Sandik.medalSilver, Sandik.medalSilverDark),
      3 => (Sandik.medalBronze, Sandik.medalBronzeDark),
      _ => (context.c.hairline, context.c.hairline),
    };
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [light, dark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$rank',
        style: context.t.numSmall.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: context.c.onAmber.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

/// Seçili rank için tür bazlı dağılım detay bloğu — stacked bar + legend.
class _AllocationDetail extends StatelessWidget {
  final TopGainerAllocation row;
  const _AllocationDetail({required this.row});

  @override
  Widget build(BuildContext context) {
    // Türleri değer sırasına göre büyükten küçüğe sırala; renkleri
    // AssetType.color'dan al, tanınmayan tür için nötr slate rengi.
    final entries = row.allocation.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final segments = entries
        .map((e) => (
              label: _labelFor(e.key),
              pct: e.value,
              color: _colorFor(e.key),
            ))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stacked bar — yatay, her türü renk ile ayırır. FractionallySized
        // ile toplam width içinde oransal segmentler.
        ClipRRect(
          borderRadius: BorderRadius.circular(SandikRadius.sm),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                for (final s in segments)
                  Expanded(
                    flex: (s.pct * 100).round().clamp(1, 100000),
                    child: Container(color: s.color),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final s in segments)
              _LegendChip(
                label: s.label,
                pct: s.pct,
                color: s.color,
              ),
          ],
        ),
      ],
    );
  }

  String _labelFor(String typeKey) {
    for (final t in AssetType.values) {
      if (t.name == typeKey) return t.label;
    }
    // Bilinmeyen tür (ileride eklenecek yeni tür); kelimeyi düzgün göster.
    if (typeKey.isEmpty) return '—';
    return typeKey[0].toUpperCase() + typeKey.substring(1);
  }

  Color _colorFor(String typeKey) {
    for (final t in AssetType.values) {
      if (t.name == typeKey) return t.color;
    }
    return const Color(0xFF9AA5B1); // nötr slate — bilinmeyen tür
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final double pct;
  final Color color;
  const _LegendChip({
    required this.label,
    required this.pct,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.t.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.c.text90,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '%${pct.toStringAsFixed(0)}',
            style: context.t.numSmall.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Global percentile için "en iyi periyot" satırı — 3 periyot arasından
/// kullanıcının en üst sırada olduğu bir tanesi vitrine çıkar.
class _BestPercentile {
  final String periodLabel; // "haftalık" | "aylık" | "yıllık"
  final int percentile;
  final int total;
  const _BestPercentile({
    required this.periodLabel,
    required this.percentile,
    required this.total,
  });
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(SandikRadius.sm),
      ),
      child: Text(
        text,
        style: context.t.labelSmall?.copyWith(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}


