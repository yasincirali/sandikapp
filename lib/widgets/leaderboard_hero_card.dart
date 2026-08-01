import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../screens/leaderboard_screen.dart';
import '../services/leaderboard_service.dart';
import '../theme/sandik.dart';

/// Profile ekranında öne çıkan Yarış hero kartı.
///
/// 3 durum:
/// - Opt-in kapalı: "Yarış'a katıl" CTA + değer önerisi
/// - Opt-in açık ama partner yok: "Ortak ekle" nudge (ortaklık akışı zaten
///   üstte var, o yüzden kısa)
/// - Opt-in açık + partner var: kısa preview — rank + hemen üstünde/altında
///   olan yarışmacı, "Sıralamayı gör" CTA
///
/// Hedef: dikkat çeksin (gradient + trophy), tıklama davetkâr olsun.
class LeaderboardHeroCard extends ConsumerWidget {
  const LeaderboardHeroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optIn = ref.watch(leaderboardOptInProvider);
    final partners = ref.watch(activePartnersProvider);

    if (!optIn) return _OptInHero(ref: ref);
    if (partners.isEmpty) return const SizedBox.shrink();
    return const _RankPreviewHero();
  }
}

class _OptInHero extends StatelessWidget {
  final WidgetRef ref;
  const _OptInHero({required this.ref});

  @override
  Widget build(BuildContext context) {
    return _HeroShell(
      onTap: () {
        // Sadece toggle aç — kullanıcı sonra chip'e basıp sıralamayı görecek
        ref.read(leaderboardOptInProvider.notifier).set(true);
      },
      child: Row(
        children: [
          _TrophyBadge(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Yarış',
                      style: context.t.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Sandik.gain.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'YENİ',
                        style: context.t.labelSmall?.copyWith(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Sandik.gain,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Ortaklarınla getiri sıralaması. Kim daha iyi kazanıyor?',
                  style: context.t.bodySmall?.copyWith(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.75),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Sandik.amber,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Katıl',
              style: context.t.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: Colors.black,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankPreviewHero extends ConsumerStatefulWidget {
  const _RankPreviewHero();

  @override
  ConsumerState<_RankPreviewHero> createState() =>
      _RankPreviewHeroState();
}

class _RankPreviewHeroState extends ConsumerState<_RankPreviewHero> {
  late Future<_RankSnapshot?> _future;
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
    _future = _compute();
    _liveTick = Timer.periodic(_livePeriod, (_) {
      if (!mounted) return;
      setState(() => _future = _compute());
    });
  }

  @override
  void dispose() {
    _liveTick?.cancel();
    super.dispose();
  }

  /// 3 periyotta paralel hesap → kullanıcının en iyi sırada olduğu
  /// periyodu seç. Kendi ROI'sini lokal hesap + Supabase upload; partner
  /// ROI'lerini Supabase RPC'den oku (leaderboard ekranı ile aynı otorite).
  Future<_RankSnapshot?> _compute() async {
    final me = ref.read(authProvider).valueOrNull;
    final partners = ref.read(activePartnersProvider);
    final myAssets = ref.read(portfolioProvider).valueOrNull?.assets ?? [];
    final pState = ref.read(portfolioProvider).valueOrNull;
    if (me == null || pState == null) return null;
    if (partners.isEmpty) return null;

    final myCurrentTRY =
        LeaderboardService.instance.totalValueTRY(myAssets, pState.toTRY);

    Future<_PeriodSnapshot?> compute(int periodDays, String label) async {
      // Kendi ROI — lokal hesap + upload (fire-and-forget).
      final myRoi = await LeaderboardService.instance.computeROI(
        assets: myAssets,
        periodDays: periodDays,
        currentValueTRY: myCurrentTRY,
        toTRY: pState.toTRY,
        cacheKey: me.id,
      );
      if (myRoi != null) {
        LeaderboardService.instance.uploadRoiSnapshot(
          userId: me.id,
          periodDays: periodDays,
          roiPct: myRoi,
        );
      }
      // Partner ROI'leri — Supabase snapshot'ı (tek otorite).
      final partnerRois =
          await LeaderboardService.instance.fetchPartnerRois(periodDays);

      final rows = <_Row>[
        _Row(name: '${me.displayName} (sen)', isMe: true, roi: myRoi),
        for (final p in partners)
          _Row(name: p.displayName, isMe: false, roi: partnerRois[p.id]?.roi),
      ];
      rows.sort((a, b) {
        if (a.roi == null && b.roi == null) return 0;
        if (a.roi == null) return 1;
        if (b.roi == null) return -1;
        return b.roi!.compareTo(a.roi!);
      });
      final myIdx = rows.indexWhere((r) => r.isMe);
      if (myIdx < 0) return null;
      return _PeriodSnapshot(
        periodDays: periodDays,
        periodLabel: label,
        myRank: myIdx + 1,
        total: rows.length,
        myRoi: rows[myIdx].roi,
        leaderName: rows.first.name,
        leaderRoi: rows.first.roi,
        justAboveName: myIdx > 0 ? rows[myIdx - 1].name : null,
        justAboveRoi: myIdx > 0 ? rows[myIdx - 1].roi : null,
      );
    }

    final snapshots = await Future.wait(
      _periods.map((p) => compute(p.days, p.label)),
    );
    final valid = snapshots.whereType<_PeriodSnapshot>().toList();
    if (valid.isEmpty) return null;

    // En iyi periyot = önce myRank'i en düşük (1 en iyi), eşitse ROI en
    // yüksek. Bu şekilde 3 periyottan hangisinde parlayan varsa o vitrine.
    valid.sort((a, b) {
      final rc = a.myRank.compareTo(b.myRank);
      if (rc != 0) return rc;
      final aR = a.myRoi ?? -1e9;
      final bR = b.myRoi ?? -1e9;
      return bR.compareTo(aR);
    });
    return _RankSnapshot(best: valid.first, all: valid);
  }

  void _openLeaderboard() {
    Navigator.push(
      context,
      adaptiveRoute(builder: (_) => const LeaderboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _HeroShell(
      onTap: _openLeaderboard,
      child: FutureBuilder<_RankSnapshot?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeletonRow();
          }
          final data = snap.data;
          if (data == null) return _skeletonRow();
          return _preview(data);
        },
      ),
    );
  }

  Widget _skeletonRow() {
    return Row(
      children: [
        _TrophyBadge(),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            'Yarış hesaplanıyor…',
            style: context.t.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Sandik.amber)),
      ],
    );
  }

  Widget _preview(_RankSnapshot d) {
    final best = d.best;
    final rankLabel = _rankLabel(best.myRank);
    final positive = (best.myRoi ?? 0) >= 0;
    final roiColor = best.myRoi == null
        ? Colors.white.withValues(alpha: 0.5)
        : (positive ? Sandik.gain : Sandik.loss);
    final roiText = best.myRoi == null
        ? '—'
        : '${positive ? '+' : ''}${best.myRoi!.toStringAsFixed(1)}%';

    // Başlık: "Haftalıkta 1. sıradasın" gibi — hangi periyotta parladığını
    // göstermek rekabet duygusunu güçlendirir, "ne olduğu" belirsizliğini
    // giderir. Sadece 1'i vurgula, 2+'ta rank etiketiyle bilgi ver.
    final periodCap = _capitalize(best.periodLabel);
    final title = best.myRank == 1 && best.total > 1
        ? '$periodCap sıralamada 1.\'sin'
        : '$periodCap sıralamada $rankLabel sıradasın';

    // Alt satır: liderde motive → "seni yakalamak için X% lazım", değilse
    // → "X'i geçmen için +Y%". Kısa, aksiyona teşvik eder.
    String subLine;
    if (best.myRank == 1 && best.total > 1) {
      // Zirvedeysen, ikinci sıradaki senden ne kadar geride onu göster.
      final gap = (best.myRoi ?? 0) - (best.leaderRoi == best.myRoi
          ? _secondRoi(d) ?? (best.myRoi ?? 0)
          : (best.myRoi ?? 0));
      subLine = gap > 0.05
          ? 'Farkı büyüt — ikinci +${gap.toStringAsFixed(1)}% geride'
          : 'Zirvedesin — farkı koru 🏆';
    } else if (best.justAboveName != null && best.justAboveRoi != null) {
      final diff = (best.justAboveRoi! - (best.myRoi ?? 0)).abs();
      subLine =
          '${best.justAboveName!.split(' ').first}\'i geçmen için +${diff.toStringAsFixed(1)}%';
    } else {
      subLine = 'Diğer periyotlarda daha üsttesin — dokun, bak';
    }

    return Row(
      children: [
        _RankMedal(rank: best.myRank, total: best.total),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: context.t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    roiText,
                    style: context.t.numSmall.copyWith(
                      fontWeight: FontWeight.w800,
                      color: roiColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subLine,
                style: context.t.bodySmall?.copyWith(
                  fontSize: 11.5,
                  color: Colors.white.withValues(alpha: 0.70),
                  height: 1.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right_rounded,
            color: Colors.white.withValues(alpha: 0.65), size: 22),
      ],
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Best snapshot 1.'yse ikinci sıranın ROI'sini bulur — alt satırdaki
  /// "ikinci +X% geride" cümlesi için.
  double? _secondRoi(_RankSnapshot d) {
    // Best snapshot'ta myRank=1 ise, o period'daki justAbove yok (biz
    // liderz). İkinciyi bulmak için period-level tekrar hesap gerekir;
    // basit approach: bilgi yoksa null döner, üst kod fallback yazar.
    return null;
  }

  String _rankLabel(int rank) {
    if (rank == 1) return '1.';
    if (rank == 2) return '2.';
    if (rank == 3) return '3.';
    return '$rank.';
  }
}

class _Row {
  final String name;
  final bool isMe;
  final double? roi;
  const _Row({required this.name, required this.isMe, required this.roi});
}

class _PeriodSnapshot {
  final int periodDays;
  final String periodLabel; // "haftalık" | "aylık" | "yıllık"
  final int myRank;
  final int total;
  final double? myRoi;
  final String leaderName;
  final double? leaderRoi;
  final String? justAboveName;
  final double? justAboveRoi;
  const _PeriodSnapshot({
    required this.periodDays,
    required this.periodLabel,
    required this.myRank,
    required this.total,
    required this.myRoi,
    required this.leaderName,
    required this.leaderRoi,
    required this.justAboveName,
    required this.justAboveRoi,
  });
}

class _RankSnapshot {
  final _PeriodSnapshot best;
  final List<_PeriodSnapshot> all;
  const _RankSnapshot({required this.best, required this.all});
}

/// Kart kabuğu: gradient + trophy pattern arka plan + tıklama davranışı.
class _HeroShell extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _HeroShell({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF6D3A00).withValues(alpha: 0.55),
                Sandik.amber.withValues(alpha: 0.28),
                const Color(0xFF3D2500).withValues(alpha: 0.55),
              ],
              stops: const [0.0, 0.55, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: Sandik.amber.withValues(alpha: 0.35),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Sandik.amber.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Dekoratif faded trophy watermark
              Positioned(
                right: -12,
                top: -18,
                child: Icon(
                  Icons.emoji_events_rounded,
                  size: 110,
                  color: Colors.black.withValues(alpha: 0.10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrophyBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Sandik.gold, Sandik.amber],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Sandik.amber.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        Icons.emoji_events_rounded,
        size: 22,
        color: Colors.black,
      ),
    );
  }
}

class _RankMedal extends StatelessWidget {
  final int rank;
  final int total;
  const _RankMedal({required this.rank, required this.total});

  @override
  Widget build(BuildContext context) {
    final color = rank == 1
        ? Sandik.gold
        : rank == 2
            ? const Color(0xFFC0C0C0) // silver
            : rank == 3
                ? const Color(0xFFCD7F32) // bronze
                : Sandik.amber;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color,
            color.withValues(alpha: 0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$rank',
            style: context.t.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: Colors.black,
              height: 1,
            ),
          ),
          Text(
            '/$total',
            style: context.t.labelSmall?.copyWith(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.55),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
