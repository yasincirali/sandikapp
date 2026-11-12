import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/aylik_rapor_provider.dart' show aylikRaporLotlari;
import '../providers/portfolio_provider.dart' show portfolioProvider;
import '../providers/preferences_provider.dart' show balanceHiddenProvider;
import '../providers/raporlar_provider.dart' show aylikRaporDonemiProvider;
import '../providers/sattiklarin_provider.dart';
import '../providers/temettu_tahmini_provider.dart';
import '../screens/aylik_rapor_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../screens/temettu_tahmini_screen.dart';
import '../services/aylik_getiri_tablosu.dart'
    show aylikGetiriAralikAySayisi, aylikGetiriAsgariAy;
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import 'sattiklarin.dart' show showSattiklarinListesi;

/// Satın alma sonrası sayfa (Ar-Ge 12 Kas 17:04 #4, "değdi" anı).
///
/// ## Neden
/// Eski sayfa 72 pt dekoratif halka + genel bir cümle ("Sınırsız varlık,
/// premium göstergeler…") + "Harika" idi: yeni ödeyen kullanıcıya NEYİ
/// açtığını kendi verisiyle göstermiyordu. Şimdi başlığın altında en fazla
/// üç satır, yalnız kullanıcıda verisi olan Premium yüzeyleri, kendi
/// sayısıyla ("Temettü tahmini: 3 hisse"). Konfeti, rozet, geri sayım yok:
/// bir yatırım uygulamasında para ödendikten sonra kutlama değil, açılan
/// kapı gösterilir.
///
/// ## Sayılar ve bekleme
/// Her satır mevcut, önbellekli bir sağlayıcıdan gelir; sayfa hiçbir şeyi
/// beklemez. Yükleniyorsa satır yok (iskelet de yok); geç gelen satır
/// `AnimatedSize` ile yer açar, hareketi azalt açıkken anında. Aylık
/// getiri tablosunun beş yıllık serisi bu sayfa için ÇEKİLMEZ: satır
/// tablonun aralığını defterden sayar ([aylikGetiriAralikAySayisi]).
/// Paywall satın almayı başlatırken sağlayıcıları dinlemeye başlar
/// (`premiumAcildiIsit`), mağaza diyaloğu sürerken sayılar hazırlanır.
///
/// ## Dönüş sözleşmesi
/// Paywall bu sayfa kapandıktan sonra HER yolda `pop(true)` der (kilit
/// satırları bu sonuca bakıyor). Satıra dokunulduysa hedef ekran paywall
/// kapandıktan sonra, paywall'ın altındaki gezginde açılır.
enum PremiumAcildiHedef { aylikRapor, temettu, sattiklarin, aylikGetiri, varlikSiniri }

/// Sayfanın girdisi: sağlayıcılardan okunan sayılar. `null`/0 = satır yok.
class PremiumAcildiVerisi {
  const PremiumAcildiVerisi({
    this.raporDonemi,
    this.temettuHisse = 0,
    this.kapanmisPozisyon = 0,
    this.getiriAy = 0,
  });

  final DateTime? raporDonemi;
  final int temettuHisse;
  final int kapanmisPozisyon;
  final int getiriAy;
}

/// Paywall kaynağının en ilgili satırı. Bilinmeyen kaynak → `null`
/// (varsayılan sıra: rapor, temettü, sattıkların, aylık getiri).
PremiumAcildiHedef? premiumAcildiKaynakHedefi(String kaynak) {
  if (kaynak.startsWith('asset_limit') || kaynak == 'bulk_add_asset_limit') {
    return PremiumAcildiHedef.varlikSiniri;
  }
  return switch (kaynak) {
    'aylik_rapor' => PremiumAcildiHedef.aylikRapor,
    'temettu_tahmini' || 'temettu_verimi' => PremiumAcildiHedef.temettu,
    'sattiklarin' || 'kapanis_ozeti' => PremiumAcildiHedef.sattiklarin,
    'aylik_getiri' => PremiumAcildiHedef.aylikGetiri,
    _ => null,
  };
}

/// Saf: hangi satırlar, hangi sırayla (en fazla üç).
///
/// - Yalnız verisi olan satır girer; aylık getiri tablonun kendi eşiğinde
///   ([aylikGetiriAsgariAy]), altında kart zaten görünmez.
/// - Kaynağın satırı öne alınır.
/// - Varlık sınırı satırı yalnız iki durumda: paywall sınırdan açıldıysa
///   (önde, o kullanıcının sorusu buydu) ya da başka hiçbir satır yoksa.
List<PremiumAcildiHedef> premiumAcildiSatirlari(
    String kaynak, PremiumAcildiVerisi v) {
  final satirlar = <PremiumAcildiHedef>[
    if (v.raporDonemi != null) PremiumAcildiHedef.aylikRapor,
    if (v.temettuHisse > 0) PremiumAcildiHedef.temettu,
    if (v.kapanmisPozisyon > 0) PremiumAcildiHedef.sattiklarin,
    if (v.getiriAy >= aylikGetiriAsgariAy) PremiumAcildiHedef.aylikGetiri,
  ];
  final ilk = premiumAcildiKaynakHedefi(kaynak);
  if (ilk == PremiumAcildiHedef.varlikSiniri) {
    return [PremiumAcildiHedef.varlikSiniri, ...satirlar.take(2)];
  }
  if (ilk != null && satirlar.remove(ilk)) satirlar.insert(0, ilk);
  if (satirlar.isEmpty) return const [PremiumAcildiHedef.varlikSiniri];
  return satirlar.take(3).toList();
}

/// Satın alma başlarken çağrılır: satır sağlayıcılarını canlı tutar ki
/// mağaza diyaloğu sürerken sayılar hazırlansın (sayfa açıldığında
/// beklemesin). Dönen fonksiyon dinlemeyi bırakır.
void Function() premiumAcildiIsit(WidgetRef ref) {
  final abonelikler = [
    ref.listenManual(temettuTahminiProvider, (_, __) {}),
    ref.listenManual(aylikRaporDonemiProvider, (_, __) {}),
    ref.listenManual(sattiklarinProvider, (_, __) {}),
  ];
  return () {
    for (final a in abonelikler) {
      a.close();
    }
  };
}

/// Satın alma sonrası akış: sayfayı gösterir, sonra [paywallBaglami]'nın
/// rotasını `true` ile kapatır, satır seçildiyse hedefi açar.
///
/// Paywall'dan ayrı fonksiyon: dönüş sözleşmesi (her yolda `pop(true)`)
/// mağazasız test edilebilsin.
Future<void> premiumAcildiAkisi(BuildContext paywallBaglami,
    {required String kaynak}) async {
  final secim = await showSandikSheet<PremiumAcildiSecim>(
    context: paywallBaglami,
    baslik: paywallBaglami.l10n.premiumUnlocked,
    isScrollControlled: true,
    builder: (_) => PremiumAcildiSayfasi(kaynak: kaynak),
  );
  if (!paywallBaglami.mounted) return;
  final gezgin = Navigator.of(paywallBaglami);
  final kapsayici = ProviderScope.containerOf(paywallBaglami, listen: false);
  gezgin.pop(true);
  // Beklenmez: hedef ekran açık kaldıkça paywall'ın satın alma akışı
  // (ve `_busy`) asılı kalmasın.
  if (secim != null) {
    unawaited(premiumAcildiHedefiniAc(gezgin, secim,
        tutarGizli: () => kapsayici.read(balanceHiddenProvider)));
  }
}

/// Satıra dokunulunca sayfanın döndürdüğü seçim.
class PremiumAcildiSecim {
  const PremiumAcildiSecim(this.hedef, {this.raporDonemi});
  final PremiumAcildiHedef hedef;
  final DateTime? raporDonemi;
}

/// Hedefin rotası; sayfa değil sekme/alt sayfa olan hedefte `null`.
/// Rapor ve temettü Raporlar kapısındaki rotanın aynısı (aynı ad).
@visibleForTesting
Route<void>? premiumAcildiRotasi(PremiumAcildiSecim s) => switch (s.hedef) {
      PremiumAcildiHedef.aylikRapor when s.raporDonemi != null =>
        adaptiveRoute<void>(
            settings: const RouteSettings(name: 'aylik_rapor'),
            builder: (_) => AylikRaporScreen(donem: s.raporDonemi!)),
      PremiumAcildiHedef.temettu => adaptiveRoute<void>(
          settings: const RouteSettings(name: 'temettu_tahmini'),
          builder: (_) => const TemettuTahminiScreen()),
      _ => null,
    };

/// Seçimi açar. [gezgin] paywall'ın altındaki gezgin (paywall kapanmış).
Future<void> premiumAcildiHedefiniAc(
    NavigatorState gezgin, PremiumAcildiSecim s,
    {required bool Function() tutarGizli}) async {
  final rota = premiumAcildiRotasi(s);
  if (rota != null) {
    await pushGuarded(gezgin.context, rota);
    return;
  }
  switch (s.hedef) {
    case PremiumAcildiHedef.sattiklarin:
      await showSattiklarinListesi(gezgin.context, tutarGizli: tutarGizli);
    case PremiumAcildiHedef.aylikGetiri:
      // Tablo Performans sekmesinde: üstteki sayfalar kapanır, sekme
      // isteği kabuğa gider (bildirim dokunuşuyla aynı kanal).
      gezgin.popUntil((r) => r.isFirst);
      MainNavigationScreen.sekmeIstegi.value =
          MainNavigationScreen.performansSekmesi;
    case _:
      break;
  }
}

/// Sayfanın gövdesi (başlık `showSandikSheet`'te).
class PremiumAcildiSayfasi extends ConsumerWidget {
  const PremiumAcildiSayfasi({super.key, required this.kaynak, this.simdi});

  final String kaynak;

  /// Test için "bugün"; verilmezse `DateTime.now()`.
  final DateTime? simdi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final durum = ref.watch(portfolioProvider).valueOrNull;
    final veri = PremiumAcildiVerisi(
      raporDonemi: ref.watch(aylikRaporDonemiProvider),
      temettuHisse:
          ref.watch(temettuTahminiProvider).valueOrNull?.satirlar.length ?? 0,
      kapanmisPozisyon: ref.watch(sattiklarinProvider).length,
      getiriAy: durum == null
          ? 0
          : aylikGetiriAralikAySayisi(
              aylikRaporLotlari(durum), simdi ?? DateTime.now()),
    );
    final satirlar = premiumAcildiSatirlari(kaynak, veri);
    final dil = Localizations.localeOf(context).toString();
    final h = SandikSpace.screenH(context);

    Widget satir(PremiumAcildiHedef hedef) {
      final ay = veri.raporDonemi == null
          ? ''
          : DateFormat('MMMM', dil).format(veri.raporDonemi!);
      final (ikon, metin, ses) = switch (hedef) {
        PremiumAcildiHedef.aylikRapor => (
            Icons.summarize_rounded,
            l.pwAcildiRapor(ay),
            l.pwAcildiRaporSes(ay)
          ),
        PremiumAcildiHedef.temettu => (
            Icons.event_repeat_rounded,
            l.pwAcildiTemettu(veri.temettuHisse),
            l.pwAcildiTemettuSes(veri.temettuHisse)
          ),
        PremiumAcildiHedef.sattiklarin => (
            Icons.sell_outlined,
            l.pwAcildiSattiklarin(veri.kapanmisPozisyon),
            l.pwAcildiSattiklarinSes(veri.kapanmisPozisyon)
          ),
        PremiumAcildiHedef.aylikGetiri => (
            Icons.calendar_view_month_rounded,
            l.pwAcildiAylikGetiri(veri.getiriAy),
            l.pwAcildiAylikGetiriSes(veri.getiriAy)
          ),
        PremiumAcildiHedef.varlikSiniri => (
            Icons.all_inclusive_rounded,
            l.pwAcildiSinir(RemoteConfigService.instance.freeAssetLimit),
            null
          ),
      };
      return _Satir(
        key: ValueKey('premium_acildi_${hedef.name}'),
        ikon: ikon,
        metin: metin,
        ses: ses,
        // Varlık sınırı bilgi satırı: açacağı ekran "kaldığın yer"in ta
        // kendisi (çoğu zaman yarım kalan Varlık ekle), ayrı hedefi yok.
        onTap: hedef == PremiumAcildiHedef.varlikSiniri
            ? null
            : () => Navigator.of(context).pop(PremiumAcildiSecim(hedef,
                raporDonemi: veri.raporDonemi)),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(h, SandikSpace.sm, h, SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Büyük yazıda (3.1×) satırlar sayfadan uzun olabilir: liste
            // kayar, düğme altta sabit kalır.
            Flexible(
              child: SingleChildScrollView(
                child: AnimatedSize(
                  duration: SandikMotion.stateOf(context),
                  curve: SandikMotion.move,
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < satirlar.length; i++) ...[
                        if (i > 0)
                          Divider(
                              height: 1,
                              thickness: 1,
                              color: context.c.hairline),
                        satir(satirlar[i]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: SandikSpace.lg),
            // İstek atmayan ana eylem: tema `FilledButton` (amber, köşe 14).
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: SandikTouch.min),
              child: FilledButton(
                key: const ValueKey('premium_acildi_don'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.pwAcildiDon, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({
    super.key,
    required this.ikon,
    required this.metin,
    required this.ses,
    required this.onTap,
  });

  final IconData ikon;
  final String metin;

  /// Ekran okuyucu cümlesi (ne var + dokununca ne olur). Bilgi satırında
  /// `null`: görünen metin zaten tam cümle.
  final String? ses;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final govde = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
        child: Row(
          children: [
            Icon(ikon, size: SandikSpace.lgs, color: c.amberText),
            const SizedBox(width: SandikSpace.md),
            Expanded(
              child: Text(
                metin,
                style: context.t.bodyLarge
                    ?.copyWith(color: c.text90, fontWeight: FontWeight.w600),
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded,
                  size: SandikSpace.lgs, color: c.text58),
          ],
        ),
      ),
    );
    if (onTap == null) return govde;
    return SandikTappable(
      onTap: onTap,
      semanticLabel: ses,
      child: govde,
    );
  }
}
