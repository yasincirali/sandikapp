import 'package:flutter/material.dart';

import '../services/tefas_service.dart';
import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import 'zirve_dagilim_seridi.dart';

/// Fon kodu → resmi TEFAS adı. Test için değiştirilebilir.
typedef ZirveFonAdiBulucu = Future<String?> Function(String kod);

Future<String?> _tefasAdi(String kod) async =>
    (await TefasService.instance.lookupFund(kod))?.name;

/// Bir Zirve portföyünün varlıkları, büyükten küçüğe (okunaklılık turu,
/// yasin 2026-10-20: "daha okunaklı ve tasarım olarak da etkili").
///
/// Eski hâl üç ayrı parçaydı: tür satırı, altında tür içi çubuklu kod
/// listesi (`ZirveVarlikListesi` / `ZirveFonListesi`) ve kartta tek satır
/// "Varlıklar: THYAO %21 · …" özeti. Sorun:
/// - Çubuklar TÜR içine göre ölçekliydi: tek kalemli altın %7 iken tam
///   dolu, hisse içinde %11 yarım görünüyordu — göz yanlış büyüklüğü okur.
/// - Sembol küçük gri çip içindeydi (9 pt), yüzde ondalığı keyfiydi.
///
/// Şimdi tek kural: her satır **toplam portföyün** payı, çubuk portföyün
/// EN BÜYÜK kalemine göre (en büyük kalem tam dolu, gerisi ona oranla).
/// Böylece "%21 THYAO" ile "%7 Çeyrek Altın" arasındaki fark çubukta da
/// üç kat. Yüzde biçimi `ZirveKiyas.pay` (tek ondalık, sondaki sıfır yok).
///
/// İki biçim:
/// - **Sıralı** ([gruplu] false): türler karışık ilk [enFazla] kalem —
///   seçili portföy kartındaki "En büyük varlıkları". Tür adı ikinci
///   satırda yazılır (renk tek başına anlam taşımaz).
/// - **Gruplu**: alt sayfa. Tür başlığı (ad + toplam pay), altında o türün
///   kalemleri ve "Diğer kalemler" (%1 altı ya da sembolsüz toplam).
///
/// ## Kilitli satır (0158 vitrini)
/// Premium olmayan kullanıcıya sunucu en büyük kalemi açık, gerisini `?n`
/// gönderir (sembol cihaza gelmez). Satır yine çizilir: ad yerine kilit +
/// "••••", oran ve çubuk açık; dokununca [onKilitli]. Ekran okuyucu
/// "Kilitli varlık %12. Premium'da görünür." duyar.
class ZirveVarlikSiralamasi extends StatefulWidget {
  const ZirveVarlikSiralamasi({
    super.key,
    required this.fonDetay,
    required this.varlikDetay,
    this.pay = const {},
    this.gruplu = false,
    this.enFazla,
    this.onKilitli,
    this.adBul,
  });

  /// {TEFAS kodu: toplam portföyün %'si}.
  final Map<String, double> fonDetay;

  /// {tür: {sembol: toplam portföyün %'si}} — fon dışı türler (0158).
  final Map<String, Map<String, double>> varlikDetay;

  /// Tür payları; gruplu biçimde başlık ve "Diğer kalemler" için.
  final Map<String, double> pay;
  final bool gruplu;

  /// Sıralı biçimde en fazla kaç kalem; null → hepsi.
  final int? enFazla;
  final VoidCallback? onKilitli;
  final ZirveFonAdiBulucu? adBul;

  /// Gösterilecek bir kalem var mı (kart "En büyük varlıkları"nı buna
  /// göre çizer).
  static bool doluMu(
          Map<String, double> fon, Map<String, Map<String, double>> varlik) =>
      ZirveKiyas.tumKalemler(fon, varlik).isNotEmpty;

  @override
  State<ZirveVarlikSiralamasi> createState() => _ZirveVarlikSiralamasiState();
}

class _ZirveVarlikSiralamasiState extends State<ZirveVarlikSiralamasi> {
  // Fon adı Future'ları kod başına bir kez; her build'de yeni istek yok.
  final Map<String, Future<String?>> _adlar = {};

  Future<String?> _ad(String kod) => _adlar.putIfAbsent(
      kod, () => (widget.adBul ?? _tefasAdi)(kod).catchError((_) => null));

  @override
  Widget build(BuildContext context) {
    final kalemler =
        ZirveKiyas.tumKalemler(widget.fonDetay, widget.varlikDetay);
    final enBuyuk = kalemler.isEmpty ? 0.0 : kalemler.first.pay;
    if (!widget.gruplu) {
      final gorunen = widget.enFazla == null
          ? kalemler
          : kalemler.take(widget.enFazla!).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final k in gorunen)
            _satir(context, k.tur, k.kod, k.pay, enBuyuk, turuYaz: true),
        ],
      );
    }
    final turler = ZirveKiyas.sirali(widget.pay);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final t in turler) ...[
          _TurBasligi(tur: t.tur, pay: t.pay),
          for (final k in kalemler.where((k) => k.tur == t.tur))
            _satir(context, k.tur, k.kod, k.pay, enBuyuk, turuYaz: false),
          if (_diger(t.tur, t.pay, kalemler) case final d?)
            _satir(context, t.tur, ZirveKiyas.fonDiger, d, enBuyuk,
                turuYaz: false),
          const SizedBox(height: SandikSpace.smd),
        ],
      ],
    );
  }

  /// Türün listelenmeyen kısmı (%1 altı, sembolsüz, eski rıza). Tür
  /// ayrıntısı hiç yoksa (ör. mevduat, eski sunucu) satır çizilmez —
  /// başlık zaten payı söyler.
  double? _diger(String tur, double turPayi,
      List<({String tur, String kod, double pay})> kalemler) {
    final detay = tur == 'fon' ? widget.fonDetay : widget.varlikDetay[tur];
    if (detay == null || detay.isEmpty) return null;
    final listelenen = kalemler
        .where((k) => k.tur == tur)
        .fold<double>(0, (s, k) => s + k.pay);
    final kalan = turPayi - listelenen;
    return kalan >= 0.5 ? kalan : null;
  }

  Widget _satir(
      BuildContext context, String tur, String kod, double pay, double enBuyuk,
      {required bool turuYaz}) {
    final kilitli = ZirveKiyas.kilitliMi(kod);
    final diger = kod == ZirveKiyas.fonDiger;
    final renk = ZirveDagilimSeridi.renk(context, tur);
    final turAdi = ZirveDagilimSeridi.etiket(context, tur);
    final yuzde = ZirveKiyas.pay(pay);
    final ad = diger
        ? 'Diğer kalemler'
        : kilitli
            ? ZirveKiyas.kilitliYer
            : tur == 'fon'
                ? kod
                : ZirveKiyas.varlikAdi(kod);

    // İkinci satır: kilitliyse ne yapacağı, fonsa resmi adı, sıralı
    // biçimde türü. Gruplu biçimde tür zaten başlıkta.
    Widget? alt;
    if (kilitli) {
      alt = _altMetin(context, "Premium'da görünür", context.c.amberText);
    } else if (diger) {
      alt = _altMetin(
          context, 'her biri %1 altı ya da sembolsüz', context.c.text58);
    } else if (tur == 'fon') {
      alt = FutureBuilder<String?>(
        future: _ad(kod),
        builder: (context, s) => _altMetin(
            context, s.data ?? (turuYaz ? turAdi : ''), context.c.text58),
      );
    } else if (turuYaz) {
      alt = _altMetin(context, turAdi, context.c.text58);
    }

    final govde = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: SandikSpace.xs2),
                  child: kilitli
                      ? Icon(Icons.lock_rounded,
                          size: SandikSpace.md2, color: context.c.amberText)
                      : Container(
                          width: SandikSpace.sm2,
                          height: SandikSpace.sm2,
                          decoration: BoxDecoration(
                            color: diger ? renk.withValues(alpha: 0.45) : renk,
                            shape: BoxShape.circle,
                          ),
                        ),
                ),
                const SizedBox(width: SandikSpace.sm2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ad,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.bodyMedium?.copyWith(
                          fontWeight: diger ? FontWeight.w500 : FontWeight.w700,
                          letterSpacing: kilitli ? 1.5 : 0,
                          color: diger ? context.c.text58 : context.c.text90,
                        ),
                      ),
                      if (alt != null) alt,
                    ],
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Text(
                  yuzde,
                  style: context.t.numSmall.copyWith(
                    color: diger ? context.c.text58 : context.c.text90,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SandikSpace.xs2),
            Padding(
              padding: const EdgeInsets.only(
                  left: SandikSpace.sm2 + SandikSpace.sm2),
              child: _Cubuk(
                oran: enBuyuk <= 0 ? 0 : (pay / enBuyuk).clamp(0.0, 1.0),
                renk: diger ? renk.withValues(alpha: 0.45) : renk,
              ),
            ),
          ],
        ),
      ),
    );

    if (!kilitli) {
      return Semantics(
        label: diger
            ? '$turAdi, diğer kalemler $yuzde'
            : '$ad${turuYaz ? ', $turAdi' : ''} $yuzde',
        excludeSemantics: true,
        child: govde,
      );
    }
    return Semantics(
      button: widget.onKilitli != null,
      label: "Kilitli varlık $yuzde. Premium'da görünür.",
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onKilitli,
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        child: govde,
      ),
    );
  }

  Widget _altMetin(BuildContext context, String metin, Color renk) {
    if (metin.isEmpty) return const SizedBox.shrink();
    return Text(
      metin,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.t.bodySmall?.copyWith(color: renk),
    );
  }
}

/// Gruplu biçimde tür başlığı: renkli kare, tür adı, toplam pay.
class _TurBasligi extends StatelessWidget {
  const _TurBasligi({required this.tur, required this.pay});

  final String tur;
  final double pay;

  @override
  Widget build(BuildContext context) {
    final ad = ZirveDagilimSeridi.etiket(context, tur);
    return Semantics(
      header: true,
      label: '$ad toplam ${ZirveKiyas.pay(pay)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: SandikSpace.xs),
        child: Row(
          children: [
            Container(
              width: SandikSpace.smd,
              height: SandikSpace.smd,
              decoration: BoxDecoration(
                color: ZirveDagilimSeridi.renk(context, tur),
                borderRadius: BorderRadius.circular(SandikSpace.xxs),
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: Text(
                ad,
                style: context.t.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.c.text90,
                ),
              ),
            ),
            Text(
              ZirveKiyas.pay(pay),
              style: context.t.numMedium.copyWith(color: context.c.text90),
            ),
          ],
        ),
      ),
    );
  }
}

/// İnce çubuk; genişlik değişince akar ("hareketi azalt" açıkken anında).
class _Cubuk extends StatelessWidget {
  const _Cubuk({required this.oran, required this.renk});

  final double oran;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SandikRadius.sm),
      child: Container(
        height: SandikSpace.xs,
        color: context.c.overlay,
        alignment: Alignment.centerLeft,
        child: AnimatedFractionallySizedBox(
          duration: SandikMotion.flowOf(context),
          curve: SandikMotion.glide,
          widthFactor: oran,
          heightFactor: 1,
          child: ColoredBox(color: renk),
        ),
      ),
    );
  }
}
