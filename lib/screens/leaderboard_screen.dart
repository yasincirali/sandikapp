import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/asset.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/leaderboard_service.dart';
import '../theme/sandik.dart';

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
      backgroundColor: Sandik.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Yarış',
          style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: !optIn
            ? _OptInPrompt(
                onEnable: () => ref
                    .read(leaderboardOptInProvider.notifier)
                    .set(true),
              )
            : activePartners.isEmpty
                ? _EmptyPartners()
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
                        child: _LeaderboardList(
                          me: me,
                          myAssets: myAssets,
                          partners: activePartners,
                          partnerAssets: partnerAssets,
                          periodDays: _periods[_periodIdx].days,
                          pnlToTRY: (val, cur) =>
                              pState?.toTRY(val, cur) ?? val,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Text(
                          'Sıralama, ortakların net getirisi (%) — deposit '
                          've çekme etkisi hariç. Kimsenin varlık listesi '
                          'gösterilmez.',
                          style: GoogleFonts.dmSans(
                            fontSize: 10,
                            color: Sandik.text36,
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
            const Icon(Icons.emoji_events_outlined,
                size: 48, color: Sandik.amber),
            const SizedBox(height: 16),
            Text(
              'Yarış\'a katılmadın',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ortaklarınla getiri sıralamasında yer almak için '
              'katılmayı aç. Sadece kaydolan ortaklar birbirinin '
              'yüzdesini görebilir. Varlıkların ve toplam TRY '
              'değerin asla paylaşılmaz.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: Sandik.text58,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onEnable,
              style: FilledButton.styleFrom(
                backgroundColor: Sandik.amber,
                foregroundColor: Colors.black,
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

class _EmptyPartners extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline_rounded,
                size: 48, color: Sandik.text36),
            const SizedBox(height: 16),
            Text(
              'Yarışacak ortağın yok',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sıralama görmek için önce en az bir ortak ekle. '
              'Ortaklar da Yarış\'a katılmış olmalı.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: Sandik.text58,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: List.generate(periods.length, (i) {
          final active = i == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChange(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active
                      ? Sandik.amber.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active
                        ? Sandik.amber.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  periods[i],
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: active ? Sandik.amber : Sandik.text58,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          );
        }),
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

  @override
  void initState() {
    super.initState();
    _future = _compute();
  }

  @override
  void didUpdateWidget(covariant _LeaderboardList old) {
    super.didUpdateWidget(old);
    if (old.periodDays != widget.periodDays ||
        old.partners.length != widget.partners.length) {
      _future = _compute();
    }
  }

  Future<List<_LeaderboardRow>> _compute() async {
    final rows = <_LeaderboardRow>[];
    // Self
    if (widget.me != null) {
      final myCurrentTRY = LeaderboardService.instance
          .totalValueTRY(widget.myAssets, widget.pnlToTRY);
      final roi = await LeaderboardService.instance.computeROI(
        assets: widget.myAssets,
        periodDays: widget.periodDays,
        currentValueTRY: myCurrentTRY,
      );
      rows.add(_LeaderboardRow(
        userId: widget.me!.id,
        displayName: '${widget.me!.displayName} (sen)',
        isMe: true,
        roi: roi,
      ));
    }
    // Partners
    for (final p in widget.partners) {
      final assets = widget.partnerAssets[p.id] ?? const <Asset>[];
      if (assets.isEmpty) {
        rows.add(_LeaderboardRow(
          userId: p.id,
          displayName: p.displayName,
          isMe: false,
          roi: null,
        ));
        continue;
      }
      final currentTRY = LeaderboardService.instance
          .totalValueTRY(assets, widget.pnlToTRY);
      final roi = await LeaderboardService.instance.computeROI(
        assets: assets,
        periodDays: widget.periodDays,
        currentValueTRY: currentTRY,
      );
      rows.add(_LeaderboardRow(
        userId: p.id,
        displayName: p.displayName,
        isMe: false,
        roi: roi,
      ));
    }
    // Sort: null'lar sona, gerisi desc
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
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Sandik.amber));
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return Center(
            child: Text(
              'Veri hazır değil.',
              style: GoogleFonts.dmSans(color: Sandik.text58),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _LeaderRow(row: rows[i], rank: i + 1),
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

class _LeaderRow extends StatelessWidget {
  final _LeaderboardRow row;
  final int rank;
  const _LeaderRow({required this.row, required this.rank});

  @override
  Widget build(BuildContext context) {
    final roi = row.roi;
    final positive = roi != null && roi >= 0;
    final roiColor = roi == null
        ? Sandik.text36
        : (positive ? Sandik.gain : Sandik.loss);
    final roiText = roi == null
        ? '—'
        : '${positive ? '+' : ''}${roi.toStringAsFixed(2)}%';

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: row.isMe
            ? Sandik.amber.withValues(alpha: 0.08)
            : Sandik.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: row.isMe
              ? Sandik.amber.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _rankColor(rank).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _rankColor(rank),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              row.displayName,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            roiText,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: roiColor,
            ),
          ),
        ],
      ),
    );
  }

  Color _rankColor(int r) {
    if (r == 1) return Sandik.gold;
    if (r == 2) return Sandik.text58;
    if (r == 3) return Sandik.amber.withValues(alpha: 0.7);
    return Sandik.text58;
  }
}
