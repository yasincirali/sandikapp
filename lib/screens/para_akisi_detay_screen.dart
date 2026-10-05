import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/fon_akisi_provider.dart';
import '../services/fon_akisi.dart';
import '../services/radar_okuma.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/para_akisi_karti.dart';
import '../widgets/radar_ortak.dart';
import '../widgets/sandik_app_bar.dart';

/// Para akışı ayrıntı ekranı (S2-A, 2026-10-05) — tek kaydırma, bölümler.
///
/// Kartın özetlediği haftanın arkasındaki her şey, analistin arayacağı
/// sırayla: seyir (haftaya dokun → o haftanın rakamı), dönem ve ayrıştırma
/// (büyüklük değişiminin ne kadarı fiyat, ne kadarı yeni para — eskiden
/// cümleydi, şimdi iki renkli tek çubuk), bağlam (büyüklük, yatırımcı),
/// kategoride akış sırası (S3-B: ilk 5 + bu fon), büyük hareketler.
///
/// Sayılar kartla AYNI provider'dan (`fonAkisiProvider`); ikinci hesap yolu
/// yok. Açıklama paragrafı yok: terimler dokunulabilir, ilk açılışta bir
/// kerelik "nasıl okunur" (başlıktaki "?" yeniden açar).
class ParaAkisiDetayScreen extends ConsumerStatefulWidget {
  const ParaAkisiDetayScreen({super.key, required this.kod});

  /// TEFAS fon kodu ('TTE').
  final String kod;

  @override
  ConsumerState<ParaAkisiDetayScreen> createState() =>
      _ParaAkisiDetayScreenState();
}

class _ParaAkisiDetayScreenState extends ConsumerState<ParaAkisiDetayScreen> {
  int? _secili;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) radarKocunuGoster(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final ozet = ref.watch(fonAkisiProvider(widget.kod)).valueOrNull;
    final gunAy =
        DateFormat('d MMM', Localizations.localeOf(context).toString());

    return Scaffold(
      appBar: SandikAppBar(
        title: l10n.rdrFonDetayBaslik(widget.kod),
        actions: [
          IconButton(
            tooltip: l10n.rdrNasilOkunur,
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => radarKocunuGoster(context, ref, zorla: true),
          ),
        ],
      ),
      body: ozet == null
          ? const SizedBox.shrink()
          : ListView(
              padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
                  SandikSpace.md, SandikSpace.screenH(context), SandikSpace.xl),
              children: [
                _Ust(ozet: ozet, kod: widget.kod, gunAy: gunAy),
                const SizedBox(height: SandikSpace.lg),
                _Seyir(
                  ozet: ozet,
                  secili: _secili,
                  onSec: (i) => setState(() => _secili = i),
                  gunAy: gunAy,
                ),
                if (ozet.ay1 != null || ozet.ay3 != null) ...[
                  const SizedBox(height: SandikSpace.lg),
                  SandikSectionHeader(title: l10n.rdrDonemUpper),
                  const SizedBox(height: SandikSpace.sm),
                  SandikCard(child: _Donem(ozet: ozet)),
                ],
                const SizedBox(height: SandikSpace.lg),
                SandikSectionHeader(title: l10n.rdrBaglamUpper),
                const SizedBox(height: SandikSpace.sm),
                SandikCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Satir(
                        etiket: TerimMetni(
                          terim: RadarTerim.buyukluk,
                          metin: l10n.flowFundSize,
                          ornek: fmtTRYCompact(ozet.buyukluk),
                          stil: t.bodyMedium?.copyWith(color: c.text58),
                        ),
                        deger: fmtTRYCompact(ozet.buyukluk),
                      ),
                      if (ozet.yatirimci != null)
                        _Satir(
                          etiket: TerimMetni(
                            terim: RadarTerim.yatirimci,
                            metin: l10n.flowInvestors,
                            stil: t.bodyMedium?.copyWith(color: c.text58),
                          ),
                          deger: ozet.yatirimciDegisimi == null
                              ? fmtNum(ozet.yatirimci!.toDouble(), digits: 0)
                              : l10n.flowInvestorsDelta(
                                  fmtNum(ozet.yatirimci!.toDouble(), digits: 0),
                                  isaretliAdet(ozet.yatirimciDegisimi!)),
                        ),
                    ],
                  ),
                ),
                _KategoriSirasi(kod: widget.kod),
                const SizedBox(height: SandikSpace.lg),
                SandikSectionHeader(title: l10n.rdrHareketlerUpper),
                const SizedBox(height: SandikSpace.sm),
                SandikCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TerimMetni(
                        terim: RadarTerim.buyukHareket,
                        metin: l10n.rdrTerimBuyukHareket,
                      ),
                      if (ozet.olaylar.isEmpty)
                        Text(l10n.flowNoEvents,
                            style: t.bodySmall?.copyWith(color: c.text58))
                      else
                        for (var i = 0; i < ozet.olaylar.length; i++) ...[
                          if (i > 0) const SizedBox(height: SandikSpace.smd),
                          _OlaySatiri(olay: ozet.olaylar[i], gunAy: gunAy),
                        ],
                    ],
                  ),
                ),
                const SizedBox(height: SandikSpace.lg),
                Text(l10n.rdrYasal('TEFAS'),
                    style: t.bodySmall?.copyWith(color: c.text36)),
                const SizedBox(height: SandikSpace.xs),
                RadarKaynakSatiri(
                    kaynak: 'TEFAS', tarih: gunAy.format(ozet.veriTarihi)),
              ],
            ),
    );
  }
}

class _Ust extends StatelessWidget {
  const _Ust({required this.ozet, required this.kod, required this.gunAy});

  final FonAkisOzeti ozet;
  final String kod;
  final DateFormat gunAy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final okunus = fonOkunusu(ozet);
    final net = ozet.sonHaftaNet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(fonCumlesi(l10n, okunus),
            style: t.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
        const SizedBox(height: SandikSpace.sm),
        Text(isaretliTutar(net),
            style: t.numLarge.copyWith(color: yonRengi(c, net))),
        TerimMetni(
          terim: RadarTerim.netAkis,
          metin: l10n.rdrFonNetAralik(l10n.flowRange(
              gunAy.format(ozet.sonHaftaIlkGun),
              gunAy.format(ozet.veriTarihi))),
          ornek: '$kod · ${isaretliTutar(net)}',
        ),
        if (okunus.kademe != null) ...[
          const SizedBox(height: SandikSpace.xs),
          OlcekCubugu(kademe: okunus.kademe!),
          const SizedBox(height: SandikSpace.xs),
          // Wrap: dar ekranda büyük yazıyla "kat" alt satıra iner.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TerimMetni(
                terim: RadarTerim.olcek,
                metin: kademeEtiketi(l10n, okunus.kademe!, hafta: true),
              ),
              if (okunus.kat != null)
                Text(
                  ' · ${l10n.rdrOlaganinKati(fmtNum(okunus.kat!, digits: 1))}',
                  style: t.bodySmall?.copyWith(color: c.text58),
                ),
            ],
          ),
        ],
        if (ozet.seri != null)
          Text(
            ozet.seri!.giris
                ? l10n.flowStreakIn('${ozet.seri!.hafta}')
                : l10n.flowStreakOut('${ozet.seri!.hafta}'),
            style: t.bodySmall
                ?.copyWith(color: c.text58, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

class _Seyir extends StatelessWidget {
  const _Seyir({
    required this.ozet,
    required this.secili,
    required this.onSec,
    required this.gunAy,
  });

  final FonAkisOzeti ozet;
  final int? secili;
  final ValueChanged<int> onSec;
  final DateFormat gunAy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final h = secili == null ? null : ozet.haftalar[secili!];
    final String bilgi;
    if (h == null) {
      bilgi = l10n.rdrHaftayaDokun;
    } else {
      // Haftanın Pazartesi–Cuma aralığı; işlem günleri.
      final aralik = l10n.flowRange(gunAy.format(h.baslangic),
          gunAy.format(h.baslangic.add(const Duration(days: 4))));
      bilgi =
          '${l10n.rdrSecilenHafta(aralik)}: ${h.net == null ? l10n.rdrVeriYok : isaretliTutar(h.net!)}';
    }
    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.flowChartCaption,
              style: t.bodySmall?.copyWith(color: c.text58)),
          const SizedBox(height: SandikSpace.smd),
          Semantics(
            label: l10n.flowChartSemantics(isaretliTutar(ozet.sonHaftaNet)),
            child: HaftaCubuklari(
              haftalar: ozet.haftalar,
              yari: SandikSpace.xxl,
              secili: secili,
              onSec: onSec,
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(bilgi,
              style: t.bodyMedium?.copyWith(
                  color: h == null ? c.text36 : c.text90,
                  fontWeight: h == null ? null : FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Donem extends StatelessWidget {
  const _Donem({required this.ozet});

  final FonAkisOzeti ozet;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    String deger(DonemAkisi d) => d.oranAnlamli
        ? l10n.flowPeriodValue(
            isaretliTutar(d.para), fmtPctIsaretli(d.paraOrani * 100, digits: 1))
        : isaretliTutar(d.para);
    final ay1 = ozet.ay1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ay1 != null)
          _Satir(
              etiket: _etiket(context, l10n.flowPeriod1m), deger: deger(ay1)),
        if (ozet.ay3 != null)
          _Satir(
              etiket: _etiket(context, l10n.flowPeriod3m),
              deger: deger(ozet.ay3!)),
        if (ay1 != null && ay1.oranAnlamli) ...[
          const SizedBox(height: SandikSpace.smd),
          Text(
            l10n.rdrAyristirmaCumle(
                fmtPctIsaretli(ay1.toplamDegisim * 100, digits: 1)),
            style: t.bodyMedium?.copyWith(color: c.text90),
          ),
          const SizedBox(height: SandikSpace.sm),
          _AyristirmaCubugu(fiyat: ay1.fiyatEtkisi, para: ay1.paraOrani),
          const SizedBox(height: SandikSpace.xs),
          Wrap(
            spacing: SandikSpace.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Lejant(
                  renk: c.info,
                  metin: l10n.rdrFiyat(
                      fmtPctIsaretli(ay1.fiyatEtkisi * 100, digits: 1))),
              _Lejant(
                  renk: c.amberFill,
                  metin: l10n.rdrYeniPara(
                      fmtPctIsaretli(ay1.paraOrani * 100, digits: 1))),
              TerimMetni(
                  terim: RadarTerim.ayristirma, metin: l10n.rdrTerimAyristirma),
            ],
          ),
        ],
      ],
    );
  }

  Widget _etiket(BuildContext context, String metin) => Text(metin,
      style: context.t.bodyMedium?.copyWith(color: context.c.text58));
}

/// Büyüklük değişiminin iki kaynağı tek çubukta: uzunluklar mutlak
/// değerlerle orantılı. Ters işaretli kaynak (fiyat düştü, para girdi)
/// soluk çizilir; lejant işaretleri yazar.
class _AyristirmaCubugu extends StatelessWidget {
  const _AyristirmaCubugu({required this.fiyat, required this.para});

  final double fiyat;
  final double para;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = (fiyat.abs() * 1000).round();
    final p = (para.abs() * 1000).round();
    if (f + p == 0) return const SizedBox.shrink();
    final toplamYon = (fiyat + para) >= 0;
    Widget parca(int flex, Color renk, bool ayniYon) => Expanded(
          flex: flex,
          child: Container(
            height: SandikSpace.smd,
            color: renk.withValues(alpha: ayniYon ? 1 : 0.4),
          ),
        );
    return ClipRRect(
      borderRadius: SandikRadius.smAll,
      child: Row(
        children: [
          if (f > 0) parca(f, c.info, (fiyat >= 0) == toplamYon),
          if (f > 0 && p > 0) const SizedBox(width: SandikSpace.xxs),
          if (p > 0) parca(p, c.amberFill, (para >= 0) == toplamYon),
        ],
      ),
    );
  }
}

class _Lejant extends StatelessWidget {
  const _Lejant({required this.renk, required this.metin});

  final Color renk;
  final String metin;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: SandikSpace.sm,
            height: SandikSpace.sm,
            decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
          ),
          const SizedBox(width: SandikSpace.xs),
          Text(metin,
              style: context.t.bodySmall?.copyWith(color: context.c.text90)),
        ],
      );
}

class _Satir extends StatelessWidget {
  const _Satir({required this.etiket, required this.deger});

  final Widget etiket;
  final String deger;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: etiket),
          const SizedBox(width: SandikSpace.sm),
          Text(
            deger,
            textAlign: TextAlign.end,
            style: context.t.numSmall
                .copyWith(fontWeight: FontWeight.w600, color: context.c.text90),
          ),
        ],
      );
}

/// S3-B: kategoride ilk 5 + bu fon. Veri yoksa (tek fonlu kategori, fon
/// haftanın bir gününde eksik) bölüm hiç çizilmez.
class _KategoriSirasi extends ConsumerWidget {
  const _KategoriSirasi({required this.kod});

  final String kod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(fonKategoriSirasiProvider(kod)).valueOrNull;
    if (liste == null || liste.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final ilk5 = liste.where((s) => s.sira <= 5).toList();
    final kendi = liste.firstWhere((s) => s.kendi);
    Widget satir(KategoriSirasi s) {
      final stil = t.bodyMedium?.copyWith(
          color: c.text90, fontWeight: s.kendi ? FontWeight.w800 : null);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
        child: Row(
          children: [
            SizedBox(
              width: SandikSpace.lg,
              child: Text('${s.sira}',
                  style: t.bodySmall?.copyWith(color: c.text58)),
            ),
            Expanded(
              child: Text(
                s.kendi ? '${s.fonKodu} (${l10n.rdrSiraBuFon})' : s.fonKodu,
                style: stil,
              ),
            ),
            Text(isaretliTutar(s.netAkis),
                style: t.numSmall.copyWith(
                    color: yonRengi(c, s.netAkis),
                    fontWeight: s.kendi ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l10n.rdrSiraUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TerimMetni(
                  terim: RadarTerim.sira,
                  metin: l10n.rdrSiraAlt(kendi.kategori),
                  ornek: '$kod · ${kendi.sira} / ${kendi.fonSayisi}',
                ),
                for (final s in ilk5) satir(s),
                if (!ilk5.contains(kendi)) ...[
                  Divider(height: SandikSpace.md, color: c.hairline),
                  satir(kendi),
                ],
                const SizedBox(height: SandikSpace.xs),
                Text(l10n.rdrSiraToplam('${kendi.fonSayisi}'),
                    style: t.bodySmall?.copyWith(color: c.text36)),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
    final cokGun = olay.gunSayisi > 1 && olay.ilkGun != null;
    final tarih = cokGun
        ? l10n.flowRange(gunAy.format(olay.ilkGun!), gunAy.format(olay.tarih))
        : gunAy.format(olay.tarih);
    final oran = fmtPct(olay.buyuklukOrani * 100, digits: 1);
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
                style: t.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600, color: c.text90),
              ),
              const SizedBox(height: SandikSpace.xxs),
              Text(
                cokGun
                    ? l10n.flowEventEvidenceMulti(
                        isaretliTutar(olay.tutar), oran, '${olay.gunSayisi}')
                    : l10n.flowEventEvidence(isaretliTutar(olay.tutar), oran,
                        fmtNum(olay.sapmaKati, digits: 1)),
                style: t.bodySmall?.copyWith(color: c.text58),
              ),
              if (olay.yatirimciDegisimi != null) ...[
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  l10n.flowEventInvestors(
                      isaretliAdet(olay.yatirimciDegisimi!)),
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
