import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/alis_satis_provider.dart';
import '../services/fiyat_kaynagi.dart'
    show gorunurSatisFiyati, kuyumcuFarkiYuzde;
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Fiyatın altındaki tek bilgi satırı: "Bozdurursan ₺X · Alırsan ₺Y ·
/// fark %Z" — altın ve döviz (2026-10-25).
///
/// ## Neden
/// Başlıktaki büyük fiyat, grafik ve portföy değeri ALIŞ'tır (fiyat
/// kaynağı madde 2). Kullanıcı kuyumcudan/bankadan SATIŞ'tan alır; ekleme
/// formu bu farkı "Kuyumcu farkı" satırıyla gösteriyor ama varlığa
/// bakarken görünmüyordu. Satır aynı sayıyı ([kuyumcuFarkiYuzde]) yazar.
///
/// ## Ne zaman görünür
/// Yalnız [gorunurSatisFiyati] kapısı satışı kabul ederse (yurt içi
/// kotasyon, TRY, satış ≥ alış, makas sınır içinde). Satış bilinmiyorsa
/// satır hiç çizilmez; yerine boşluk ya da "—" bile konmaz (uydurma yok;
/// satır yoksa yer de kaplamaz).
///
/// Renk taşımaz (yön değil bilgi), dokunulmaz; ekran okuyucu tam cümle
/// okur. Büyük yazıda alt satıra kayar, kırpılmaz.
class BozdurAlSatiri extends ConsumerWidget {
  const BozdurAlSatiri({
    super.key,
    required this.ticker,
    required this.paraBirimi,
    this.ustBosluk = SandikSpace.xs,
  });

  final String ticker;

  /// Kotasyonun para birimi (`Asset.currency` / `VarlikKimligi.currency`).
  final String paraBirimi;

  /// Satır görünürse üstündeki boşluk; görünmezse boşluk da yok.
  final double ustBosluk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = ref.watch(alisSatisProvider(ticker)).valueOrNull;
    if (k == null) return const SizedBox.shrink();
    final satis = gorunurSatisFiyati(
      ticker: ticker,
      paraBirimi: paraBirimi,
      alis: k.alis,
      satis: k.satis,
    );
    if (satis == null) return const SizedBox.shrink();
    final l = context.l10n;
    final alis = fmtTRYFiyat(k.alis);
    final satisMetni = fmtTRYFiyat(satis);
    final fark =
        fmtPct(kuyumcuFarkiYuzde(alis: k.alis, satis: satis), digits: 1);
    return Padding(
      padding: EdgeInsets.only(top: ustBosluk),
      child: Semantics(
        label: l.bozdurAlSatiriSemantik(alis, satisMetni, fark),
        child: ExcludeSemantics(
          child: Text(
            l.bozdurAlSatiri(alis, satisMetni, fark),
            key: const ValueKey('bozdur-al-satiri'),
            softWrap: true,
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
        ),
      ),
    );
  }
}
