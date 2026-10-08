import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../providers/analiz_provider.dart';
import '../providers/fon_akisi_provider.dart';
import '../screens/analiz_notu_screen.dart';
import '../theme/sandik.dart';

/// Varlık sayfasında haftalık not kutusu (S15-B, 2026-10-05): notun başlık
/// cümlesi + "Notu oku". Başlık ücretsiz katmandır (`analiz_ozetleri`);
/// maddeler ayrıntı ekranında.
///
/// ## Ne zaman HİÇ çizilmez
/// Bayrak kapalı, varlık radar dışında, bu varlığın son üç haftada
/// yayında notu yok. "Not henüz yok" kutusu çizilmez: not her varlıkta
/// olmayabilir (yalnız kullanıcıların tuttuğu ilk 300 varlık), boş kutu
/// bir şeyin bozuk olduğunu düşündürür.
class AnalizNotuKutusu extends ConsumerWidget {
  const AnalizNotuKutusu({
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
    final anahtar = notAnahtari(tur: tur, ticker: ticker);
    if (anahtar == null) return const SizedBox.shrink();
    final not = ref.watch(varlikNotOzetiProvider(anahtar)).valueOrNull;
    if (not == null) return const SizedBox.shrink();

    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final gunAy =
        DateFormat('d MMM', Localizations.localeOf(context).toString());
    final bas = not.veriBaslangic ?? not.donem;
    final bitis = not.veriBitis ?? not.donem.add(const Duration(days: 6));
    final kod = notKodu(anahtar);
    void ac() => pushGuarded(
          context,
          adaptiveRoute<void>(
            builder: (_) => AnalizNotuScreen(
              ticker: anahtar,
              tur: 'haftalik',
              donem: not.donem,
              kod: kod,
              baslik: not.baslik,
            ),
          ),
        );

    return Padding(
      padding: dis,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l10n.anzNotUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            onTap: ac,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(not.baslik,
                    style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600, color: c.text90)),
                const SizedBox(height: SandikSpace.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.anzMeta(
                            '${not.maddeSayisi}',
                            l10n.flowRange(
                                gunAy.format(bas), gunAy.format(bitis))),
                        style: t.bodySmall?.copyWith(color: c.text58),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                          minimumSize: SandikTouch.minSize),
                      onPressed: ac,
                      child: Text(l10n.anzNotuOku),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
