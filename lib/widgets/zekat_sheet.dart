import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../providers/zekat_provider.dart';
import '../services/zekat_hesabi.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'sandik_bos_durum.dart';
import 'sandik_skeleton.dart';

/// Profil'deki "Zekât hesabı" satırı (2026-11-12).
///
/// ## Neden Profil, Raporlar değil
/// Raporlar kapısı bayrak ardında (`raporlar_kapisi` / Premium görünürlüğü),
/// demoda hiç çizilmez ve satır kuralı "kapı yeni erişim icat etmez" der.
/// Zekât hesabı ÜCRETSİZ ve edinme amaçlı (bilinçli karar): herkese
/// görünen bir yerde durmalı. Profil'in araç satırları (halka arz, hedef)
/// ile aynı kalıp; sıfır yükseklik koşulu yok, hep görünür.
class ZekatProfilSatiri extends StatelessWidget {
  const ZekatProfilSatiri({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.lg),
      child: SandikCard(
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.md, vertical: SandikSpace.smd),
        onTap: () => showZekatSheet(context),
        child: Semantics(
          button: true,
          child: Row(
            children: [
              Icon(Icons.volunteer_activism_rounded,
                  size: SandikSpace.lgs, color: c.amberText),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.zkSatirBaslik,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600, color: c.text90),
                    ),
                    Text(
                      l.zkSatirAlt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall?.copyWith(color: c.text58),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.text36),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zekât hesabını alt sayfada açar. Hesap `zekatHesapla`'da (saf); sayfa
/// yalnız gösterir. Borç alanı bellek içi: sayfa kapanınca unutulur.
Future<void> showZekatSheet(BuildContext context) => showSandikSheet<void>(
      context: context,
      baslik: context.l10n.zkSatirBaslik,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
      builder: (_) => const ZekatSayfasi(),
    );

class ZekatSayfasi extends ConsumerStatefulWidget {
  const ZekatSayfasi({super.key});

  @override
  ConsumerState<ZekatSayfasi> createState() => _ZekatSayfasiState();
}

class _ZekatSayfasiState extends ConsumerState<ZekatSayfasi> {
  final _borc = TextEditingController();

  @override
  void dispose() {
    _borc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final borc = parseTrNumber(_borc.text) ?? 0;
    final sonuc = ref.watch(zekatSonucuProvider(borc > 0 ? borc : 0));
    // Kaydırılabilir: 2× yazıda satırlar telefon boyunu aşar.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
          SandikSpace.xs, SandikSpace.screenH(context), SandikSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.zkAciklama,
              style: context.t.bodyMedium?.copyWith(color: c.text58)),
          const SizedBox(height: SandikSpace.md),
          // İlk açılışta önceki sonuç yokken iskelet; borç yazılırken
          // family anahtarı değişir ama gram fiyatı önbellekte, anında gelir.
          if (sonuc.isLoading && !sonuc.hasValue)
            const SizedBox(
              height: 140,
              child: SandikSkeletonList(rows: 3, padding: EdgeInsets.zero),
            )
          else if (sonuc.valueOrNull case final s?)
            _Hesap(sonuc: s, borcAlani: _borcAlani(context))
          else
            // Kur yok (ya da kaynak hata verdi): nisap ve sonuç YOK —
            // uydurma sayı yasak. Hata boş durum gibi gösterilmez kuralının
            // istisnası değil: burada eksik olan veri, işlem değil.
            SandikBosDurum(metin: l.zkKurYok, alt: l.zkKurYokAlt),
          const SizedBox(height: SandikSpace.md),
          Text(l.zkDipnot,
              style: context.t.bodySmall?.copyWith(color: c.text58)),
        ],
      ),
    );
  }

  Widget _borcAlani(BuildContext context) {
    final l = context.l10n;
    return TextField(
      controller: _borc,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: context.c.text90),
      onChanged: (_) => setState(() {}),
      // Dolgu/çerçeve temadan (`inputDecoration` = tema kuralı).
      decoration: context.inputDecoration(l.zkBorcIpucu,
          labelText: l.zkBorcEtiket),
    );
  }
}

class _Hesap extends StatelessWidget {
  const _Hesap({required this.sonuc, required this.borcAlani});

  final ZekatSonucu sonuc;
  final Widget borcAlani;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final s = sonuc;
    final notStili = context.t.bodySmall?.copyWith(color: c.text58);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TutarSatiri(etiket: l.zkTabi, tutar: fmtTRY(s.tabiTutar)),
        if (s.yeniTutar > 0)
          _TutarSatiri(
              etiket: l.zkYeni, alt: l.zkYeniAlt, tutar: fmtTRY(s.yeniTutar)),
        const SizedBox(height: SandikSpace.sm),
        borcAlani,
        const SizedBox(height: SandikSpace.sm),
        if (s.borc > 0)
          _TutarSatiri(etiket: l.zkBorcSatir, tutar: fmtTRY(s.borc)),
        _TutarSatiri(etiket: l.zkMatrah, tutar: fmtTRY(s.matrah)),
        _TutarSatiri(
          etiket: l.zkNisap,
          alt: l.zkNisapAyrinti(
              fmtNum(ZekatOlcusu.nisapGram), fmtTRYFiyat(s.gramFiyati)),
          tutar: fmtTRY(s.nisapTutari),
        ),
        const SizedBox(height: SandikSpace.sm),
        // Sonuç: nisap üstü/altı metinle söylenir, renkle değil.
        SandikCard(
          padding: const EdgeInsets.all(SandikSpace.md),
          child: MergeSemantics(
            child: s.nisabaUlasti
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.zkSonuc,
                          style: context.t.bodyMedium
                              ?.copyWith(color: c.text58)),
                      const SizedBox(height: SandikSpace.xs),
                      Text(
                        fmtTRY(s.zekat),
                        style: context.t.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600, color: c.text90),
                      ),
                    ],
                  )
                : Text(l.zkNisapAlti,
                    style:
                        context.t.bodyMedium?.copyWith(color: c.text90)),
          ),
        ),
        if (s.fiyatsizVarlik > 0)
          Padding(
            padding: const EdgeInsets.only(top: SandikSpace.sm),
            child: Text(l.zkFiyatsiz(s.fiyatsizVarlik), style: notStili),
          ),
        if (s.haricTurler.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: SandikSpace.sm),
            child: Text(
              l.zkHaric([
                for (final t in AssetType.values)
                  if (s.haricTurler.contains(t)) t.labelOf(l),
              ].join(', ')),
              style: notStili,
            ),
          ),
      ],
    );
  }
}

/// Etiket solda, tutar sağda. 2× yazıda tutar alta kayabilsin diye ikisi
/// de esnek; ekran okuyucu satırı tek düğüm okur.
class _TutarSatiri extends StatelessWidget {
  const _TutarSatiri({required this.etiket, required this.tutar, this.alt});

  final String etiket;
  final String tutar;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final alt = this.alt;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(etiket,
                      style:
                          context.t.bodyMedium?.copyWith(color: c.text90)),
                  if (alt != null)
                    Text(alt,
                        style:
                            context.t.bodySmall?.copyWith(color: c.text58)),
                ],
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Flexible(
              flex: 2,
              child: Text(
                tutar,
                textAlign: TextAlign.end,
                style: context.t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600, color: c.text90),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
