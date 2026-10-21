import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/gunler_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/veri_kalitesi_provider.dart';
import '../services/analytics_service.dart';
import '../services/temettu_gecmisi.dart' show trGunu;
import '../theme/sandik.dart';
import 'sandik_skeleton.dart';

/// Ana sayfa, Bugün kartının altında: "Perşembe: TCMB faiz kararı" gibi
/// iki gün içindeki TEK olay (`seni_ilgilendiren_gunler.dart`; yasin onayı,
/// müşteri raporu 2026-10-20 21:15).
///
/// Özellik önerisiyle AYNI yuvayı paylaşır ([anaSayfaDurtusuProvider]):
/// görünürken öneri kartı susar. Kalıp [OzellikOnerisiKarti] ile aynı
/// (SandikCard, ikon + iki satır + kapat) — yuvadaki iki dürtü aynı
/// görünür, kullanıcı yeni bir bileşen öğrenmez. Dokununca 14 günlük liste
/// sayfası açılır; kapatma yalnız o olayı düşürür, sıradaki iki gün
/// içindeyse o çıkar, yoksa yuva öneriye kalır. Bayraksız ve ücretsiz:
/// mevcut veriye dayanan ek, söyleyecek bir şey yoksa yer kaplamaz.
class GunlerSatiri extends ConsumerWidget {
  const GunlerSatiri({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SandikBelirme(child: _govde(context, ref));

  Widget _govde(BuildContext context, WidgetRef ref) {
    if (ref.watch(anaSayfaDurtusuProvider) != AnaSayfaDurtusu.takvim) {
      return const SizedBox.shrink();
    }
    final olay = ref.watch(takvimSatiriProvider);
    if (olay == null) return const SizedBox.shrink();
    final c = context.c;
    final t = context.t;
    final l = context.l10n;
    final bugun = trGunu(ref.watch(veriKalitesiSaatProvider)());
    return Padding(
      padding: padding,
      child: SandikCard(
        padding: const EdgeInsets.only(
            left: SandikSpace.md, top: SandikSpace.xs, bottom: SandikSpace.xs),
        onTap: () {
          AnalyticsService.instance
              .logGunlerSatiri(tur: olay.tur.name, eylem: 'ac');
          gunlerSayfasiniAc(context);
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Row(
            children: [
              Icon(gunIkonu(olay), color: c.amberText, size: SandikSpace.lgs),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        gunBasligi(
                            l,
                            olay,
                            gunEtiketi(
                                l, context.tarihDili, olay.gun, bugun)),
                        style: t.bodyMedium?.copyWith(
                            color: c.text90, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        gunAlti(l, olay),
                        style: t.bodySmall?.copyWith(color: c.text58),
                      ),
                    ],
                  ),
                ),
              ),
              _KapatTusu(olay: olay),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Bugün" / "Yarın" / gün adı ("Perşembe"). İki günlük pencerede gün adı
/// tarihten kısadır ve yanlış okunmaz.
String gunEtiketi(
    AppLocalizations l, String dil, DateTime gun, DateTime bugun) {
  final fark = gun.difference(bugun).inDays;
  if (fark == 0) return l.sigBugun;
  if (fark == 1) return l.sigYarin;
  return DateFormat.EEEE(dil).format(gun);
}

String gunBasligi(AppLocalizations l, GunOlayi o, String gun) =>
    switch (o.tur) {
      GunOlayiTuru.tcmb => l.sigTcmb(gun),
      GunOlayiTuru.fomc => l.sigFomc(gun),
      GunOlayiTuru.temettu => l.sigTemettu(gun, o.kod ?? ''),
    };

String gunAlti(AppLocalizations l, GunOlayi o) => switch (o.tur) {
      GunOlayiTuru.tcmb => l.sigTcmbAlt,
      GunOlayiTuru.fomc => l.sigFomcAlt,
      GunOlayiTuru.temettu => l.sigTemettuAlt,
    };

IconData gunIkonu(GunOlayi o) => switch (o.tur) {
      GunOlayiTuru.tcmb || GunOlayiTuru.fomc => Icons.account_balance_outlined,
      GunOlayiTuru.temettu => Icons.payments_outlined,
    };

void _kapat(WidgetRef ref, GunOlayi o) {
  SandikHaptic.selection.perform();
  ref
      .read(gunlerKapatilanProvider.notifier)
      .set({...ref.read(gunlerKapatilanProvider), o.kimlik});
  AnalyticsService.instance.logGunlerSatiri(tur: o.tur.name, eylem: 'kapat');
}

class _KapatTusu extends ConsumerWidget {
  const _KapatTusu({required this.olay});
  final GunOlayi olay;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        tooltip: context.l10n.sigKapat,
        // 18: öneri kartının kapat ikonuyla aynı (yuvadaki iki dürtü eş).
        icon: Icon(Icons.close_rounded, size: 18, color: context.c.text36),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
            minWidth: SandikTouch.min, minHeight: SandikTouch.min),
        onPressed: () => _kapat(ref, olay),
      );
}

/// Önümüzdeki 14 günün listesi. Sayfa açıkken kapatılan satır yerinde
/// düşer (sayfa sağlayıcıyı izler); tümü kapanınca boş cümlesi kalır.
Future<void> gunlerSayfasiniAc(BuildContext context) => showSandikSheet<void>(
      context: context,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => const _GunlerSayfasi(),
    );

class _GunlerSayfasi extends ConsumerWidget {
  const _GunlerSayfasi();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final t = context.t;
    final l = context.l10n;
    final olaylar = ref.watch(yaklasanGunlerProvider);
    final tarih = DateFormat('d MMMM EEEE', context.tarihDili);
    // Başlık ve not da kayan listenin içinde: ×3.1 yazıda not tek başına
    // sayfa yüksekliğini aşıyordu (sabit başlık + kayan liste taşıyordu).
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: SandikSpace.sm),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SandikSpace.lg, SandikSpace.lg, SandikSpace.lg, SandikSpace.xs),
            child: Semantics(
              header: true,
              child: Text(
                l.sigSayfaBaslik,
                style: t.titleMedium
                    ?.copyWith(color: c.text90, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SandikSpace.lg, 0, SandikSpace.lg, SandikSpace.sm),
            child: Text(
              l.sigSayfaNot(listePenceresiGun),
              style: t.bodySmall?.copyWith(color: c.text58),
            ),
          ),
          if (olaylar.isEmpty)
            Padding(
              padding: const EdgeInsets.all(SandikSpace.lg),
              child: Text(l.sigBos,
                  style: t.bodyMedium?.copyWith(color: c.text58)),
            ),
          for (final o in olaylar)
            ListTile(
              key: ValueKey(o.kimlik),
              leading: Icon(gunIkonu(o), color: c.amberText),
              title: Text(gunBasligi(l, o, tarih.format(o.gun)),
                  style: t.bodyLarge?.copyWith(color: c.text90)),
              subtitle: Text(gunAlti(l, o),
                  style: t.bodySmall?.copyWith(color: c.text58)),
              trailing: _KapatTusu(olay: o),
            ),
        ],
      ),
    );
  }
}
