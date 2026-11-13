import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/magaza.dart';
import '../l10n/l10n.dart';
import '../models/kapanis_ozeti.dart';
import '../screens/yillik_rapor_screen.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../screens/paywall_screen.dart';
import '../services/review_prompt_service.dart';
import '../theme/sandik.dart';
import '../utils/money_format.dart';
import '../utils/tr_format.dart';
import '../utils/tr_iyelik.dart';
import 'review_prompt_sheet.dart';
import 'share_card.dart';
import 'tam_ekran/grafik_paylasimi.dart' show grafikPaylasimKisaBaglanti;

/// Kapanış özeti sayfası ("Tümünü sat" kaydedildikten sonra; sonradan
/// Portföy › Sattıkların listesinden, Premium).
///
/// ## Kurallar (müşteri işi 10 Kas)
/// - Kutlama yok: konfeti, rozet, "tebrikler" yok. Kazançta da zararda da
///   aynı sakin sayfa; zararda tek nötr cümle, paylaş düğmesi yok
///   (kullanıcıyı zararını göstermeye çağırmayız).
/// - Paylaşım yalnız kazançta ve yalnız YÜZDE taşır ([kapanisPaylasimKarti]):
///   tutar, lot, maliyet karta da metne de girmez (`ShareCardData` kuralı).
/// - Maliyet bilinmiyorsa yalnız süre cümlesi: tutar ve yüzde uydurulmaz.
/// - "Yıllık raporda gör" yalnız rapor satırının göründüğü yerde
///   (`premiumOzellikleriGorunur`, Raporlar kapısıyla aynı anahtar);
///   kapalıyken bağlantı da yok, yoksa gizli ekran bu yoldan açılırdı.
///   Kapı provider'dan okunur (`RemoteConfigService.instance` değil):
///   satın alma/geri yükleme sayfa açıkken bağlantıyı günceller.
/// - Ücretsizde bağlantı "Bu satışın yıllık raporu Premium'da" der ve
///   dokununca DOĞRUDAN paywall açar (`kapanis_rapor`, yasin 2026-11-13):
///   önce tam sayfa kilit, sonra paywall iki adımdı. Paywall yalnız
///   dokunuşla açılır; sayfa kendiliğinden satış istemez.
/// - Paylaşım ve rapor sayfa KAPANDIKTAN sonra açılır: iki katman modal
///   olmasın (`showShareSheet` ile aynı gerekçe).
enum _Secim { paylas, rapor, paywall }

/// Kapanış özetindeki kilitli rapor bağlantısının analitik kaynağı.
const kapanisRaporPaywallKaynagi = 'kapanis_rapor';

Future<void> showKapanisOzeti(
  BuildContext context,
  KapanisOzeti ozet, {
  bool tutarGizli = false,
  bool degerlendirme = true,
}) async {
  final l = context.l10n;
  final secim = await showSandikSheet<_Secim>(
    context: context,
    baslik: l.kapanisBaslik,
    builder: (_) => KapanisOzetiSayfasi(ozet: ozet, tutarGizli: tutarGizli),
  );
  if (!context.mounted) return;
  switch (secim) {
    case _Secim.paylas:
      final pct = ozet.karPct;
      if (pct == null) return;
      // Paylaşım sonrası değerlendirme istemini `showShareSheet` kendisi
      // sorar (`ReviewAni.paylasim`); burada ikinci kez sorulmaz.
      await showShareSheet(
        context,
        data: kapanisPaylasimKarti(l, ad: ozet.ad, karPct: pct),
        metin: kapanisPaylasimMetni(l, ad: ozet.ad, karPct: pct),
        subject: l.kapanisBaslik,
        analyticsPeriod: 'kapanis',
        sayfaBasligi: l.shareWord,
      );
      return;
    case _Secim.rapor:
      await pushGuarded(
          context,
          adaptiveRoute<void>(
              settings: const RouteSettings(name: 'yillik_rapor'),
              builder: (_) => const YillikRaporScreen()));
      return;
    case _Secim.paywall:
      await PaywallScreen.show(context, source: kapanisRaporPaywallKaynagi);
      return;
    case null:
      break;
  }
  // Kayda değer kazançla kapanan pozisyon "mutlu an"dır; karar ve sıklık
  // `ReviewPromptService`'te (erteleme, tavan, yeni kullanıcı kapısı).
  // "Sattıkların"dan yeniden açılan eski kapanış o an değildir
  // ([degerlendirme] false): kullanıcı geçmişe bakıyor, yeni bir iş bitmedi.
  if (degerlendirme &&
      ozet.kazanc &&
      (ozet.karPct ?? 0) >= kapanisDegerlendirmeEsigiPct &&
      context.mounted) {
    await ReviewPromptSheet.belkiGoster(context, ReviewAni.kapanis);
  }
}

/// Paylaşım kartı: başlık varlığın adı, kahraman gerçekleşen yüzde. Tutar
/// yok; dipnotta kısa indirme bağlantısı ve "Yatırım tavsiyesi değildir"
/// (Bugün kartıyla aynı düzen, `bugun_paylasimi.dart`).
ShareCardData kapanisPaylasimKarti(
  AppLocalizations l, {
  required String ad,
  required double karPct,
}) =>
    ShareCardData(
      baslik: ad,
      degisimPct: karPct,
      degisimEtiketi: l.kapanisPaylasEtiketi,
      dipnotlar: [grafikPaylasimKisaBaglanti(), l.notInvestmentAdvice],
    );

String kapanisPaylasimMetni(
  AppLocalizations l, {
  required String ad,
  required double karPct,
}) =>
    [
      l.kapanisPaylasMetni(ad, fmtPctIsaretli(karPct, digits: 1)),
      l.notInvestmentAdvice,
      '',
      l.trackingWithSandik,
      Magaza.indirBaglantisi(kaynak: 'kapanis_ozeti', kampanya: 'kapanis'),
    ].join('\n');

/// Süre metni: "1 yıl 4 ay", "3 ay", "12 gün", "bir günden kısa".
String kapanisSureMetni(AppLocalizations l, KapanisOzeti o) {
  if (o.yil > 0) {
    return o.ay == 0
        ? l.eldeTutmaSureYil('${o.yil}')
        : l.eldeTutmaSureYilAy('${o.yil}', '${o.ay}');
  }
  if (o.ay > 0) return l.kapanisSureAy(o.ay);
  if (o.gun > 0) return l.kapanisSureGun(o.gun);
  return l.kapanisSureBirGundenKisa;
}

class KapanisOzetiSayfasi extends ConsumerWidget {
  const KapanisOzetiSayfasi(
      {super.key, required this.ozet, this.tutarGizli = false});

  final KapanisOzeti ozet;

  /// Bakiye gizliyken tutar maskeli; yüzde görünür (yüzde tutar sızdırmaz).
  final bool tutarGizli;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.c;
    final kar = ozet.karTry;
    final pct = ozet.karPct;
    final kazanc = ozet.kazanc;
    final cumle = l.kapanisTuttun(
        ozet.ad, trBelirtme(ozet.ad), kapanisSureMetni(l, ozet));
    final raporAcik = ref.watch(premiumOzellikleriGorunurProvider);
    final raporKilitli = ref.watch(premiumKilitliProvider);
    final h = SandikSpace.screenH(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(h, 0, h, SandikSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(cumle,
                key: const ValueKey('kapanis_sure'),
                style: context.t.titleMedium?.copyWith(color: c.text90)),
            if (kar != null && pct != null) ...[
              const SizedBox(height: SandikSpace.md),
              // Kâr/zarar adı satırda yazılı ve tutar işaretli: anlam yalnız
              // renkte değil (HIG renk körlüğü).
              Text(
                kazanc ? l.kapanisGerceklesenKar : l.kapanisGerceklesenZarar,
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
              const SizedBox(height: SandikSpace.xs),
              Text(
                '${tutarGizli ? const BazPara.lira().gizliTutar : '${kar > 0 ? '+' : ''}${fmtTRY(kar)}'}'
                ' · ${fmtPctIsaretli(pct, digits: 1)}',
                key: const ValueKey('kapanis_sonuc'),
                style: context.t.numMedium.copyWith(
                    color: kar >= 0 ? c.gain : c.loss,
                    fontWeight: FontWeight.w600),
              ),
              if (ozet.yillikPct case final y?) ...[
                const SizedBox(height: SandikSpace.xs),
                Text(l.kapanisYillik(fmtPctIsaretli(y, digits: 1)),
                    key: const ValueKey('kapanis_yillik'),
                    style: context.t.bodyMedium?.copyWith(color: c.text58)),
              ],
              if (kar < 0) ...[
                const SizedBox(height: SandikSpace.md),
                Text(l.kapanisZarar,
                    style: context.t.bodyMedium?.copyWith(color: c.text58)),
              ],
            ] else ...[
              const SizedBox(height: SandikSpace.sm),
              Text(l.kapanisMaliyetBilinmiyor,
                  style: context.t.bodyMedium?.copyWith(color: c.text58)),
            ],
            if (raporAcik) ...[
              const SizedBox(height: SandikSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('kapanis_rapor'),
                  style: TextButton.styleFrom(
                      minimumSize: SandikTouch.minSize,
                      padding: EdgeInsets.zero),
                  onPressed: () => Navigator.pop(
                      context, raporKilitli ? _Secim.paywall : _Secim.rapor),
                  // Kilit ikonu: "Premium'da" metinde de yazılı, anlam
                  // yalnız ikonda değil (HIG renk/ikon körlüğü).
                  child: raporKilitli
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.lock_outline_rounded,
                              size: SandikSpace.md),
                          const SizedBox(width: SandikSpace.xs),
                          Flexible(child: Text(l.kapanisYillikRaporKilitli)),
                        ])
                      : Text(l.kapanisYillikRapor),
                ),
              ),
            ],
            const SizedBox(height: SandikSpace.lg),
            Row(
              children: [
                if (kazanc && pct != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('kapanis_paylas'),
                      onPressed: () => Navigator.pop(context, _Secim.paylas),
                      icon: const Icon(Icons.ios_share_rounded),
                      label: Text(l.shareWord),
                    ),
                  ),
                  const SizedBox(width: SandikSpace.sm),
                ],
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('kapanis_tamam'),
                    onPressed: () => Navigator.pop(context),
                    child: Text(l.kapanisTamam),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
