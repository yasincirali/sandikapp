import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/fon_xray_provider.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../services/portfoy_xray.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/fon_dagilimi_karti.dart';
import '../widgets/premium_kilit_karti.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_bos_durum.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/sandik_skeleton.dart';

/// Portföy X-Ray (Premium, yasin 2026-10-10): bugünkü portföyün, fonların
/// içi açılarak, varlık sınıflarına gerçek dağılımı.
///
/// Performans › Raporlar kapısından açılır (Yıllık rapor ve Temettü tahmini
/// gibi; görünürlük `premiumOzellikleriGorunur`). Kural ve gerekçe saf
/// `portfoy_xray.dart`'ta; ekran yalnız çizer.
///
/// Her sayının yanında kaynak ve tarih: fon dağılımı "TEFAS · tarih", kalem
/// örtüşmesi "KAP · ay sonu", doğrudan varlıklar bugünkü fiyat. Kapsanmayan
/// pay "X-Ray dışı" satırı olarak kalır; diğer dilimlere dağıtılmaz.
class PortfoyXrayScreen extends ConsumerWidget {
  const PortfoyXrayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (ref.watch(premiumKilitliProvider)) {
      return Scaffold(
        appBar: SandikAppBar(title: l.xrEkranBaslik),
        body: PremiumKilitGovdesi(
          kart: PremiumKilitKarti(
            ikon: Icons.donut_large_rounded,
            baslik: l.xrEkranBaslik,
            govde: l.xrEkranKilitGovde,
            kilitMetni: l.xrEkranKilitSatir,
            kaynak: 'portfoy_xray',
          ),
        ),
      );
    }
    final xray = ref.watch(portfoyXrayProvider);
    return Scaffold(
      appBar: SandikAppBar(title: l.xrEkranBaslik),
      body: xray.when(
        loading: () => const SandikSkeletonList(rows: 4),
        error: (e, _) => SandikErrorView(
            error: e, onRetry: () => ref.invalidate(xrayFonVerisiProvider)),
        data: (x) => x.bos
            ? SandikBosDurum(metin: l.xrBos, alt: l.xrBosAlt)
            : _Govde(x: x),
      ),
    );
  }
}

class _Govde extends StatelessWidget {
  const _Govde({required this.x});

  final PortfoyXray x;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final h = SandikSpace.screenH(context);
    final dil = Localizations.localeOf(context).toString();
    final kovalar = x.siraliKovalar;
    final notStili = context.t.bodySmall?.copyWith(color: c.text58);
    final kaynakStili = context.t.bodySmall?.copyWith(color: c.text36);

    return ListView(
      padding: EdgeInsets.fromLTRB(h, SandikSpace.sm, h, SandikSpace.xl),
      children: [
        SandikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.xrToplamEtiket,
                  style: context.t.bodyMedium?.copyWith(color: c.text58)),
              const SizedBox(height: SandikSpace.xs),
              Text(fmtTRY(x.toplam),
                  style: context.t.numLarge
                      .copyWith(fontWeight: FontWeight.w800, color: c.text90)),
              const SizedBox(height: SandikSpace.md),
              XrayCubugu(
                paylar: [for (final e in kovalar) (e.key, e.value)],
                disi: x.xrayDisi,
              ),
            ],
          ),
        ),
        const SizedBox(height: SandikSpace.lg),
        SandikSectionHeader(title: l.xrDagilimUpper),
        const SizedBox(height: SandikSpace.sm),
        SandikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in kovalar)
                XrayKovaSatiri(
                  kova: e.key,
                  deger: fmtPct(x.pay(e.value), digits: 1),
                  ikinci: fmtTRY(e.value),
                ),
              if (x.xrayDisi > 0) ...[
                Divider(
                    height: SandikSpace.md, thickness: 1, color: c.hairline),
                XrayKovaSatiri(
                  kova: null,
                  ad: l.xrDisi,
                  renk: c.text20.withValues(alpha: 0.5),
                  deger: fmtPct(x.pay(x.xrayDisi), digits: 1),
                  ikinci: fmtTRY(x.xrayDisi),
                ),
                const SizedBox(height: SandikSpace.xs),
                Text(l.xrDisiAciklama, style: notStili),
                if (x.xrayDisiFonlar.isNotEmpty) ...[
                  const SizedBox(height: SandikSpace.xs),
                  Text(
                    l.xrDisiFonlar(
                        x.xrayDisiFonlar.map((f) => f.kod ?? f.ad).join(', ')),
                    style: notStili,
                  ),
                ],
              ],
            ],
          ),
        ),
        if (x.ortusmeler.isNotEmpty) ...[
          const SizedBox(height: SandikSpace.lg),
          SandikSectionHeader(title: l.xrOrtusmeUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.xrOrtusmeAciklama, style: notStili),
                const SizedBox(height: SandikSpace.sm),
                for (final o in x.ortusmeler) _OrtusmeSatiri(o: o),
                if (x.kalemDonemi != null) ...[
                  const SizedBox(height: SandikSpace.sm),
                  Text(
                    l.xrKaynakKalemler(
                        DateFormat('MMMM y', dil).format(x.kalemDonemi!)),
                    style: kaynakStili,
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: SandikSpace.lg),
        if (x.fonTarihleri case (final eski, final yeni)) ...[
          Text(l.xrKaynakFonlar(_aralik(dil, eski, yeni)), style: kaynakStili),
          const SizedBox(height: SandikSpace.xs),
        ],
        Text(l.xrKaynakDogrudan, style: kaynakStili),
      ],
    );
  }

  /// Tek gün ya da "3 Eki - 9 Ekim 2026" (fonlar farklı günlerde
  /// güncellenmiş olabilir; en eskisi de söylenir).
  static String _aralik(String dil, DateTime eski, DateTime yeni) {
    final tam = DateFormat('d MMMM y', dil);
    if (eski == yeni) return tam.format(yeni);
    return '${DateFormat('d MMM', dil).format(eski)} - ${tam.format(yeni)}';
  }
}

class _OrtusmeSatiri extends StatelessWidget {
  const _OrtusmeSatiri({required this.o});

  final Ortusme o;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final kaynaklar = [...o.fonlar, if (o.dogrudan) l.xrDogrudan].join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.kod == o.ad ? o.kod : '${o.kod} · ${o.ad}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodyMedium
                      ?.copyWith(color: c.text90, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  '${l.xrOrtusmeKaynak(o.kaynakSayisi)}: $kaynaklar',
                  style: context.t.bodySmall?.copyWith(color: c.text58),
                ),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          Text(fmtTRY(o.tutar),
              style: context.t.bodyMedium
                  ?.copyWith(color: c.text90, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
