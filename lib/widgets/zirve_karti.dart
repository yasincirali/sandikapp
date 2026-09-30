import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/leaderboard_service.dart';
import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import 'sandik_skeleton.dart';
import 'zirve_dagilim_seridi.dart';

typedef ZirveYukleyici = Future<List<TopGainerAllocation>> Function(int gun);
typedef HavuzYukleyici = Future<int?> Function(int gun);

/// Performans › tür dökümünün altındaki küçük "Zirvedeki Portföyler" kartı.
///
/// Tek cümle + birincinin tür şeridi; dokununca cetvel ekranı
/// (`ZirvePortfoylerScreen`). Yarış ekranındaki eski kart 2026-09-29'da
/// buraya taşındı: zirve bir KIYAS verisidir, yarış değil; kıyas ekranı
/// Performans'tır. Ortak ya da yarışa katılım şartı yok — küresel bayrak
/// (`global_leaderboard_enabled`) yeter. Havuz AÇIK RIZAYA dayanır (0091,
/// 2026-10-01): rıza vermemiş kullanıcıya kart "havuz oluşuyor" DEMEZ —
/// sunucu ona listeyi zaten boş döner (karşılıklılık); kart katılım
/// davetini gösterir, dokununca ekrandaki rıza kartı açılır.
///
/// Dönem Performans'ın seçicisini izler (`ZirveDonem.yakin`); ekran o
/// dönemle açılır. Kart kendi başına yenilenmez (poller yok): Performans
/// dönemi değişince yeniden kurulur, ekran ise 45 sn'de bir tazeler.
class ZirveKarti extends StatefulWidget {
  const ZirveKarti({
    super.key,
    required this.donem,
    required this.onAc,
    this.yukleyici,
    this.havuzYukleyici,
    this.rizaYukleyici,
  });

  final ZirveDonem donem;
  final VoidCallback onAc;

  /// Test için sunucu yerine sabit satırlar; null → `LeaderboardService`.
  final ZirveYukleyici? yukleyici;
  final HavuzYukleyici? havuzYukleyici;

  /// Test için rıza durumu; null → `LeaderboardService.fetchZirveRizasi`.
  final Future<bool?> Function()? rizaYukleyici;

  @override
  State<ZirveKarti> createState() => _ZirveKartiState();
}

class _ZirveKartiState extends State<ZirveKarti> {
  late Future<List<TopGainerAllocation>> _satirlar;
  late Future<int?> _havuz;

  /// Geçerli zirve rızası; `null` (okunamadı) davet göstermez, eski boş
  /// durum kalır — rıza varsayılmaz ama yok da sayılmaz.
  late Future<bool?> _riza;

  static const double _kupaBoyu = 30;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void didUpdateWidget(covariant ZirveKarti old) {
    super.didUpdateWidget(old);
    if (old.donem != widget.donem) _yukle();
  }

  void _yukle() {
    final y = widget.yukleyici ??
        (gun) => LeaderboardService.instance
            .fetchTopGainersAllocation(periodDays: gun, topN: 3);
    _satirlar = y(widget.donem.gun);
    final h = widget.havuzYukleyici ??
        (gun) => LeaderboardService.instance
            .fetchZirveHavuzBoyutu(periodDays: gun);
    _havuz = h(widget.donem.gun);
    _riza = (widget.rizaYukleyici ??
        LeaderboardService.instance.fetchZirveRizasi)();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.topPortfolios,
      child: SandikCard(
        onTap: widget.onAc,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _baslik(context),
            const SizedBox(height: SandikSpace.smd),
            FutureBuilder<List<TopGainerAllocation>>(
              future: _satirlar,
              builder: (context, snap) {
                final satirlar = snap.data ?? const <TopGainerAllocation>[];
                if (snap.connectionState == ConnectionState.waiting &&
                    satirlar.isEmpty) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SandikSkeleton(height: 14),
                      SizedBox(height: SandikSpace.xs2),
                      SandikSkeleton(width: 180, height: 14),
                      SizedBox(height: SandikSpace.smd),
                      SandikSkeleton(height: 14),
                    ],
                  );
                }
                if (satirlar.isEmpty) {
                  return FutureBuilder<bool?>(
                    future: _riza,
                    builder: (context, r) =>
                        r.data == false ? _davet(context) : _bos(context),
                  );
                }
                return _dolu(context, satirlar.first);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _baslik(BuildContext context) {
    return Row(
      children: [
        Container(
          width: _kupaBoyu,
          height: _kupaBoyu,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: context.c.amberGradient,
            borderRadius: BorderRadius.circular(SandikRadius.sm),
          ),
          child: Icon(Icons.emoji_events_rounded,
              color: context.c.onAmber, size: 16),
        ),
        const SizedBox(width: SandikSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.topPortfolios,
                style: context.t.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.c.text90,
                ),
              ),
              Text(
                '${widget.donem.sifat} · anonim · tür ve fon payı',
                style: context.t.labelMedium?.copyWith(
                  letterSpacing: 0,
                  color: context.c.text58,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: context.c.text36),
      ],
    );
  }

  Widget _dolu(BuildContext context, TopGainerAllocation birinci) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          birinci.ben
              ? '${widget.donem.ad} zirvedeki portföy senin: '
                  '${ZirveKiyas.getiriParcasi(birinci.roiPct)}.'
              : '${widget.donem.ad} zirvedeki portföy '
                  '${ZirveKiyas.getiriParcasi(birinci.roiPct)}.',
          style: context.t.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: context.c.text90,
            height: 1.35,
          ),
        ),
        const SizedBox(height: SandikSpace.sm),
        ZirveDagilimSeridi(
          pay: birinci.allocation,
          enFazlaEtiket: 3,
          canlandir: false,
        ),
        const SizedBox(height: SandikSpace.sm),
        Text(
          'Kendi yerini ve üç portföyün dağılımını gör ›',
          style: context.t.labelMedium?.copyWith(
            letterSpacing: 0,
            fontWeight: FontWeight.w700,
            color: context.c.amberText,
          ),
        ),
      ],
    );
  }

  /// Rıza yok: katılım daveti. Ne karşılığında ne verildiği tek cümlede;
  /// ayrıntı ve karar ekrandaki rıza kartında.
  Widget _davet(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Katılanların anonim portföylerini gör: en çok kazandıranlar neye '
          'yatırmış, senden farkı ne. Katılım isteğe bağlı; kimlik, tutar '
          've TL paylaşılmaz.',
          style: context.t.bodyMedium?.copyWith(
            color: context.c.text90,
            height: 1.35,
          ),
        ),
        const SizedBox(height: SandikSpace.sm),
        Text(
          'Nasıl çalıştığını oku ve katıl ›',
          style: context.t.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.c.amberText,
          ),
        ),
      ],
    );
  }

  /// Boş durum: "yakında" değil, ilerleme. Havuz sayısı gelmezse sayı
  /// yazılmaz (uydurma sayı yok), cümle eşiği yine söyler.
  Widget _bos(BuildContext context) {
    return FutureBuilder<int?>(
      future: _havuz,
      builder: (context, snap) {
        final n = snap.data;
        final metin = n == null
            ? 'Havuz oluşuyor; ${ZirveKiyas.havuzEsigi} portföy olunca zirve '
                'belli olur.'
            : 'Havuz oluşuyor: $n portföy var, ${ZirveKiyas.havuzEsigi} '
                'olunca zirve belli olur.';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metin,
              style: context.t.bodyMedium?.copyWith(
                color: context.c.text90,
                height: 1.35,
              ),
            ),
            if (n != null) ...[
              const SizedBox(height: SandikSpace.sm),
              ZirveHavuzCubugu(havuz: n),
            ],
          ],
        );
      },
    );
  }
}

/// Havuz ilerleme çubuğu: N / 8. Kart ve ekranın boş durumu paylaşır.
class ZirveHavuzCubugu extends StatelessWidget {
  const ZirveHavuzCubugu({super.key, required this.havuz});

  final int havuz;

  @override
  Widget build(BuildContext context) {
    final oran = (havuz / ZirveKiyas.havuzEsigi).clamp(0.0, 1.0);
    return Semantics(
      label: 'Havuz $havuz / ${ZirveKiyas.havuzEsigi}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        child: Container(
          height: 6,
          color: context.c.overlay,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: oran,
            child: Container(color: context.c.amberFill),
          ),
        ),
      ),
    );
  }
}
