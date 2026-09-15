import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/analytics_service.dart';
import '../services/inflation_service.dart';
import '../services/recap_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/share_card.dart';
import '../l10n/l10n.dart';

/// "sandık Özeti" — yıllık geriye bakış.
///
/// **Neden hikâye formatı:** özet okunacak bir rapor değil, bir kimlik
/// anlatısı. Tek ekranda liste hâlinde verilirse kullanıcı tarar ve geçer;
/// sayfa sayfa verildiğinde her rakam kendi anını alır. Wrapped'in işleyen
/// biçimi bu.
///
/// **Neden tutar yok:** paylaşılabilirlik bu özelliğin tek amacı ve tutarlı
/// bir kart paylaşılmaz. Yüzde ve etiket yeter.
///
/// Sayfalar veriye göre kurulur — eksik veri için sayfa üretilmez. Boş bir
/// "veri yok" sayfası kutlamayı bozar.
class RecapScreen extends StatefulWidget {
  final RecapData data;
  final int year;

  const RecapScreen({super.key, required this.data, required this.year});

  static Future<void> show(BuildContext context, RecapData d, int year) {
    AnalyticsService.instance.logRecapViewed(period: d.period);
    return Navigator.of(context).push(
      adaptiveRoute(builder: (_) => RecapScreen(data: d, year: year)),
    );
  }

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_Sayfa> _sayfalar(BuildContext context) {
    final d = widget.data;
    final c = context.c;
    final out = <_Sayfa>[
      _Sayfa(
        ustBaslik: context.l10n.recapInYear(widget.year),
        baslik: context.l10n.recapTitle,
        altBaslik: context.l10n.recapSubtitle,
        ikon: Icons.auto_stories_rounded,
        renk: c.amberText,
      ),
      // Karakter sayfası HER ZAMAN var: paylaşılabilirliğin çekirdeği bu.
      _Sayfa(
        ustBaslik: 'Sen bir',
        baslik: d.character.label,
        altBaslik: d.character.tagline,
        ikon: Icons.fingerprint_rounded,
        renk: c.gold,
      ),
    ];

    if (d.changePct != null) {
      final artis = d.changePct! >= 0;
      out.add(_Sayfa(
        ustBaslik: context.l10n.recapYourPortfolio,
        baslik:
            '${artis ? '+' : '−'}%${fmtNum(d.changePct!.abs(), digits: 1)}',
        altBaslik: artis ? context.l10n.recapGrewThisYear : context.l10n.recapToughYear,
        ikon: artis ? Icons.trending_up_rounded : Icons.trending_down_rounded,
        renk: artis ? c.gain : c.loss,
      ));
    }

    if (d.inflationSpread != null) {
      final onde = d.inflationSpread! >= 0;
      out.add(_Sayfa(
        ustBaslik: context.l10n.recapVsInflation,
        baslik:
            context.l10n.recapPoints(fmtNum(d.inflationSpread!.abs(), digits: 1)),
        altBaslik: onde
            ? context.l10n.recapKeptPower
            : context.l10n.recapInflationWon,
        ikon: Icons.shield_moon_rounded,
        renk: onde ? c.gain : c.loss,
      ));
    }

    if (d.bestAsset != null) {
      out.add(_Sayfa(
        ustBaslik: context.l10n.recapBestAsset,
        baslik: d.bestAsset!.name,
        // "Yılın en iyisi" DEĞİL: elimizdeki ömürlük getiri, döneme ait
        // değil. Üç yıl önce alınmış bir varlığı "yılın yıldızı" diye
        // sunmak yanlış olurdu.
        altBaslik:
            context.l10n.recapReturnedPct(fmtNum(d.bestAsset!.changePct, digits: 1)),
        ikon: Icons.workspace_premium_rounded,
        renk: c.gain,
      ));
    }

    if (d.mostPatientDays != null && d.mostPatientDays! >= 90) {
      out.add(_Sayfa(
        ustBaslik: context.l10n.recapMostPatient,
        baslik: d.mostPatient!.name,
        altBaslik: context.l10n.recapInPortfolioDays(d.mostPatientDays ?? 0),
        ikon: Icons.hourglass_bottom_rounded,
        renk: c.amberText,
      ));
    }

    if (d.trackedDays >= 5) {
      out.add(_Sayfa(
        ustBaslik: 'Takipteydin',
        baslik: context.l10n.recapDays(d.trackedDays),
        altBaslik: d.typeCount > 1
            ? context.l10n.recapTypeCount(d.typeCount)
            : context.l10n.recapForAYear,
        ikon: Icons.visibility_rounded,
        renk: c.info,
      ));
    }

    return out;
  }

  /// Önizlemeli paylaşım — dönem özetiyle aynı kart (`showShareSheet`).
  Future<void> _paylas() {
    final d = widget.data;
    final metin = RecapService.shareText(d, year: widget.year);
    return showShareSheet(
      context,
      data: ShareCardData(
        baslik: context.l10n.myRecapYear(widget.year),
        degisimPct: d.changePct,
        karakter: d.character,
        enflasyonPuan: d.inflationSpread,
        takipGunu: d.trackedDays,
      ),
      metin: metin,
      subject: context.l10n.recapShareTitle(widget.year),
      analyticsPeriod: d.period,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sayfalar = _sayfalar(context);
    final sonSayfa = _index == sayfalar.length - 1;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // İlerleme çubukları — hikâye biçiminin en tanınan işareti;
            // kullanıcı kaç sayfa kaldığını bilmeden ilerlemez.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  for (var i = 0; i < sayfalar.length; i++)
                    Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= _index ? c.amberFill : c.text20,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, color: c.text58),
                tooltip: 'Kapat',
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: sayfalar.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => sayfalar[i],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.amberFill,
                    foregroundColor: c.onAmber,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: sonSayfa
                      ? _paylas
                      // Sayfa geçişi bir YÜZEY hareketidir → `surface` (240ms).
                      // Çıplak süre yerine token: `design_token_leak_test`
                      // bunu kovalıyor ve `surfaceOf` "hareketi azalt"
                      // ayarına da uyuyor (çıplak Duration uymuyordu).
                      : () => _controller.nextPage(
                            duration: SandikMotion.surfaceOf(context),
                            curve: SandikMotion.enter,
                          ),
                  child: Text(sonSayfa ? context.l10n.shareWord : 'Devam'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tek bir hikâye sayfası.
class _Sayfa extends StatelessWidget {
  final String ustBaslik;
  final String baslik;
  final String altBaslik;
  final IconData ikon;
  final Color renk;

  const _Sayfa({
    required this.ustBaslik,
    required this.baslik,
    required this.altBaslik,
    required this.ikon,
    required this.renk,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 40, color: renk),
          const SizedBox(height: 24),
          Text(
            ustBaslik,
            style: context.t.titleMedium?.copyWith(color: c.text58),
          ),
          const SizedBox(height: 6),
          Text(
            baslik,
            style: context.t.displaySmall?.copyWith(
              color: renk,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            altBaslik,
            style: context.t.bodyLarge?.copyWith(color: c.text58, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ── Giriş noktası ────────────────────────────────────────────────────────────

/// Profil ekranında özeti açan afiş.
///
/// Kendi kendini kapatır — üç kapı:
///   1. Remote Config bayrağı,
///   2. TAKVİM: yalnızca 26 Aralık–10 Ocak (bkz. [RecapService.isYearlyWindow]),
///   3. Verinin anlamlı olması ([RecapData.isMeaningful]).
///
/// Üçünden biri sağlanmazsa tek piksel yer kaplamaz. Özet, yılın 11 ayı
/// görünmemesi gereken bir özellik; afişin sürekli durması onu sıradanlaştırır.
class RecapBanner extends ConsumerStatefulWidget {
  const RecapBanner({super.key});

  @override
  ConsumerState<RecapBanner> createState() => _RecapBannerState();
}

class _RecapBannerState extends ConsumerState<RecapBanner> {
  RecapData? _veri;
  bool _istendi = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (_istendi || !mounted) return;
    _istendi = true;

    if (!RemoteConfigService.instance.recapEnabled) return;
    final simdi = DateTime.now();
    // Takvim kapısı EN BAŞTA: pencere dışındaysa hiçbir sorgu yapılmaz.
    if (!RecapService.isYearlyWindow(simdi)) return;

    final me = ref.read(authProvider).valueOrNull;
    final state = ref.read(portfolioProvider).valueOrNull;
    if (me == null || state == null) return;

    // Yılbaşından bu yana. Ocak'ta açılan özet bir önceki yıla ait olduğu
    // için pencere de o yıldan başlar.
    final yil = RecapService.yearFor(simdi);
    final baslangic = DateTime(yil, 1, 1).millisecondsSinceEpoch;

    List<({int ts, Map<String, double> values})> snapshots = const [];
    try {
      snapshots = await SupabaseService.instance
          .fetchSnapshots(baslangic, userId: me.id);
    } catch (_) {
      // Snapshot çekilemezse özet yine kurulur; yalnızca değişim sayfası
      // eksilir. Boş dönmek, özeti tamamen kaçırmaktan iyidir.
    }

    final enflasyon = await InflationService.instance.inflationForPeriod(365);

    final d = RecapService.compute(
      period: 'yearly',
      assets: state.assets,
      snapshots: snapshots,
      toTRY: state.toTRY,
      now: simdi,
      inflationPct: enflasyon,
    );
    if (!mounted || !d.isMeaningful) return;
    setState(() => _veri = d);
  }

  @override
  Widget build(BuildContext context) {
    final d = _veri;
    if (d == null) return const SizedBox.shrink();
    final c = context.c;
    final yil = RecapService.yearFor(DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => RecapScreen.show(context, d, yil),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.amberFill.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_stories_rounded, color: c.gold, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.recapReady(yil),
                          style:
                              context.t.titleLarge?.copyWith(color: c.text90)),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.recapCardSubtitle(d.character.label),
                        style:
                            context.t.bodyMedium?.copyWith(color: c.text58),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.text36),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
