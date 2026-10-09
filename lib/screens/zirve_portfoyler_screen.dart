import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/crash_reporter.dart';
import '../services/leaderboard_service.dart';
import '../services/yasal_onay_service.dart';
import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/polling.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/sandik_segment.dart';
import '../widgets/sandik_skeleton.dart';
import '../widgets/zirve_ayna_kiyas.dart';
import '../widgets/zirve_cetveli.dart';
import '../widgets/zirve_dagilim_seridi.dart';
import '../widgets/zirve_donem_secici.dart';
import '../widgets/zirve_fon_listesi.dart';
import '../widgets/zirve_karti.dart';
import '../widgets/zirve_riza_karti.dart';
import '../widgets/zorunlu_okuma.dart';

/// Zirvedeki Portföyler (kullanıcı seçimi 2026-09-29, "A · Cetvel önde").
///
/// 2026-10-05: tam ekran kabuğu (`ZirvePortfoylerScreen`) bayrak
/// `siralama_tek_sayfa` ile birlikte silindi; gövde ([ZirveGovdesi]) yalnız
/// Sıralama › Zirvedekiler sekmesinde çizilir. Aşağıdaki not gövdeyi anlatır.
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
/// - Havuz AÇIK RIZAYA dayanır (0091, 2026-10-01; 0083'te beyansızdı):
///   rıza vermemiş kullanıcı önce `ZirveRizaKarti`'nı görür — ne paylaşılır,
///   ne paylaşılmaz, karşılığında ne alır, nasıl geri çeker. Karşılıklılık:
///   liste yalnız katılana açılır (sunucu da rızasız çağırana boş döner).
///   Yarış ekranı ve onun katılım anahtarı bundan bağımsız.
/// - Sen: getiri istemcide `LeaderboardService.computeROI` — seçimlerinin
///   getirisi (TWR, 0095; Yarış ve sunucuyla AYNI kural,
///   `secim_getirisi.dart`), dağılım `computeAllocation`. Sunucuya bir şey
///   yazılmaz — snapshot'ı yalnız sunucu alıyor.
///
/// ## Dil
/// Sayı yalnız başına konuşmaz; cümleler `ZirveKiyas`'ta. Dağılım farkı
/// renklendirilmez (iyi/kötü değil); renk yalnızca getiride.
///
/// ## Gövde — rıza kartı ya da cetvel
/// `ZirvePortfoylerScreen`'den ayrıldı (sadeleştirme madde 8, 2026-10-04; o
/// kabuk 2026-10-05'te silindi): tek "Sıralama" sayfasının "Herkes" sekmesi
/// bu gövdeyi çizer. Dönem
/// dışarıdan yönetilir ki sayfa iki sekmede tek dönem tutsun. Açık rıza
/// akışı (0091) gövdede kalır: hangi kapıdan gelinirse gelinsin rızasız
/// liste istenmez, "Şimdi değil" eski davranışla sayfayı kapatır.
class ZirveGovdesi extends ConsumerStatefulWidget {
  const ZirveGovdesi({
    super.key,
    required this.donem,
    required this.onDonem,
    this.rizaYukleyici,
  });

  final ZirveDonem donem;
  final ValueChanged<ZirveDonem> onDonem;

  /// Test için rıza durumu; null → `LeaderboardService.fetchZirveRizasi`
  /// (`ZirveKarti.rizaYukleyici` ile aynı kalıp).
  final Future<bool?> Function()? rizaYukleyici;

  @override
  ConsumerState<ZirveGovdesi> createState() => _ZirveGovdesiState();
}

class _ZirveGovdesiState extends ConsumerState<ZirveGovdesi> {
  /// Dönem sahibi kabuk (ekran ya da Sıralama sayfası); gövde okur.
  ZirveDonem get _donem => widget.donem;
  String _secili = '1';

  /// Son seçimin yönü (+1 sağa / −1 sola, cetvelde). Başlık ve cümle bu
  /// yönde kayarak yenilenir — imleçle aynı yöne akar.
  int _yon = 1;

  /// Ayna kıyasının karşı tarafı (zirve sırası). Kendine dokununca DEĞİŞMEZ:
  /// kıyas son seçtiğin zirveyle kalır, boşalmaz.
  String? _kiyasHedefi;
  late Future<List<TopGainerAllocation>> _satirlar = _cek();
  late Future<int?> _havuz = _havuzCek();

  /// Geçerli zirve rızası (0091). `null` = okunamadı; rıza varsayılmaz.
  late Future<bool?> _riza = _rizaCek();

  Future<bool?> _rizaCek() =>
      (widget.rizaYukleyici ?? LeaderboardService.instance.fetchZirveRizasi)();
  double? _senRoi;

  /// "Sen" değerleri sunucudan mı (havuzdasın, 0085 `zirve_benim`)? Öyleyse
  /// zirveyle aynı kaynak; değilse istemci hesabı.
  bool _senSunucuda = false;
  Map<String, double> _senPay = const {};
  Map<String, double> _senFonDetay = const {};
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
    // Metinlerdeki asgari süre sunucudan (0128); gelince yeniden çiz.
    LeaderboardService.instance.asgariGunuGetir().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tik.dispose();
    super.dispose();
  }

  void _donemSec(ZirveDonem d) {
    if (d == _donem) return;
    widget.onDonem(d);
  }

  /// Dönem kabukta değişti → liste, havuz ve "Sen" o dönemle yeniden.
  /// (Eskiden `_donemSec` içindeydi; dönem artık dışarıda tutuluyor.)
  @override
  void didUpdateWidget(covariant ZirveGovdesi old) {
    super.didUpdateWidget(old);
    if (old.donem == widget.donem) return;
    _satirlar = _cek();
    _havuz = _havuzCek();
    _senYenile();
  }

  /// Kullanıcının getirisi ve dağılımı. Önce önbellekteki (bayat) değer
  /// gösterilir, hesap arka planda biter; dönem bu arada değiştiyse eski
  /// sonuç yazılmaz.
  ///
  /// Havuzdaysan (sunucu `zirve_benim` satır döndürür) değerler SUNUCUDAN
  /// alınır — açık bulgu 2026-09-29: aynı portföy "Sen" −%3,2 (istemci) ve
  /// "2." +%2,8 (sunucu) olarak iki kez görünüyordu. Havuzda değilsen
  /// (yeni portföy, tek varlık) istemci hesabı kalır.
  Future<void> _senYenile() async {
    final me = ref.read(authProvider).valueOrNull;
    final p = ref.read(portfolioProvider).valueOrNull;
    if (me == null || p == null || !mounted) return;
    final servis = LeaderboardService.instance;
    final donem = _donem;
    setState(() {
      _senPay = servis.computeAllocation(p.assets, p.toTRY);
      _senFonDetay = servis.computeFonDetay(p.assets, p.toTRY);
      // Zirve anonim: sunucuyla aynı geriye tarih kuralı (`SiralamaKapsami`).
      _senRoi = servis.staleROI(
          userId: me.id,
          periodDays: donem.gun,
          kapsam: SiralamaKapsami.anonim);
    });
    final sonuc = await Future.wait<Object?>([
      servis.fetchZirveBenim(periodDays: donem.gun),
      servis.computeROI(
        assets: p.assets,
        periodDays: donem.gun,
        kapsam: SiralamaKapsami.anonim,
        currentValueTRY: servis.totalValueTRY(p.assets, p.toTRY),
        toTRY: p.toTRY,
        cacheKey: me.id,
      ),
    ]);
    if (!mounted || donem != _donem) return;
    final benim = sonuc[0] as ZirveBenim?;
    final roi = sonuc[1] as double?;
    setState(() {
      _senSunucuda = benim != null;
      if (benim != null) {
        _senRoi = benim.roiPct;
        _senPay = benim.allocation;
        _senFonDetay = benim.fonDetay;
      } else {
        _senRoi = roi;
      }
    });
  }

  /// Rıza verildi → liste ve "Sen" yeniden çekilir. Hata kartta kalır
  /// (`SandikAsyncButton` yeniden basılabilir), durum değişmemiş sayılır.
  ///
  /// Rıza her zaman zorunlu okumadan gelir ([ZirveRizaOkumaGovdesi]:
  /// "Katılıyorum" metnin sonuna kaydırılmadan açılmaz) → kayıt
  /// `sonuna_kadar_okundu` taşır. Bayrak `zorunlu_okuma` 2026-10-05'te kalktı.
  Future<void> _katil() async {
    // Onay kaydının dili — `await`'ten önce (context sonra geçersiz olabilir).
    final dil = Localizations.localeOf(context).toString();
    try {
      await LeaderboardService.instance.setZirveRizasi(true);
    } catch (e) {
      if (mounted) showAppError(context, e);
      return;
    }
    // Rıza kartının metni yasal onay kaydına (0102). `zirve_rizalari` asıl
    // kapı; bu ispat kaydı —
    // beklenmez, fırlatmaz. Geri çekme sunucuda aynı işlemde damgalanır.
    CrashReporter.arkaPlan(
        YasalOnayService.instance.zirveRizasiniKaydet(
            locale: dil, sonunaKadarOkundu: true),
        reason: 'YasalOnayService.zirve');
    if (!mounted) return;
    setState(() {
      _riza = Future.value(true);
      _satirlar = _cek();
      _havuz = _havuzCek();
    });
    await _senYenile();
  }

  /// Rızayı geri çek: onay → sunucu ölçümleri aynı işlemde siler.
  Future<void> _ayril() async {
    final onay = await showSandikConfirm(
      context: context,
      title: "Zirvedeki Portföyler'den ayrıl",
      message: 'Portföyün havuzdan çıkar ve bugüne kadarki ölçümlerin hemen '
          'silinir. Katılanların portföylerini de artık göremezsin. İstediğin '
          'an yeniden katılabilirsin.',
      confirmLabel: 'Ayrıl',
      destructive: true,
    );
    if (!onay || !mounted) return;
    try {
      await LeaderboardService.instance.setZirveRizasi(false);
    } catch (e) {
      if (mounted) showAppError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() => _riza = Future.value(false));
  }

  void _isaretSec(String k, List<ZirveIsaret> isaretler,
      List<TopGainerAllocation> satirlar) {
    if (k == _secili) return;
    double? roiOf(String a) =>
        isaretler.where((i) => i.anahtar == a).firstOrNull?.roi;
    final eski = roiOf(_secili);
    final yeni = roiOf(k);
    final satir = satirlar.where((s) => '${s.rank}' == k).firstOrNull;
    setState(() {
      _yon = (eski == null || yeni == null || yeni >= eski) ? 1 : -1;
      _secili = k;
      if (satir != null && !satir.ben) _kiyasHedefi = k;
    });
  }

  void _ayrintiAc(TopGainerAllocation? satir) {
    showSandikSheet<void>(
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
        senFonDetay: _senFonDetay,
        senRoi: _senRoi,
        senHavuzda: _senSunucuda,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(portfolioProvider, (_, __) => _senYenile());
    final hp = SandikSpace.screenH(context);
    return FutureBuilder<bool?>(
      future: _riza,
      builder: (context, rizaSnap) {
        if (rizaSnap.connectionState != ConnectionState.done) {
          return ListView(
            padding: EdgeInsets.fromLTRB(hp, SandikSpace.sm, hp, SandikSpace.lg),
            children: const [_Iskelet()],
          );
        }
        final riza = rizaSnap.data;
        if (riza == null) {
          return SandikErrorView(
            error: 'Katılım durumun okunamadı.',
            onRetry: () => setState(() => _riza = _rizaCek()),
          );
        }
        if (!riza) {
          return ZirveRizaOkumaGovdesi(
            hp: hp,
            onKatil: _katil,
            onSimdiDegil: () => Navigator.of(context).maybePop(),
          );
        }
        return _liste(hp);
      },
    );
  }

  Widget _liste(double hp) {
    return FutureBuilder<List<TopGainerAllocation>>(
          future: _satirlar,
          builder: (context, snap) {
            final satirlar = snap.data ?? const <TopGainerAllocation>[];
            final yukleniyor =
                snap.connectionState == ConnectionState.waiting &&
                    satirlar.isEmpty;
            return ListView(
              padding: EdgeInsets.fromLTRB(hp, SandikSpace.sm, hp, SandikSpace.lg),
              children: [
                ZirveDonemSecici(secili: _donem, onSec: _donemSec),
                const SizedBox(height: SandikSpace.md),
                if (yukleniyor)
                  const _Iskelet()
                else if (satirlar.isEmpty)
                  _BosDurum(havuz: _havuz)
                else
                  ..._dolu(context, satirlar),
                const SizedBox(height: SandikSpace.md),
                // Onay + rıza geri çekme isteği tek Future: gösterge düğmede
                // döner, ikinci dokunuş yutulur (tek yükleniyor davranışı,
                // 2026-10-08). Eskiden onaydan sonra istek göstergesiz gidiyordu.
                Center(
                  child: SandikAsyncButton.kompakt(
                    tur: SandikAsyncTur.metin,
                    onPressed: _ayril,
                    child: const Text("Zirvedeki Portföyler'den ayrıl"),
                  ),
                ),
              ],
            );
          },
        );
  }

  List<Widget> _dolu(BuildContext context, List<TopGainerAllocation> satirlar) {
    final zirve = satirlar.first;
    final roiler = [for (final s in satirlar) s.roiPct];
    final senRoi = _senRoi;
    // Zirve satırlarından biri senin mi (sunucu `ben`)? Öyleyse o işaret
    // "Sen" olur ve ikinci bir Sen işareti konmaz.
    final benSatiri = satirlar.where((s) => s.ben).firstOrNull;
    final benSira = benSatiri?.rank;
    final isaretler = [
      for (final s in satirlar)
        ZirveIsaret(
          anahtar: '${s.rank}',
          etiket: s.ben ? 'Sen' : '${s.rank}.',
          roi: s.roiPct,
          sira: s.rank,
          sen: s.ben,
        ),
      if (senRoi != null && benSatiri == null)
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
    final senMi = seciliSatir == null || seciliSatir.ben;
    final seciliPay = seciliSatir?.allocation ?? _senPay;
    final seciliFon = seciliSatir?.fonDetay ?? _senFonDetay;
    final seciliRoi = seciliSatir?.roiPct ?? senRoi;
    final getiriEki =
        seciliRoi == null ? '' : ' ${_donem.ad} ${ZirveKiyas.getiriParcasi(seciliRoi)}.';
    // Ayna kıyasının karşısı: seçili işaret bir zirveyse o; kendin
    // seçiliysen son seçtiğin zirve; hiç seçmediysen senden olmayan ilk sıra.
    final adaylar = satirlar.where((s) => !s.ben).toList();
    final hedefAnahtari = seciliSatir != null && !seciliSatir.ben
        ? '${seciliSatir.rank}'
        : _kiyasHedefi;
    final hedef = adaylar
            .where((s) => '${s.rank}' == hedefAnahtari)
            .firstOrNull ??
        adaylar.firstOrNull;

    return [
      _Hero(
        donem: _donem,
        zirveRoi: zirve.roiPct,
        senRoi: senRoi,
        zirveRoileri: roiler,
        benSira: benSira,
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
        onSec: (k) => _isaretSec(k, isaretler, satirlar),
      ),
      const SizedBox(height: SandikSpace.md),
      _SeciliPortfoy(
        anahtar: gecerli,
        yon: _yon,
        roi: seciliRoi,
        sira: seciliSatir?.rank,
        baslik: senMi
            ? 'Sen neye yatırmışsın?'
            : '${seciliSatir.rank}. portföy neye yatırmış?',
        cumle: ZirveKiyas.dagilimCumlesi(seciliPay, sen: senMi) + getiriEki,
        pay: seciliPay,
        fonDetay: seciliFon,
        onAyrinti: () => _ayrintiAc(seciliSatir),
      ),
      if (hedef != null) ...[
        const SizedBox(height: SandikSpace.lg),
        SandikSectionHeader(title: 'SEN VE ${hedef.rank}. PORTFÖY'),
        const SizedBox(height: SandikSpace.sm),
        _KiyasSecici(
          adaylar: adaylar,
          secili: hedef.rank,
          onSec: (rank) => _isaretSec('$rank', isaretler, satirlar),
        ),
        const SizedBox(height: SandikSpace.smd),
        ZirveAynaKiyas(
          senPay: _senPay,
          senFon: _senFonDetay,
          zirvePay: hedef.allocation,
          zirveFon: hedef.fonDetay,
          zirveAd: '${hedef.rank}. portföy',
          senRoi: senRoi,
          zirveRoi: hedef.roiPct,
        ),
      ],
      const SizedBox(height: SandikSpace.lg),
      _AltNot(havuz: _havuz),
    ];
  }
}

// ── Parçalar ─────────────────────────────────────────────────────────────────

/// Cümle + iki hücre (Sen · Zirve). Renk yalnızca getiride.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.donem,
    required this.zirveRoi,
    required this.senRoi,
    required this.zirveRoileri,
    required this.benSira,
  });

  final ZirveDonem donem;
  final double zirveRoi;
  final double? senRoi;
  final List<double> zirveRoileri;

  /// Zirve satırlarında senin sıran (varsa).
  final int? benSira;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ZirveKiyas.getiriCumlesi(
              donem: donem,
              zirveRoi: zirveRoi,
              senRoi: senRoi,
              benSira: benSira),
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
                    senRoi: senRoi,
                    zirveRoileri: zirveRoileri,
                    benSira: benSira),
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: _Hucre(
                etiket: 'ZİRVE',
                senIsareti: false,
                deger: zirveRoi,
                alt: benSira == 1 ? 'senin portföyün' : '1. portföy',
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
    return SandikCard(
      padding: const EdgeInsets.fromLTRB(
          SandikSpace.smd, SandikSpace.sm, SandikSpace.smd, SandikSpace.sm),
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
          if (d == null)
            Text(
              '—',
              style: context.t.numMedium.copyWith(
                fontWeight: FontWeight.w800,
                color: renk,
              ),
            )
          else
            // Dönem ya da kaynak değişince sayı SAYARAK yeni değere gider;
            // işaret (+/−) geçişte değişirse renk de o anda döner.
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: d),
              duration: SandikMotion.flowOf(context),
              curve: SandikMotion.glide,
              builder: (context, v, _) => Text(
                ZirveKiyas.isaretliYuzde(v),
                style: context.t.numMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: v < 0 ? context.c.loss : context.c.gain,
                ),
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
///
/// ## Geçiş (2026-09-29, "daha göz alıcı ve akışkan")
/// - Başlık, cümle ve fon satırı seçimin YÖNÜNDE kayarak yenilenir
///   (cetveldeki imleçle aynı yöne; [yon]).
/// - Getiri sayarak yeni değere gider.
/// - Şerit dilimleri sabit tür sırasında genişleyip daralarak akar
///   (`ZirveDagilimSeridi`).
/// Hepsi `SandikMotion` üzerinden; "hareketi azalt" açıkken anında.
class _SeciliPortfoy extends StatelessWidget {
  const _SeciliPortfoy({
    required this.anahtar,
    required this.yon,
    required this.roi,
    required this.sira,
    required this.baslik,
    required this.cumle,
    required this.pay,
    required this.fonDetay,
    required this.onAyrinti,
  });

  /// Seçili işaretin anahtarı — yenilenen parçaların anahtarı.
  final String anahtar;
  final int yon;
  final double? roi;
  final int? sira;
  final String baslik;
  final String cumle;
  final Map<String, double> pay;

  /// Fon türünün kod bazında kırılımı; boşsa satır çizilmez.
  final Map<String, double> fonDetay;
  final VoidCallback onAyrinti;

  Widget _kaydir(BuildContext context, String parca, Widget child) {
    return AnimatedSwitcher(
      duration: SandikMotion.surfaceOf(context),
      switchInCurve: SandikMotion.enter,
      switchOutCurve: SandikMotion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (c, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0.08 * yon, 0),
            end: Offset.zero,
          ).animate(anim),
          child: c,
        ),
      ),
      child: KeyedSubtree(key: ValueKey('$parca-$anahtar'), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = roi;
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
                Expanded(
                  child: _kaydir(
                    context,
                    'baslik',
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
                      ],
                    ),
                  ),
                ),
                if (r != null)
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: r),
                    duration: SandikMotion.flowOf(context),
                    curve: SandikMotion.glide,
                    builder: (context, v, _) => Text(
                      ZirveKiyas.isaretliYuzde(v),
                      style: context.t.numSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: v < 0 ? context.c.loss : context.c.gain,
                      ),
                    ),
                  ),
                Icon(Icons.chevron_right_rounded, color: context.c.text36),
              ],
            ),
            const SizedBox(height: SandikSpace.sm),
            _kaydir(
              context,
              'cumle',
              Text(
                cumle,
                style: context.t.bodyMedium?.copyWith(
                  color: context.c.text90,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: SandikSpace.smd),
            ZirveDagilimSeridi(pay: pay),
            if (fonDetay.isNotEmpty) ...[
              const SizedBox(height: SandikSpace.sm),
              _kaydir(
                context,
                'fon',
                Text(
                  'Fonlar: ${ZirveKiyas.fonOzeti(fonDetay)}',
                  style: context.t.labelMedium?.copyWith(
                    letterSpacing: 0,
                    color: context.c.text58,
                  ),
                ),
              ),
            ],
            const SizedBox(height: SandikSpace.sm),
            Text(
              fonDetay.isEmpty
                  ? 'Tür tür dağılım ve senden farkı ›'
                  : 'Tür tür dağılım, fonların adı ve senden farkı ›',
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

/// Ayna kıyasının karşısı: 1. · 2. · 3. (kendi satırın hariç). Seçmek
/// cetvelde o işareti seçmekle aynı — imleç de oraya kayar.
///
/// Kabuk ortak [SandikSegment] (tek seçici, 2026-10-08 — yol haritası
/// 2.12): eskiden aralıklı ayrı çiplerdi; aynı ekranın dönem seçicisi
/// (`ZirveDonemSecici`) kayan zeminli olduğundan bir ekranda iki seçim
/// dili vardı. Yükseklik eski çiplerin 44 pt'si — ROI rakamı sığsın.
class _KiyasSecici extends StatelessWidget {
  const _KiyasSecici({
    required this.adaylar,
    required this.secili,
    required this.onSec,
  });

  final List<TopGainerAllocation> adaylar;
  final int secili;
  final ValueChanged<int> onSec;

  @override
  Widget build(BuildContext context) {
    return SandikSegment(
      adet: adaylar.length,
      secili: adaylar.indexWhere((a) => a.rank == secili),
      onSec: (i) => onSec(adaylar[i].rank),
      yukseklik: SandikTouch.min,
      metinStili: context.t.labelMedium?.copyWith(letterSpacing: 0),
      semantik: (i) => '${adaylar[i].rank}. portföyle kıyasla',
      oge: (_, i, __) => Text(
        '${adaylar[i].rank}.  '
        '${ZirveKiyas.isaretliYuzde(adaylar[i].roiPct)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
/// düğmesi de yok — bu kartı gören zaten katılmış; havuz başkalarının
/// katılımıyla dolar.
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
                // Süre sunucudan (0128, varsayılan 30): ilk varlığın edinme
                // tarihinden sayılır (2026-10-09); havuzun 5 günlük
                // şartından önce o dolmalı.
                'Havuzda yalnız katılmayı kabul edenler var; ilk varlığını '
                'edinmesinin üzerinden en az '
                '${LeaderboardService.instance.asgariGun} gün geçmiş ve en '
                'az 2 farklı varlığı olan katılımcılar sayılır. Sıralama seçimlerinin getirisidir: her gün '
                'tutulan varlıklar piyasa fiyatıyla ölçülür, para ekleme '
                'zamanı etkilemez. Bugünden 3 günden fazla geriye tarihli '
                'girilen kaydın (içe aktarılan geçmiş dahil) getirisi '
                'girildiği günden ölçülür. Kimlik, miktar ve TL paylaşılmaz; yalnız getiri, '
                'tür payı ve fon payları.',
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
    required this.senFonDetay,
    required this.senRoi,
    required this.senHavuzda,
  });

  final ZirveDonem donem;

  /// null ya da `ben` → kullanıcının kendi portföyü.
  final TopGainerAllocation? satir;
  final Map<String, double> senPay;
  final Map<String, double> senFonDetay;
  final double? senRoi;

  /// Kullanıcının portföyü havuzda mı (sunucu `zirve_benim`)?
  final bool senHavuzda;

  @override
  Widget build(BuildContext context) {
    final s = satir;
    final senMi = s == null || s.ben;
    final pay = s?.allocation ?? senPay;
    final fonDetay = s?.fonDetay ?? senFonDetay;
    final roi = s?.roiPct ?? senRoi;
    final baslik = senMi ? 'Senin portföyün' : '${s.rank}. portföy';
    final siraEki = s != null && s.ben ? ' · zirvede ${s.rank}. sıradasın' : '';
    final altBaslik = roi == null
        ? 'Getirin henüz hesaplanamıyor'
        : '${donem.ad} ${ZirveKiyas.getiriParcasi(roi)}$siraEki';
    final turler = ZirveKiyas.sirali(pay);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(SandikSpace.lg, SandikSpace.sm,
          SandikSpace.lg, SandikSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: const SandikTutamac(),
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
            // Fon satırının altında hangi fonlar: kod, resmi TEFAS adı,
            // portföy içindeki payı; zirve portföyünde "sende %X" kıyası.
            if (t.tur == 'fon' && fonDetay.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: SandikSpace.md),
                // Kıyas aşağıdaki aynada; burada yalnız bu portföyün
                // fonları ve resmi adları.
                child: ZirveFonListesi(fonDetay: fonDetay),
              ),
              const SizedBox(height: SandikSpace.xs2),
            ],
          ],
          if (!senMi) ...[
            const SizedBox(height: SandikSpace.smd),
            const SandikSectionHeader(title: 'SENDEN FARKI'),
            const SizedBox(height: SandikSpace.sm),
            ZirveAynaKiyas(
              senPay: senPay,
              senFon: senFonDetay,
              zirvePay: pay,
              zirveFon: fonDetay,
              zirveAd: '${s.rank}. portföy',
              senRoi: senRoi,
              zirveRoi: s.roiPct,
            ),
          ],
          const SizedBox(height: SandikSpace.sm),
          Text(
            senMi
                ? (senHavuzda || (s != null && s.ben)
                    ? 'Portföyün havuzda, anonim. İlk üçe girersen başkaları '
                        'getirini, tür payını ve fonlarının TEFAS kodu ile '
                        'payını görür; kimliğin, tutarın ve diğer varlıkların '
                        'asla görünmez.'
                    : 'Portföyün henüz havuzda değil: katıldın, ama ilk '
                        'varlığını edinmenin üzerinden en az '
                        '${LeaderboardService.instance.asgariGun} gün geçmeli '
                        've en az 2 farklı varlık içermeli. Şart sağlanınca '
                        'anonim olarak girer.')
                : 'Anonim: bu portföyün kimliği, tutarı ve miktarları '
                    'paylaşılmaz; yalnız tür payı ve fonların TEFAS kodu ile '
                    'payı. Fon adları resmi TEFAS listesinden.',
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

/// Zorunlu okumada rıza kartı (2026-10-04; bayrak `zorunlu_okuma`
/// 2026-10-05'te kalktı — rıza yalnız böyle sorulur).
///
/// Kart rızanın TAM metnidir (katalogdaki `zirve_riza` gövdesi kartın
/// sabitlerinden kurulur) ve "Katılıyorum" metnin son satırıdır — onay
/// zaten metnin sonunda. Eklenen tek şey: kullanıcı kartın sonuna
/// kaydırana kadar "Katılıyorum" kapalı, altta ipucu durur. Kart ekrana
/// sığıyorsa düğme baştan açık. Metin değişmez (sürüm/migration gerekmez).
class ZirveRizaOkumaGovdesi extends StatefulWidget {
  const ZirveRizaOkumaGovdesi({
    super.key,
    required this.hp,
    required this.onKatil,
    required this.onSimdiDegil,
  });

  final double hp;
  final Future<void> Function() onKatil;
  final VoidCallback onSimdiDegil;

  @override
  State<ZirveRizaOkumaGovdesi> createState() => _ZirveRizaOkumaGovdesiState();
}

class _ZirveRizaOkumaGovdesiState extends State<ZirveRizaOkumaGovdesi> {
  bool _sonaUlasti = false;
  double _ilerleme = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SonaKadarOkumaIzleyici(
            // "Katılıyorum"dan sonra metin yok: "Şimdi değil" düğmesi ve
            // liste alt boşluğu (bkz. OkumaOlcumu.sonaUlasti).
            sonPay: SandikTouch.min + SandikSpace.xs + SandikSpace.lg,
            onSonaUlasti: () => setState(() => _sonaUlasti = true),
            onIlerleme: (v) => setState(() => _ilerleme = v),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  widget.hp, SandikSpace.sm, widget.hp, SandikSpace.lg),
              children: [
                ZirveRizaKarti(
                  onKatil: widget.onKatil,
                  onSimdiDegil: widget.onSimdiDegil,
                  katilEtkin: _sonaUlasti,
                ),
              ],
            ),
          ),
        ),
        if (!_sonaUlasti) OkumaIpucu(ilerleme: _ilerleme),
      ],
    );
  }
}
