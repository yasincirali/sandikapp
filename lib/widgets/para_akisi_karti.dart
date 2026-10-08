import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../providers/fon_akisi_provider.dart';
import '../providers/premium_provider.dart';
import '../screens/hafta_ozeti_screen.dart';
import '../screens/para_akisi_detay_screen.dart';
import '../screens/paywall_screen.dart';
import '../services/fon_akisi.dart';
import '../services/fon_karnesi.dart' show fonKoduOf;
import '../services/radar_okuma.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'radar_ortak.dart';

/// Para akışı kartı (Balina B1 2026-10-04; özet kart 2026-10-05, S1-B).
///
/// Hesap `fon_akisi.dart` + `radar_okuma.dart`'ta (saf), veri
/// `fonAkisiProvider`'da, kural sunucuda (`_shared/balina.ts`); bu dosya
/// yalnızca çizer.
///
/// ## Neden özet kart + ayrıntı ekranı
/// Kart eskiden altı bölüm ve dört açıklama paragrafıyla fon sayfasının en
/// uzun kartıydı; az bilgili kullanıcı paragrafları okumuyor, bilgili
/// kullanıcıyı yoruyordu (kullanıcı kararı 2026-10-05: "açıklama yerine ux").
/// Kart artık tek soruyu cevaplar — "son hafta bu fona ne oldu?":
///   1. veriden üretilen düz cümle (`fonOkunusu`),
///   2. kanıtı olan sayı ve dokunulabilir "net akış" terimi,
///   3. fonun KENDİ olağanına göre ölçek,
///   4. 8 haftalık küçük çubuklar ve "Ayrıntı ›".
/// Dönem oranları, ayrıştırma, yatırımcı, kategori sırası ve büyük
/// hareketler ayrıntı ekranında (`ParaAkisiDetayScreen`).
///
/// ## Ne zaman HİÇ çizilmez
/// Bayrak (`balina_radari_acik`) kapalı — istek de atılmaz —, varlık fon/BES
/// değil, veri yükleniyor / yok / bayat / okunamadı. Yükleme iskeleti
/// çizilmez: gelmeyebilecek bir kutu için yer ayırmak boşluk bırakırdı.
///
/// ## Premium (S12-B)
/// Paywall açık ve kullanıcı Premium değilse cümle ve sayı AÇIK kalır
/// (ücretsiz katman da bir şey öğrenir), 8 haftalık seyir ve ayrıntı
/// kilitlenir: yerine "8 haftalık seyir ve N büyük hareket Premium'da ›".
/// Paywall kapalıyken kilit yoktur — bugünkü davranış.
///
/// ## Dil
/// "Balina" denmez: TEFAS kimin alıp sattığını vermiyor. Renk yalnız yön
/// bildirir (giriş `gain`, çıkış `loss`); ölçek nötr; al/sat dili yok.
class ParaAkisiKarti extends ConsumerWidget {
  const ParaAkisiKarti({
    super.key,
    required this.tur,
    required this.ticker,
    this.dis = const EdgeInsets.only(bottom: SandikSpace.lg),
    this.haftaBaglantisi = false,
  });

  final AssetType tur;
  final String ticker;

  /// Kartın altında "Tüm fonlarımın haftası" bağlantısı. Yalnız kullanıcının
  /// KENDİ varlığının sayfasında: o ekran tuttuğu varlıkları listeler; takip
  /// / önizleme sayfasında (portföyde olmayan fon) bağlantı yanıltırdı.
  final bool haftaBaglantisi;

  /// Kart çizildiğinde çevresine bırakılan boşluk; çizilmezse boşluk da yok.
  final EdgeInsetsGeometry dis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(balinaRadariAcikProvider)) return const SizedBox.shrink();
    final kod = fonKoduOf(tur: tur, ticker: ticker);
    if (kod == null) return const SizedBox.shrink();
    final ozet = ref.watch(fonAkisiProvider(kod)).valueOrNull;
    if (ozet == null) return const SizedBox.shrink();
    final kilitli = ref.watch(radarKilitliProvider);

    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final gunAy =
        DateFormat('d MMM', Localizations.localeOf(context).toString());
    final okunus = fonOkunusu(ozet);
    final net = ozet.sonHaftaNet;
    final aralik = l10n.flowRange(
        gunAy.format(ozet.sonHaftaIlkGun), gunAy.format(ozet.veriTarihi));
    final olaySayisi = ozet.olaylar.length;

    void ayrintiyaGit() => pushGuarded(
          context,
          adaptiveRoute<void>(builder: (_) => ParaAkisiDetayScreen(kod: kod)),
        );

    return Padding(
      padding: dis,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l10n.flowTitleUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            onTap: kilitli ? null : ayrintiyaGit,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1) Cümle.
                Text(fonCumlesi(l10n, okunus),
                    style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600, color: c.text90)),
                const SizedBox(height: SandikSpace.sm),
                // 2) Kanıt: sayı + kademe etiketi.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(isaretliTutar(net),
                        style: t.numMedium.copyWith(color: yonRengi(c, net))),
                    const SizedBox(width: SandikSpace.sm),
                    if (okunus.kademe != null)
                      Expanded(
                        child: Text(
                          kademeEtiketi(l10n, okunus.kademe!, hafta: true),
                          textAlign: TextAlign.end,
                          style: t.bodySmall?.copyWith(
                              color: c.text58, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
                TerimMetni(
                  terim: RadarTerim.netAkis,
                  metin: l10n.rdrFonNetAralik(aralik),
                  ornek: '$kod · ${isaretliTutar(net)}',
                ),
                // 3) Ölçek.
                if (okunus.kademe != null) ...[
                  const SizedBox(height: SandikSpace.xs),
                  OlcekCubugu(kademe: okunus.kademe!),
                ],
                const SizedBox(height: SandikSpace.md),
                // 4) Seyir ya da kilit.
                if (kilitli)
                  KilitSatiri(
                    metin: l10n.prmKilitAkis('$olaySayisi'),
                    kaynak: 'para_akisi_karti',
                  )
                else ...[
                  Semantics(
                    label: l10n.flowChartSemantics(isaretliTutar(net)),
                    child: ExcludeSemantics(
                      child: HaftaCubuklari(
                          haftalar: ozet.haftalar, yari: SandikSpace.lgs),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${l10n.rdrSon8Hafta} · ${olaySayisi == 0 ? l10n.rdrBuyukHareketYok : l10n.rdrBuyukHareketSayisi('$olaySayisi')}',
                          style: t.bodySmall?.copyWith(color: c.text58),
                        ),
                      ),
                      AyrintiBaglantisi(onTap: ayrintiyaGit),
                    ],
                  ),
                ],
                RadarKaynakSatiri(
                    kaynak: 'TEFAS', tarih: gunAy.format(ozet.veriTarihi)),
                if (haftaBaglantisi)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    // Yatay dolgu yok: bağlantı üstündeki kaynak satırıyla
                    // aynı hizadan başlasın (web testinde içeride kalıyordu).
                    // Dokunma alanı yükseklikte korunur.
                    child: TextButton(
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: SandikTouch.minSize),
                      onPressed: () => pushGuarded(
                        context,
                        adaptiveRoute<void>(
                            builder: (_) => const HaftaOzetiScreen()),
                      ),
                      child: Text(l10n.weekLink),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartın ve ayrıntı ekranının tepe cümlesi. Yön ve kademe AYNI okunuştan:
/// cümle "girdi" derken sayı eksi olamaz (`radar_okuma_test`).
String fonCumlesi(AppLocalizations l, FonOkunusu o) {
  if (o.yon == Yon.denge) return l.rdrFonDenge;
  if (o.karsiYonOlay) return l.rdrFonKarisik;
  final giris = o.yon == Yon.giris;
  return switch (o.kademe) {
    null => giris ? l.rdrFonGiris : l.rdrFonCikis,
    Kademe.sakin => giris ? l.rdrFonGirisSakin : l.rdrFonCikisSakin,
    Kademe.hareketli => giris ? l.rdrFonGirisHareketli : l.rdrFonCikisHareketli,
    Kademe.cokHareketli => giris ? l.rdrFonGirisCok : l.rdrFonCikisCok,
  };
}

Color yonRengi(SandikPalette c, double v) => v > 0
    ? c.gain
    : v < 0
        ? c.loss
        : c.text90;

/// Kilitli içerik satırı (S12-B) — radar kartları ve not kutusu ortak
/// kullanır: ne kilitli olduğunu somut söyler, satın alma ekranını açar.
class KilitSatiri extends StatelessWidget {
  const KilitSatiri({super.key, required this.metin, required this.kaynak});

  final String metin;

  /// Analitikte paywall'ın nereden açıldığı.
  final String kaynak;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: () => PaywallScreen.show(context, source: kaynak),
      borderRadius: SandikRadius.smAll,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded,
                size: SandikSpace.md, color: c.amberText),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: Text(metin,
                  style: context.t.bodySmall
                      ?.copyWith(color: c.text90, fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right_rounded,
                size: SandikSpace.lgs, color: c.text58),
          ],
        ),
      ),
    );
  }
}

/// Haftalık net akış çubukları: sıfır çizgisinin üstü giriş, altı çıkış.
///
/// Verisi olmayan hafta BOŞ kalır (sıfır yüksekliğinde çubuk "para girmedi"
/// derdi). Son hafta (ya da [secili]) tam renk, diğerleri soluk. [onSec]
/// verilirse her çubuk dokunulabilir (ayrıntı ekranı).
class HaftaCubuklari extends StatelessWidget {
  const HaftaCubuklari({
    super.key,
    required this.haftalar,
    this.yari = 36,
    this.secili,
    this.onSec,
  });

  final List<HaftaAkisi> haftalar;

  /// Sıfır çizgisinin bir yanındaki en yüksek çubuk.
  final double yari;
  final int? secili;
  final ValueChanged<int>? onSec;

  /// Sıfırdan farklı akışın en kısa çubuğu — küçük hafta da görünsün.
  static const double _enKisa = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    var enBuyuk = 0.0;
    for (final h in haftalar) {
      enBuyuk = math.max(enBuyuk, (h.net ?? 0).abs());
    }
    final vurgu = secili ?? haftalar.length - 1;

    return SizedBox(
      height: yari * 2 + 1,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: yari,
            child: Container(height: 1, color: c.hairline),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < haftalar.length; i++) ...[
                if (i > 0) const SizedBox(width: SandikSpace.xs2),
                Expanded(
                  child: onSec == null
                      ? _cubuk(haftalar[i].net, enBuyuk, i == vurgu, c)
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSec!(i),
                          child:
                              _cubuk(haftalar[i].net, enBuyuk, i == vurgu, c),
                        ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _cubuk(double? net, double enBuyuk, bool vurgulu, SandikPalette c) {
    if (net == null || net == 0 || enBuyuk <= 0) return const SizedBox.expand();
    final boy = math.max(_enKisa, net.abs() / enBuyuk * yari);
    final renk =
        (net > 0 ? c.gain : c.loss).withValues(alpha: vurgulu ? 1 : 0.45);
    final kutu = Container(
      height: boy,
      decoration: BoxDecoration(
        color: renk,
        borderRadius: BorderRadius.circular(SandikSpace.xxs),
      ),
    );
    return Column(
      children: [
        SizedBox(
          height: yari,
          child: net > 0
              ? Align(alignment: Alignment.bottomCenter, child: kutu)
              : null,
        ),
        const SizedBox(height: 1),
        SizedBox(
          height: yari,
          child: net < 0
              ? Align(alignment: Alignment.topCenter, child: kutu)
              : null,
        ),
      ],
    );
  }
}

/// Yönlü kısa tutar: `+₺412,00M` / `−₺10,85M` / `₺0`. Eksi U+2212 —
/// uygulamanın tutarlarıyla aynı işaret (bkz. `fmtPctIsaretli` notu).
String isaretliTutar(double v) {
  final govde = fmtTRYCompact(v.abs());
  if (v > 0) return '+$govde';
  if (v < 0) return '−$govde';
  return govde;
}

String isaretliAdet(int n) {
  String adet(int x) => fmtNum(x.toDouble(), digits: 0);
  if (n > 0) return '+${adet(n)}';
  if (n < 0) return '−${adet(-n)}';
  return '0';
}
