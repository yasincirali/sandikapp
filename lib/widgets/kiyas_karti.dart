import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/kiyas_provider.dart';
import '../services/fiyat_kaynagi.dart';
import '../services/kiyas_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'sandik_skeleton.dart';

/// **"Başka yere koysaydın"** — kullanıcının dönemi ile aynı paraların
/// dolar / gram altın / BIST 100'e yatırılmış hâli (Özet sekmesi).
///
/// Hesap `KiyasService`'te (kamu piyasası eşdeğeri; yöntem ve sınırlar
/// orada), seriler `kiyasSerileriProvider`'dan. Bu widget yalnızca çizer.
///
/// ## Görünüm
/// Özet'in bağlam kartlarıyla aynı yüzey (`surfaceCard`, `SandikRadius.lg`,
/// başlık `titleSmall`/`text58`) — `_BaglamKarti` private olduğu için
/// aynı tokenlarla kurulur, sınıfı kopyalanmaz.
///
/// ## Kurallar
/// * Hesaplanamayan kıyasın satırı ÇİZİLMEZ (fiyat eksik ya da çekiş kıyas
///   değerini aştı) — "₺0" ya da "—" yazmak ölçülmemiş bir sayı olurdu.
/// * Fark ▲/▼ VE kelimeyle söylenir ("3,2 puan önündesin"); renk tek
///   başına anlam taşımaz (renk körlüğü, ekran okuyucu).
/// * Kullanıcının getirisi yoksa kart hiç çizilmez: kıyaslanacak "senin"
///   yoksa kıyas da yoktur.
class KiyasKarti extends ConsumerWidget {
  /// Kullanıcının dönemi — `KiyasGirdisi.kur(...)` ile, Özet'e verilen
  /// AYNI girdilerden kurulur.
  final KiyasGirdisi girdi;

  const KiyasKarti({super.key, required this.girdi});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durum = ref.watch(kiyasProvider(girdi));
    return durum.when(
      skipLoadingOnReload: true,
      loading: () => _Kabuk(girdi: girdi, child: const _Iskelet()),
      // Seri hatası `KiyasYukleyici`'de Crashlytics'e gitti. Hata BOŞ
      // değildir (TASARIM_DILI §6.1): metin aynı ("şu an alınamadı"), yanında
      // kart içi "Tekrar dene". Eskiden kullanıcı sayfayı kapatıp açmadan
      // yeniden deneyemiyordu. Tam ekran `SandikErrorView` kart içinde fazla
      // büyük; aynı iş küçük ölçekte.
      error: (_, __) => _Kabuk(
        girdi: girdi,
        child: _VeriYok(
          onRetry: () => ref.invalidate(kiyasSerileriProvider(girdi.period)),
        ),
      ),
      data: (ozet) {
        if (ozet == null) return const SizedBox.shrink();
        if (ozet.satirlar.isEmpty) {
          return _Kabuk(girdi: girdi, child: const _VeriYok());
        }
        return _Kabuk(girdi: girdi, child: _Govde(ozet: ozet));
      },
    );
  }
}

/// Kıyas varlığının etiketi — piyasa bandıyla AYNI adlar.
String kiyasEtiketi(BuildContext context, KiyasVarligi v) {
  final l = context.l10n;
  return switch (v) {
    KiyasVarligi.dolar => l.marketDollar,
    KiyasVarligi.altin => l.marketGold,
    KiyasVarligi.bist100 => l.marketBist,
  };
}

class _Kabuk extends StatelessWidget {
  final KiyasGirdisi girdi;
  final Widget child;

  const _Kabuk({required this.girdi, required this.child});

  @override
  Widget build(BuildContext context) {
    final yerel = Localizations.maybeLocaleOf(context)?.toString() ?? 'tr_TR';
    final f = DateFormat(
      girdi.start.year == girdi.end.year ? 'd MMM' : 'd MMM y',
      yerel,
    );
    final aralik = '${f.format(girdi.start)} → ${f.format(girdi.end)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.md, vertical: SandikSpace.md2),
      decoration: context.surfaceCard(radius: SandikRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.kiyasBaslik,
            style: context.t.titleSmall?.copyWith(color: context.c.text58),
          ),
          const SizedBox(height: SandikSpace.xxs),
          Text(
            aralik,
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
          const SizedBox(height: SandikSpace.smd),
          child,
        ],
      ),
    );
  }
}

class _Govde extends StatelessWidget {
  final KiyasOzeti ozet;

  const _Govde({required this.ozet});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final g = ozet.girdi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Satir(
          etiket: context.l10n.kiyasSenin,
          getiriPct: g.getiriPct!,
          sonTRY: g.sonTRY,
          vurgulu: true,
        ),
        const SizedBox(height: SandikSpace.smd),
        Divider(color: c.hairline, height: 1),
        for (final e in ozet.satirlar.entries) ...[
          const SizedBox(height: SandikSpace.smd),
          _Satir(
            key: ValueKey('kiyas-${e.key.name}'),
            etiket: kiyasEtiketi(context, e.key),
            getiriPct: e.value.getiriPct,
            sonTRY: e.value.sonTRY,
            farkPuan: e.value.farkPuan,
          ),
        ],
        const SizedBox(height: SandikSpace.smd),
        Text(
          context.l10n.kiyasAciklama,
          style: context.t.bodySmall?.copyWith(color: c.text58),
        ),
        if (g.temettuVar) ...[
          const SizedBox(height: SandikSpace.xs),
          Text(
            context.l10n.kiyasTemettuNotu,
            style: context.t.bodySmall?.copyWith(color: c.text36),
          ),
        ],
      ],
    );
  }
}

class _Satir extends StatelessWidget {
  final String etiket;
  final double getiriPct;
  final double sonTRY;

  /// Kullanıcı − kıyas (puan). `null` → fark satırı yok (kullanıcının
  /// kendi satırı).
  final double? farkPuan;
  final bool vurgulu;

  const _Satir({
    super.key,
    required this.etiket,
    required this.getiriPct,
    required this.sonTRY,
    this.farkPuan,
    this.vurgulu = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fark = farkPuan;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiket,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodyMedium?.copyWith(
                    color: c.text90,
                    fontWeight: vurgulu ? FontWeight.w600 : null,
                  ),
                ),
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  fmtTRY(sonTRY),
                  style: context.t.bodySmall?.copyWith(color: c.text36),
                ),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmtPctIsaretli(getiriPct),
                style: context.t.numSmall.copyWith(
                  color: c.text90,
                  fontWeight: vurgulu ? FontWeight.w600 : null,
                ),
              ),
              if (fark != null) ...[
                const SizedBox(height: SandikSpace.xxs),
                _FarkEtiketi(farkPuan: fark),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// "▲ 3,2 puan önündesin" / "▼ 1,1 puan gerisindesin" / "Başa baş".
///
/// Tek ondalığa yuvarlanmış fark sıfırsa başa baş: "▲ 0,0 puan" olmayan
/// bir yönü yazardı (`reelFarkMetni` ile aynı kural).
class _FarkEtiketi extends StatelessWidget {
  final double farkPuan;

  const _FarkEtiketi({required this.farkPuan});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l10n;
    final puan = fmtNum(farkPuan.abs(), digits: 1);
    final esit = puan == fmtNum(0, digits: 1);
    final onde = farkPuan > 0;
    final ton = esit ? c.text36 : (onde ? c.gain : c.loss);
    final metin = esit
        ? l.kiyasBasaBas
        : '${onde ? '▲' : '▼'} ${onde ? l.pointsAhead(puan) : l.pointsBehind(puan)}';
    return Text(
      metin,
      style: context.t.bodySmall?.copyWith(color: ton),
    );
  }
}

class _Iskelet extends StatelessWidget {
  const _Iskelet();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(height: SandikSpace.smd),
            const SandikSkeleton(width: double.infinity, height: 14),
          ],
        ],
      );
}

class _VeriYok extends StatelessWidget {
  const _VeriYok({this.onRetry});

  /// Yalnız hata hâlinde: veri gerçekten eksikse (satır yok) yeniden denemek
  /// aynı sonucu verir, düğme konmaz.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final metin = Text(
      context.l10n.kiyasVeriYok,
      style: context.t.bodySmall?.copyWith(color: context.c.text36),
    );
    final onRetry = this.onRetry;
    if (onRetry == null) return metin;
    return Row(
      children: [
        Expanded(child: metin),
        TextButton(
          style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
          onPressed: onRetry,
          child: Text(context.l10n.retryLower),
        ),
      ],
    );
  }
}
