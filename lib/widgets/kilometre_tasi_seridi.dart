import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/kilometre_tasi_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/milestone_service.dart';
import '../theme/sandik.dart';
import 'milestone_sheet.dart';

/// Profil'de "Kilometre taşların" (Ar-Ge 1 Kas 20:45 #1, müşteri raporu
/// 21:15 YAP; yasin "önerini uygula": ücretsiz).
///
/// **Neden:** eşik geçildiğinde kutlama bir kez açılıyor, sonra hiçbir
/// yerde görünmüyordu; kişinin kendi birikim hikâyesi kayboluyordu. Satır
/// yalnız GÖSTERİR: kutlamayı tetiklemez, kayıt yazmaz, sıklık kuralı
/// (`MilestoneRepository.canCelebrate`) değişmez.
///
/// **Tek satır (Profil yeniden tasarımı, yasin 7 Kas):** önce yatay rozet
/// şeridiydi; beşinci rozet ekran kenarında yarım kalıyor, sıradaki taşın
/// ilerlemesi küçük bir halkada okunmuyordu. Taslaktaki "12 eşit kart"
/// da reddedildi (aynı ağırlıkta 12 kart hiyerarşi kurmaz). Şimdi tek
/// soru yanıtlanır: "sıradaki ne, ne kadar kaldı": "Sıradaki: 5 milyon ₺",
/// ilerleme çubuğu, "2,3 milyon ₺ kaldı", sağda merdivendeki yer
/// ("8 / 10", [MilestoneService.esikSayaci]). Geçilen taşlar altında küçük
/// işaretler; satıra dokununca tam liste (sheet). Kutlamayı yeniden açma ve
/// Paylaş o listeden (satıra dokun).
///
/// **Ücretsiz:** rozet bir ödül; kilitli rozet ödüllendirmek yerine
/// cezalandırır. Premium kapısı yok.
///
/// Kurallar:
/// * Geçilen taş kalıcı (sunucu kaydı + bugünkü hesap,
///   `MilestoneService.koleksiyon`).
/// * Bakiye gizliyken tutar yazılmaz (`MilestoneService.gizli`, kalan
///   tutar yok); çubuk ve "8 / 10" kalır: eşik de gizli olduğundan oran
///   tutarı ele vermez (eski halkadaki yüzde kuralının aynısı).
/// * Toplam bilinmiyorsa (≤ 0) çubuk ve kalan çizilmez; hepsi geçildiyse
///   "Bütün portföy eşiklerini geçtin". Uydurma sayı yok.
/// * Durum yalnız renkle verilmez: çubuğun yanında metin ve sayaç var.
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

    final l = context.l10n;
    final c = context.c;
    final sayac = MilestoneService.esikSayaci(veri.siradaki);
    // Çubuk yalnız sıradaki taş ve bilinen toplamla (uydurma oran yok).
    final oran = siradaki == null ? null : veri.ilerleme;
    // Bakiye gizliyken kalan TUTAR yazılmaz.
    final kalan = siradaki == null || gizli || veri.kalan == null
        ? null
        : MilestoneService.kalanKisa(veri.kalan!);
    final yuzde = oran == null ? null : (oran * 100).floor();
    final baslik = siradaki == null
        ? l.kilometreTasiHepsiGecildi
        : l.kilometreTasiSiradakiSatir(siradaki.title);
    final ust = siradaki == null
        ? l.kilometreTasiHepsiGecildi
        : yuzde == null
            ? l.kilometreTasiSiradakiEtiket(siradaki.title)
            : kalan == null
                ? l.kilometreTasiSiradakiYuzdeEtiket(siradaki.title, yuzde)
                : l.kilometreTasiSiradakiIlerlemeEtiket(
                    siradaki.title, yuzde, kalan);
    final etiket = '$ust. '
        '${l.kilometreTasiSayacEtiket(sayac.gecilen, sayac.toplam)}. '
        '${l.kilometreTaslariTumuEtiket}';

    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l.kilometreTaslariUpper),
          const SizedBox(height: SandikSpace.sm),
          Semantics(
            container: true,
            button: true,
            label: etiket,
            excludeSemantics: true,
            child: SandikCard(
              key: const ValueKey('kilometreTasiSatiri'),
              padding: const EdgeInsets.symmetric(
                  horizontal: SandikSpace.md, vertical: SandikSpace.smd),
              onTap: () => _tumunuAc(context,
                  [for (final m in veri.kazanilan) goster(m)], siradaki),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Wrap, Row değil: büyük yazıda (3.1×, 320 pt) sayaç
                  // başlığın altına iner; Row'da başlık harf harf
                  // daralıyor, sayaç taşıyordu. Normal boyda ikisi aynı
                  // satırda, sayaç sağda.
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: SandikSpace.sm,
                    children: [
                      Text(
                        baslik,
                        style: context.t.titleMedium?.copyWith(
                            color: c.text90, fontWeight: FontWeight.w600),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              l.kilometreTasiSayac(
                                  sayac.gecilen, sayac.toplam),
                              style: context.t.labelLarge?.copyWith(
                                  color: c.text58,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ]),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: c.text36, size: SandikSpace.lgs),
                        ],
                      ),
                    ],
                  ),
                  if (oran != null) ...[
                    const SizedBox(height: SandikSpace.sm),
                    _IlerlemeCubugu(oran: oran),
                  ],
                  if (kalan != null) ...[
                    const SizedBox(height: SandikSpace.xs2),
                    Text(
                      l.kilometreTasiKalan(kalan),
                      style: context.t.bodySmall?.copyWith(color: c.text58),
                    ),
                  ],
                  if (vitrin.isNotEmpty) ...[
                    const SizedBox(height: SandikSpace.smd),
                    Wrap(
                      spacing: SandikSpace.xs2,
                      runSpacing: SandikSpace.xs2,
                      children: [
                        for (final m in vitrin) _Isaret(m: m),
                      ],
                    ),
                  ],
                ],
              ),
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
      shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
      builder: (ctx) => _TumuSayfasi(hepsi: hepsi, siradaki: siradaki),
    );
  }
}

/// Sıradaki taşa ilerleme: ince yatay çubuk. Kendi çizimi,
/// `LinearProgressIndicator` değil: bu bir yükleniyor göstergesi değil,
/// statik ölçü (`yukleniyor_tek_davranis_test`; ekran okuyucu "ilerleme"
/// diye yanlış okurdu). Hareket yok: değer her açılışta aynı yerde, dolma
/// animasyonu süs olurdu.
class _IlerlemeCubugu extends StatelessWidget {
  const _IlerlemeCubugu({required this.oran});

  final double oran;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: SandikRadius.smAll,
      child: SizedBox(
        height: SandikSpace.xs2,
        child: ColoredBox(
          color: context.c.overlay,
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: oran.clamp(0.0, 1.0),
            child: ColoredBox(color: context.c.amberText),
          ),
        ),
      ),
    );
  }
}

/// Geçilen taşın etiketi (her türün en yükseği): ikon + ad. Etkileşimsiz:
/// dokunma satırın tamamında; ayrıntı tam listede.
///
/// Önce yalnız ikondu; yasin 10 Kas ekran görüntüsünde "neler bunlar?" diye
/// sordu: kum saati, kumbara, yükselen çizgi ve pasta grafiği ad olmadan
/// bir şey anlatmıyordu. Ad, tam listedeki başlığın aynısı (bakiye gizliyken
/// [MilestoneService.gizli] tutarı çıkarmış hâli).
class _Isaret extends StatelessWidget {
  const _Isaret({required this.m});

  final Milestone m;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm, vertical: SandikSpace.xs),
      decoration: BoxDecoration(
        borderRadius: SandikRadius.lgAll,
        color: c.amberFill.withValues(alpha: 0.16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(MilestoneSheet.ikonu(m.kind),
              size: SandikSpace.md, color: c.amberText),
          const SizedBox(width: SandikSpace.xs),
          Flexible(
            child: Text(m.title,
                style: context.t.labelMedium?.copyWith(color: c.text90)),
          ),
        ],
      ),
    );
  }
}

/// "Tümü": kazanılan bütün taşlar, en sonda sıradaki. Ayrı ekran değil,
/// sheet (sadeleştirme: yeni sayfa yok). Kazanılan satıra dokununca
/// kutlama sayfası yeniden açılır (Paylaş orada); eski şeritte bu rozete
/// dokunarak yapılıyordu, tek satıra geçince buraya taşındı.
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
                for (final m in hepsi)
                  _Satir(
                    m: m,
                    onTap: () => MilestoneSheet.show(context, m, tekrar: true),
                  ),
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
  const _Satir({required this.m, this.siradaki = false, this.onTap});

  final Milestone m;
  final bool siradaki;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final satir = ConstrainedBox(
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
    if (onTap == null) {
      return Semantics(
        label: '${context.l10n.kilometreTasiSiradaki}: ${m.title}. ${m.body}',
        excludeSemantics: true,
        child: satir,
      );
    }
    return SandikTappable(
      semanticLabel: '${m.title}. ${m.body}',
      onTap: onTap,
      child: satir,
    );
  }
}
