import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/fon_akisi_provider.dart';
import '../services/hisse_hacmi.dart';
import '../services/radar_okuma.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/hacim_radari_karti.dart';
import '../widgets/radar_ortak.dart';
import '../widgets/sandik_app_bar.dart';

/// Hacim / alıcı baskısı ayrıntı ekranı (S4-B + S5-A, 2026-10-05) — para
/// akışı ayrıntısıyla aynı tek kaydırma düzeni: tepe (cümle, sayı, ölçek),
/// seyir (güne / saate dokun → o anın rakamı), olağandışı günler, kaynak.
///
/// Hisse ve kripto TEK ekran: ikisi de aynı `HacimOzeti`'ni taşır; fark
/// yalnız para birimi (TL / USDT) ve kriptoda halat + saatlik bölüm. Ayrı
/// ekran iki kez aynı hatayı yapma fırsatı olurdu.
///
/// Sayılar kartla AYNI provider'dan; ikinci hesap yolu yok. Fiyat
/// değişimi seçilen günün kapanışının bir önceki güne oranıdır — seride
/// önceki gün yoksa fiyat yazılmaz (uydurma sayı yok).
class HacimDetayScreen extends ConsumerStatefulWidget {
  const HacimDetayScreen(
      {super.key, required this.anahtar, required this.kripto});

  /// Hisse: 'THYAO.IS'; kripto: 'KRIPTO:BTC'.
  final String anahtar;
  final bool kripto;

  @override
  ConsumerState<HacimDetayScreen> createState() => _HacimDetayScreenState();
}

class _HacimDetayScreenState extends ConsumerState<HacimDetayScreen> {
  int? _seciliGun;
  int? _seciliSaat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) radarKocunuGoster(context, ref);
    });
  }

  String get _kod => widget.kripto
      ? widget.anahtar.replaceFirst('KRIPTO:', '')
      : widget.anahtar.replaceFirst(RegExp(r'\.IS$'), '');

  String _tutar(double v) => widget.kripto ? kisaDolar(v) : fmtTRYCompact(v);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final ozet = ref
        .watch(widget.kripto
            ? kriptoBaskiProvider(widget.anahtar)
            : hisseHacmiProvider(widget.anahtar))
        .valueOrNull;
    final saatlik = widget.kripto
        ? ref.watch(kriptoSaatlikProvider(widget.anahtar)).valueOrNull
        : null;
    final gunAy =
        DateFormat('d MMM', Localizations.localeOf(context).toString());
    final kaynak = widget.kripto ? 'Binance' : 'Yahoo Finance';

    return Scaffold(
      appBar: SandikAppBar(
        title: widget.kripto
            ? l10n.rdrKriptoDetayBaslik(_kod)
            : l10n.rdrHacimDetayBaslik(_kod),
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
                if (widget.kripto)
                  _KriptoUst(ozet: ozet, gunAy: gunAy)
                else
                  _HisseUst(ozet: ozet, gunAy: gunAy, tutar: _tutar),
                if (saatlik != null) ...[
                  const SizedBox(height: SandikSpace.lg),
                  SandikSectionHeader(title: l10n.rdrSaatlikUpper),
                  const SizedBox(height: SandikSpace.sm),
                  SandikCard(
                    child: _Saatlik(
                      akis: saatlik,
                      secili: _seciliSaat,
                      onSec: (i) => setState(() => _seciliSaat = i),
                    ),
                  ),
                ],
                const SizedBox(height: SandikSpace.lg),
                SandikSectionHeader(title: l10n.rdrIslemHacmiUpper),
                const SizedBox(height: SandikSpace.sm),
                SandikCard(
                  child: _GunSeyri(
                    ozet: ozet,
                    secili: _seciliGun,
                    onSec: (i) => setState(() => _seciliGun = i),
                    gunAy: gunAy,
                    tutar: _tutar,
                  ),
                ),
                const SizedBox(height: SandikSpace.lg),
                SandikSectionHeader(title: l10n.rdrOlagandisiUpper),
                const SizedBox(height: SandikSpace.sm),
                SandikCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TerimMetni(
                        terim: RadarTerim.olagandisi,
                        metin: l10n.rdrTerimOlagandisi,
                      ),
                      if (ozet.olaylar.isEmpty)
                        Text(l10n.volNoEvents,
                            style: t.bodySmall?.copyWith(color: c.text58))
                      else
                        for (var i = 0; i < ozet.olaylar.length; i++) ...[
                          if (i > 0) const SizedBox(height: SandikSpace.smd),
                          _OlaySatiri(
                            olay: ozet.olaylar[i],
                            gunAy: gunAy,
                            tutar: _tutar,
                            kripto: widget.kripto,
                          ),
                        ],
                    ],
                  ),
                ),
                const SizedBox(height: SandikSpace.lg),
                Text(l10n.rdrYasal(kaynak),
                    style: t.bodySmall?.copyWith(color: c.text36)),
                const SizedBox(height: SandikSpace.xs),
                RadarKaynakSatiri(
                    kaynak: kaynak, tarih: gunAy.format(ozet.sonGun.tarih)),
              ],
            ),
    );
  }
}

class _HisseUst extends StatelessWidget {
  const _HisseUst(
      {required this.ozet, required this.gunAy, required this.tutar});

  final HacimOzeti ozet;
  final DateFormat gunAy;
  final String Function(double) tutar;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final kademe = hacimKademesi(ozet);
    final tarih = gunAy.format(ozet.sonGun.tarih);
    final miktar = tutar(ozet.sonGun.paraHacmi);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(hisseCumlesi(l10n, kademe, tarih, miktar),
            style: t.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
        const SizedBox(height: SandikSpace.sm),
        Text(miktar, style: t.numLarge.copyWith(color: c.text90)),
        TerimMetni(
          terim: RadarTerim.hacim,
          metin: ozet.fiyatDegisim == null
              ? l10n.rdrHacimAltFiyatsiz
              : l10n.rdrHacimAlt(
                  fmtPctIsaretli(ozet.fiyatDegisim! * 100, digits: 1)),
          ornek: '$tarih · $miktar',
        ),
        if (kademe != null) ...[
          const SizedBox(height: SandikSpace.xs),
          OlcekCubugu(kademe: kademe),
          const SizedBox(height: SandikSpace.xs),
          TerimMetni(
            terim: RadarTerim.olcek,
            metin: kademeEtiketi(l10n, kademe, hafta: false),
          ),
        ],
        if (ozet.kat != null)
          TerimMetni(
            terim: RadarTerim.kat,
            metin: l10n.volVsAverage(fmtNum(ozet.kat!, digits: 1)),
            ornek: '$tarih · ${fmtNum(ozet.kat!, digits: 1)}×',
          ),
      ],
    );
  }
}

class _KriptoUst extends StatelessWidget {
  const _KriptoUst({required this.ozet, required this.gunAy});

  final HacimOzeti ozet;
  final DateFormat gunAy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final okunus = kriptoOkunusu(ozet);
    final tarih = gunAy.format(ozet.sonGun.tarih);
    if (okunus == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(kriptoCumlesi(l10n, okunus, tarih),
            style: t.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
        const SizedBox(height: SandikSpace.md),
        HalatCubugu(aliciPayi: ozet.aliciPayi!),
        TerimMetni(
          terim: RadarTerim.aliciPayi,
          metin: ozet.aliciPayi7 == null
              ? l10n.rdrTerimAliciPayi
              : l10n.rdrYediGunOrt(fmtPct(ozet.aliciPayi7! * 100, digits: 1)),
          ornek:
              '$tarih · ${l10n.rdrAlici(fmtPct(ozet.aliciPayi! * 100, digits: 1))}',
        ),
        const SizedBox(height: SandikSpace.xs),
        OlcekCubugu(kademe: okunus.kademe),
        const SizedBox(height: SandikSpace.xs),
        TerimMetni(
          terim: RadarTerim.olcek,
          metin: kademeEtiketi(l10n, okunus.kademe, hafta: false),
        ),
        Text(l10n.cryVolumeLabel(kisaDolar(ozet.sonGun.paraHacmi)),
            style: t.bodySmall?.copyWith(color: c.text58)),
      ],
    );
  }
}

class _Saatlik extends StatelessWidget {
  const _Saatlik(
      {required this.akis, required this.secili, required this.onSec});

  final SaatlikAkis akis;
  final int? secili;
  final ValueChanged<int> onSec;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final s = secili == null ? null : akis.saatler[secili!];
    final String bilgi;
    if (secili == null) {
      bilgi = l10n.rdrSaateDokun;
    } else if (s == null) {
      bilgi = l10n.rdrVeriYok;
    } else {
      bilgi = l10n.rdrSecilenGunFiyatsiz(saatAraligi(context, akis, s.saat),
          '${isaretliDolar(s.netAlim)} · ${l10n.rdrAlici(fmtPct(s.aliciPayi * 100, digits: 1))}');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TerimMetni(terim: RadarTerim.netAlim, metin: l10n.rdrTerimNetAlim),
        const SizedBox(height: SandikSpace.sm),
        SaatlikCubuklar(
            akis: akis, yari: SandikSpace.xxl, secili: secili, onSec: onSec),
        const SizedBox(height: SandikSpace.sm),
        Text(bilgi,
            style: t.bodyMedium?.copyWith(
                color: secili == null ? c.text36 : c.text90,
                fontWeight: secili == null ? null : FontWeight.w600)),
        const SizedBox(height: SandikSpace.xs),
        EnIstekliSaat(akis: akis),
      ],
    );
  }
}

class _GunSeyri extends StatelessWidget {
  const _GunSeyri({
    required this.ozet,
    required this.secili,
    required this.onSec,
    required this.gunAy,
    required this.tutar,
  });

  final HacimOzeti ozet;
  final int? secili;
  final ValueChanged<int> onSec;
  final DateFormat gunAy;
  final String Function(double) tutar;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final gunler = ozet.gunler;
    final String bilgi;
    if (secili == null) {
      bilgi = l10n.rdrGuneDokun;
    } else {
      final g = gunler[secili!];
      final tarih = gunAy.format(g.tarih);
      // Fiyat değişimi önceki kapanışa göre; ilk günün öncesi seride yok.
      final onceki = secili! > 0 ? gunler[secili! - 1].kapanis : null;
      bilgi = onceki == null || onceki <= 0
          ? l10n.rdrSecilenGunFiyatsiz(tarih, tutar(g.paraHacmi))
          : l10n.rdrSecilenGun(tarih, tutar(g.paraHacmi),
              fmtPctIsaretli((g.kapanis / onceki - 1) * 100, digits: 1));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TerimMetni(terim: RadarTerim.hacim, metin: l10n.rdrTerimHacim),
        const SizedBox(height: SandikSpace.sm),
        GunCubuklari(
          gunler: gunler,
          ortalama: ozet.ortalama,
          vurgulu: {for (final o in ozet.olaylar) o.tarih},
          boy: SandikSpace.xxl * 2,
          secili: secili,
          onSec: onSec,
        ),
        const SizedBox(height: SandikSpace.xs),
        if (ozet.ortalama != null)
          Text(l10n.rdrOrtalamaCizgisi,
              style: t.bodySmall?.copyWith(color: c.text58)),
        const SizedBox(height: SandikSpace.sm),
        Text(bilgi,
            style: t.bodyMedium?.copyWith(
                color: secili == null ? c.text36 : c.text90,
                fontWeight: secili == null ? null : FontWeight.w600)),
      ],
    );
  }
}

class _OlaySatiri extends StatelessWidget {
  const _OlaySatiri({
    required this.olay,
    required this.gunAy,
    required this.tutar,
    required this.kripto,
  });

  final HacimOlayi olay;
  final DateFormat gunAy;
  final String Function(double) tutar;
  final bool kripto;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final kat = fmtNum(olay.ortalamaKati, digits: 1);
    final fiyat = fmtPctIsaretli(olay.fiyatDegisim * 100, digits: 1);
    final kanit = kripto && olay.aliciPayi != null
        ? l10n.cryEventEvidence(tutar(olay.paraHacmi), kat, fiyat,
            fmtPct(olay.aliciPayi! * 100, digits: 1))
        : l10n.volEventEvidence(tutar(olay.paraHacmi), kat, fiyat);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: SandikSpace.xs2),
          child: Container(
            width: SandikSpace.sm,
            height: SandikSpace.sm,
            // Nokta nötr: hacim yön taşımaz; fiyat yönü metinde yazılı.
            decoration: BoxDecoration(color: c.text90, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: SandikSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.volEventTitle(gunAy.format(olay.tarih)),
                  style: t.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600, color: c.text90)),
              const SizedBox(height: SandikSpace.xxs),
              Text(kanit, style: t.bodySmall?.copyWith(color: c.text58)),
            ],
          ),
        ),
      ],
    );
  }
}
