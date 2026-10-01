import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../models/sozlesme.dart';
import '../screens/add_asset/emeklilik_fonu_secici.dart';
import '../services/bes_hesabi.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'sozlesme_formu_ortak.dart';

/// BES fon dağılımı düzenleyicisi — ekleme formu ve "Fon değiştir" sayfası.
///
/// İki yerde aynı satır, aynı %100 kuralı: ayrı kopyalar ayrışırdı (bu
/// projede tekrar eden hata sınıfı). Durum burada tutulur; çağıran
/// [BesDagilimEditoruState.dagilim] ile okur.
class BesDagilimEditoru extends StatefulWidget {
  const BesDagilimEditoru({
    super.key,
    this.baslangic = const [],
    this.adlar = const {},
    this.hata,
    this.degisti,
  });

  /// Açılıştaki satırlar (fon değişikliğinde bugünkü dağılım).
  final List<FonPayi> baslangic;

  /// Kod → fon adı; bilinmeyen kodun yalnız kodu yazılır.
  final Map<String, String> adlar;

  /// Satırların altında gösterilecek doğrulama hatası.
  final String? hata;

  /// Bir oran ya da satır değişti.
  final VoidCallback? degisti;

  @override
  State<BesDagilimEditoru> createState() => BesDagilimEditoruState();
}

class _FonSatiri {
  _FonSatiri(this.kod, this.ad, String oran)
      : oran = TextEditingController(text: oran);
  final String kod;
  final String ad;
  final TextEditingController oran;
}

class BesDagilimEditoruState extends State<BesDagilimEditoru> {
  late final List<_FonSatiri> _fonlar = [
    for (final f in widget.baslangic)
      _FonSatiri(f.kod, widget.adlar[f.kod] ?? '',
          fmtNumFlex(f.oran, maxDigits: 2)),
  ];

  @override
  void dispose() {
    for (final f in _fonlar) {
      f.oran.dispose();
    }
    super.dispose();
  }

  List<FonPayi> get dagilim => [
        for (final f in _fonlar)
          FonPayi(kod: f.kod, oran: parseTrNumber(f.oran.text) ?? 0),
      ];

  double get _oranToplami => dagilim.fold<double>(0, (t, f) => t + f.oran);

  Future<void> _fonEkle() async {
    final f = await emeklilikFonuSec(context, devletKatkisi: false);
    if (f == null || !mounted) return;
    if (_fonlar.any((x) => x.kod == f.code)) return;
    setState(() {
      // İlk fon %100, sonrakiler kalan yüzdeyle açılır.
      final kalan = 100 - _oranToplami;
      _fonlar.add(_FonSatiri(
          f.code, f.name, fmtNumFlex(kalan > 0 ? kalan : 0, maxDigits: 2)));
    });
    widget.degisti?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final renk = AssetType.bes.onSurface(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in _fonlar) ...[
          _FonSatiriGorunumu(
            satir: f,
            renk: renk,
            degisti: () {
              setState(() {});
              widget.degisti?.call();
            },
            sil: () {
              setState(() {
                _fonlar.remove(f);
                f.oran.dispose();
              });
              widget.degisti?.call();
            },
          ),
          const SizedBox(height: SandikSpace.sm),
        ],
        // Sarmalı: büyük metin ölçeğinde (320pt × 3.0) düğme ve toplam
        // yan yana sığmıyordu; toplam alt satıra iner.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: SandikSpace.sm,
          children: [
            TextButton.icon(
              onPressed: _fonEkle,
              icon: Icon(Icons.add_rounded, color: context.c.amberText),
              label: Text(l10n.pensionAddFund,
                  style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.c.amberText)),
            ),
            if (_fonlar.isNotEmpty)
              Text(
                l10n.pensionShareTotal(fmtPct(_oranToplami, digits: 0)),
                style: context.t.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: BesHesabi.dagilimGecerli(dagilim)
                      ? context.c.text58
                      : context.c.danger,
                ),
              ),
          ],
        ),
        if (widget.hata != null)
          Text(widget.hata!,
              style: context.t.bodySmall?.copyWith(color: context.c.danger)),
      ],
    );
  }
}

class _FonSatiriGorunumu extends StatelessWidget {
  const _FonSatiriGorunumu({
    required this.satir,
    required this.renk,
    required this.degisti,
    required this.sil,
  });

  final _FonSatiri satir;
  final Color renk;
  final VoidCallback degisti;
  final VoidCallback sil;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(satir.kod,
                    style: context.t.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800, color: renk)),
                if (satir.ad.isNotEmpty)
                  Text(satir.ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58)),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          SizedBox(
            width: 96,
            child: SozlesmeAlani(
              controller: satir.oran,
              ipucu: '0',
              sonek: '%',
              sayi: true,
              degisti: (_) => degisti(),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            onPressed: sil,
            icon: Icon(Icons.close_rounded, color: context.c.text36),
          ),
        ],
      );
}
