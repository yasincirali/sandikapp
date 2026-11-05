import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/kilometre_tasi_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/milestone_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart' show fmtPct;
import 'milestone_sheet.dart';

/// Profil'de "Kilometre taşların" rozet şeridi (Ar-Ge 1 Kas 20:45 #1,
/// müşteri raporu 21:15 YAP; yasin "önerini uygula": ücretsiz).
///
/// **Neden:** eşik geçildiğinde kutlama bir kez açılıyor, sonra hiçbir
/// yerde görünmüyordu; kişinin kendi birikim hikâyesi kayboluyordu. Şerit
/// yalnız GÖSTERİR: kutlamayı tetiklemez, kayıt yazmaz, sıklık kuralı
/// (`MilestoneRepository.canCelebrate`) değişmez.
///
/// **Ücretsiz:** rozet bir ödül; kilitli rozet ödüllendirmek yerine
/// cezalandırır. Premium kapısı yok.
///
/// Kurallar:
/// * Geçilen taş kalıcı (sunucu kaydı + bugünkü hesap,
///   `MilestoneService.koleksiyon`).
/// * Bakiye gizliyken tutar taşıyan taş tutarsız yazılır
///   (`MilestoneService.gizli`), açılan kutlama sayfası da.
/// * Sıradaki taş dolu değil çerçeveli ve üstünde "Sıradaki" yazısı var:
///   durum yalnız renkle verilmez.
/// * Ton kutlamayla aynı (fintech, sakin); oyun dili yok.
class KilometreTasiSeridi extends ConsumerWidget {
  const KilometreTasiSeridi({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final veri = ref.watch(kilometreTaslariProvider);
    if (veri == null) return const SizedBox.shrink();
    final gizli = ref.watch(balanceHiddenProvider);
    Milestone goster(Milestone m, {bool siradaki = false}) =>
        gizli ? MilestoneService.gizli(m, siradaki: siradaki) : m;

    final vitrin = [
      for (final m in MilestoneService.vitrin(veri.kazanilan)) goster(m)
    ];
    final siradaki =
        veri.siradaki == null ? null : goster(veri.siradaki!, siradaki: true);
    if (vitrin.isEmpty && siradaki == null) return const SizedBox.shrink();
    final tumu = veri.kazanilan.length > vitrin.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(
            title: context.l10n.kilometreTaslariUpper,
            trailing: tumu
                ? SandikTappable(
                    semanticLabel: context.l10n.kilometreTaslariTumuEtiket,
                    onTap: () => _tumunuAc(context,
                        [for (final m in veri.kazanilan) goster(m)], siradaki),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          minHeight: SandikTouch.min,
                          minWidth: SandikTouch.min),
                      child: Align(
                        alignment: Alignment.centerRight,
                        widthFactor: 1,
                        child: ExcludeSemantics(
                          child: Text(
                            '${context.l10n.kilometreTaslariTumu} ›',
                            style: context.t.labelLarge
                                ?.copyWith(color: context.c.amberText),
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          if (!tumu) const SizedBox(height: SandikSpace.sm),
          // Yatay kaydırma: Dynamic Type büyüdükçe rozet aşağı uzar, satır
          // taşmaz; sabit yükseklik yok.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in vitrin)
                  _Rozet(
                    m: m,
                    onTap: () => MilestoneSheet.show(context, m, tekrar: true),
                  ),
                if (siradaki != null)
                  _Rozet(
                    m: siradaki,
                    siradaki: true,
                    ilerleme: veri.ilerleme,
                    // Bakiye gizliyken kalan TUTAR yazılmaz; yüzde kalır
                    // (eşik de gizli olduğundan yüzde tutarı ele vermez).
                    kalan: gizli || veri.kalan == null
                        ? null
                        : MilestoneService.kalanKisa(veri.kalan!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _tumunuAc(
      BuildContext context, List<Milestone> hepsi, Milestone? siradaki) {
    return showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface1,
      shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
      builder: (ctx) => _TumuSayfasi(hepsi: hepsi, siradaki: siradaki),
    );
  }
}

/// Tek rozet: 46 pt daire + iki satıra kadar etiket. Dokunma alanı
/// sütunun tamamı (≥44 pt).
class _Rozet extends StatelessWidget {
  const _Rozet({
    required this.m,
    this.siradaki = false,
    this.onTap,
    this.ilerleme,
    this.kalan,
  });

  final Milestone m;
  final bool siradaki;
  final VoidCallback? onTap;

  /// Sıradaki taşta bugünkü toplam / eşik (Ar-Ge 5 Kas 21:00 #1). `null`
  /// → toplam bilinmiyor, bayrak eskisi gibi.
  final double? ilerleme;

  /// "70 bin ₺"; bakiye gizliyken `null`.
  final String? kalan;

  static const double _cap = 46;
  static const double _genislik = 84;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l10n;
    final oran = siradaki ? ilerleme : null;
    // Taban yüzde: eşiğe varmadan "%100" yazmasın.
    final yuzde = oran == null ? null : (oran * 100).floor();
    final etiket = !siradaki
        ? l.kilometreTasiEtiket(m.title)
        : yuzde == null
            ? l.kilometreTasiSiradakiEtiket(m.title)
            : kalan == null
                ? l.kilometreTasiSiradakiYuzdeEtiket(m.title, yuzde)
                : l.kilometreTasiSiradakiIlerlemeEtiket(
                    m.title, yuzde, kalan!);
    final govde = SizedBox(
      width: _genislik,
      child: Padding(
        padding: const EdgeInsets.only(right: SandikSpace.sm),
        child: Column(
          children: [
            if (yuzde != null)
              _IlerlemeHalkasi(
                  oran: oran!, yuzde: yuzde, cap: _cap)
            else
            Container(
              width: _cap,
              height: _cap,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: siradaki ? null : c.amberFill.withValues(alpha: 0.16),
                border:
                    siradaki ? Border.all(color: c.text36, width: 1.5) : null,
              ),
              child: Icon(
                siradaki ? Icons.flag_outlined : MilestoneSheet.ikonu(m.kind),
                size: SandikSpace.lg,
                color: siradaki ? c.text58 : c.amberText,
              ),
            ),
            const SizedBox(height: SandikSpace.xs2),
            if (siradaki)
              Text(
                context.l10n.kilometreTasiSiradaki,
                textAlign: TextAlign.center,
                style: context.t.labelSmall?.copyWith(color: c.text36),
              ),
            Text(
              m.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodySmall
                  ?.copyWith(color: siradaki ? c.text58 : c.text90),
            ),
            if (siradaki && kalan != null)
              Text(
                l.kilometreTasiKalan(kalan!),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelSmall?.copyWith(color: c.text36),
              ),
          ],
        ),
      ),
    );
    final icerik = ExcludeSemantics(child: govde);
    if (onTap == null) {
      return Semantics(label: etiket, child: icerik);
    }
    return SandikTappable(semanticLabel: etiket, onTap: onTap, child: icerik);
  }
}

/// Sıradaki taşın ince ilerleme halkası, ortasında yüzde. Durum renkle
/// değil yüzde metniyle de söylenir. Hareket yok: değer her açılışta
/// aynı yerde, dolma animasyonu süs olurdu (hareketi azalt sorusu da
/// böylece doğmaz).
class _IlerlemeHalkasi extends StatelessWidget {
  const _IlerlemeHalkasi(
      {required this.oran, required this.yuzde, required this.cap});

  final double oran;
  final int yuzde;
  final double cap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox.square(
      dimension: cap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: oran,
              strokeWidth: 3,
              backgroundColor: c.overlay,
              color: c.amberText,
              strokeCap: StrokeCap.round,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(SandikSpace.xs2),
              child: Text(
                fmtPct(yuzde.toDouble(), digits: 0),
                style: context.t.labelSmall?.copyWith(
                    color: c.text90, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Tümü": kazanılan bütün taşlar, en sonda sıradaki. Ayrı ekran değil,
/// sheet (sadeleştirme: yeni sayfa yok).
class _TumuSayfasi extends StatelessWidget {
  const _TumuSayfasi({required this.hepsi, this.siradaki});

  final List<Milestone> hepsi;
  final Milestone? siradaki;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: SandikSpace.smd),
          const Center(child: SandikTutamac()),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SandikSpace.lg, SandikSpace.md, SandikSpace.lg, SandikSpace.xs),
            child: Text(
              context.l10n.kilometreTaslariBaslik,
              style: context.t.headlineSmall?.copyWith(color: c.text90),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.lg),
            child: Text(
              context.l10n.kilometreTaslariNot,
              style: context.t.bodySmall?.copyWith(color: c.text58),
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                  SandikSpace.lg,
                  SandikSpace.xs,
                  SandikSpace.lg,
                  SandikSpace.lg + MediaQuery.paddingOf(context).bottom),
              children: [
                for (final m in hepsi) _Satir(m: m),
                if (siradaki != null) _Satir(m: siradaki!, siradaki: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({required this.m, this.siradaki = false});

  final Milestone m;
  final bool siradaki;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              siradaki ? Icons.flag_outlined : MilestoneSheet.ikonu(m.kind),
              size: SandikSpace.lgs,
              color: siradaki ? c.text58 : c.amberText,
            ),
            const SizedBox(width: SandikSpace.smd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    siradaki
                        ? '${context.l10n.kilometreTasiSiradaki}: ${m.title}'
                        : m.title,
                    style: context.t.bodyLarge?.copyWith(
                        color: siradaki ? c.text58 : c.text90,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: SandikSpace.xxs),
                  Text(
                    m.body,
                    style: context.t.bodySmall?.copyWith(color: c.text58),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
