import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/leaderboard_service.dart';
import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import '../utils/polling.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_skeleton.dart';
import '../widgets/zirve_cetveli.dart';
import '../widgets/zirve_dagilim_seridi.dart';
import '../widgets/zirve_karti.dart';

/// Zirvedeki Portföyler — tam ekran (kullanıcı seçimi 2026-09-29, "A ·
/// Cetvel önde").
///
/// Üstte dönem seçici (1H · 1A · 1Y), altındaki her şey o döneme göre
/// yeniden yazılır: cümle, iki büyük sayı, cetveldeki işaretler, seçili
/// portföyün dağılımı ve fark cümlesi. Tek ekran, kaydırma gerekmeden
/// okunur; ayrıntı isteyen seçili portföye dokunup alt sayfayı açar
/// (tür tür dağılım + senden farkı).
///
/// ## Veri
/// - Zirve: `get_top_gainers_allocation` (sıra, getiri, tür payı; anonim).
///   Sunucu snapshot'ı günde iki kez (0081/0082); ekran 45 sn'de bir
///   yeniden sorar ki dönem değişimi ve cron sonrası taze olsun.
/// - Havuz beyana dayanmaz (0083): portföyü 5 günden, hesabı 7 günden eski
///   herkes anonim olarak içinde. Ekran kimseyi "katılmaya" çağırmaz;
///   Yarış ekranı ve onun katılım anahtarı bundan bağımsız.
/// - Sen: getiri istemcide `LeaderboardService.computeROI` (Yarış
///   ekranıyla AYNI formül), dağılım `computeAllocation`. Sunucuya bir şey
///   yazılmaz — snapshot'ı artık sunucu alıyor.
///
/// ## Dil
/// Sayı yalnız başına konuşmaz; cümleler `ZirveKiyas`'ta. Dağılım farkı
/// renklendirilmez (iyi/kötü değil); renk yalnızca getiride.
class ZirvePortfoylerScreen extends ConsumerStatefulWidget {
  const ZirvePortfoylerScreen({super.key, this.baslangic = ZirveDonem.ay});

  /// Açılış dönemi — kart Performans'ın dönemini eşleyip geçirir.
  final ZirveDonem baslangic;

  @override
  ConsumerState<ZirvePortfoylerScreen> createState() =>
      _ZirvePortfoylerScreenState();
}

class _ZirvePortfoylerScreenState extends ConsumerState<ZirvePortfoylerScreen> {
  late ZirveDonem _donem = widget.baslangic;
  String _secili = '1';
  late Future<List<TopGainerAllocation>> _satirlar = _cek();
  late Future<int?> _havuz = _havuzCek();
  double? _senRoi;
  Map<String, double> _senPay = const {};
  late final ForegroundPoller _tik = ForegroundPoller(
    interval: const Duration(seconds: 45),
    onTick: () async {
      if (!mounted) return;
      final f = _cek();
      setState(() => _satirlar = f);
      await f;
    },
  );

  Future<List<TopGainerAllocation>> _cek() =>
      LeaderboardService.instance.fetchTopGainersAllocation(
        periodDays: _donem.gun,
        // Sunucu [n_min, n_max] = [3, 4] aralığına kırpar; 3 bir istek.
        topN: 3,
      );

  Future<int?> _havuzCek() =>
      LeaderboardService.instance.fetchZirveHavuzBoyutu(periodDays: _donem.gun);

  @override
  void initState() {
    super.initState();
    _tik.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _senYenile());
  }

  @override
  void dispose() {
    _tik.dispose();
    super.dispose();
  }

  void _donemSec(ZirveDonem d) {
    if (d == _donem) return;
    setState(() {
      _donem = d;
      _satirlar = _cek();
      _havuz = _havuzCek();
    });
    _senYenile();
  }

  /// Kullanıcının getirisi ve dağılımı. Önce önbellekteki (bayat) değer
  /// gösterilir, hesap arka planda biter; dönem bu arada değiştiyse eski
  /// sonuç yazılmaz.
  Future<void> _senYenile() async {
    final me = ref.read(authProvider).valueOrNull;
    final p = ref.read(portfolioProvider).valueOrNull;
    if (me == null || p == null || !mounted) return;
    final servis = LeaderboardService.instance;
    final donem = _donem;
    setState(() {
      _senPay = servis.computeAllocation(p.assets, p.toTRY);
      _senRoi = servis.staleROI(userId: me.id, periodDays: donem.gun);
    });
    final roi = await servis.computeROI(
      assets: p.assets,
      periodDays: donem.gun,
      currentValueTRY: servis.totalValueTRY(p.assets, p.toTRY),
      toTRY: p.toTRY,
      cacheKey: me.id,
    );
    if (!mounted || donem != _donem) return;
    setState(() => _senRoi = roi);
  }

  void _ayrintiAc(TopGainerAllocation? satir) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.c.surface1,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => _PortfoyAyrintisi(
        donem: _donem,
        satir: satir,
        senPay: _senPay,
        senRoi: _senRoi,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(portfolioProvider, (_, __) => _senYenile());
    final hp = SandikSpace.screenH(context);
    return Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(title: 'Zirvedeki Portföyler'),
      body: SafeArea(
        child: FutureBuilder<List<TopGainerAllocation>>(
          future: _satirlar,
          builder: (context, snap) {
            final satirlar = snap.data ?? const <TopGainerAllocation>[];
            final yukleniyor =
                snap.connectionState == ConnectionState.waiting &&
                    satirlar.isEmpty;
            return ListView(
              padding: EdgeInsets.fromLTRB(hp, SandikSpace.sm, hp, SandikSpace.lg),
              children: [
                _DonemSecici(secili: _donem, onSec: _donemSec),
                const SizedBox(height: SandikSpace.md),
                if (yukleniyor)
                  const _Iskelet()
                else if (satirlar.isEmpty)
                  _BosDurum(havuz: _havuz)
                else
                  ..._dolu(context, satirlar),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _dolu(BuildContext context, List<TopGainerAllocation> satirlar) {
    final zirve = satirlar.first;
    final roiler = [for (final s in satirlar) s.roiPct];
    final senRoi = _senRoi;
    final isaretler = [
      for (final s in satirlar)
        ZirveIsaret(
          anahtar: '${s.rank}',
          etiket: '${s.rank}.',
          roi: s.roiPct,
          sira: s.rank,
        ),
      if (senRoi != null)
        ZirveIsaret(
          anahtar: ZirveKiyas.senAnahtari,
          etiket: 'Sen',
          roi: senRoi,
          sen: true,
        ),
    ];
    final gecerli =
        isaretler.any((i) => i.anahtar == _secili) ? _secili : '${zirve.rank}';
    final seciliSatir =
        satirlar.where((s) => '${s.rank}' == gecerli).firstOrNull;
    final senMi = seciliSatir == null;
    final seciliPay = seciliSatir?.allocation ?? _senPay;
    final seciliRoi = seciliSatir?.roiPct ?? senRoi;
    final getiriEki =
        seciliRoi == null ? '' : ' ${_donem.ad} ${ZirveKiyas.getiriParcasi(seciliRoi)}.';

    return [
      _Hero(
        donem: _donem,
        zirveRoi: zirve.roiPct,
        senRoi: senRoi,
        zirveRoileri: roiler,
      ),
      const SizedBox(height: SandikSpace.lg),
      SandikSectionHeader(
        title: 'HERKES AYNI ÇİZGİDE',
        trailing: Text(
          'bir işarete dokun',
          style: context.t.labelMedium
              ?.copyWith(letterSpacing: 0, color: context.c.text36),
        ),
      ),
      const SizedBox(height: SandikSpace.xs),
      ZirveCetveli(
        isaretler: isaretler,
        secili: gecerli,
        onSec: (k) => setState(() => _secili = k),
      ),
      const SizedBox(height: SandikSpace.md),
      _SeciliPortfoy(
        sira: seciliSatir?.rank,
        baslik: senMi
            ? 'Sen neye yatırmışsın?'
            : '${seciliSatir.rank}. portföy neye yatırmış?',
        cumle: ZirveKiyas.dagilimCumlesi(seciliPay, sen: senMi) + getiriEki,
        pay: seciliPay,
        onAyrinti: () => _ayrintiAc(seciliSatir),
      ),
      const SizedBox(height: SandikSpace.smd),
      _FarkNotu(
        metin: senMi
            ? 'Bir zirve işaretine dokun, farkı burada söyleyelim.'
            : ZirveKiyas.farkCumlesi(
                senPay: _senPay,
                zirvePay: seciliSatir.allocation,
                zirveAd: seciliSatir.rank == 1
                    ? 'zirve'
                    : '${seciliSatir.rank}. portföy',
              ),
      ),
      const SizedBox(height: SandikSpace.lg),
      _AltNot(havuz: _havuz),
    ];
  }
}

// ── Parçalar ─────────────────────────────────────────────────────────────────

/// Üç duraklı dönem seçici. Yarış ekranındaki `_PeriodBar` ile aynı dil
/// (amber dolgu, kaydırmalı seçim); süre `SandikMotion` üzerinden ki
/// "hareketi azalt" saygı görsün.
class _DonemSecici extends StatelessWidget {
  const _DonemSecici({required this.secili, required this.onSec});

  final ZirveDonem secili;
  final ValueChanged<ZirveDonem> onSec;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: SandikTouch.min + SandikSpace.xs2,
      padding: const EdgeInsets.all(SandikSpace.xs2),
      decoration: BoxDecoration(
        color: context.c.overlay,
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        border: Border.all(color: context.c.hairline),
      ),
      child: Row(
        children: [
          for (final d in ZirveDonem.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: d == secili,
                label: d.ad,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSec(d),
                    child: AnimatedContainer(
                      duration: SandikMotion.surfaceOf(context),
                      curve: SandikMotion.enter,
                      margin: EdgeInsets.symmetric(
                          horizontal: d == secili ? 0 : 2),
                      decoration: BoxDecoration(
                        gradient: d == secili ? context.c.amberGradient : null,
                        borderRadius: BorderRadius.circular(SandikRadius.md),
                        boxShadow: d == secili
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
                            color: d == secili
                                ? context.c.onAmber
                                : context.c.text58,
                          ),
                          child: Text(d.kisa),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cümle + iki hücre (Sen · Zirve). Renk yalnızca getiride.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.donem,
    required this.zirveRoi,
    required this.senRoi,
    required this.zirveRoileri,
  });

  final ZirveDonem donem;
  final double zirveRoi;
  final double? senRoi;
  final List<double> zirveRoileri;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ZirveKiyas.getiriCumlesi(
              donem: donem, zirveRoi: zirveRoi, senRoi: senRoi),
          style: context.t.bodyLarge?.copyWith(
            color: context.c.text90,
            height: 1.4,
          ),
        ),
        const SizedBox(height: SandikSpace.smd),
        Row(
          children: [
            Expanded(
              child: _Hucre(
                etiket: 'SEN',
                senIsareti: true,
                deger: senRoi,
                alt: ZirveKiyas.konumCumlesi(
                    senRoi: senRoi, zirveRoileri: zirveRoileri),
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: _Hucre(
                etiket: 'ZİRVE',
                senIsareti: false,
                deger: zirveRoi,
                alt: '1. portföy',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Hucre extends StatelessWidget {
  const _Hucre({
    required this.etiket,
    required this.senIsareti,
    required this.deger,
    required this.alt,
  });

  final String etiket;
  final bool senIsareti;
  final double? deger;
  final String alt;

  @override
  Widget build(BuildContext context) {
    final d = deger;
    final renk = d == null
        ? context.c.text36
        : d < 0
            ? context.c.loss
            : context.c.gain;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          SandikSpace.smd, SandikSpace.sm, SandikSpace.smd, SandikSpace.sm),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: senIsareti ? context.c.amberFill : null,
                  border: senIsareti
                      ? null
                      : Border.all(color: context.c.text58, width: 1.5),
                ),
              ),
              const SizedBox(width: SandikSpace.xs2),
              Text(
                etiket,
                style: context.t.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.c.text58,
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.xs2),
          Text(
            d == null ? '—' : ZirveKiyas.isaretliYuzde(d),
            style: context.t.numMedium.copyWith(
              fontWeight: FontWeight.w800,
              color: renk,
            ),
          ),
          Text(
            alt,
            maxLines: 2,
            style: context.t.labelMedium?.copyWith(
              letterSpacing: 0,
              color: context.c.text58,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sıra madalyası (1 altın, 2 gümüş, 3 bronz) ya da "S" (sen).
class _Madalya extends StatelessWidget {
  const _Madalya({this.sira});

  /// null → kullanıcı.
  final int? sira;

  static const double _boy = 24;

  @override
  Widget build(BuildContext context) {
    final (acik, koyu) = switch (sira) {
      1 => (Sandik.medalGold, Sandik.medalGoldDark),
      2 => (Sandik.medalSilver, Sandik.medalSilverDark),
      3 => (Sandik.medalBronze, Sandik.medalBronzeDark),
      null => (context.c.amberFill, context.c.amberFill),
      _ => (context.c.hairline, context.c.hairline),
    };
    return Container(
      width: _boy,
      height: _boy,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [acik, koyu],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Text(
        sira == null ? 'S' : '$sira',
        style: context.t.numSmall.copyWith(
          fontWeight: FontWeight.w900,
          color: context.c.onAmber,
        ),
      ),
    );
  }
}

/// Seçili işaretin bloğu: soru, cevap cümlesi, şerit; dokununca ayrıntı.
class _SeciliPortfoy extends StatelessWidget {
  const _SeciliPortfoy({
    required this.sira,
    required this.baslik,
    required this.cumle,
    required this.pay,
    required this.onAyrinti,
  });

  final int? sira;
  final String baslik;
  final String cumle;
  final Map<String, double> pay;
  final VoidCallback onAyrinti;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$baslik Ayrıntı için dokun.',
      child: SandikCard(
        onTap: onAyrinti,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Madalya(sira: sira),
                const SizedBox(width: SandikSpace.sm),
                Expanded(
                  child: Text(
                    baslik,
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.c.text90,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.c.text36),
              ],
            ),
            const SizedBox(height: SandikSpace.sm),
            Text(
              cumle,
              style: context.t.bodyMedium?.copyWith(
                color: context.c.text90,
                height: 1.4,
              ),
            ),
            const SizedBox(height: SandikSpace.smd),
            ZirveDagilimSeridi(pay: pay),
            const SizedBox(height: SandikSpace.sm),
            Text(
              'Tür tür dağılım ve senden farkı ›',
              style: context.t.labelMedium?.copyWith(
                letterSpacing: 0,
                fontWeight: FontWeight.w700,
                color: context.c.amberText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Sen fona ağırlık vermişsin, zirve altına." — amber not, renksiz fark.
class _FarkNotu extends StatelessWidget {
  const _FarkNotu({required this.metin});

  final String metin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SandikSpace.smd),
      decoration: BoxDecoration(
        color: context.c.amberFill.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SandikRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.compare_arrows_rounded,
              size: 18, color: context.c.amberText),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Text(
              metin,
              style: context.t.bodyMedium?.copyWith(
                color: context.c.text90,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AltNot extends StatelessWidget {
  const _AltNot({required this.havuz});

  final Future<int?> havuz;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int?>(
      future: havuz,
      builder: (context, snap) {
        final n = snap.data;
        final havuzMetni = n == null ? '' : 'Havuz: $n portföy · ';
        return Text(
          '${havuzMetni}anlık görüntü günde iki kez · kimlik, miktar ve TL '
          'paylaşılmaz',
          style: context.t.labelMedium?.copyWith(
            letterSpacing: 0,
            color: context.c.text36,
            height: 1.4,
          ),
        );
      },
    );
  }
}

/// Havuz eşiği dolmamış: ilerleme + nasıl dolduğu. "Yakında" yok, çağrı
/// düğmesi de yok — havuz beyana dayanmaz, kullanıcının yapacağı bir şey yok.
class _BosDurum extends StatelessWidget {
  const _BosDurum({required this.havuz});

  final Future<int?> havuz;

  @override
  Widget build(BuildContext context) {
    return SandikCard(
      child: FutureBuilder<int?>(
        future: havuz,
        builder: (context, snap) {
          final n = snap.data;
          final metin = n == null
              ? 'Havuz oluşuyor; ${ZirveKiyas.havuzEsigi} portföy olunca '
                  'zirve belli olur ve kıyas burada açılır.'
              : 'Havuz oluşuyor: $n portföy var, ${ZirveKiyas.havuzEsigi} '
                  'olunca zirve belli olur ve kıyas burada açılır.';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Zirve henüz belli değil',
                style: context.t.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.c.text90,
                ),
              ),
              const SizedBox(height: SandikSpace.sm),
              Text(
                metin,
                style: context.t.bodyMedium?.copyWith(
                  color: context.c.text90,
                  height: 1.4,
                ),
              ),
              if (n != null) ...[
                const SizedBox(height: SandikSpace.sm),
                ZirveHavuzCubugu(havuz: n),
              ],
              const SizedBox(height: SandikSpace.sm),
              Text(
                'Portföyü 5 günden eski herkes kendiliğinden ve anonim olarak '
                'havuzdadır; ayrıca katılman gerekmez. Kimlik, miktar ve TL '
                'paylaşılmaz; yalnız getiri ve tür payı.',
                style: context.t.labelMedium?.copyWith(
                  letterSpacing: 0,
                  color: context.c.text58,
                  height: 1.4,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Iskelet extends StatelessWidget {
  const _Iskelet();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SandikSkeleton(height: 16),
        SizedBox(height: SandikSpace.xs2),
        SandikSkeleton(width: 220, height: 16),
        SizedBox(height: SandikSpace.smd),
        SandikSkeleton(height: 72, radius: SandikRadius.md),
        SizedBox(height: SandikSpace.lg),
        SandikSkeleton(height: ZirveCetveli.yukseklik, radius: SandikRadius.md),
        SizedBox(height: SandikSpace.md),
        SandikSkeleton(height: 140, radius: SandikRadius.md),
      ],
    );
  }
}

// ── Ayrıntı alt sayfası ──────────────────────────────────────────────────────

/// Bir portföyün (ya da kullanıcının) tür tür dağılımı ve senden farkı.
///
/// Zirve tarafında yüzde dışında hiçbir şey yok (anonimlik); kullanıcı
/// tarafında da yalnız yüzde — tutar bu ekranın konusu değil.
class _PortfoyAyrintisi extends StatelessWidget {
  const _PortfoyAyrintisi({
    required this.donem,
    required this.satir,
    required this.senPay,
    required this.senRoi,
  });

  final ZirveDonem donem;

  /// null → kullanıcının kendi portföyü.
  final TopGainerAllocation? satir;
  final Map<String, double> senPay;
  final double? senRoi;

  @override
  Widget build(BuildContext context) {
    final s = satir;
    final senMi = s == null;
    final pay = s?.allocation ?? senPay;
    final roi = s?.roiPct ?? senRoi;
    final baslik = senMi ? 'Senin portföyün' : '${s.rank}. portföy';
    final altBaslik = roi == null
        ? 'Getirin henüz hesaplanamıyor'
        : '${donem.ad} ${ZirveKiyas.getiriParcasi(roi)}';
    final turler = ZirveKiyas.sirali(pay);
    final farklar = senMi
        ? const <({String tur, double sen, double zirve})>[]
        : ([
            for (final t in {...senPay.keys, ...pay.keys})
              (tur: t, sen: senPay[t] ?? 0.0, zirve: pay[t] ?? 0.0),
          ]..sort((a, b) =>
            (b.sen - b.zirve).abs().compareTo((a.sen - a.zirve).abs())));

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(SandikSpace.lg, SandikSpace.sm,
          SandikSpace.lg, SandikSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.c.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.md),
          Row(
            children: [
              _Madalya(sira: s?.rank),
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      baslik,
                      style: context.t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: context.c.text90,
                      ),
                    ),
                    Text(
                      altBaslik,
                      style: context.t.labelMedium?.copyWith(
                        letterSpacing: 0,
                        color: roi == null
                            ? context.c.text58
                            : roi < 0
                                ? context.c.loss
                                : context.c.gain,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.md),
          Text(
            ZirveKiyas.dagilimCumlesi(pay, sen: senMi),
            style: context.t.bodyMedium?.copyWith(
              color: context.c.text90,
              height: 1.4,
            ),
          ),
          const SizedBox(height: SandikSpace.smd),
          ZirveDagilimSeridi(pay: pay, canlandir: false),
          const SizedBox(height: SandikSpace.lg),
          const SandikSectionHeader(title: 'TÜR TÜR'),
          const SizedBox(height: SandikSpace.sm),
          for (final t in turler) ...[
            _TurSatiri(tur: t.tur, pay: t.pay),
            const SizedBox(height: SandikSpace.sm),
          ],
          if (!senMi) ...[
            const SizedBox(height: SandikSpace.smd),
            const SandikSectionHeader(title: 'SENDEN FARKI'),
            const SizedBox(height: SandikSpace.sm),
            Text(
              '${ZirveKiyas.farkCumlesi(senPay: senPay, zirvePay: pay, zirveAd: s.rank == 1 ? 'zirve' : '${s.rank}. portföy')} '
              '${ZirveKiyas.enBuyukFarkCumlesi(senPay, pay)}',
              style: context.t.bodyMedium?.copyWith(
                color: context.c.text90,
                height: 1.4,
              ),
            ),
            const SizedBox(height: SandikSpace.smd),
            for (final f in farklar) ...[
              _FarkSatiri(tur: f.tur, sen: f.sen, zirve: f.zirve),
              const SizedBox(height: SandikSpace.sm),
            ],
          ],
          const SizedBox(height: SandikSpace.sm),
          Text(
            senMi
                ? 'Portföyün de havuzda, anonim. İlk üçe girersen başkaları '
                    'yalnız getirini ve tür payını görür; kimliğin, tutarın '
                    've varlıkların asla görünmez.'
                : 'Anonim: bu portföyün kimliği, tutarı ve varlıkları '
                    'paylaşılmaz; yalnız tür payı.',
            style: context.t.labelMedium?.copyWith(
              letterSpacing: 0,
              color: context.c.text36,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TurSatiri extends StatelessWidget {
  const _TurSatiri({required this.tur, required this.pay});

  final String tur;
  final double pay;

  @override
  Widget build(BuildContext context) {
    final renk = ZirveDagilimSeridi.renk(context, tur);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: renk,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: SandikSpace.sm),
        SizedBox(
          width: 64,
          child: Text(
            ZirveDagilimSeridi.etiket(context, tur),
            style: context.t.bodyMedium?.copyWith(color: context.c.text90),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SandikRadius.sm),
            child: Container(
              height: 8,
              color: context.c.overlay,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (pay / 100).clamp(0.0, 1.0),
                child: Container(color: renk),
              ),
            ),
          ),
        ),
        const SizedBox(width: SandikSpace.sm),
        SizedBox(
          width: 44,
          child: Text(
            '%${pay.round()}',
            textAlign: TextAlign.right,
            style: context.t.numSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: context.c.text90,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Altın · sende %18 · onda %56 · 38 puan". Fark renksiz.
class _FarkSatiri extends StatelessWidget {
  const _FarkSatiri({required this.tur, required this.sen, required this.zirve});

  final String tur;
  final double sen;
  final double zirve;

  @override
  Widget build(BuildContext context) {
    final fark = (sen - zirve).round();
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            ZirveDagilimSeridi.etiket(context, tur),
            style: context.t.bodyMedium?.copyWith(color: context.c.text90),
          ),
        ),
        Expanded(
          child: Text(
            'sende %${sen.round()} · onda %${zirve.round()}',
            style: context.t.labelMedium?.copyWith(
              letterSpacing: 0,
              color: context.c.text58,
            ),
          ),
        ),
        Text(
          fark == 0 ? 'aynı' : '${fark.abs()} puan',
          style: context.t.numSmall.copyWith(color: context.c.text36),
        ),
      ],
    );
  }
}
