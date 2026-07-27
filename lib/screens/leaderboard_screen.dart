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
                      _GlobalPercentileTeaser(
                        periodDays: _periods[_periodIdx].days,
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
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(22),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: List.generate(periods.length, (i) {
            final active = i == selected;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChange(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  margin: EdgeInsets.symmetric(
                      horizontal: active ? 0 : 2),
                  decoration: BoxDecoration(
                    gradient: active
                        ? LinearGradient(
                            colors: [Sandik.gold, Sandik.amber],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: Sandik.amber
                                  .withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color:
                            active ? Colors.black : Sandik.text58,
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

  @override
  void initState() {
    super.initState();
    _staleRows = _readCachedRows();
    _future = _compute();
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
    // Tüm katılımcılar için ROI hesabını paralel başlat — sequential await
    // önceki tasarımda 5 partner × 500ms = 2.5sn bekletiyordu. Future.wait
    // ile total süre = en yavaş fetch'e düşer.
    final tasks = <Future<_LeaderboardRow>>[];

    if (widget.me != null) {
      final myAssets = widget.myAssets;
      final me = widget.me!;
      final myCurrentTRY = LeaderboardService.instance
          .totalValueTRY(myAssets, widget.pnlToTRY);
      tasks.add(
        LeaderboardService.instance
            .computeROI(
          assets: myAssets,
          periodDays: widget.periodDays,
          currentValueTRY: myCurrentTRY,
          toTRY: widget.pnlToTRY,
          cacheKey: me.id,
        )
            .then((roi) => _LeaderboardRow(
                  userId: me.id,
                  displayName: '${me.displayName} (sen)',
                  isMe: true,
                  roi: roi,
                )),
      );
    }

    for (final p in widget.partners) {
      final assets = widget.partnerAssets[p.id] ?? const <Asset>[];
      if (assets.isEmpty) {
        tasks.add(Future.value(_LeaderboardRow(
          userId: p.id,
          displayName: p.displayName,
          isMe: false,
          roi: null,
        )));
        continue;
      }
      final currentTRY = LeaderboardService.instance
          .totalValueTRY(assets, widget.pnlToTRY);
      tasks.add(
        LeaderboardService.instance
            .computeROI(
          assets: assets,
          periodDays: widget.periodDays,
          currentValueTRY: currentTRY,
          toTRY: widget.pnlToTRY,
          cacheKey: p.id,
        )
            .then((roi) => _LeaderboardRow(
                  userId: p.id,
                  displayName: p.displayName,
                  isMe: false,
                  roi: roi,
                )),
      );
    }

    final rows = await Future.wait(tasks);
    // Kendi ROI'mizi global percentile için snapshot olarak yükle —
    // asenkron ve unawaited, ana leaderboard render'ını yavaşlatmaz.
    if (widget.me != null) {
      final myRow = rows.firstWhere(
        (r) => r.isMe,
        orElse: () => const _LeaderboardRow(
            userId: '', displayName: '', isMe: false, roi: null),
      );
      if (myRow.roi != null && myRow.userId.isNotEmpty) {
        // Fire-and-forget — kullanıcıyı bekletmesin.
        LeaderboardService.instance.uploadRoiSnapshot(
          userId: myRow.userId,
          periodDays: widget.periodDays,
          roiPct: myRow.roi!,
        );
      }
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
        final isLoading =
            snap.connectionState == ConnectionState.waiting;
        // Öncelik: fresh Future data > stale cache > spinner
        final rows = snap.data ?? _staleRows;
        if (rows == null) {
          return const Center(
              child: CircularProgressIndicator(color: Sandik.amber));
        }
        if (rows.isEmpty) {
          return Center(
            child: Text(
              'Veri hazır değil.',
              style: GoogleFonts.dmSans(color: Sandik.text58),
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
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 2,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: Sandik.amber,
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
        ? Sandik.text36
        : (positive ? Sandik.gain : Sandik.loss);
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
            ? Sandik.amber.withValues(alpha: 0.10)
            : Sandik.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe
              ? Sandik.amber.withValues(alpha: 0.55)
              : isLeader
                  ? Sandik.gold.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.05),
          width: isLeader && !isMe ? 1.2 : 1.0,
        ),
        boxShadow: isLeader
            ? [
                BoxShadow(
                  color: Sandik.gold.withValues(alpha: 0.15),
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
              _rankBadge(),
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
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
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
                                  Sandik.gold.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'LİDER',
                              style: GoogleFonts.dmSans(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                color: Sandik.gold,
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
                        style: GoogleFonts.dmSans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Sandik.amber.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
          if (barRatio > 0) ...[
            const SizedBox(height: 10),
            _DiffBar(ratio: barRatio, color: roiColor),
          ],
        ],
      ),
    );
  }

  Widget _rankBadge() {
    // 1-3: gradient madalyalar; 4+: sade amber outlined
    if (rank <= 3) {
      final (Color light, Color dark) = switch (rank) {
        1 => (Sandik.gold, const Color(0xFFB8860B)),
        2 => (const Color(0xFFE0E0E0), const Color(0xFF9E9E9E)),
        _ => (const Color(0xFFCD7F32), const Color(0xFF8B4513)),
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
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Colors.black.withValues(alpha: 0.75),
          ),
        ),
      );
    }
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
        ),
      ),
      child: Text(
        '$rank',
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Sandik.text58,
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
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 4,
        color: Colors.white.withValues(alpha: 0.05),
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
              borderRadius: BorderRadius.circular(4),
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
  late Future<({int percentile, int total})?> _future;

  @override
  void initState() {
    super.initState();
    _future = LeaderboardService.instance.fetchPercentile(widget.periodDays);
  }

  @override
  void didUpdateWidget(covariant _GlobalPercentileTeaser old) {
    super.didUpdateWidget(old);
    if (old.periodDays != widget.periodDays) {
      _future = LeaderboardService.instance.fetchPercentile(widget.periodDays);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: FutureBuilder<({int percentile, int total})?>(
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
            const Color(0xFF1A3D2E).withValues(alpha: 0.7),
            Sandik.surface1.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }

  Widget _content(
      ({int percentile, int total})? data, ConnectionState state) {
    // Loading
    if (state == ConnectionState.waiting && data == null) {
      return _row(
        badge: const _Badge(text: 'YÜKLENİYOR', color: Sandik.text58),
        title: 'Genel Sıralama',
        subtitle: 'Anonim havuz kontrol ediliyor…',
        icon: Icons.public_rounded,
        iconColor: Sandik.text58,
      );
    }

    // k-anonymity altında veya yeterli veri yok
    if (data == null) {
      return _row(
        badge: const _Badge(text: 'YAKINDA', color: Sandik.gain),
        title: 'Genel Sıralama',
        subtitle:
            'Yeterli katılımcı olunca sıran açılacak — anonim, KVKK uyumlu',
        icon: Icons.public_rounded,
        iconColor: Sandik.gain,
      );
    }

    // Gerçek percentile
    final pct = data.percentile;
    final total = data.total;
    final tone = _toneFor(pct);
    return _row(
      badge: _Badge(
        text: total > 1000 ? '${(total / 1000).toStringAsFixed(1)}K KİŞİ'
            : '$total KİŞİ',
        color: Colors.white.withValues(alpha: 0.6),
      ),
      title: 'İlk %$pct\'desin',
      subtitle: tone,
      icon: Icons.public_rounded,
      iconColor: pct <= 25 ? Sandik.gain : Sandik.amber,
      hero: true,
    );
  }

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
            borderRadius: BorderRadius.circular(10),
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
                      style: GoogleFonts.dmSans(
                        fontSize: hero ? 14 : 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
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
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.65),
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
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.dmSans(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
