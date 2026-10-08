import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/varlik_masraflari.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'radar_ortak.dart' show RozetCipi;

/// Varlık ekranının "Masraflar" kartı (bayrak `varlik_masraflari`,
/// 2026-10-08).
///
/// Sayı HESAPLAMAZ: kalemler ve toplamlar `varlikMasraflari`'ndan hazır
/// gelir (tutar yalnız kayıtlı komisyondan ya da resmî orandan; gerekçe
/// orada). Kart yalnız çizer.
///
/// ## Düzen
/// Üstte iki toplam (ödenen · satarken tahmini) — kullanıcının ilk sorusu
/// "ne ödedim, satınca ne öderim". Altında kalemler: başlık + nitelik
/// rozeti, kısa açıklama, sağda tutar / oran / "—". Kalem sayısı ABD
/// hissesinde altıya çıkar; kart varsayılan KAPALI açılır, ilk üç kalem
/// görünür (önce tutarlı olanlar — servis sırası öyle), gerisi "Tümünü
/// gör" ile. Rozet ortak [RozetCipi]: radar kartlarıyla aynı görünüş.
class MasrafKarti extends StatefulWidget {
  const MasrafKarti({super.key, required this.ozet});

  final MasrafOzeti ozet;

  /// Kapalıyken görünen kalem sayısı.
  static const kapaliKalem = 3;

  @override
  State<MasrafKarti> createState() => _MasrafKartiState();
}

class _MasrafKartiState extends State<MasrafKarti> {
  bool _acik = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ozet = widget.ozet;
    if (ozet.kalemler.isEmpty) return const SizedBox.shrink();
    final fazla = ozet.kalemler.length > MasrafKarti.kapaliKalem;
    final gorunen = _acik || !fazla
        ? ozet.kalemler
        : ozet.kalemler.take(MasrafKarti.kapaliKalem).toList();
    final odenenVar = ozet.odenenToplamTry > 0;

    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l.costsUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (odenenVar || ozet.tahminiVar) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _Toplam(
                          etiket: l.costsPaid,
                          tutar: odenenVar ? ozet.odenenToplamTry : null,
                        ),
                      ),
                      if (ozet.tahminiVar) ...[
                        const SizedBox(width: SandikSpace.smd),
                        Expanded(
                          child: _Toplam(
                            etiket: l.costsEstimatedOnSale,
                            tutar: ozet.tahminiToplamTry,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: SandikSpace.smd),
                  Divider(height: 1, color: context.c.hairline),
                ],
                for (var i = 0; i < gorunen.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: context.c.hairline),
                  _Satir(kalem: gorunen[i]),
                ],
                if (fazla)
                  Semantics(
                    button: true,
                    expanded: _acik,
                    child: SandikBasma(
                      onTap: () => setState(() => _acik = !_acik),
                      child: ConstrainedBox(
                        // 48 pt dokunma hedefi (HIG 44'ün üstü; satırın
                        // tamamı dokunulabilir).
                        constraints:
                            const BoxConstraints(minHeight: SandikSpace.xxl),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _acik
                                    ? l.costsShowLess
                                    : l.costsShowAll(ozet.kalemler.length),
                                style: context.t.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: context.c.amberText,
                                ),
                              ),
                            ),
                            Icon(
                              _acik
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: context.c.amberText,
                            ),
                          ],
                        ),
                      ),
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

/// Küçük TL tutarı kuruşuyla (SEC ücreti çoğu pozisyonda birkaç lira),
/// büyüğü tam sayıyla.
String _tl(double v) => fmtTRY(v, digits: v.abs() < 100 ? 2 : 0);

/// Oran (kesir) → yüzde. SEC oranı (%0,00206) iki haneyle "%0,00" olurdu.
String _oran(double kesir) {
  final yuzde = kesir * 100;
  if (yuzde == yuzde.roundToDouble()) return fmtPct(yuzde, digits: 0);
  return fmtPct(yuzde, digits: yuzde < 0.01 ? 5 : 2);
}

class _Toplam extends StatelessWidget {
  const _Toplam({required this.etiket, required this.tutar});

  final String etiket;

  /// `null` → "—" (kayıtlı komisyon yok; sıfır yazmak "ödemedin" demek olur).
  final double? tutar;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiket,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodySmall?.copyWith(color: context.c.text58)),
          const SizedBox(height: SandikSpace.xxs),
          Text(
            tutar == null ? '—' : _tl(tutar!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.numMedium.copyWith(
                fontWeight: FontWeight.w700, color: context.c.text90),
          ),
        ],
      );
}

class _Satir extends StatelessWidget {
  const _Satir({required this.kalem});

  final MasrafKalemi kalem;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (rozet, renk) = switch (kalem.nitelik) {
      MasrafNiteligi.odendi => (l.costTagPaid, context.c.amberText),
      MasrafNiteligi.tahmini => (l.costTagEstimated, context.c.gold),
      MasrafNiteligi.bilgi => (l.costTagInfo, null),
    };
    final tutar = kalem.tutarTry;
    final oran = kalem.oran;
    final deger = tutar != null
        ? _tl(tutar)
        : oran != null
            ? _oran(oran)
            : '—';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SandikSpace.smd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: SandikSpace.sm,
                  runSpacing: SandikSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      kalem.baslik,
                      style: context.t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.c.text90),
                    ),
                    RozetCipi(metin: rozet, renk: renk),
                  ],
                ),
                const SizedBox(height: SandikSpace.xs),
                Text(
                  kalem.aciklama,
                  style:
                      context.t.bodySmall?.copyWith(color: context.c.text58),
                ),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.smd),
          Text(
            deger,
            style: context.t.numSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: tutar != null ? context.c.text90 : context.c.text58,
            ),
          ),
        ],
      ),
    );
  }
}
