import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../services/aylik_getiri_tablosu.dart' show AylikKiyas;
import '../services/aylik_rapor_ozeti.dart';
import '../theme/sandik.dart';
import '../utils/pozisyon_etiketi.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import 'hacim_radari_karti.dart' show kisaDolar;

/// Aylık raporun sayısal bölümleri (2026-11-07). Üçü de SandikCard içinde
/// satır listesi; hesap yok (veri `AylikRaporOzeti`'nde hazır), yalnız
/// biçim.
///
/// Yerleşim kuralı (HIG, Dynamic Type): satır `Row` + `Expanded`/`Flexible`
/// ve sarılabilen metin; sabit genişlik yok, 3.1× yazıda ve 320 pt'de taşma
/// yok (`aylik_rapor_bolumleri_test`). Yön yalnız renkle verilmez: tutar ve
/// yüzde işaretle (+/−) yazılır.

/// "Ayın varlıkları": her varlığın ay başına göre değişimi.
class AyinVarliklariBolumu extends StatelessWidget {
  const AyinVarliklariBolumu({super.key, required this.ozet});

  final AylikRaporOzeti ozet;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final dil = context.tarihDili;
    final olculemeyen = [
      for (final (k, tur, ad) in ozet.olculemeyen)
        pozisyonEtiketi(k, tur, l10n, ad: ad)
    ]..sort();
    final fiyat = ozet.fiyatTarihi;
    return _Bolum(
      baslik: l10n.anzAylikVarliklarBaslik,
      satirlar: [
        for (final v in ozet.varliklar) _VarlikSatiri(varlik: v),
      ],
      dipnotlar: [
        l10n.anzAylikVarliklarDipnot +
            (fiyat == null
                ? ''
                : ' ${l10n.raporFiyatTarihi(fmtTarih(fiyat, dil: dil, saat: true))}'),
        if (olculemeyen.isNotEmpty)
          l10n.anzAylikOlculemeyen(olculemeyen.join(', ')),
      ],
      c: c,
      t: t,
    );
  }
}

class _VarlikSatiri extends StatelessWidget {
  const _VarlikSatiri({required this.varlik});

  final AyinVarligi varlik;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final ad = pozisyonEtiketi(varlik.anahtar, varlik.tur, l10n, ad: varlik.ad);
    final yuzde = fmtPctIsaretli(varlik.pct, digits: 1);
    final tutar = isaretliTL(varlik.piyasaTRY);
    final renk = context.signColor(varlik.pct);
    return Semantics(
      label: l10n.anzAylikSemVarlik(ad, yuzde, tutar),
      excludeSemantics: true,
      child: _Satir(
        sol: Text(ad, style: t.bodyMedium?.copyWith(color: c.text90)),
        sag: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(yuzde,
                textAlign: TextAlign.end,
                style: t.numSmall.copyWith(color: renk)),
            Text(tutar,
                textAlign: TextAlign.end,
                style: t.bodySmall?.copyWith(color: c.text58)),
          ],
        ),
      ),
    );
  }
}

/// "Para girişi ve çıkışı": alım, satış, temettü ve net katkı.
class ParaAkisiBolumu extends StatelessWidget {
  const ParaAkisiBolumu({super.key, required this.akis});

  final AyinParaAkisi akis;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    Widget satir(String ad, String tutar, int? adet, {bool kalin = false}) =>
        MergeSemantics(
          child: _Satir(
            sol: Text(ad,
                style: t.bodyMedium?.copyWith(
                    color: c.text90,
                    fontWeight: kalin ? FontWeight.w600 : null)),
            sag: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(tutar,
                    textAlign: TextAlign.end,
                    style: t.numSmall.copyWith(color: c.text90)),
                if (adet != null)
                  Text(l10n.anzAylikAkisAdet(adet),
                      textAlign: TextAlign.end,
                      style: t.bodySmall?.copyWith(color: c.text58)),
              ],
            ),
          ),
        );
    return _Bolum(
      baslik: l10n.anzAylikAkisBaslik,
      satirlar: [
        if (akis.alimSayisi > 0)
          satir(
              l10n.anzAylikAkisAlim, isaretliTL(akis.alimTRY), akis.alimSayisi),
        if (akis.satisSayisi > 0)
          satir(l10n.anzAylikAkisSatis, isaretliTL(-akis.satisTRY),
              akis.satisSayisi),
        if (akis.temettuSayisi > 0)
          satir(l10n.anzAylikAkisTemettu, isaretliTL(-akis.temettuTRY),
              akis.temettuSayisi),
        satir(l10n.anzAylikAkisNet, isaretliTL(akis.netTRY), null, kalin: true),
      ],
      dipnotlar: [l10n.anzAylikAkisDipnot],
      c: c,
      t: t,
    );
  }
}

/// "Önemli gelişmeler": tarihli olaylar, yeniden eskiye.
class GelismelerBolumu extends StatelessWidget {
  const GelismelerBolumu({super.key, required this.gelismeler});

  final List<AyinGelismesi> gelismeler;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final gunAy = DateFormat('d MMMM', context.tarihDili);
    return _Bolum(
      baslik: l10n.anzAylikGelismeBaslik,
      satirlar: [
        for (final g in gelismeler)
          MergeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${gunAy.format(g.tarih)} · ${g.kod}',
                      style: t.bodySmall?.copyWith(
                          color: c.text58, fontWeight: FontWeight.w600)),
                  const SizedBox(height: SandikSpace.xxs),
                  Text(gelismeCumlesi(l10n, g),
                      style: t.bodyMedium?.copyWith(color: c.text90)),
                ],
              ),
            ),
          ),
      ],
      dipnotlar: [l10n.anzAylikGelismeDipnot],
      c: c,
      t: t,
    );
  }
}

/// Bir gelişmenin cümlesi — ekran ve (Türkçe sınıfla) PDF aynı metni yazar.
String gelismeCumlesi(AppLocalizations l10n, AyinGelismesi g) {
  String tutar(double v) => g.dolar ? kisaDolar(v) : fmtTRYCompact(v);
  return switch (g.tur) {
    AyinGelismeTuru.fonGiris => l10n.anzAylikGelismeFonGiris(
        tutar(g.tutar), fmtPct((g.oran ?? 0) * 100, digits: 1)),
    AyinGelismeTuru.fonCikis => l10n.anzAylikGelismeFonCikis(
        tutar(g.tutar), fmtPct((g.oran ?? 0) * 100, digits: 1)),
    AyinGelismeTuru.hacimYukselis ||
    AyinGelismeTuru.hacimDusus =>
      l10n.anzAylikGelismeHacim(tutar(g.tutar), fmtNum(g.kat ?? 0, digits: 1),
          fmtPctIsaretli((g.fiyatDegisim ?? 0) * 100, digits: 1)),
    AyinGelismeTuru.temettu => l10n.anzAylikGelismeTemettu(fmtTRY(g.tutar)),
  };
}

/// Önemli gelişmeler kartındaki haber satırı (0177): tarih, modelin kendi
/// cümlesiyle rakamsız özet ve kaynak bağlantısı. Bağlantı dış tarayıcıda
/// açılır (`url_launcher`, KAP satırının deseni); açılamazsa uyarı.
///
/// HIG: bağlantı düğmesi ≥ 44 pt (`SandikTouch.minSize`), erişilebilirlik
/// etiketi "… sayfasını tarayıcıda aç"; anlam yalnız renkle verilmez
/// ("Kaynak:" metni + dış bağlantı simgesi); metin sarılır, Dynamic Type'ta
/// taşma yok.
class AyinHaberiSatiri extends StatelessWidget {
  const AyinHaberiSatiri({super.key, required this.haber, this.acici});

  final AyinHaberi haber;

  /// Test için; verilmezse `launchUrl` (dış uygulama).
  final Future<bool> Function(Uri)? acici;

  Future<void> _ac(BuildContext context) async {
    var ok = false;
    try {
      ok = await (acici ??
          (u) => launchUrl(u, mode: LaunchMode.externalApplication))(haber.url);
    } catch (_) {
      // Tarayıcı yok / eklenti yanıt vermedi: aşağıdaki uyarı yeter;
      // kullanıcı eylemine bağlı, raporlanacak bir arıza değil.
      ok = false;
    }
    if (!ok && context.mounted) {
      sandikSnack(context, context.l10n.anzAylikHaberAcilamadi,
          kind: SandikSnackKind.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final gunAy = DateFormat('d MMMM', context.tarihDili);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.anzAylikHaberEtiket(gunAy.format(haber.tarih)),
            style: t.bodySmall
                ?.copyWith(color: c.text58, fontWeight: FontWeight.w600)),
        const SizedBox(height: SandikSpace.xxs),
        Text(haber.metin, style: t.bodyMedium?.copyWith(color: c.text90)),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(
            link: true,
            label: l10n.anzAylikHaberSemKaynak(haber.kaynak),
            excludeSemantics: true,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                  minimumSize: SandikTouch.minSize,
                  padding:
                      const EdgeInsets.symmetric(horizontal: SandikSpace.xs)),
              onPressed: () => _ac(context),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(l10n.anzAylikHaberKaynak(haber.kaynak),
                  overflow: TextOverflow.ellipsis, maxLines: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _Bolum extends StatelessWidget {
  const _Bolum({
    required this.baslik,
    required this.satirlar,
    required this.dipnotlar,
    required this.c,
    required this.t,
  });

  final String baslik;
  final List<Widget> satirlar;
  final List<String> dipnotlar;
  final SandikPalette c;
  final TextTheme t;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: SandikSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SandikSectionHeader(title: baslik),
            const SizedBox(height: SandikSpace.sm),
            SandikCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: SandikSpace.md, vertical: SandikSpace.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < satirlar.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: c.hairline),
                    satirlar[i],
                  ],
                ],
              ),
            ),
            for (final d in dipnotlar) ...[
              const SizedBox(height: SandikSpace.xs),
              Text(d, style: t.bodySmall?.copyWith(color: c.text58)),
            ],
          ],
        ),
      );
}

class _Satir extends StatelessWidget {
  const _Satir({required this.sol, required this.sag});

  final Widget sol;
  final Widget sag;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        // Satır bilgi taşır, dokunulmaz; yine de liste ritmi 44 pt.
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: sol),
              const SizedBox(width: SandikSpace.sm),
              // Değer sütunu sağa yaslı: rakamlar alt alta aynı kenarda biter.
              Expanded(
                flex: 2,
                child:
                    Align(alignment: AlignmentDirectional.topEnd, child: sag),
              ),
            ],
          ),
        ),
      );
}

/// Kilitli aylık rapor kartının kişisel satırı (2026-11-12). Yalnız sayısı
/// sıfırdan büyük parçalar yazılır; hiçbiri yoksa `null` (satır yok).
/// [ay]: ayın adı ("Ekim").
String? aylikKancaCumlesi(
    AppLocalizations l, String ay, AylikRaporKancasi k) {
  if (k.bos) return null;
  final parcalar = [
    if (k.alimSayisi > 0) l.prmAylikKancaAlim(k.alimSayisi),
    if (k.satisSayisi > 0) l.prmAylikKancaSatis(k.satisSayisi),
    if (k.temettuSayisi > 0) l.prmAylikKancaTemettu(k.temettuSayisi),
  ];
  final liste = switch (parcalar.length) {
    0 => null,
    1 => parcalar.first,
    _ => l.prmAylikKancaVe(
        parcalar.sublist(0, parcalar.length - 1).join(', '), parcalar.last),
  };
  if (liste == null) return l.prmAylikKancaNot(ay, k.notSayisi);
  if (k.notSayisi == 0) return l.prmAylikKancaHareket(ay, liste);
  return l.prmAylikKancaIkisi(ay, liste, k.notSayisi);
}

/// Aylık raporun kişisel kıyas cümlesi (2026-11-12). Ekran ve PDF aynı
/// cümleyi yazar. En iyi ay övülür, en zayıf ay yumuşak söylenir (artıda
/// geçen aylar hemen ardından); arada sıra verilir. Renk yok.
String aylikKiyasCumlesi(AppLocalizations l, AylikKiyas k) {
  if (k.enIyi) return l.prmKiyasEnIyi(k.arti, k.olculen);
  if (k.enZayif) return l.prmKiyasEnZayif(k.arti, k.olculen);
  return l.prmKiyasOrta(k.arti, k.olculen, k.sira);
}
