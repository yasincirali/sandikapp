import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../providers/fon_akisi_provider.dart';
import '../providers/premium_provider.dart';
import '../screens/hacim_detay_screen.dart';
import '../services/fon_akisi.dart' show HaftaAkisi;
import '../services/hisse_hacmi.dart';
import '../services/radar_okuma.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'para_akisi_karti.dart' show HaftaCubuklari, KilitSatiri;
import 'radar_ortak.dart';

/// Hacim radarı kartı (Balina B2 2026-10-04; özet kart 2026-10-05, S4-B) —
/// BIST hissesinin para hacmi.
///
/// Hesap `hisse_hacmi.dart` + `radar_okuma.dart`'ta (saf), veri
/// `hisseHacmiProvider`'da, kural sunucuda (`_shared/hacim.ts`); bu dosya
/// yalnızca çizer. Düzen para akışı kartıyla AYNI (cümle → sayı → ölçek →
/// seyir → Ayrıntı): kullanıcı deseni bir kez öğrenir.
///
/// ## Ne zaman HİÇ çizilmez
/// Bayrak (`balina_radari_acik`) kapalı, varlık BIST hissesi değil, veri
/// yok / bayat / okunamadı. Para akışı kartıyla aynı karar ve aynı bayrak.
///
/// ## Dil — fon kartından FARKLI ve bilinçli
/// Fonda pay adedi değiştiği için "para girdi/çıktı" ölçülebilir. Hissede
/// ölçülemez: her işlemin bir alıcısı ve bir satıcısı vardır. Bu yüzden
/// kart "giriş/çıkış" demez, çubuklar yeşil/kırmızı DEĞİL nötrdür; yön
/// yalnız o günün fiyat değişimi olarak yazılır. "Balina" denmez.
class HacimRadariKarti extends ConsumerWidget {
  const HacimRadariKarti({
    super.key,
    required this.tur,
    required this.ticker,
    this.dis = const EdgeInsets.only(bottom: SandikSpace.lg),
  });

  final AssetType tur;
  final String ticker;
  final EdgeInsetsGeometry dis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(balinaRadariAcikProvider)) return const SizedBox.shrink();
    final sembol = bistSembolu(tur: tur, ticker: ticker);
    if (sembol == null) return const SizedBox.shrink();
    final ozet = ref.watch(hisseHacmiProvider(sembol)).valueOrNull;
    if (ozet == null) return const SizedBox.shrink();
    final kilitli = ref.watch(radarKilitliProvider);

    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final gunAy =
        DateFormat('d MMM', Localizations.localeOf(context).toString());
    final kademe = hacimKademesi(ozet);
    final tarih = gunAy.format(ozet.sonGun.tarih);
    final tutar = fmtTRYCompact(ozet.sonGun.paraHacmi);

    void ayrintiyaGit() => pushGuarded(
          context,
          adaptiveRoute<void>(
              builder: (_) => HacimDetayScreen(anahtar: sembol, kripto: false)),
        );

    return Padding(
      padding: dis,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l10n.volTitleUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            onTap: kilitli ? null : ayrintiyaGit,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(hisseCumlesi(l10n, kademe, tarih, tutar),
                    style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600, color: c.text90)),
                const SizedBox(height: SandikSpace.sm),
                _SayiVeKademe(
                    sayi: tutar,
                    etiket: kademe == null
                        ? null
                        : kademeEtiketi(l10n, kademe, hafta: false)),
                TerimMetni(
                  terim: RadarTerim.hacim,
                  metin: ozet.fiyatDegisim == null
                      ? l10n.rdrHacimAltFiyatsiz
                      : l10n.rdrHacimAlt(
                          fmtPctIsaretli(ozet.fiyatDegisim! * 100, digits: 1)),
                  ornek: '$tarih · $tutar',
                ),
                if (kademe != null) ...[
                  const SizedBox(height: SandikSpace.xs),
                  OlcekCubugu(kademe: kademe),
                ],
                HaftaOlayiSatiri(ozet: ozet),
                const SizedBox(height: SandikSpace.md),
                if (kilitli)
                  KilitSatiri(
                      metin: l10n.prmKilitAyrinti, kaynak: 'hacim_radari')
                else ...[
                  Semantics(
                    label: l10n.volChartSemantics(tutar),
                    child: ExcludeSemantics(
                      child: GunCubuklari(
                        gunler: ozet.gunler,
                        ortalama: ozet.ortalama,
                        vurgulu: {for (final o in ozet.olaylar) o.tarih},
                        boy: SandikSpace.xl,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ozet.ortalama == null
                              ? l10n.volChartCaption
                              : l10n.rdrOrtalamaCizgisi,
                          style: t.bodySmall?.copyWith(color: c.text58),
                        ),
                      ),
                      AyrintiBaglantisi(onTap: ayrintiyaGit),
                    ],
                  ),
                ],
                RadarKaynakSatiri(kaynak: 'Yahoo Finance', tarih: tarih),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hisse kartı ve ayrıntı ekranının tepe cümlesi.
String hisseCumlesi(
        AppLocalizations l, Kademe? k, String tarih, String tutar) =>
    switch (k) {
      null => l.rdrHisseYalin(tarih, tutar),
      Kademe.sakin => l.rdrHisseSakin(tarih),
      Kademe.hareketli => l.rdrHisseHareketli(tarih),
      Kademe.cokHareketli => l.rdrHisseCok(tarih),
    };

/// Kripto kartı ve ayrıntı ekranının tepe cümlesi.
String kriptoCumlesi(AppLocalizations l, KriptoOkunusu o, String tarih) =>
    switch ((o.yon, o.kademe)) {
      (Yon.giris, Kademe.cokHareketli) => l.rdrKriptoAliciCok(tarih),
      (Yon.giris, _) => l.rdrKriptoAlici(tarih),
      (Yon.cikis, Kademe.cokHareketli) => l.rdrKriptoSaticiCok(tarih),
      (Yon.cikis, _) => l.rdrKriptoSatici(tarih),
      (Yon.denge, _) => l.rdrKriptoDenge(tarih),
    };

class _SayiVeKademe extends StatelessWidget {
  const _SayiVeKademe({required this.sayi, this.etiket});

  final String sayi;
  final String? etiket;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(sayi,
              style: context.t.numMedium.copyWith(color: context.c.text90)),
          const SizedBox(width: SandikSpace.sm),
          if (etiket != null)
            Expanded(
              child: Text(etiket!,
                  textAlign: TextAlign.end,
                  style: context.t.bodySmall?.copyWith(
                      color: context.c.text58, fontWeight: FontWeight.w600)),
            ),
        ],
      );
}

/// Günlük para hacmi çubukları. Renk NÖTR (hacim yön taşımaz); olağandışı
/// günler, son gün ve [secili] koyu, diğerleri soluk. [ortalama] verilirse
/// kesikli yatay çizgi: "olağan" gözle görülsün. [onSec] verilirse günler
/// dokunulabilir (ayrıntı ekranı).
class GunCubuklari extends StatelessWidget {
  const GunCubuklari({
    super.key,
    required this.gunler,
    required this.vurgulu,
    this.ortalama,
    this.boy = 64,
    this.secili,
    this.onSec,
  });

  final List<HacimGunu> gunler;
  final Set<DateTime> vurgulu;
  final double? ortalama;
  final double boy;
  final int? secili;
  final ValueChanged<int>? onSec;

  static const double _enKisa = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    var enBuyuk = ortalama ?? 0.0;
    for (final g in gunler) {
      enBuyuk = math.max(enBuyuk, g.paraHacmi);
    }
    double yukseklik(double v) =>
        enBuyuk <= 0 ? _enKisa : math.max(_enKisa, v / enBuyuk * boy);
    return SizedBox(
      height: boy,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < gunler.length; i++) ...[
                if (i > 0) const SizedBox(width: SandikSpace.xxs),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSec == null ? null : () => onSec!(i),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: yukseklik(gunler[i].paraHacmi),
                        decoration: BoxDecoration(
                          color: (secili == null
                                  ? (vurgulu.contains(gunler[i].tarih) ||
                                      i == gunler.length - 1)
                                  : i == secili)
                              ? c.text90
                              : c.text20,
                          borderRadius: BorderRadius.circular(SandikSpace.xxs),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (ortalama != null && enBuyuk > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: yukseklik(ortalama!),
              child: IgnorePointer(child: _KesikliCizgi(renk: c.amberText)),
            ),
        ],
      ),
    );
  }
}

class _KesikliCizgi extends StatelessWidget {
  const _KesikliCizgi({required this.renk});

  final Color renk;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, kutu) {
          const parca = SandikSpace.xs;
          final adet = (kutu.maxWidth / (parca * 2)).floor();
          return Row(
            children: [
              for (var i = 0; i < adet; i++) ...[
                Container(width: parca, height: 1, color: renk),
                const SizedBox(width: parca),
              ],
            ],
          );
        },
      );
}

/// BIST hissesinin sunucudaki anahtarı (`THYAO.IS`); değilse null. Yabancı
/// hisse kapsam dışı — para hacmi TL olmazdı (sunucu da toplamıyor).
String? bistSembolu({required AssetType tur, required String ticker}) {
  if (tur != AssetType.hisse) return null;
  final t = ticker.trim().toUpperCase();
  return RegExp(r'^[A-Z0-9]{2,10}\.IS$').hasMatch(t) ? t : null;
}

/// Kısa dolar tutarı (`$2,62Mr`, `$243,00M`) — TL kısaltmasıyla aynı kural,
/// yalnız simge farklı. Kripto hacmi USDT'dir; TL'ye çevrilmez.
String kisaDolar(double v) => fmtTRYCompact(v).replaceFirst('₺', r'$');

/// İşaretli kısa dolar: `+$212,40M`.
String isaretliDolar(double v) {
  final g = kisaDolar(v.abs());
  if (v > 0) return '+$g';
  if (v < 0) return '−$g';
  return g;
}

/// Uygulamadaki kripto ticker'ı ('KRIPTO:BTC'); değilse null. USDT'nin
/// kendisinin USDT paritesi yoktur.
String? kriptoTickeri({required AssetType tur, required String ticker}) {
  if (tur != AssetType.kripto) return null;
  final t = ticker.trim().toUpperCase();
  if (!RegExp(r'^KRIPTO:[A-Z0-9]{2,15}$').hasMatch(t)) return null;
  return t == 'KRIPTO:USDT' ? null : t;
}

/// Alıcı baskısı kartı (Balina B3 2026-10-05; S5-A aynı gün) — coinin
/// Binance USDT paritesinde alıcı ile satıcının "halat çekmesi" ve son 24
/// saatin saatlik net alımı.
///
/// ## Neden halat, neden "büyük işlemler" listesi değil
/// "Kim daha istekli" sorusu tek bakışta okunmalı: iki renkli tek çubuk.
/// Plandaki "büyük işlemler" listesi yerine saatlik net alım geldi: Binance
/// tek tek işlemleri 1.000'erlik parçalarla veriyor, 24 saati taramak
/// binlerce istek; eksik bir "büyük işlemler" listesi yanıltıcı olurdu.
/// Saatlik mumlar (0115) her saatin alıcı payını verir; net alım
/// = 2 × alıcı hacmi − toplam (sunucudaki `netAlim` ile aynı formül).
///
/// Tutarlar USDT'dir ("$"); TL'ye çevrilmez. Kaynak yalnız Binance.
class KriptoBaskiKarti extends ConsumerWidget {
  const KriptoBaskiKarti({
    super.key,
    required this.tur,
    required this.ticker,
    this.dis = const EdgeInsets.only(bottom: SandikSpace.lg),
  });

  final AssetType tur;
  final String ticker;
  final EdgeInsetsGeometry dis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(balinaRadariAcikProvider)) return const SizedBox.shrink();
    final anahtar = kriptoTickeri(tur: tur, ticker: ticker);
    if (anahtar == null) return const SizedBox.shrink();
    final ozet = ref.watch(kriptoBaskiProvider(anahtar)).valueOrNull;
    final okunus = ozet == null ? null : kriptoOkunusu(ozet);
    if (ozet == null || okunus == null) return const SizedBox.shrink();
    final kilitli = ref.watch(radarKilitliProvider);
    final saatlik =
        kilitli ? null : ref.watch(kriptoSaatlikProvider(anahtar)).valueOrNull;

    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final gunAy =
        DateFormat('d MMM', Localizations.localeOf(context).toString());
    final tarih = gunAy.format(ozet.sonGun.tarih);

    void ayrintiyaGit() => pushGuarded(
          context,
          adaptiveRoute<void>(
              builder: (_) => HacimDetayScreen(anahtar: anahtar, kripto: true)),
        );

    return Padding(
      padding: dis,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l10n.cryTitleUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            onTap: kilitli ? null : ayrintiyaGit,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(kriptoCumlesi(l10n, okunus, tarih),
                    style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600, color: c.text90)),
                const SizedBox(height: SandikSpace.smd),
                HalatCubugu(aliciPayi: ozet.aliciPayi!),
                TerimMetni(
                  terim: RadarTerim.aliciPayi,
                  metin: ozet.aliciPayi7 == null
                      ? l10n.rdrTerimAliciPayi
                      : l10n.rdrYediGunOrt(
                          fmtPct(ozet.aliciPayi7! * 100, digits: 1)),
                  ornek:
                      '$tarih · ${l10n.rdrAlici(fmtPct(ozet.aliciPayi! * 100, digits: 1))}',
                ),
                const SizedBox(height: SandikSpace.xs),
                OlcekCubugu(kademe: okunus.kademe),
                HaftaOlayiSatiri(ozet: ozet),
                const SizedBox(height: SandikSpace.md),
                if (kilitli)
                  KilitSatiri(
                      metin: l10n.prmKilitAyrinti, kaynak: 'kripto_baski')
                else ...[
                  if (saatlik != null) ...[
                    Text(l10n.rdrSaatlikUpper,
                        style: t.labelSmall?.copyWith(
                            color: c.text58,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0)),
                    const SizedBox(height: SandikSpace.sm),
                    SaatlikCubuklar(akis: saatlik, yari: SandikSpace.lgs),
                    const SizedBox(height: SandikSpace.xs),
                    EnIstekliSaat(akis: saatlik),
                  ],
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AyrintiBaglantisi(onTap: ayrintiyaGit),
                  ),
                ],
                RadarKaynakSatiri(
                  kaynak: 'Binance',
                  tarih: saatlik == null
                      ? tarih
                      : l10n.rdrSonMum(saatEtiketi(
                          context, saatlik.saatler.nonNulls.last.saat)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Alıcı / satıcı halat çubuğu: solda alıcı payı (`gain`), sağda satıcı
/// (`loss`); ortadaki ince çizgi %50.
class HalatCubugu extends StatelessWidget {
  const HalatCubugu({super.key, required this.aliciPayi});

  final double aliciPayi;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final a = (aliciPayi * 1000).round().clamp(1, 999);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Wrap: dar ekranda büyük yazıyla satıcı payı alt satıra iner.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(l10n.rdrAlici(fmtPct(aliciPayi * 100, digits: 1)),
                style: t.bodyMedium
                    ?.copyWith(color: c.gain, fontWeight: FontWeight.w700)),
            Text(l10n.rdrSatici(fmtPct((1 - aliciPayi) * 100, digits: 1)),
                style: t.bodyMedium
                    ?.copyWith(color: c.loss, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: SandikSpace.xs),
        SizedBox(
          height: SandikSpace.smd,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: SandikRadius.smAll,
                child: Row(
                  children: [
                    Expanded(flex: a, child: Container(color: c.gain)),
                    Expanded(flex: 1000 - a, child: Container(color: c.loss)),
                  ],
                ),
              ),
              Align(
                child: Container(width: 1, color: c.background),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Saatlik net alım çubukları: üstü net alım, altı net satış; boş saat boş.
class SaatlikCubuklar extends StatelessWidget {
  const SaatlikCubuklar(
      {super.key, required this.akis, this.yari = 36, this.secili, this.onSec});

  final SaatlikAkis akis;
  final double yari;
  final int? secili;
  final ValueChanged<int>? onSec;

  @override
  Widget build(BuildContext context) => HaftaCubuklari(
        // Aynı işaretli çubuk çizimi; "hafta" burada bir saattir.
        haftalar: [
          for (final s in akis.saatler)
            HaftaAkisi(baslangic: s?.saat ?? DateTime.utc(0), net: s?.netAlim),
        ],
        yari: yari,
        secili: secili,
        onSec: onSec,
      );
}

/// "03:00–04:00 en istekli saat · +$212,40M net".
class EnIstekliSaat extends StatelessWidget {
  const EnIstekliSaat({super.key, required this.akis});

  final SaatlikAkis akis;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = akis.enIstekli;
    return Text(
      s == null
          ? l10n.rdrIstekliSaatYok
          : l10n.rdrEnIstekliSaat(
              l10n.flowRange(saatEtiketi(context, s.saat),
                  saatEtiketi(context, s.saat.add(const Duration(hours: 1)))),
              isaretliDolar(s.netAlim)),
      style: context.t.bodySmall?.copyWith(color: context.c.text58),
    );
  }
}

/// Cihaz saatinde "14:00".
String saatEtiketi(BuildContext context, DateTime utc) =>
    DateFormat('HH:mm', Localizations.localeOf(context).toString())
        .format(utc.toLocal());

/// Kartın konusu SON GÜN; Haftanın özeti ise son 7 günü okur. Listeden
/// "Olağandışı hacim" rozetiyle gelen kullanıcı kartta yalnız "sakin gün"
/// görürse rozet yanlış sanılır (2026-10-05 web testi: THYAO 1 Eki 3,4 kat,
/// kart 2 Eki'yi anlatıyordu). Son 7 günde son gün DIŞINDA olağandışı gün
/// varsa kart onu da tek satırla söyler; son günse kademe zaten en üsttedir.
class HaftaOlayiSatiri extends StatelessWidget {
  const HaftaOlayiSatiri({super.key, required this.ozet});

  final HacimOzeti ozet;

  @override
  Widget build(BuildContext context) {
    final olay = sonHaftaHacimOlayi(ozet);
    if (olay == null || olay.tarih == ozet.sonGun.tarih) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final gunAy =
        DateFormat('d MMM', Localizations.localeOf(context).toString());
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bolt_rounded,
              size: SandikSpace.md, color: context.c.amberText),
          const SizedBox(width: SandikSpace.xs),
          Expanded(
            child: Text(
              l10n.rdrKartHaftaOlayi(l10n.rdrSatirHacim(
                  gunAy.format(olay.tarih),
                  fmtNum(olay.ortalamaKati, digits: 1),
                  fmtPctIsaretli(olay.fiyatDegisim * 100, digits: 1))),
              style: context.t.bodySmall?.copyWith(color: context.c.text90),
            ),
          ),
        ],
      ),
    );
  }
}
