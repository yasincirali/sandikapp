import 'package:flutter/material.dart';
import '../widgets/sandik_skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/crash_reporter.dart';
import '../services/leaderboard_service.dart';
import '../services/remote_config_service.dart';
import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/tr_format.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/yaris_sahnesi.dart';
import '../widgets/zirve_donem_secici.dart';
import '../utils/polling.dart';
import '../l10n/l10n.dart';

// NOT: `LeaderboardScreen` (ayrı Yarış ekranı) 2026-10-05'te silindi —
// yalnız bayrak `siralama_tek_sayfa` kapalıyken açılıyordu. Yarış artık
// yalnız Sıralama › Ortaklarım'da (`SiralamaScreen`); gövdesi aşağıda.

/// Yarış'ın üst çubuk eylemleri: ayrılma menüsü (katılımcıya) ve "Getiri
/// nasıl hesaplanıyor?" düğmesi.
///
/// Fonksiyon olarak ayrıldı (sadeleştirme madde 8, 2026-10-04): tek
/// "Sıralama" sayfası (`SiralamaScreen`) "Ortaklarım" sekmesindeyken bu
/// eylemleri çizer.
List<Widget> yarisEylemleri(BuildContext context, WidgetRef ref) {
  final optIn = ref.watch(leaderboardOptInProvider);
  final me = ref.watch(authProvider).valueOrNull;
  return [
    // "Yarış'a katıl" anahtarı Ayarlar'dan buraya taşındı (2026-09-14):
    // katılım bu ekranın CTA'sı, ayrılma da bu ekranın menüsü. Bir
    // özelliğin açma/kapama yeri özelliğin kendisidir.
    if (optIn)
      PopupMenuButton<String>(
        icon: Icon(Icons.more_vert_rounded, color: context.c.text58),
        tooltip: context.l10n.raceOptions,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SandikRadius.md)),
        onSelected: (v) async {
          if (v != 'ayril') return;
          final ok = await showSandikConfirm(
            context: context,
            title: context.l10n.leaveRace,
            message: context.l10n.leaveRaceBody,
            confirmLabel: context.l10n.leaveWord,
            destructive: true,
          );
          if (ok) {
            await ref.read(leaderboardOptInProvider.notifier).set(false);
            LeaderboardService.instance.optInSunucuyaYaz(me?.id, false);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'ayril', child: Text(context.l10n.leaveRace)),
        ],
      ),
    // Yarıştaki getiri (dönemsel) ile Performans ekranındaki yüzde
    // (ilk alımdan bugüne toplam) farklı sorulardır. Kullanıcı ikisini
    // yan yana görünce "hangisi doğru?" diye soruyor — açıklama burada.
    IconButton(
      icon: Icon(Icons.info_outline_rounded, color: context.c.text58, size: 22),
      tooltip: context.l10n.howReturnCalculated,
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
  ];
}

/// Yarış ekranının gövdesi — katılım daveti ya da sıralama.
///
/// `LeaderboardScreen`'den ayrıldı (sadeleştirme madde 8, 2026-10-04; o
/// kabuk 2026-10-05'te silindi): tek "Sıralama" sayfasının "Ortaklarım"
/// sekmesi bu gövdeyi çizer. Dönem
/// dışarıdan yönetilir ki sayfa iki sekmede tek dönem tutsun; metrik ve
/// hesap burada değişmez (seçimlerinin getirisi, TWR — `secim_getirisi`).
///
/// Katılım akışı (opt-in → sunucuya yaz, 0081) gövdede kalır: hangi kapıdan
/// gelinirse gelinsin rızasız sıralama çizilmez.
class YarisGovdesi extends ConsumerWidget {
  const YarisGovdesi({
    super.key,
    required this.donemIdx,
    required this.onDonem,
  });

  /// [_YarisDonemleri] içindeki seçili dönem (0=7g, 1=30g, 2=1y).
  final int donemIdx;
  final ValueChanged<int> onDonem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optIn = ref.watch(leaderboardOptInProvider);
    final kuresel = RemoteConfigService.instance.globalLeaderboardEnabled;
    final me = ref.watch(authProvider).valueOrNull;
    final activePartners = ref.watch(activePartnersProvider);
    final myAssets = ref.watch(portfolioProvider).valueOrNull?.assets ?? [];
    final partnerAssets = ref.watch(allPartnerAssetsProvider).valueOrNull ?? {};
    final pState = ref.watch(portfolioProvider).valueOrNull;
    final periodDays = _YarisDonemleri.gunler[donemIdx];

    if (!optIn) {
      return _OptInPrompt(
        onEnable: () {
          ref.read(leaderboardOptInProvider.notifier).set(true);
          // Sunucu da bilsin: günlük snapshot bu bayrağa bakar (0081).
          LeaderboardService.instance.optInSunucuyaYaz(me?.id, true);
        },
      );
    }
    return Column(
      children: [
        // Dönem seçici "Herkes" sekmesiyle AYNI bileşen (`ZirveDonemSecici`,
        // 1H · 1A · 1Y, kayan hap) — sekme değişince seçici yerinde kalır,
        // etiket ve kabuk değişmez. Eski "7G / 30G" amber seçici
        // (`_PeriodBar`) düello arenası bayrağıyla birlikte 2026-10-05'te
        // silindi.
        Padding(
          padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
              SandikSpace.sm, SandikSpace.screenH(context), SandikSpace.sm),
          child: ZirveDonemSecici(
            secili: ZirveDonem.values[donemIdx],
            onSec: (d) => onDonem(ZirveDonem.values.indexOf(d)),
          ),
        ),
        Expanded(
          child: activePartners.isEmpty
              // Küresel sıralama parametrik kapalıyken solo panel
              // (küresel dilim + en çok kazandıranlar) anlamsız:
              // ortak ekleme daveti gösterilir (2026-09-21).
              ? (kuresel
                  ? _SoloPanel(
                      me: me,
                      myAssets: myAssets,
                      periodDays: periodDays,
                      pnlToTRY: (val, cur) => pState?.toTRY(val, cur) ?? val,
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(SandikSpace.lg),
                        child: Text(
                          context.l10n.racePitch,
                          textAlign: TextAlign.center,
                          style: context.t.bodyMedium
                              ?.copyWith(color: context.c.text58),
                        ),
                      ),
                    ))
              : _LeaderboardList(
                  me: me,
                  myAssets: myAssets,
                  partners: activePartners,
                  partnerAssets: partnerAssets,
                  periodDays: periodDays,
                  pnlToTRY: (val, cur) => pState?.toTRY(val, cur) ?? val,
                ),
        ),
        // Kendi satırının ek bilgisi (R1): paranın getirisi —
        // Performans ile aynı sayı. Sıralama seçimleri ölçer.
        if (me != null && pState != null)
          _ParaninGetirisiSatiri(
            portfoy: pState,
            periodDays: periodDays,
          ),
        if (kuresel) ...[
          // Genel sıralama (yüzdelik dilim) GEÇİCİ olarak kapalı
          // (kullanıcı kararı 2026-09-29): havuz k_min'i geçene kadar
          // "sıran açılacak" kartı boş vaat. Bayrak yeni değil —
          // aynı kavramın ana ekran şeridiyle ortak anahtarı
          // `percentile_strip_enabled`; ikisi birlikte açılır,
          // yayın gerekmez. Zirve portföyler 2026-09-29'da
          // Performans sekmesine taşındı (`ZirveKarti` +
          // `ZirvePortfoylerScreen`): zirve bir kıyas verisi,
          // yarış değil; kıyas ekranı Performans.
          if (RemoteConfigService.instance.percentileStripEnabled)
            _GlobalPercentileTeaser(periodDays: periodDays),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text(
            activePartners.isEmpty
                ? context.l10n.raceFooterGlobal
                : context.l10n.raceFooterPartners,
            style: context.t.labelMedium?.copyWith(
              letterSpacing: 0,
              color: context.c.text36,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// Yarış dönemleri. Gün sayıları `ZirveDonem` ile BİREBİR (7 · 30 · 365):
/// tek Sıralama sayfası iki sekmede aynı dönemi indeksle taşır
/// (`siralama_test` eşitliği kilitler).
abstract final class _YarisDonemleri {
  static const gunler = [7, 30, 365];
}

/// Test kilidi için dışa açık gün listesi (`ZirveDonem` eşitliği).
@visibleForTesting
List<int> get yarisDonemGunleri =>
    _YarisDonemleri.gunler;

/// Kendi satırının ek bilgisi: PARANIN GETİRİSİ (para ağırlıklı, XIRR) —
/// Performans › Özet'in aynı dönemdeki sayısı (R1, 2026-10-01).
///
/// Sıralama SEÇİMLERİ ölçer (TWR; para ekleme zamanı etkilemez). Kullanıcı
/// "benim param ne yaptı?" diye de sorar; o sorunun cevabı Performans'taki
/// rakamdır ve burada AYNI rakam görünür — yeni bir hesap değil
/// (`LeaderboardService.paraninGetirisiPct`). İki sayı farklıysa nedeni
/// "Getiri nasıl hesaplanıyor?" sayfasında yazar. Sayı yoksa (yeni
/// portföy, Özet bayrağı kapalı) satır çizilmez — uydurma yok.
///
/// Dönem değişince yeniden hesaplanır; fiyat tiklerinde değil (Özet'in
/// kendisi de dönem başına bir kez hesaplar).
class _ParaninGetirisiSatiri extends StatefulWidget {
  const _ParaninGetirisiSatiri({required this.portfoy, required this.periodDays});

  final PortfolioState portfoy;
  final int periodDays;

  @override
  State<_ParaninGetirisiSatiri> createState() => _ParaninGetirisiSatiriState();
}

class _ParaninGetirisiSatiriState extends State<_ParaninGetirisiSatiri> {
  Future<double?>? _sonuc;
  int? _gun;

  @override
  Widget build(BuildContext context) {
    if (_gun != widget.periodDays) {
      _gun = widget.periodDays;
      _sonuc = LeaderboardService.instance
          .paraninGetirisiPct(widget.portfoy, widget.periodDays);
    }
    return FutureBuilder<double?>(
      future: _sonuc,
      builder: (context, snap) {
        final v = snap.data;
        if (v == null) return const SizedBox.shrink();
        final c = context.c;
        return Padding(
          padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
              SandikSpace.xs, SandikSpace.screenH(context), 0),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: SandikSpace.md, color: c.text58),
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: context.l10n.raceMoneyReturn(fmtPctIsaretli(v)),
                      style: context.t.bodySmall?.copyWith(
                        color: c.text90,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: ' · ${context.l10n.raceMoneyReturnHint}',
                      style: context.t.bodySmall?.copyWith(color: c.text58),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Getiri nasıl hesaplanıyor?" açıklaması.
///
/// Yarış metriği 2026-10-01'den (0095) beri SEÇİMLERİNİN GETİRİSİ (zaman
/// ağırlıklı, TWR; `secim_getirisi.dart`): dönem günlere bölünür, her gün
/// tutulan varlıklar piyasa fiyatıyla değerlenir, günler çarpılır. Öncesinde
/// simülasyondu (bugünkü sepet dönem başından beri tutulmuş sayılırdı).
///
/// Performans ekranındaki yüzdeden FARKLIDIR — o, paranın getirisidir
/// (zamanlama dahil); bu sayfa farkı açıklar.
class _RoiInfoSheet extends StatelessWidget {
  const _RoiInfoSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 14, SandikSpace.screenH(context), 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: const SandikTutamac(),
            ),
            const SizedBox(height: 14),
            // Başlık + KAPAT.
            //
            // Sheet'in tek kapanma yolu aşağı sürüklemekti: yukarıdaki tutamak
            // dekoratif bir `Container` (dokunma dinlemez) ve
            // `isScrollControlled: true` + uzun içerik yüzünden ekranın
            // neredeyse tamamı kaplandığı için "dışarı dokun" alanı da bir
            // şeride iniyordu. Açık bir çıkış düğmesi şart.
            //
            // Desen `paywall_screen.dart` ile aynı: `Icons.close_rounded`,
            // 44pt hedef.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    context.l10n.howReturnCalculated,
                    style: context.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.c.text90,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SandikTappable(
                  semanticLabel: 'Kapat',
                  onTap: () => Navigator.of(context).pop(),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.close_rounded,
                        size: 22, color: context.c.text58),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _InfoBlock(
              icon: Icons.emoji_events_outlined,
              title: context.l10n.selectedPeriodReturn,
              body: context.l10n.selectedPeriodReturnBody,
            ),
            const SizedBox(height: 12),
            _InfoBlock(
              icon: Icons.savings_outlined,
              title: context.l10n.depositsDontChangeRank,
              body: context.l10n.depositsDontChangeRankBody,
            ),
            const SizedBox(height: 12),
            _InfoBlock(
              icon: Icons.groups_outlined,
              title: context.l10n.everyoneMeasuredSame,
              body: context.l10n.everyoneMeasuredSameBody,
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
                      context.l10n.rankVsPortfolioNote,
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
              context.l10n.rankSwapNote,
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
              context.l10n.notInRace,
              style: context.t.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.c.text90,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.notInRaceBody,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text(context.l10n.joinRace),
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
  // ForegroundPoller: arka planda durur, öne gelince hemen bir tur atar,
  // yavaş ağda turlar üst üste binmez. Çıplak `Timer.periodic` bunların
  // hiçbirini yapmıyordu (TECHNICAL_DEBT "5 bağımsız canlı tick").
  late final ForegroundPoller _liveTick = ForegroundPoller(
    interval: const Duration(seconds: 15),
    onTick: () async {
      if (mounted) await _refresh();
    },
  );

  @override
  void initState() {
    super.initState();
    _myRoi = widget.me == null
        ? null
        : LeaderboardService.instance.staleROI(
            userId: widget.me!.id,
            periodDays: widget.periodDays,
            kapsam: SiralamaKapsami.anonim,
          );
    _refresh();
    _liveTick.start();
  }

  @override
  void dispose() {
    _liveTick.dispose();
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
              kapsam: SiralamaKapsami.anonim,
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
    // Tek başına panel GENEL sıralamanın yanında durur (yüzdelik dilim
    // sunucudan, anonim): sayı da anonim kuralla ölçülür ki ikisi aynı
    // şeyi söylesin. Ortaklı liste `ortaklar` kapsamıyla ölçer.
    final roi = await LeaderboardService.instance.computeROI(
      assets: widget.myAssets,
      periodDays: widget.periodDays,
      kapsam: SiralamaKapsami.anonim,
      currentValueTRY: myCurrentTRY,
      toTRY: widget.pnlToTRY,
      cacheKey: me.id,
    );
    // ROI anlık görüntüsü artık YALNIZ sunucuda yazılır (0095): genel
    // yüzdelik ve Zirve, cron'un TWR'sini okur.
    if (!mounted) return;
    setState(() {
      _myRoi = roi;
      _computing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 8, SandikSpace.screenH(context), 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SoloRoiCard(roi: _myRoi, computing: _computing),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: context.c.surface1,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              border: Border.all(color: context.c.hairline),
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
                        context.l10n.addPartnerToRace,
                        style: context.t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.c.text90,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.l10n.raceNoListShared,
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
        ? (computing ? context.l10n.calculatingEllipsis : '—')
        : fmtPctIsaretli(r);

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
                  context.l10n.yourReturnUpper,
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
          if (computing) const CustomLoadingIndicator(size: 18),
        ],
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

  /// Her tamamlanan hesapta artar; sahne nabzı ve "lider değişti" olayı
  /// bunu izler (`YarisSahnesi.yenileme`).
  int _yenileme = 0;
  DateTime? _sonGuncelleme;

  /// Arenanın lider şeridi — satırlarla AYNI turda hesaplanır ve atanır ki
  /// şeridin "bugün"ü arenadaki lideri anlatsın. Yalnız tam bir ortak
  /// varken; aksi hâlde hiç hesaplanmaz (maliyet yok).
  LiderSeridi? _serit;
  // "Anlık" hissi için düzenli tick — her tetikte kendi ROI'sini
  // yeniden hesaplayıp upload eder, sonra partner ROI'lerini
  // Supabase'ten tazeler.
  late final ForegroundPoller _liveTick = ForegroundPoller(
    interval: const Duration(seconds: 15),
    onTick: () async {
      if (!mounted) return;
      final f = _compute();
      setState(() {
        _future = f;
      });
      await f;
    },
  );

  @override
  void initState() {
    super.initState();
    _staleRows = _readCachedRows();
    _future = _compute();
    _liveTick.start();
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
    _liveTick.dispose();
    super.dispose();
  }

  /// LeaderboardService cache'inden — TTL geçmiş bile olsa — synchronous
  /// rows üret. Hepsi cache'te varsa gerçek rows kadar iyi; birkaçı yoksa
  /// onlar için `roi: null` gelir ve Future dolunca yerlerine oturur.
  List<_LeaderboardRow>? _readCachedRows() {
    if (widget.me == null) return null;
    final rows = <_LeaderboardRow>[];
    // "(sen)" artık addan değil etiketten gelir (`YarisSahnesi`, "SEN").
    rows.add(_LeaderboardRow(
      userId: widget.me!.id,
      displayName: widget.me!.displayName,
      isMe: true,
      donemGun: widget.periodDays,
      roi: LeaderboardService.instance.staleROI(
        userId: widget.me!.id,
        periodDays: widget.periodDays,
        kapsam: SiralamaKapsami.ortaklar,
      ),
    ));
    for (var i = 0; i < widget.partners.length; i++) {
      final p = widget.partners[i];
      rows.add(_LeaderboardRow(
        userId: p.id,
        displayName: p.displayName,
        isMe: false,
        renkSirasi: i + 1,
        donemGun: widget.periodDays,
        roi: LeaderboardService.instance.staleROI(
          userId: p.id,
          periodDays: widget.periodDays,
          kapsam: SiralamaKapsami.ortaklar,
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
    // Herkesin kâr/zararı BU CİHAZDA hesaplanır — kimsenin uygulamayı
    // açması beklenmez.
    //
    // Eskiden ortakların değeri Supabase snapshot'ından okunuyordu ve o
    // snapshot'ı yalnızca ortağın KENDİ cihazı yazabiliyordu. Sonuç:
    //   · ortak uygulamayı hiç açmadıysa → yarışta değeri YOK,
    //   · eski sürümde açtıysa → eski formülle yazılmış bayat değer,
    //   · bugün açmadıysa → dünkü fiyatlarla hesaplanmış değer.
    //
    // Oysa ortağın lot'ları `allPartnerAssetsProvider` ile zaten burada ve
    // `refreshPrices` onların `currentPrice`'ını canlı kotasyonla
    // güncelliyor. Yerel hesap üçünü birden çözer: herkes aynı anda, aynı
    // fiyatlarla, aynı formülle ölçülür.
    //
    // Snapshot upload'ı SÜRÜYOR — global yüzdelik dilim (`get_percentile_
    // bucket`) ve top-gainers özellikleri onu okuyor.
    final me = widget.me;
    final donem = widget.periodDays;
    double? myRoi;
    if (me != null) {
      final myCurrentTRY = LeaderboardService.instance
          .totalValueTRY(widget.myAssets, widget.pnlToTRY);
      myRoi = await LeaderboardService.instance.computeROI(
        assets: widget.myAssets,
        periodDays: widget.periodDays,
        kapsam: SiralamaKapsami.ortaklar,
        currentValueTRY: myCurrentTRY,
        toTRY: widget.pnlToTRY,
        cacheKey: me.id,
      );
      if (myRoi != null) {
        // ROI anlık görüntüsü artık YALNIZ sunucuda yazılır (0095).
        // Top gainers allocation feature'ı için anonim tür dağılımını da
        // gönder — miktar/TL yok, sadece {tür: %}. RPC k-anonymity + min
        // type_count filtreleri ile agregat gösterir.
        final alloc = LeaderboardService.instance
            .computeAllocation(widget.myAssets, widget.pnlToTRY);
        if (alloc.length >= 2) {
          CrashReporter.arkaPlan(
            LeaderboardService.instance.uploadAllocationSnapshot(
              userId: me.id,
              allocation: alloc,
              typeCount: alloc.length,
            ),
            reason: 'LeaderboardScreen.uploadAllocationSnapshot',
          );
        }
      }
    }

    final rows = <_LeaderboardRow>[];
    if (me != null) {
      rows.add(_LeaderboardRow(
        userId: me.id,
        displayName: me.displayName,
        isMe: true,
        donemGun: donem,
        roi: myRoi,
      ));
    }
    // Lider şeridi sıralamayla paralel (aynı fiyat serileri; HistoryService
    // sembol başına önbellekli). Ölçü değişmez: şerit aynı motorun gün gün
    // birikimidir (`SecimGetirisi.donemSerisi`).
    final seritIstegi = me != null && widget.partners.length == 1
        ? LeaderboardService.instance.liderSeridi(
            benLotlari: widget.myAssets,
            rakipLotlari: widget.partnerAssets[widget.partners.first.id] ??
                const [],
            periodDays: donem,
          )
        : Future<LiderSeridi?>.value(null);
    // Ortakların getirisi paralel hesaplanır — her biri kendi fiyat serisini
    // çekiyor; sırayla beklemek ortak sayısıyla doğru orantılı gecikme
    // yaratırdı. `HistoryService` sembol başına önbellekli, yani aynı hisseye
    // sahip iki ortak tek istek eder.
    final partnerRois = await Future.wait(
      widget.partners.map((p) => LeaderboardService.instance.donemGetirisiPct(
          widget.partnerAssets[p.id] ?? const [], widget.periodDays,
              kapsam: SiralamaKapsami.ortaklar)),
    );
    final serit = await seritIstegi;
    for (var i = 0; i < widget.partners.length; i++) {
      final p = widget.partners[i];
      rows.add(_LeaderboardRow(
        userId: p.id,
        displayName: p.displayName,
        isMe: false,
        renkSirasi: i + 1,
        donemGun: donem,
        roi: partnerRois[i],
      ));
    }

    rows.sort((a, b) {
      if (a.roi == null && b.roi == null) return 0;
      if (a.roi == null) return 1;
      if (b.roi == null) return -1;
      return b.roi!.compareTo(a.roi!);
    });
    _yenileme++;
    _sonGuncelleme = DateTime.now();
    _serit = serit;
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_LeaderboardRow>>(
      future: _future,
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        // Öncelik: fresh Future data > stale cache > spinner
        final rows = snap.data ?? _staleRows;
        if (rows == null) {
          // İçerik yüklenirken iskelet (UX denetimi 2026-09-29).
          return const SandikSkeletonList(rows: 4);
        }
        if (rows.isEmpty) {
          return Center(
            child: Text(
              context.l10n.dataNotReady,
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
          );
        }
        return Stack(
          children: [
            // Sahne (canlı liste + düello/kürsü) `widgets/yaris_sahnesi.dart`
            // — kullanıcı kararı 2026-09-29, gerekçe orada.
            ListView(
              padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
                  SandikSpace.smd, SandikSpace.screenH(context), SandikSpace.lgs),
              children: [
                YarisSahnesi(
                  katilimcilar: [
                    for (final r in rows)
                      YarisKatilimci(
                        id: r.userId,
                        ad: r.displayName,
                        ben: r.isMe,
                        roi: r.roi,
                        renkSirasi: r.renkSirasi,
                      ),
                  ],
                  yenileme: _yenileme,
                  sonGuncelleme: _sonGuncelleme,
                  donemGun: rows.first.donemGun,
                  liderSeridi: _serit,
                ),
              ],
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

  /// Ortak listesindeki yer (sen 0) — sahnede kişinin rengi.
  final int renkSirasi;

  /// Bu satırın hesaplandığı dönem. `widget.periodDays` DEĞİL: dönem
  /// değişince FutureBuilder yeni veri gelene kadar ESKİ dönemin satırlarını
  /// gösterir; sahne dönemi ekrandan okusaydı yeni veri gelişini "canlı
  /// sıra değişimi" sanıp ▲ çipi ve konfeti patlatırdı.
  final int donemGun;
  const _LeaderboardRow({
    required this.userId,
    required this.displayName,
    required this.isMe,
    required this.roi,
    required this.donemGun,
    this.renkSirasi = 0,
  });
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

class _GlobalPercentileTeaserState extends State<_GlobalPercentileTeaser> {
  late Future<_BestPercentile?> _future;
  late final ForegroundPoller _liveTick = ForegroundPoller(
    interval: const Duration(seconds: 30),
    onTick: () async {
      if (!mounted) return;
      final f = _computeBest();
      setState(() {
        _future = f;
      });
      await f;
    },
  );

  static const _periods = <({int days, String label})>[
    (days: 7, label: 'haftalık'),
    (days: 30, label: 'aylık'),
    (days: 365, label: 'yıllık'),
  ];

  @override
  void initState() {
    super.initState();
    _future = _computeBest();
    _liveTick.start();
  }

  @override
  void dispose() {
    _liveTick.dispose();
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
      padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 4, SandikSpace.screenH(context), 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        border: Border.all(color: context.c.hairline),
      ),
      child: child,
    );
  }

  Widget _content(_BestPercentile? data, ConnectionState state) {
    // Loading
    if (state == ConnectionState.waiting && data == null) {
      return _row(
        badge: _Badge(text: context.l10n.loadingUpper, color: context.c.text58),
        title: context.l10n.globalRanking,
        subtitle: context.l10n.checkingAnonPool,
        icon: Icons.public_rounded,
        iconColor: context.c.text58,
      );
    }

    // k-anonymity altında veya yeterli veri yok
    if (data == null) {
      return _row(
        badge: _Badge(text: context.l10n.comingSoonUpper, color: context.c.gain),
        title: context.l10n.globalRanking,
        subtitle:
            context.l10n.globalRankingSoon,
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
            ? context.l10n.nThousandPeople(fmtNum(total / 1000, digits: 1))
            : context.l10n.nPeopleUpper(total),
        color: context.c.text58,
      ),
      title: context.l10n.topPercentile(periodCap, pct),
      subtitle: tone,
      icon: Icons.public_rounded,
      iconColor: pct <= 25 ? context.c.gain : context.c.amberText,
      hero: true,
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _toneFor(int pct) {
    if (pct <= 5) return context.l10n.toneTop5;
    if (pct <= 10) return context.l10n.toneTop10;
    if (pct <= 25) return context.l10n.toneTop25;
    if (pct <= 50) return context.l10n.toneTop50;
    if (pct <= 75) return context.l10n.toneTop75;
    return context.l10n.toneRest;
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
