// Halka arz takvimi (F6, ADR-3).
//
// Tamamen yeni yüzey: veri `HalkaArzService` (Pages JSON → dosya/gömülü
// kopya), gruplama `halkaArzGorunumuProvider`'da. Var olan hiçbir hesaba
// dokunmaz; katılım kaydı mevcut ekleme formuna ön dolu açılır ve NORMAL
// ALIM lot'u olarak kaydedilir (yeni işlem türü yok).
//
// Giriş noktası Profil'deki [HalkaArzProfilSatiri]; bayrak
// (`ipo_calendar_enabled`) kapalıyken satır hiç çizilmez, ekran erişilmez.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../models/halka_arz.dart';
import '../providers/halka_arz_provider.dart';
import '../services/analytics_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/sandik_skeleton.dart';
import '../utils/sandik_snack.dart';
import 'add_asset_screen.dart';

class HalkaArzScreen extends ConsumerStatefulWidget {
  const HalkaArzScreen({super.key, this.yuzey = 'profile'});

  /// Analytics `ipo_viewed.surface` — ekranın nereden açıldığı.
  final String yuzey;

  @override
  ConsumerState<HalkaArzScreen> createState() => _HalkaArzScreenState();
}

class _HalkaArzScreenState extends ConsumerState<HalkaArzScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logIpoViewed(surface: widget.yuzey);
  }

  /// Aşağı çekince bellek önbelleği atlanır; görünüm yeniden kurulur.
  Future<void> _yenile() async {
    await ref.read(halkaArzServiceProvider).yukle(zorla: true);
    ref.invalidate(halkaArzGorunumuProvider);
    await ref.read(halkaArzGorunumuProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(halkaArzGorunumuProvider);
    return Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(title: l.ipoTitle),
      body: async.when(
        // Önceki değer varken (yenileme) iskelet yerine liste kalır.
        skipLoadingOnRefresh: true,
        loading: () => const SandikSkeletonList(rows: 5),
        error: (e, _) => SandikErrorView(
          error: e,
          onRetry: () => ref.invalidate(halkaArzGorunumuProvider),
        ),
        data: (g) => RefreshIndicator.adaptive(
          color: context.c.amberText,
          onRefresh: _yenile,
          child: _Liste(gorunum: g),
        ),
      ),
    );
  }
}

class _Liste extends ConsumerWidget {
  const _Liste({required this.gorunum});
  final HalkaArzGorunumu gorunum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final h = SandikSpace.screenH(context);
    final tarih = gorunum.guncelleme == null
        ? null
        : _gunAy(context, gorunum.guncelleme!, yil: true);
    final cevrimdisi = gorunum.kaynak != HalkaArzKaynagi.ag;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(h, SandikSpace.sm, h, SandikSpace.xl),
      children: [
        // Ağdan gelmeyen liste eski olabilir; kullanıcı bunu bilmeli.
        if (cevrimdisi) ...[
          _Not(
            ikon: Icons.cloud_off_outlined,
            metin: tarih == null
                ? l.ipoOfflineNoDate
                : l.ipoOfflineNote(tarih),
          ),
          const SizedBox(height: SandikSpace.md),
        ],
        if (gorunum.bos)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.xl),
            child: Text(
              l.ipoEmpty,
              textAlign: TextAlign.center,
              style: context.t.bodyLarge?.copyWith(color: context.c.text58),
            ),
          ),
        for (final e in gorunum.gruplar.entries) ...[
          SandikSectionHeader(
            title: ustHarf(_grupAdi(l, e.key), l),
            count: e.value.length,
          ),
          const SizedBox(height: SandikSpace.sm),
          for (final a in e.value) ...[
            _Satir(arz: a, durum: e.key),
            const SizedBox(height: SandikSpace.sm),
          ],
          const SizedBox(height: SandikSpace.md),
        ],
        Text(
          l.ipoDisclaimer,
          style: context.t.bodySmall?.copyWith(color: context.c.text58),
        ),
        if (tarih != null && !cevrimdisi) ...[
          const SizedBox(height: SandikSpace.xs),
          Text(
            l.ipoListDate(tarih),
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
        ],
      ],
    );
  }
}

class _Not extends StatelessWidget {
  const _Not({required this.ikon, required this.metin});
  final IconData ikon;
  final String metin;

  @override
  Widget build(BuildContext context) {
    return SandikCard(
      padding: const EdgeInsets.all(SandikSpace.smd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 18, color: context.c.text58),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Text(
              metin,
              style: context.t.bodyMedium?.copyWith(color: context.c.text90),
            ),
          ),
        ],
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({required this.arz, required this.durum});
  final HalkaArz arz;
  final HalkaArzDurumu durum;

  @override
  Widget build(BuildContext context) {
    final alt = _tarihSatiri(context, arz, durum);
    final fiyat = arz.fiyat;
    return SandikCard(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.md, vertical: SandikSpace.smd),
      onTap: () => halkaArzDetayiniAc(context, arz, durum),
      child: Semantics(
        button: true,
        label: '${arz.kod}, ${arz.sirket}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    arz.kod,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.c.text90,
                    ),
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                // Bilinmeyen fiyat "—": 0 ya da tahmin YAZILMAZ.
                Text(
                  fiyat == null ? '—' : fmtTRYFiyat(fiyat),
                  style: context.t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.c.text90,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SandikSpace.xxs),
            Text(
              arz.sirket,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
            if (alt != null) ...[
              const SizedBox(height: SandikSpace.xs),
              Text(
                alt,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.bodySmall?.copyWith(
                  color: durum == HalkaArzDurumu.talepToplaniyor
                      ? context.c.amberText
                      : context.c.text58,
                  fontWeight: durum == HalkaArzDurumu.talepToplaniyor
                      ? FontWeight.w700
                      : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Satırın alt çizgisi: talep aşamasında talep aralığı, sonrasında işlem
/// başlangıcı. Tarih yoksa satır çizilmez (boşluk "?" ile doldurulmaz).
String? _tarihSatiri(BuildContext context, HalkaArz a, HalkaArzDurumu d) {
  final l = context.l10n;
  final talep = _talepAraligi(context, a);
  final islem =
      a.islemBaslangic == null ? null : _gunAy(context, a.islemBaslangic!);
  switch (d) {
    case HalkaArzDurumu.talepToplaniyor:
    case HalkaArzDurumu.yaklasan:
      return talep == null ? null : l.ipoRowTalep(talep);
    case HalkaArzDurumu.islemBekliyor:
    case HalkaArzDurumu.islemGoruyor:
    case HalkaArzDurumu.bilinmiyor:
      if (islem != null) return l.ipoRowIslem(islem);
      return talep == null ? null : l.ipoRowTalep(talep);
  }
}

String? _talepAraligi(BuildContext context, HalkaArz a, {bool yil = false}) {
  final b = a.talepBaslangic;
  final s = a.talepBitis;
  if (b == null && s == null) return null;
  if (b == null) return _gunAy(context, s!, yil: yil);
  if (s == null || s == b) return _gunAy(context, b, yil: yil);
  return '${_gunAy(context, b)} - ${_gunAy(context, s, yil: yil)}';
}

String _gunAy(BuildContext context, DateTime t, {bool yil = false}) =>
    DateFormat(yil ? 'd MMM yyyy' : 'd MMM', context.l10n.localeName)
        .format(t);

String _grupAdi(AppLocalizations l, HalkaArzDurumu d) => switch (d) {
      HalkaArzDurumu.talepToplaniyor => l.ipoGroupTalep,
      HalkaArzDurumu.yaklasan => l.ipoGroupYaklasan,
      HalkaArzDurumu.islemBekliyor => l.ipoGroupIslemBekliyor,
      HalkaArzDurumu.islemGoruyor => l.ipoGroupIslemGoruyor,
      HalkaArzDurumu.bilinmiyor => l.ipoGroupBilinmiyor,
    };

/// JSON'daki dağıtım metni veridir; bilinen değerler çevrilir, tanınmayan
/// olduğu gibi yazılır.
String? _dagitimMetni(AppLocalizations l, HalkaArz a) =>
    switch (a.dagitimTuru) {
      HalkaArzDagitim.esit => l.ipoDagitimEsit,
      HalkaArzDagitim.oransal => l.ipoDagitimOransal,
      HalkaArzDagitim.diger => a.dagitim,
      null => null,
    };

/// Detay alt sayfası. Satırdan ve testlerden açılır.
Future<void> halkaArzDetayiniAc(
  BuildContext context,
  HalkaArz arz,
  HalkaArzDurumu durum,
) {
  return showSandikSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.c.surface1,
    shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
    builder: (_) => HalkaArzDetay(arz: arz, durum: durum),
  );
}

class HalkaArzDetay extends ConsumerWidget {
  const HalkaArzDetay({super.key, required this.arz, required this.durum});
  final HalkaArz arz;
  final HalkaArzDurumu durum;

  Future<void> _kaynagiAc(BuildContext context) async {
    final uri = Uri.tryParse(arz.kaynak);
    var ok = false;
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        // Tarayıcı yoksa/eklenti yanıt vermezse aşağıdaki uyarı yeterli;
        // hata kullanıcı eylemine bağlı, raporlanacak bir arıza değil.
        ok = false;
      }
    }
    if (!ok && context.mounted) {
      sandikSnack(context, context.l10n.ipoSourceFailed,
          kind: SandikSnackKind.warning);
    }
  }

  Future<void> _katildim(BuildContext context, WidgetRef ref) async {
    final simdi = ref.read(halkaArzSaatProvider)();
    // Detay sayfası kapanır; form Halka arzlar ekranının üstünde açılır.
    final nav = Navigator.of(context);
    final ust = nav.context;
    nav.pop();
    final sonuc = await pushGuarded<Object>(
      ust,
      adaptiveRoute(
        fullscreenDialog: true,
        builder: (_) => AddAssetScreen(
          prefillTicker: arz.sembol,
          prefillName: arz.sirket,
          prefillType: AssetType.hisse,
          prefillPrice: arz.fiyat,
          prefillDate: halkaArzAlisTarihi(arz, simdi),
        ),
      ),
    );
    // Form kayıtta `true` ya da `AlarmAdayi` döner; geri tuşu `null`.
    if (sonuc == null || sonuc == false) return;
    unawaited(AnalyticsService.instance.logIpoParticipationRecorded());
    if (ust.mounted) {
      sandikSnack(ust, ust.l10n.ipoParticipationSaved,
          kind: SandikSnackKind.success);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final talep = _talepAraligi(context, arz, yil: true);
    final islem = arz.islemBaslangic == null
        ? null
        : _gunAy(context, arz.islemBaslangic!, yil: true);
    final bilgiTarihi = arz.guncelleme == null
        ? null
        : _gunAy(context, arz.guncelleme!, yil: true);
    final fiyat = arz.fiyat;
    final kaydedilebilir = halkaArzKatilimKaydedilebilir(durum);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        SandikSpace.lgs,
        SandikSpace.lgs,
        SandikSpace.lgs,
        SandikSpace.lgs + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            arz.kod,
            style: context.t.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: context.c.text90,
            ),
          ),
          const SizedBox(height: SandikSpace.xxs),
          Text(
            arz.sirket,
            style: context.t.bodyLarge?.copyWith(color: context.c.text58),
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            ustHarf(_grupAdi(l, durum), l),
            style: context.t.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: context.c.amberText,
            ),
          ),
          const SizedBox(height: SandikSpace.md),
          _Alan(l.ipoFieldTalep, talep),
          _Alan(l.ipoFieldFiyat, fiyat == null ? null : fmtTRYFiyat(fiyat)),
          _Alan(l.ipoFieldDagitim, _dagitimMetni(l, arz)),
          _Alan(l.ipoFieldIslem, islem),
          _Alan(l.ipoFieldPazar, arz.pazar),
          _Alan(l.ipoFieldGuncelleme, bilgiTarihi),
          const SizedBox(height: SandikSpace.md),
          Text(
            !kaydedilebilir
                ? l.ipoParticipateLater
                : fiyat == null
                    ? l.ipoParticipateNoPrice
                    // İşlem başlamışsa "işlem başlayana kadar halka arz
                    // fiyatıyla görünür" cümlesi yanlış olurdu (emülatör
                    // testi 2, #15): hisse zaten canlı fiyatla görünür.
                    : durum == HalkaArzDurumu.islemGoruyor
                        ? l.ipoParticipateHintTraded
                        : l.ipoParticipateHint,
            style: context.t.bodyMedium?.copyWith(
              color: kaydedilebilir && fiyat == null
                  ? context.c.amberText
                  : context.c.text58,
            ),
          ),
          if (kaydedilebilir) ...[
            const SizedBox(height: SandikSpace.md),
            SizedBox(
              height: SandikTouch.min + SandikSpace.sm2,
              child: FilledButton(
                onPressed: () => _katildim(context, ref),
                style: FilledButton.styleFrom(
                  backgroundColor: context.c.amberFill,
                  foregroundColor: context.c.onAmber,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SandikRadius.md)),
                  elevation: 0,
                ),
                child: Text(
                  l.ipoParticipate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Renk açıkça `onAmber` (açık tema denetimi 2026-10-08):
                  // `titleMedium` kendi rengini (`text90`) taşır ve düğmenin
                  // `foregroundColor`'ını ezer — koyu temada amber üstüne
                  // beyaz 1,87:1 kalıyordu.
                  style: context.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800, color: context.c.onAmber),
                ),
              ),
            ),
          ],
          const SizedBox(height: SandikSpace.sm),
          TextButton.icon(
            onPressed: () => _kaynagiAc(context),
            style: TextButton.styleFrom(
              minimumSize: SandikTouch.minSize,
              foregroundColor: context.c.amberText,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(l.ipoOpenSource),
          ),
        ],
      ),
    );
  }
}

/// Etiket–değer satırı. Değer yoksa "—": bilinmeyen alan boş bırakılmaz
/// ki kullanıcı eksik bilgiyi "sıfır" sanmasın, ama tahmin de yazılmaz.
class _Alan extends StatelessWidget {
  const _Alan(this.etiket, this.deger);
  final String etiket;
  final String? deger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              etiket,
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
          ),
          const SizedBox(width: SandikSpace.smd),
          Flexible(
            child: Text(
              deger ?? '—',
              textAlign: TextAlign.end,
              style: context.t.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.c.text90,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Profil ekranındaki giriş satırı. Bayrak kapalıyken HİÇ yer kaplamaz —
/// Profil'in yerleşimi bayrak kapalıyken birebir eskisi gibi kalır.
class HalkaArzProfilSatiri extends ConsumerWidget {
  const HalkaArzProfilSatiri({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(halkaArzEtkinProvider)) return const SizedBox.shrink();
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.lg),
      child: SandikCard(
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.md, vertical: SandikSpace.smd),
        onTap: () => pushGuarded<void>(
          context,
          adaptiveRoute<void>(builder: (_) => const HalkaArzScreen()),
        ),
        child: Semantics(
          button: true,
          child: Row(
            children: [
              Icon(Icons.event_note_outlined,
                  size: 22, color: context.c.amberText),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.ipoTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.c.text90,
                      ),
                    ),
                    Text(
                      l.ipoProfileRowSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.c.text58),
            ],
          ),
        ),
      ),
    );
  }
}
