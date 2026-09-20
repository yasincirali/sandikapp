// Ana ekrandaki "Bugün" kartı.
//
// Hesap `services/bugun_service.dart`'ta (saf); burada yalnızca gün içi
// serinin çekimi (kilit ekranı/widget ile ORTAK önbellek — üç yüzey aynı
// rakamı göstermeli), tercihler ve çizim var.
//
// Kendi kapılarını kendi kurar: kendi görünümü + açık pozisyon varken
// çizilir; seri gelmeden de kalan satırları gösterir (boş kart yok).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/position.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../screens/portfolio_performance_screen.dart';
import '../services/analytics_service.dart';
import '../services/bugun_service.dart';
import '../services/crash_reporter.dart';
import '../services/daily_summary.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'hedef_sheet.dart';

class BugunKarti extends ConsumerStatefulWidget {
  const BugunKarti({
    super.key,
    required this.state,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
  });

  final PortfolioState state;
  final EdgeInsets padding;

  @override
  ConsumerState<BugunKarti> createState() => _BugunKartiState();
}

class _BugunKartiState extends ConsumerState<BugunKarti> {
  Map<int, double>? _seri;
  bool _istendi = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (_istendi || !mounted) return;
    _istendi = true;
    if (widget.state.assets.isEmpty) return;
    try {
      final s = await IntradaySeriesCache.instance.get(widget.state);
      if (!mounted) return;
      setState(() => _seri = s);
    } catch (e, st) {
      // Seri gelmezse kart yine çizilir (hareket satırı düşer); ağ hatası
      // kullanıcıya gösterilmez, sessiz kalmasın diye raporlanır.
      CrashReporter.report(e, st, reason: 'BugunKarti.intraday');
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final seri = _seri;
    final ozet = seri == null
        ? null
        : DailySummary.from(state: widget.state, series: seri, now: now);
    final pozisyonlar = aggregatePositions(aktifLotlar(widget.state.assets));
    final veri = BugunService.hesapla(
      karZararlar: [for (final p in pozisyonlar) p.gainLoss],
      toplamDeger: widget.state.totalValue,
      ozet: ozet,
      hedefTRY: ref.watch(portfolioGoalProvider),
      now: now,
    );
    if (veri.bos) return const SizedBox.shrink();
    _gosterimiOlc(veri, now);

    final gizli = ref.watch(balanceHiddenProvider);
    final l10n = context.l10n;
    final dil = Localizations.localeOf(context).languageCode == 'en'
        ? 'en_US'
        : 'tr_TR';

    final satirlar = <Widget>[
      if (veri.birincil != null) _satirWidget(veri.birincil!, gizli),
      for (final s in veri.ikincil) _satirWidget(s, gizli),
      if (veri.aylik != null) _satirWidget(veri.aylik!, gizli),
    ];

    return Padding(
      padding: widget.padding,
      child: SandikCard(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.md, SandikSpace.smd, SandikSpace.md, SandikSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.today_rounded, size: 18, color: context.c.amberText),
                const SizedBox(width: SandikSpace.sm),
                Text(
                  l10n.todayTitle,
                  style: context.t.titleMedium?.copyWith(
                    color: context.c.text90,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                // Esnek: 320pt'te "20 Eylül Pazar" başlıkla çarpışıyordu
                // (taşma testi, 80px).
                Expanded(
                  child: Text(
                    DateFormat('d MMMM EEEE', dil).format(now),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodySmall?.copyWith(color: context.c.text58),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SandikSpace.xs),
            for (var i = 0; i < satirlar.length; i++) ...[
              if (i > 0)
                Divider(height: 1, color: context.c.text90.withValues(alpha: 0.06)),
              satirlar[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _satirWidget(BugunSatiri s, bool gizli) {
    final l10n = context.l10n;
    switch (s) {
      case GunlukDegisimSatiri():
        final renk = s.flat
            ? context.c.text58
            : context.signColor(s.changeTRY);
        final tutar = gizli ? '••••' : fmtTRY(s.changeTRY.abs());
        final metin = s.flat
            ? l10n.todayFlat
            : (s.changeTRY > 0
                ? l10n.todayUp(tutar, fmtPct(s.changePct.abs()))
                : l10n.todayDown(tutar, fmtPct(s.changePct.abs())));
        return _Satir(
          ikon: s.flat
              ? Icons.remove_rounded
              : (s.changeTRY > 0
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded),
          renk: renk,
          metin: metin,
          vurgu: true,
        );
      case PiyasaKapaliSatiri():
        final acilis = s.sonrakiAcilis;
        final bugun = DateTime.now();
        final ayniGun = acilis.year == bugun.year &&
            acilis.month == bugun.month &&
            acilis.day == bugun.day;
        final ne = ayniGun
            ? l10n.todayAt(DateFormat.Hm().format(acilis))
            : '${DateFormat.EEEE(_dil).format(acilis)} ${DateFormat.Hm().format(acilis)}';
        return _Satir(
          ikon: Icons.schedule_rounded,
          renk: context.c.text58,
          metin: l10n.todayMarketClosed(ne),
        );
      case YesilOranSatiri():
        return _Satir(
          ikon: Icons.donut_small_rounded,
          renk: s.yesil * 2 >= s.toplam ? context.c.gain : context.c.text58,
          metin: l10n.todayGreenShare(s.yesil, s.toplam),
        );
      case HedefSatiri():
        if (s.belirlenmedi) {
          return _Satir(
            ikon: Icons.flag_outlined,
            renk: context.c.amberText,
            metin: l10n.todayGoalSet,
            altMetin: l10n.todayGoalSetHint,
            onTap: _olcerek(s, () => showHedefSheet(context, ref)),
          );
        }
        final yuzde = (s.oran * 100).floor();
        return _Satir(
          ikon: Icons.flag_rounded,
          renk: s.ulasildi ? context.c.gain : context.c.amberText,
          metin: s.ulasildi
              ? l10n.todayGoalReached(gizli ? '••••' : fmtTRYCompact(s.hedefTRY.toDouble()))
              : l10n.todayGoalProgress(
                  yuzde, gizli ? '••••' : fmtTRYCompact(s.kalan)),
          cubuk: s.oran,
          onTap: _olcerek(s, () => showHedefSheet(context, ref)),
        );
      case YaklasanOlaySatiri():
        final ne = switch (s.gunKaldi) {
          0 => l10n.todayWordToday,
          1 => l10n.todayWordTomorrow,
          _ => l10n.todayInDays(s.gunKaldi),
        };
        final metin = switch (s.tur) {
          BugunOlayTuru.tuikAciklamasi => l10n.todayEventCpi(ne),
          BugunOlayTuru.bistTatili => l10n.todayEventHoliday(ne),
          BugunOlayTuru.aySonu => l10n.todayEventMonthEnd(ne),
        };
        return _Satir(
          ikon: Icons.event_rounded,
          renk: context.c.text58,
          metin: metin,
        );
      case AylikOzetSatiri():
        return _Satir(
          ikon: Icons.summarize_rounded,
          renk: context.c.amberText,
          metin: l10n.todayMonthlySummary(DateFormat.MMMM(_dil).format(s.ay)),
          altMetin: l10n.todayMonthlySummaryHint,
          onTap: _olcerek(
            s,
            () => pushGuarded<void>(
              context,
              adaptiveRoute<void>(
                builder: (_) => const PortfolioPerformanceScreen(
                  showBackButton: true,
                  initialOzet: true,
                  // 1A — geçen ayın özeti; Özet sekmesi TÜFE farkını da taşır.
                  initialPeriodIdx: 2,
                ),
              ),
            ),
          ),
        );
    }
  }

  String get _dil =>
      Localizations.localeOf(context).languageCode == 'en' ? 'en_US' : 'tr_TR';

  /// Gösterim ölçümü — gün + satır bileşimi başına BİR olay.
  ///
  /// Kart her fiyat yenilemesinde yeniden kurulur; her build'i saymak
  /// "kaç kez görüldü"yü değil "kaç kez çizildi"yi ölçerdi. Anahtar
  /// uygulama ömrü boyunca statik: aynı gün ikinci açılışta tekrar
  /// sayılmaz, ertesi gün sayılır.
  static String? _sonOlculen;

  void _gosterimiOlc(BugunKartiVerisi veri, DateTime now) {
    final turler = [
      if (veri.birincil != null) _tur(veri.birincil!),
      for (final s in veri.ikincil) _tur(s),
      if (veri.aylik != null) _tur(veri.aylik!),
    ];
    final anahtar = '${dayKey(now)}|${turler.join(',')}';
    if (_sonOlculen == anahtar) return;
    _sonOlculen = anahtar;
    for (final t in turler) {
      unawaited(AnalyticsService.instance.logTodayRowShown(kind: t));
    }
  }

  static String _tur(BugunSatiri s) => switch (s) {
        GunlukDegisimSatiri() => 'degisim',
        PiyasaKapaliSatiri() => 'kapali',
        YesilOranSatiri() => 'yesil',
        HedefSatiri() => s.belirlenmedi ? 'hedef_yok' : 'hedef',
        YaklasanOlaySatiri() => switch (s.tur) {
            BugunOlayTuru.tuikAciklamasi => 'olay_tuik',
            BugunOlayTuru.bistTatili => 'olay_tatil',
            BugunOlayTuru.aySonu => 'olay_aysonu',
          },
        AylikOzetSatiri() => 'aylik',
      };

  /// Dokunuş ölçümü — satırın kendi eylemini sarar.
  VoidCallback _olcerek(BugunSatiri s, VoidCallback eylem) => () {
        unawaited(AnalyticsService.instance.logTodayRowTapped(kind: _tur(s)));
        eylem();
      };
}

class _Satir extends StatelessWidget {
  const _Satir({
    required this.ikon,
    required this.renk,
    required this.metin,
    this.altMetin,
    this.cubuk,
    this.onTap,
    this.vurgu = false,
  });

  final IconData ikon;
  final Color renk;
  final String metin;
  final String? altMetin;

  /// 0..1 ilerleme çubuğu (hedef).
  final double? cubuk;
  final VoidCallback? onTap;

  /// Birincil satır: bir kademe büyük ve kalın.
  final bool vurgu;

  @override
  Widget build(BuildContext context) {
    final govde = Padding(
      padding: const EdgeInsets.symmetric(vertical: SandikSpace.smd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(ikon, size: 20, color: renk),
          const SizedBox(width: SandikSpace.smd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metin,
                  style: (vurgu ? context.t.titleMedium : context.t.bodyMedium)
                      ?.copyWith(
                    color: vurgu ? renk : context.c.text90,
                    fontWeight: vurgu ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (altMetin != null) ...[
                  const SizedBox(height: SandikSpace.xxs),
                  Text(
                    altMetin!,
                    style: context.t.bodySmall?.copyWith(color: context.c.text58),
                  ),
                ],
                if (cubuk != null) ...[
                  const SizedBox(height: SandikSpace.xs2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                    child: SizedBox(
                      height: 6,
                      child: Stack(
                        children: [
                          Container(color: context.c.surface2),
                          FractionallySizedBox(
                            widthFactor: cubuk!.clamp(0.02, 1.0),
                            child: Container(color: renk),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: SandikSpace.xs),
            Icon(Icons.chevron_right_rounded, size: 20, color: context.c.text58),
          ],
        ],
      ),
    );
    if (onTap == null) return govde;
    return Semantics(
      button: true,
      label: metin,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        child: govde,
      ),
    );
  }
}
