import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/asset.dart';
import '../models/user_model.dart';
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
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
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
                        style: GoogleFonts.dmSans(
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
                  style: GoogleFonts.dmSans(
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
              style: GoogleFonts.dmSans(
                fontSize: 11,
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

  @override
  void initState() {
    super.initState();
    _future = _compute();
  }

  Future<_RankSnapshot?> _compute() async {
    final me = ref.read(authProvider).valueOrNull;
    final partners = ref.read(activePartnersProvider);
    final myAssets = ref.read(portfolioProvider).valueOrNull?.assets ?? [];
    final partnerAssets =
        ref.read(allPartnerAssetsProvider).valueOrNull ?? {};
    final pState = ref.read(portfolioProvider).valueOrNull;
    if (me == null || pState == null) return null;

    Future<double?> roiFor(String userId, List<Asset> assets) async {
      if (assets.isEmpty) return null;
      final currentTRY = LeaderboardService.instance
          .totalValueTRY(assets, pState.toTRY);
      return LeaderboardService.instance.computeROI(
        assets: assets,
        periodDays: 30,
        currentValueTRY: currentTRY,
        toTRY: pState.toTRY,
        cacheKey: userId,
      );
    }

    // Paralel fetch — sequential await yerine Future.wait
    final tasks = <Future<_Row>>[
      roiFor(me.id, myAssets).then(
          (roi) => _Row(name: '${me.displayName} (sen)', isMe: true, roi: roi)),
      for (final p in partners)
        roiFor(p.id, partnerAssets[p.id] ?? const []).then(
            (roi) => _Row(name: p.displayName, isMe: false, roi: roi)),
    ];
    final rows = await Future.wait(tasks);
    rows.sort((a, b) {
      if (a.roi == null && b.roi == null) return 0;
      if (a.roi == null) return 1;
      if (b.roi == null) return -1;
      return b.roi!.compareTo(a.roi!);
    });

    final myIdx = rows.indexWhere((r) => r.isMe);
    if (myIdx < 0) return null;

    return _RankSnapshot(
      myRank: myIdx + 1,
      total: rows.length,
      myRoi: rows[myIdx].roi,
      leaderName: rows.first.name,
      leaderRoi: rows.first.roi,
      justAboveName:
          myIdx > 0 ? rows[myIdx - 1].name : null,
      justAboveRoi: myIdx > 0 ? rows[myIdx - 1].roi : null,
    );
  }

  void _openLeaderboard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
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
            style: GoogleFonts.dmSans(
              fontSize: 13,
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
    final rankLabel = _rankLabel(d.myRank);
    final positive = (d.myRoi ?? 0) >= 0;
    final roiColor = d.myRoi == null
        ? Colors.white.withValues(alpha: 0.5)
        : (positive ? Sandik.gain : Sandik.loss);
    final roiText = d.myRoi == null
        ? '—'
        : '${positive ? '+' : ''}${d.myRoi!.toStringAsFixed(1)}%';

    // Alt satır mesajı: liderdeysem "Zirvedesin" göster, değilsem
    // "hemen üstündekini" kimin geçmesi gerektiği bilgisiyle ver.
    String subLine;
    if (d.myRank == 1 && d.total > 1) {
      subLine = 'Zirvedesin 🏆';
    } else if (d.justAboveName != null && d.justAboveRoi != null) {
      final diff = (d.justAboveRoi! - (d.myRoi ?? 0)).abs();
      subLine =
          '${d.justAboveName!.split(' ').first}\'i geçmen için +${diff.toStringAsFixed(1)}%';
    } else {
      subLine = 'Son 30 gün getiri sıralaması';
    }

    return Row(
      children: [
        _RankMedal(rank: d.myRank, total: d.total),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '$rankLabel sıradasın',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    roiText,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: roiColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subLine,
                style: GoogleFonts.dmSans(
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

class _RankSnapshot {
  final int myRank;
  final int total;
  final double? myRoi;
  final String leaderName;
  final double? leaderRoi;
  final String? justAboveName;
  final double? justAboveRoi;
  const _RankSnapshot({
    required this.myRank,
    required this.total,
    required this.myRoi,
    required this.leaderName,
    required this.leaderRoi,
    required this.justAboveName,
    required this.justAboveRoi,
  });
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
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              height: 1,
            ),
          ),
          Text(
            '/$total',
            style: GoogleFonts.dmSans(
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
