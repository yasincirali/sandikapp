import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../providers/fon_akisi_provider.dart';
import '../services/fon_akisi.dart';
import '../services/fon_karnesi.dart' show fonKoduOf;
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Para akışı kartı (Balina B1, 2026-10-04) — fona giren ve çıkan para.
///
/// Hesap `fon_akisi.dart`'ta (saf), veri `fonAkisiProvider`'da, kural
/// sunucuda (`_shared/balina.ts`); bu dosya yalnızca çizer.
///
/// ## Ne zaman HİÇ çizilmez
///   · Bayrak (`balina_radari_acik`) kapalı — o durumda istek de atılmaz,
///   · varlık fon/BES değil,
///   · veri yükleniyor, yok, bayat ya da okunamadı.
/// Yükleme iskeleti çizilmez (fon karnesiyle aynı karar): gelmeyebilecek bir
/// kutu için yer ayırmak sayfada boşluk bırakırdı.
///
/// ## Okuma sırası (yukarıdan aşağı)
/// 1. Tek sayı: son haftanın net girişi/çıkışı ve hangi günleri kapsadığı.
/// 2. Sekiz haftalık çubuklar — sayı tek başına büyük mü küçük mü, bağlamı.
/// 3. Fon büyüklüğü ve yatırımcı sayısı — sayının neye göre büyük olduğu.
/// 4. Büyük hareketler — kurala uyan günler, kanıtıyla.
/// 5. Kaynak, veri tarihi ve sınır: "kimin aldığı bilinemez".
///
/// ## Dil
/// "Balina" denmez: TEFAS kimin alıp sattığını vermiyor; bilmediğimizi ima
/// eden bir etiket yanıltıcı olurdu. Etiket kanıtla sınırlı: "büyük giriş".
/// Renk yalnız yön bildirir (giriş `gain`, çıkış `loss`); "iyi/kötü" yorumu
/// yok, al/sat dili yok.
class ParaAkisiKarti extends ConsumerWidget {
  const ParaAkisiKarti({
    super.key,
    required this.tur,
    required this.ticker,
    this.dis = const EdgeInsets.only(bottom: SandikSpace.lg),
  });

  final AssetType tur;
  final String ticker;

  /// Kart çizildiğinde çevresine bırakılan boşluk; çizilmezse boşluk da yok.
  final EdgeInsetsGeometry dis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(balinaRadariAcikProvider)) return const SizedBox.shrink();
    final kod = fonKoduOf(tur: tur, ticker: ticker);
    if (kod == null) return const SizedBox.shrink();
    final ozet = ref.watch(fonAkisiProvider(kod)).valueOrNull;
    if (ozet == null) return const SizedBox.shrink();

    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final gunAy = DateFormat('d MMM', Localizations.localeOf(context).toString());
    final net = ozet.sonHaftaNet;
    final (baslik, renk) = net > 0
        ? (l10n.flowLastWeekIn, c.gain)
        : net < 0
            ? (l10n.flowLastWeekOut, c.loss)
            : (l10n.flowLastWeekFlat, c.text90);

    return Padding(
      padding: dis,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l10n.flowTitleUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1) Tek sayı.
                Text(baslik,
                    style: t.bodyMedium?.copyWith(color: c.text58)),
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  isaretliTutar(net),
                  style: t.numMedium.copyWith(color: renk),
                ),
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  l10n.flowRange(gunAy.format(ozet.sonHaftaIlkGun),
                      gunAy.format(ozet.veriTarihi)),
                  style: t.bodySmall?.copyWith(color: c.text58),
                ),
                const SizedBox(height: SandikSpace.md),

                // 2) Sekiz hafta.
                Semantics(
                  label: l10n.flowChartSemantics(isaretliTutar(net)),
                  child: ExcludeSemantics(
                    child: _HaftaCubuklari(haftalar: ozet.haftalar),
                  ),
                ),
                const SizedBox(height: SandikSpace.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.flowChartCaption,
                        style: t.bodySmall?.copyWith(color: c.text36),
                      ),
                    ),
                    const SizedBox(width: SandikSpace.sm),
                    Text(
                      l10n.flowWeekOf(
                          gunAy.format(ozet.haftalar.last.baslangic)),
                      style: t.bodySmall?.copyWith(color: c.text36),
                    ),
                  ],
                ),
                const SizedBox(height: SandikSpace.xs),
                Text(l10n.flowExplain,
                    style: t.bodySmall?.copyWith(color: c.text58)),

                // 3) Bağlam.
                _Ayrac(),
                _Satir(
                    etiket: l10n.flowFundSize,
                    deger: fmtTRYCompact(ozet.buyukluk)),
                if (ozet.yatirimci != null) ...[
                  const SizedBox(height: SandikSpace.sm),
                  _Satir(
                    etiket: l10n.flowInvestors,
                    deger: ozet.yatirimciDegisimi == null
                        ? _adet(ozet.yatirimci!)
                        : l10n.flowInvestorsDelta(_adet(ozet.yatirimci!),
                            _isaretliAdet(ozet.yatirimciDegisimi!)),
                  ),
                ],

                // 4) Büyük hareketler.
                _Ayrac(),
                Text(
                  l10n.flowEventsTitle,
                  style: t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600, color: c.text90),
                ),
                const SizedBox(height: SandikSpace.sm),
                if (ozet.olaylar.isEmpty)
                  Text(l10n.flowNoEvents,
                      style: t.bodySmall?.copyWith(color: c.text58))
                else
                  for (var i = 0; i < ozet.olaylar.length; i++) ...[
                    if (i > 0) const SizedBox(height: SandikSpace.smd),
                    _OlaySatiri(olay: ozet.olaylar[i], gunAy: gunAy),
                  ],

                // 5) Kaynak ve sınır.
                const SizedBox(height: SandikSpace.md),
                Text(
                  l10n.flowFootnote(gunAy.format(ozet.veriTarihi)),
                  style: t.bodySmall?.copyWith(color: c.text36),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Haftalık net akış çubukları: sıfır çizgisinin üstü giriş, altı çıkış.
///
/// Verisi olmayan hafta BOŞ kalır (sıfır yüksekliğinde çubuk "para girmedi"
/// derdi). Son hafta tam renk, öncekiler soluk: üstteki sayının hangi çubuk
/// olduğu aranmadan görülsün.
class _HaftaCubuklari extends StatelessWidget {
  const _HaftaCubuklari({required this.haftalar});

  final List<HaftaAkisi> haftalar;

  /// Sıfır çizgisinin bir yanındaki en yüksek çubuk.
  static const double _yari = 36;

  /// Sıfırdan farklı akışın en kısa çubuğu — küçük hafta da görünsün.
  static const double _enKisa = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    var enBuyuk = 0.0;
    for (final h in haftalar) {
      enBuyuk = math.max(enBuyuk, (h.net ?? 0).abs());
    }

    return SizedBox(
      height: _yari * 2 + 1,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: _yari,
            child: Container(height: 1, color: c.hairline),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < haftalar.length; i++) ...[
                if (i > 0) const SizedBox(width: SandikSpace.xs2),
                Expanded(
                  child: _cubuk(
                    haftalar[i].net,
                    enBuyuk,
                    sonHafta: i == haftalar.length - 1,
                    c: c,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _cubuk(double? net, double enBuyuk,
      {required bool sonHafta, required SandikPalette c}) {
    if (net == null || net == 0 || enBuyuk <= 0) return const SizedBox.shrink();
    final boy = math.max(_enKisa, net.abs() / enBuyuk * _yari);
    final renk = (net > 0 ? c.gain : c.loss)
        .withValues(alpha: sonHafta ? 1 : 0.45);
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
          height: _yari,
          child: net > 0
              ? Align(alignment: Alignment.bottomCenter, child: kutu)
              : null,
        ),
        const SizedBox(height: 1),
        SizedBox(
          height: _yari,
          child: net < 0
              ? Align(alignment: Alignment.topCenter, child: kutu)
              : null,
        ),
      ],
    );
  }
}

class _Ayrac extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.smd),
        child: Divider(height: 1, thickness: 1, color: context.c.hairline),
      );
}

class _Satir extends StatelessWidget {
  const _Satir({required this.etiket, required this.deger});

  final String etiket;
  final String deger;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(etiket,
                style: context.t.bodyMedium
                    ?.copyWith(color: context.c.text58)),
          ),
          const SizedBox(width: SandikSpace.sm),
          // Değer kısa ve tek satır (kısaltılmış tutar, adet): `Flexible`
          // satırı etiketle yarı yarıya bölüp değeri ortada bırakıyordu
          // (emülatör, 2026-10-04). Esneyen yalnız etiket.
          Text(
            deger,
            textAlign: TextAlign.end,
            style: context.t.numSmall.copyWith(
                fontWeight: FontWeight.w600, color: context.c.text90),
          ),
        ],
      );
}

class _OlaySatiri extends StatelessWidget {
  const _OlaySatiri({required this.olay, required this.gunAy});

  final FonBalinaOlayi olay;
  final DateFormat gunAy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final tarih = gunAy.format(olay.tarih);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: SandikSpace.xs2),
          child: Container(
            width: SandikSpace.sm,
            height: SandikSpace.sm,
            decoration: BoxDecoration(
              color: olay.giris ? c.gain : c.loss,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: SandikSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                olay.giris ? l10n.flowEventIn(tarih) : l10n.flowEventOut(tarih),
                style: t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600, color: c.text90),
              ),
              const SizedBox(height: SandikSpace.xxs),
              Text(
                l10n.flowEventEvidence(
                  isaretliTutar(olay.tutar),
                  fmtPct(olay.buyuklukOrani * 100, digits: 1),
                  fmtNum(olay.sapmaKati, digits: 1),
                ),
                style: t.bodySmall?.copyWith(color: c.text58),
              ),
              if (olay.yatirimciDegisimi != null) ...[
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  l10n.flowEventInvestors(
                      _isaretliAdet(olay.yatirimciDegisimi!)),
                  style: t.bodySmall?.copyWith(color: c.text58),
                ),
              ],
            ],
          ),
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

String _adet(int n) => fmtNum(n.toDouble(), digits: 0);

String _isaretliAdet(int n) {
  if (n > 0) return '+${_adet(n)}';
  if (n < 0) return '−${_adet(-n)}';
  return '0';
}
