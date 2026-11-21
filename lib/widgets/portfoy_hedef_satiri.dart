// Portföy hedefi (Premium, Ar-Ge 15 Kas 17:03 #2).
//
// Amaca göre ayırmanın asıl karşılığı "Çocuğun için: hedefe %42, ₺290K
// kaldı, plandasın" cümlesi. Hedef Ben/Birlikte/ortak görünümleri için
// vardı; portföy hedefi aynı aileye yeni anahtarla eklenir
// (`portfoyHedefKapsami`), sayfa aynı (`showHedefSheet`), cümle Bugün
// kartının kısa hâliyle aynı parçalardan kurulur — ikinci bir hedef dili
// yazılmaz. Hesap `portfoyHedefDurumuProvider`'da (build'de değil).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../models/gorunum_kapsami.dart';
import '../providers/portfolio_provider.dart';
import '../providers/portfoy_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/hedef_ritmi.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'hedef_sheet.dart';
import 'para_akisi_karti.dart' show KilitSatiri;

/// Hedef satırının tek cümlesi: "Hedefe %42 · ₺290K kaldı · plandasın".
/// Ritim yoksa (gün yok, defter kısa) son parça düşer; ulaşıldıysa
/// "Hedef · Ulaşıldı". Bakiye gizliyken tutarlar `••••`, oran görünür
/// (Bugün kartıyla aynı kural).
String portfoyHedefMetni(AppLocalizations l, KapsamHedefDurumu d,
    {required bool gizli}) {
  if (d.ulasildi) return '${l.todayGoalLabel} · ${l.todayGoalDone}';
  final kalan = gizli ? '••••' : fmtTRYCompactSade(d.kalan);
  return [
    l.todayGoalProgressTitle(d.yuzde),
    l.todayGoalLeftShort(kalan),
    if (d.ritim case final r?)
      hedefRitmiMetinleri(l, r, gizli: gizli, tutar: fmtTRYCompactSade).orta,
  ].join(' · ');
}

/// Portföyün hedef sayfası ([id] `null` = Ana). Sayfa kimin için olduğunu
/// [ad] ile söyler; çipler ve "plandasın" o portföyün değeri ve defteriyle.
Future<void> portfoyHedefSayfasiniAc(
  BuildContext context,
  WidgetRef ref, {
  required String? id,
  required String ad,
}) {
  final s = ref.read(portfolioProvider).valueOrNull;
  final liste = ref.read(portfoylerProvider).valueOrNull ?? const [];
  final defter = s == null
      ? const <Asset>[]
      : portfoyeGoreBol(s.assets, {for (final p in liste) p.id})[id] ??
          const <Asset>[];
  return showHedefSheet(
    context,
    ref,
    kapsam: portfoyHedefKapsami(id),
    etiket: ad,
    deger: ref.read(portfoyOzetleriProvider)[id]?.deger,
    sonUcAyOrtalamasi: HedefRitmiService.sonUcAyOrtalamasi(defter,
        now: portfoyHedefSaati()),
    gizli: ref.read(balanceHiddenProvider),
  );
}

/// Portföy sekmesinin üstünde, seçili portföyün hedefi: tek satır cümle +
/// ince ilerleme çizgisi. Tümü seçiliyken, hedef yokken ya da özellik bu
/// kullanıcıda açık değilken (Premium bitti: değer durur, gösterim kapanır)
/// hiç yer kaplamaz. Dokununca hedef sayfası.
class PortfoyHedefSatiri extends ConsumerWidget {
  const PortfoyHedefSatiri({super.key, this.bosluk = EdgeInsets.zero});

  /// Satır ÇİZİLDİĞİNDE çevresine bırakılacak boşluk.
  final EdgeInsets bosluk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secim = ref.watch(portfoyKapsamiProvider).secim;
    if (secim == PortfoySecimi.tumu) return const SizedBox.shrink();
    final id = secim == PortfoySecimi.ana ? null : secim;
    final d = ref.watch(portfoyHedefDurumuProvider(id));
    final l = context.l10n;
    final ad = id == null
        ? (ref.watch(anaPortfoyAdiProvider) ?? l.portfoyAnaUzun)
        : (ref
                .watch(portfoylerProvider)
                .valueOrNull
                ?.where((p) => p.id == id)
                .firstOrNull
                ?.ad ??
            '');
    if (d == null) {
      // Premium bitince kayıtlı hedef kaybolmaz, sessizce de yok olmaz
      // (2026-11-21, bugun_karti "Hedef günün kayıtlı" ile aynı gerekçe):
      // kilit satırı hedefin durduğunu söyler. Hedef hiç yoksa ya da özellik
      // gizliyse (paywall kapalı) hiçbir şey çizilmez. Tutar/yüzde sızmaz.
      if (ref.watch(hedefTarihiDurumuProvider) != OzellikDurumu.kilitli ||
          ref.watch(kapsamHedefiProvider(portfoyHedefKapsami(id))) <= 0) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: bosluk,
        child: KilitSatiri(
          metin: l.portfoyHedefKayitliKilit(ad),
          kaynak: 'portfoy_hedef',
          ozellik: 'hedef_tarihi',
          kilitEtiketi: l.goalDateLockedLabel,
        ),
      );
    }
    final metin =
        portfoyHedefMetni(l, d, gizli: ref.watch(balanceHiddenProvider));
    return Padding(
      padding: bosluk,
      child: SandikTappable(
        key: const ValueKey('portfoy-hedef-satiri'),
        semanticLabel: metin,
        onTap: () => portfoyHedefSayfasiniAc(context, ref, id: id, ad: ad),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Text(
                  metin,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodySmall?.copyWith(color: context.c.text58),
                ),
              ),
              const SizedBox(height: SandikSpace.xs),
              PortfoyHedefCizgisi(oran: d.oran),
            ],
          ),
        ),
      ),
    );
  }
}

/// İnce ilerleme çizgisi (hedef sayfasının önizlemesiyle aynı çizim).
class PortfoyHedefCizgisi extends StatelessWidget {
  const PortfoyHedefCizgisi({super.key, required this.oran});

  final double oran;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: SandikRadius.smAll,
        child: LinearProgressIndicator(
          value: oran,
          minHeight: SandikSpace.xxs,
          backgroundColor: context.c.hairline,
          valueColor: AlwaysStoppedAnimation(context.c.amberText),
        ),
      );
}
