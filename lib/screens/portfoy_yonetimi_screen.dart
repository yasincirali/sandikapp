import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../models/position.dart';
import '../models/portfoy.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/base_currency_provider.dart';
import '../providers/ortak_paylasimi_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/portfoy_provider.dart';
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../widgets/gorunum_cipi.dart';
import '../widgets/ortak_paylasim_sayfasi.dart';
import '../widgets/portfoy_secici.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_async_button.dart';

/// Portföy yönetimi (çoklu portföy, 0133): oluştur, yeniden adlandır,
/// sırala, sil.
///
/// "Ana" bir satır değildir (`portfoy_id IS NULL`); listenin başında sabit
/// durur, yeri değişmez, silinemez; adı değişir (`anaPortfoyAdiProvider`,
/// yasin 2026-10-10). Bir portföy İÇİNDEKİ VARLIKLARLA silinir
/// (`PortfoylerNotifier.sil`); onay sayfası silinecek varlıkları listeler.
/// Değerler
/// `portfoyOzetleriProvider`'dan (hesap build'de değil).
class PortfoyYonetimiScreen extends ConsumerWidget {
  const PortfoyYonetimiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final liste = ref.watch(portfoylerProvider).valueOrNull ?? const [];
    final ozet = ref.watch(portfoyOzetleriProvider);
    final baz = ref.watch(gosterimBazParaProvider);
    final hp = SandikSpace.screenH(context);
    final anaAdi = ref.watch(anaPortfoyAdiProvider) ?? l.portfoyAnaUzun;
    // Ortak görünürlüğü (0135). Tek ortakta her satır "Ayşe görüyor /
    // görmüyor" der — kararı portföyün yanında görmek "neyi paylaşıyorum"
    // sorusunun en kısa cevabı. Birden çok ortakta satır sessiz kalır
    // (kimin neyi gördüğü tek satıra sığmaz); alttaki ortak satırları söyler.
    final paylasimVar = ref.watch(ortakPaylasimSecimiVarProvider);
    final ortaklar = paylasimVar
        ? [
            for (final p in ref.watch(partnersProvider).valueOrNull ??
                const <PartnerAccount>[])
              p.user
          ]
        : const <AppUser>[];
    final tekOrtak = ortaklar.length == 1 ? ortaklar.single : null;
    final tekPaylasim = tekOrtak == null
        ? null
        : ref.watch(benimPaylasimimProvider(tekOrtak.id));
    ({String metin, bool gizli})? durum(String? id) {
      if (tekOrtak == null || tekPaylasim == null) return null;
      final ad = GorunumCipi.ilkAd(tekOrtak.displayName);
      final gorur = tekPaylasim.gorur(id);
      return (
        metin: gorur ? l.portfoyOrtakGoruyor(ad) : l.portfoyOrtakGizli(ad),
        gizli: !gorur,
      );
    }

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(title: l.portfoyYonetimiBaslik),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hp, SandikSpace.sm, hp, 0),
              child: Text(
                l.portfoyYonetimiAciklama,
                style: context.t.bodyMedium?.copyWith(color: context.c.text58),
              ),
            ),
            const SizedBox(height: SandikSpace.md),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hp),
              // Ana silinemez (silinen portföylerin lotları oraya döner)
              // ama adı değişir (yasin 2026-10-10).
              child: _Satir(
                key: const ValueKey('portfoy-satir-ana'),
                ad: anaAdi,
                alt: l.portfoyAnaAciklama,
                deger: baz.fmt(ozet[null]?.deger ?? 0),
                ortakDurumu: durum(null),
                onYenidenAdlandir: () => showPortfoyAdiSayfasi(
                  context,
                  baslik: l.portfoyYenidenAdlandir,
                  dugme: l.save,
                  baslangic: anaAdi,
                  kaydet: (ad) => ref
                      .read(anaPortfoyAdiProvider.notifier)
                      .yenidenAdlandir(ad),
                ),
              ),
            ),
            const SizedBox(height: SandikSpace.sm),
            if (liste.length > 1)
              Padding(
                padding: EdgeInsets.fromLTRB(hp, 0, hp, SandikSpace.xs),
                child: Text(
                  l.portfoySiralaIpucu,
                  style: context.t.bodySmall?.copyWith(color: context.c.text36),
                ),
              ),
            Expanded(
              child: ReorderableListView.builder(
                padding: EdgeInsets.fromLTRB(hp, 0, hp, SandikSpace.lg),
                itemCount: liste.length,
                // Sürükleme tutamacı satırın kendisi (uzun basış): ayrı bir
                // tutamaç ikonu dar ekranda adı kısaltırdı.
                buildDefaultDragHandles: true,
                onReorderItem: (eski, yeni) {
                  final ids = [for (final p in liste) p.id];
                  ids.insert(yeni, ids.removeAt(eski));
                  CrashReporter.arkaPlan(
                    ref
                        .read(portfoylerProvider.notifier)
                        .sirala(ids)
                        .catchError((Object e) {
                      if (context.mounted) {
                        sandikSnackError(context, e,
                            prefix: l.portfoyKaydedilemedi);
                      }
                    }),
                    reason: 'portfoyYonetimi.sirala',
                  );
                },
                itemBuilder: (context, i) {
                  final p = liste[i];
                  return Padding(
                    key: ValueKey('portfoy-satir-${p.id}'),
                    padding: const EdgeInsets.only(bottom: SandikSpace.sm),
                    child: _Satir(
                      ad: p.ad,
                      deger: baz.fmt(ozet[p.id]?.deger ?? 0),
                      ortakDurumu: durum(p.id),
                      onYenidenAdlandir: () => showPortfoyAdiSayfasi(
                        context,
                        baslik: l.portfoyYenidenAdlandir,
                        dugme: l.save,
                        baslangic: p.ad,
                        kaydet: (ad) => ref
                            .read(portfoylerProvider.notifier)
                            .yenidenAdlandir(p.id, ad),
                      ),
                      onSil: () => _silOnayi(context, ref, p),
                    ),
                  );
                },
              ),
            ),
            if (ortaklar.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(hp, 0, hp, SandikSpace.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SandikSectionHeader(title: l.portfoyOrtakBolum),
                    for (final o in ortaklar)
                      Padding(
                        padding: const EdgeInsets.only(bottom: SandikSpace.sm),
                        child: SandikCard(
                          padding: const EdgeInsets.fromLTRB(SandikSpace.md,
                              SandikSpace.sm, SandikSpace.sm, SandikSpace.xs),
                          child: Row(
                            children: [
                              GorunumCipi.avatar(context, o, boy: 32),
                              const SizedBox(width: SandikSpace.smd),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(GorunumCipi.ilkAd(o.displayName),
                                        style: context.t.titleSmall?.copyWith(
                                            color: context.c.text90,
                                            fontWeight: FontWeight.w700)),
                                    OrtakPaylasimSatiri(
                                        ortak: o, ustBosluk: false),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(hp, 0, hp, SandikSpace.md),
              child: FilledButton.icon(
                key: const ValueKey('portfoy-yeni-dugmesi'),
                onPressed: () => CrashReporter.arkaPlan(
                    yeniPortfoyAkisi(context, ref, sec: false),
                    reason: 'portfoyYonetimi.yeni'),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.portfoyYeni),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Silme onayı alt sayfada (`showSandikSheet`).
  ///
  /// yasin 2026-10-10: içinde varlık olan portföyde varlıklar LİSTELENİR ve
  /// onay öyle alınır (kullanıcı neyin silineceğini görerek karar verir);
  /// boş portföyde yalnız kısa "emin misin". Varlıklar portföyle birlikte
  /// silinir, Ana'ya taşınmaz ("taşıma yapmamalıyız"); listede görünmeyen
  /// kapanmış pozisyon geçmişi de silindiği için sayısı ayrıca söylenir.
  /// Silme düğmenin İÇİNDE koşar; hata sayfanın üstünde söylenir ve sayfa
  /// açık kalır.
  Future<void> _silOnayi(
    BuildContext context,
    WidgetRef ref,
    Portfoy p,
  ) async {
    final l = context.l10n;
    final pozisyonlar = ref.read(portfoyPozisyonlariProvider(p.id));
    final baz = ref.read(gosterimBazParaProvider);
    // Kapanmış pozisyonların geçmişi de silinir; listede görünmediği için
    // sayısı ayrıca söylenir.
    final acik = {for (final v in pozisyonlar) v.pozisyon.key};
    final gecmis = [
      for (final g in portfoyunSilinecekGruplari(
          ref.read(portfolioProvider).valueOrNull?.assets ?? const [],
          p.id,
          {
            for (final x in ref.read(portfoylerProvider).valueOrNull ??
                const <Portfoy>[])
              x.id
          },
          ref.read(authProvider).valueOrNull?.id))
        if (!acik.contains(positionKey(g.first))) ...g,
    ].length;
    final silindi = await showSandikSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(SandikSpace.screenH(ctx), SandikSpace.md,
              SandikSpace.screenH(ctx), SandikSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SandikTutamac()),
              const SizedBox(height: SandikSpace.md),
              Text(
                l.portfoySilBaslik(p.ad),
                style: ctx.t.titleLarge?.copyWith(
                    color: ctx.c.text90, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: SandikSpace.sm),
              Text(
                [
                  if (pozisyonlar.isNotEmpty)
                    l.portfoySilAciklama
                  else
                    l.portfoySilBosAciklama,
                  if (gecmis > 0) l.portfoySilGecmisAciklama(gecmis),
                ].join(' '),
                style: ctx.t.bodyMedium?.copyWith(color: ctx.c.text58),
              ),
              if (pozisyonlar.isNotEmpty) ...[
                const SizedBox(height: SandikSpace.md),
                Text(
                  l.portfoySilVarliklar(pozisyonlar.length),
                  style: ctx.t.labelLarge?.copyWith(color: ctx.c.text58),
                ),
                const SizedBox(height: SandikSpace.sm),
                SandikCard(
                  key: const ValueKey('portfoy-sil-varliklar'),
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.md, vertical: SandikSpace.xs),
                  child: Column(
                    children: [
                      for (final (i, v) in pozisyonlar.indexed) ...[
                        if (i > 0) Divider(height: 1, color: ctx.c.hairline),
                        _SilinecekVarlik(
                          gorunum: v.pozisyon.asDisplayAsset(),
                          miktar: v.pozisyon.totalQuantity,
                          deger: baz.fmt(v.deger),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: SandikSpace.lg),
              SandikAsyncButton.kompakt(
                key: const ValueKey('portfoy-sil-onay'),
                style: FilledButton.styleFrom(
                  backgroundColor: ctx.c.danger,
                  foregroundColor: ctx.c.onStatus,
                ),
                onPressed: () async {
                  try {
                    await ref.read(portfoylerProvider.notifier).sil(p.id);
                  } catch (e, st) {
                    CrashReporter.report(e, st, reason: 'portfoyYonetimi.sil');
                    if (ctx.mounted) {
                      sandikSnackError(ctx, e, prefix: l.portfoySilinemedi);
                    }
                    return;
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: Text(
                    pozisyonlar.isNotEmpty
                        ? l.portfoyVarliklarlaSil
                        : l.portfoySil,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.cancel),
              ),
            ],
          ),
        ),
      ),
    );
    if (silindi == true && context.mounted) {
      sandikSnack(
          context,
          pozisyonlar.isNotEmpty
              ? l.portfoySilindi(p.ad)
              : l.portfoySilindiBos(p.ad),
          kind: SandikSnackKind.success);
    }
  }
}

/// Silme onayındaki tek varlık satırı: ad, miktar, güncel değer. Metin
/// tam okunur (çok satıra kayar, kesilmez); ekran okuyucu tek cümle duyar.
class _SilinecekVarlik extends StatelessWidget {
  const _SilinecekVarlik({
    required this.gorunum,
    required this.miktar,
    required this.deger,
  });

  final Asset gorunum;
  final double miktar;
  final String deger;

  @override
  Widget build(BuildContext context) {
    final miktarMetni =
        gorunum.miktarMetni(miktar, (v, d) => fmtNum(v, digits: d));
    // Ad önde (Portföy satırıyla aynı); kod yalnız fon/hissede, miktarın
    // yanında — ham `TEFAS:AFT` / `ALTIN_GRAM` gösterilmez.
    final ad = gorunum.name.trim().isNotEmpty ? gorunum.name : gorunum.ticker;
    final alt = gorunum.showTicker
        ? '${gorunum.displayTicker} · $miktarMetni'
        : miktarMetni;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ad,
                      style: context.t.titleSmall?.copyWith(
                          color: context.c.text90,
                          fontWeight: FontWeight.w600)),
                  Text(alt,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58)),
                ],
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Text(deger,
                style: context.t.bodyMedium?.copyWith(
                    color: context.c.text90, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({
    super.key,
    required this.ad,
    required this.deger,
    this.alt,
    this.ortakDurumu,
    this.onYenidenAdlandir,
    this.onSil,
  });

  final String ad;
  final String deger;
  final String? alt;

  /// Tek ortakta "Ayşe görüyor / görmüyor" (0135); yoksa satır yok.
  final ({String metin, bool gizli})? ortakDurumu;
  final VoidCallback? onYenidenAdlandir;
  final VoidCallback? onSil;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SandikCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad,
                  style: context.t.titleSmall?.copyWith(
                      color: context.c.text90, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  deger,
                  style:
                      context.t.bodyMedium?.copyWith(color: context.c.text58),
                ),
                if (alt != null) ...[
                  const SizedBox(height: SandikSpace.xxs),
                  Text(
                    alt!,
                    style:
                        context.t.bodySmall?.copyWith(color: context.c.text36),
                  ),
                ],
                if (ortakDurumu case final d?) ...[
                  const SizedBox(height: SandikSpace.sm),
                  // Hap: gördüğü portföy sakin, gizlenen amber — liste
                  // taranınca "neyi gizliyorum" tek bakışta okunur.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
                    decoration: context.chip(
                        selected: d.gizli, radius: SandikRadius.sm),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          d.gizli
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 14,
                          color:
                              d.gizli ? context.c.amberText : context.c.text58,
                        ),
                        const SizedBox(width: SandikSpace.xs),
                        Text(
                          d.metin,
                          style: context.t.labelMedium?.copyWith(
                              color: d.gizli
                                  ? context.c.amberText
                                  : context.c.text58,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onYenidenAdlandir != null)
            IconButton(
              tooltip: l.portfoyYenidenAdlandir,
              constraints: const BoxConstraints(
                  minWidth: SandikTouch.min, minHeight: SandikTouch.min),
              onPressed: onYenidenAdlandir,
              icon: Icon(Icons.edit_outlined, color: context.c.text58),
            ),
          if (onSil != null)
            IconButton(
              tooltip: l.portfoySil,
              constraints: const BoxConstraints(
                  minWidth: SandikTouch.min, minHeight: SandikTouch.min),
              onPressed: onSil,
              icon: Icon(Icons.delete_outline_rounded, color: context.c.danger),
            ),
        ],
      ),
    );
  }
}
