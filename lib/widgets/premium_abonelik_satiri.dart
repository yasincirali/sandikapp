import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/premium_kullanim_provider.dart';
import '../providers/premium_provider.dart';
import '../screens/paywall_screen.dart';
import '../services/abonelik_yonetimi.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart' show fmtMagazaTutari;
import 'sandik_async_button.dart';
import 'satin_alim_geri_yukleme.dart';

/// Profil'de Premium hakkı satırı (S14-A, 2026-10-05): ne tür hak, ne zaman
/// yenilenir/biter (ücretsiz denemede ilk ödeme günü), ve iki eylem.
///
/// - "Yönet" yalnız mağaza aboneliğinde: iptal/plan değişikliği mağazanın
///   kendi sayfasında yapılır (Apple/Google kuralı); uygulama aracı olamaz.
///   iOS'ta o sayfa uygulama içinde açılır (`AbonelikYonetimi`, 2026-10-23).
/// - "Satın alımları geri yükle" paywall ile aynı akıştır
///   ([satinAlimlariGeriYukle]): mağazaya sorar, sonucu söyler, sonra hakları
///   sunucudan yeniden okur. Önce yalnız sunucuyu tazeliyor ve hiçbir şey
///   söylemiyordu (Ar-Ge 12 Kas #1). Abonelik durumu RevenueCat webhook'uyla
///   sunucuya yazılır (0116); başka cihazda alınmış abonelik de görünür.
/// - Sunucu hakkı henüz yoksa da (`hak == null`: mağaza alımı webhook'tan
///   önce, yönetici) satır açılır ve "Yönet" görünür (yasin 10 Kas: "premium
///   müşteri premium'u nasıl iptal ediyor?"). Abonelik yoksa mağaza sayfası
///   boş gelir, zararı yok; varsa iptalin yolu kapanmamış olur.
class PremiumAbonelikSatiri extends ConsumerWidget {
  const PremiumAbonelikSatiri({super.key, required this.hak});

  final PremiumHakki? hak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final tarihBicimi =
        DateFormat('d MMMM y', Localizations.localeOf(context).toString());
    final hak = this.hak;
    final baslik = hak == null
        ? l10n.premiumDurum
        : hak.hediye
            ? l10n.prmAbonelikHediye
            : hak.yillik
                ? l10n.prmAbonelikYillik
                : l10n.prmAbonelikAylik;
    final bitis =
        hak?.bitis == null ? null : tarihBicimi.format(hak!.bitis!.toLocal());
    final magaza = switch (hak?.magaza) {
      'app_store' || 'APP_STORE' => 'App Store',
      'play_store' || 'PLAY_STORE' => 'Google Play',
      _ => null,
    };
    // Hediyede kalan gün de yazılır ve son günlerde "devam et" düğmesi
    // çıkar: bitiş sessiz olmasın (paywall incelemesi, 2026-10-20).
    final kalan =
        hak != null && hak.hediye ? hak.kalanGun(DateTime.now()) : null;
    final yonet = hak == null || hak.kaynak == 'revenuecat';
    final String? alt;
    if (hak == null || bitis == null) {
      alt = null;
    } else if (hak.kaynak == 'revenuecat' &&
        !hak.iptalEdildi &&
        magaza != null) {
      // Denemede "Yenileme" ilk ödemeyi saklıyordu (Ar-Ge 12 Kas #2):
      // sürpriz ödeme hissi = iade isteği. Satır denemeyi ve ilk ödeme
      // gününü düz cümleyle söyler; tutar yalnız mağazanın priceString'iyle
      // biliniyorsa. Sayaç, geri sayım, uyarı rengi yok: bilgi, baskı değil.
      // İptal edilmiş denemede ödeme olmayacağı için aşağıdaki "biter" kalır.
      final donem = ref.watch(abonelikDonemiProvider).valueOrNull;
      final tutar = donem?.ilkOdemeTutari;
      alt = donem?.deneme != true
          ? l10n.prmYenileme(bitis, magaza)
          : tutar == null
              ? l10n.prmDenemeIlkOdeme(bitis, magaza)
              : l10n.prmDenemeIlkOdemeTutar(bitis, tutar, magaza);
    } else if (kalan != null) {
      alt = l10n.prmHediyeKalan(bitis, kalan);
    } else {
      alt = l10n.prmBitis(bitis);
    }
    final sonGunler = kalan != null && kalan <= hediyeSonGunlerEsigi;
    // "Premium'la kullandıkların" (Ar-Ge 14 Kas #2): yenileme öncesi "neye
    // ödüyorum" sorusunun cevabı kullanıcının kendi sayıları. Sayım
    // sağlayıcıda; hiçbir kalem yoksa satır yok.
    final kullanim =
        premiumKullanimMetni(l10n, ref.watch(premiumKullanimProvider));
    // Yıllığa geçiş tasarrufu (Ar-Ge 14 Kas #4): yalnız aylık ve iptal
    // edilmemiş mağaza abonesinde. İptal etmiş birine "yıllığa geç" demek
    // kararını yok saymaktır. Tutar mağazanın iki fiyatından hesaplanır;
    // mağaza yoksa satır yok. Teklif yalnız bu kişide okunur.
    final aylikAbone = hak != null &&
        hak.kaynak == 'revenuecat' &&
        !hak.yillik &&
        !hak.iptalEdildi;
    final tasarruf =
        aylikAbone ? ref.watch(yillikTasarrufProvider).valueOrNull : null;

    return SandikCard(
      // `min`: kart alt sayfada açılır (Profil › Premium satırı). Varsayılan
      // `max` sütun, sayfanın 9/16 sınırına kadar uzayıp altında boş bir
      // kutu bırakıyordu (yasin 10 Kas ekran görüntüsü: "Premium'u olan
      // kullanıcıda bu şekilde gözüküyor").
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded, color: c.amberText),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(baslik,
                        style: t.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600, color: c.text90)),
                    if (alt != null)
                      Text(alt, style: t.bodySmall?.copyWith(color: c.text58)),
                    if (kullanim != null)
                      Text(kullanim,
                          style: t.bodySmall?.copyWith(color: c.text58)),
                  ],
                ),
              ),
            ],
          ),
          if (tasarruf != null)
            _YillikTasarrufSatiri(
              metin: l10n.prmYillikGecTasarruf(fmtMagazaTutari(
                  tasarruf.tutar, tasarruf.paraBirimi,
                  dil: context.tarihDili)),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: SandikSpace.xs,
            children: [
              SandikAsyncButton.kompakt(
                tur: SandikAsyncTur.metin,
                style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
                onPressed: () async {
                  await satinAlimlariGeriYukle(context, ref);
                },
                child: Text(l10n.prmGeriYukle),
              ),
              if (yonet)
                TextButton(
                  style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
                  onPressed: AbonelikYonetimi.ac,
                  child: Text(l10n.prmYonet),
                ),
              if (sonGunler)
                FilledButton.tonal(
                  style:
                      FilledButton.styleFrom(minimumSize: SandikTouch.minSize),
                  onPressed: () =>
                      PaywallScreen.show(context, source: 'hediye_bitiyor'),
                  child: Text(l10n.prmHediyeDevam),
                ),
            ],
          ),
          if (yonet)
            Text(l10n.prmIptalIpucu,
                style: t.bodySmall?.copyWith(color: c.text58)),
        ],
      ),
    );
  }
}

/// "Yıllığa geçersen yılda ₺309,89 az ödersin": dokununca paywall yıllık
/// seçili açılır (`profil_yillik_tasarruf`). Tek semantik düğüm, düğme
/// rolü, en az 44 pt. Renk vurgu rengi, uyarı değil: bilgi, baskı yok.
class _YillikTasarrufSatiri extends StatelessWidget {
  const _YillikTasarrufSatiri({required this.metin});

  final String metin;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(SandikRadius.sm),
          onTap: () => PaywallScreen.show(context,
              source: 'profil_yillik_tasarruf', yillikSecili: true),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: SandikTouch.min),
            child: Row(
              children: [
                Expanded(
                  child: Text(metin,
                      style: context.t.bodySmall?.copyWith(
                          color: c.amberText, fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: SandikSpace.md2, color: c.amberText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kalemleri tek satıra dizer: "Premium'la kullandıkların: 14 varlık · 3
/// gösterge alarmı". Boş listede null (satır çizilmez).
String? premiumKullanimMetni(AppLocalizations l, List<PremiumKullanim> k) {
  if (k.isEmpty) return null;
  final parcalar = [
    for (final e in k)
      switch (e.kalem) {
        PremiumKalem.varlik => l.prmKullanimVarlik(e.sayi),
        PremiumKalem.takip => l.prmKullanimTakip(e.sayi),
        PremiumKalem.fiyatAlarmi => l.prmKullanimFiyatAlarmi(e.sayi),
        PremiumKalem.gostergeAlarmi => l.prmKullanimGostergeAlarmi(e.sayi),
        PremiumKalem.cizgiAlarmi => l.prmKullanimCizgiAlarmi(e.sayi),
        PremiumKalem.portfoy => l.prmKullanimPortfoy(e.sayi),
      },
  ];
  return l.prmKullanim(parcalar.join(' · '));
}
