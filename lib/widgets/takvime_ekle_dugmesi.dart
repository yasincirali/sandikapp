import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/crash_reporter.dart';
import '../services/share_card_service.dart';
import '../services/takvim_ics.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';

/// Kart başlığının sağındaki "Takvime ekle" ikon düğmesi (2026-11-11):
/// mevduat vadesi, Eurobond kuponu, beklenen temettü.
///
/// Halka arzdaki yolun aynısı (`takvim_ics.dart`): izin/eklenti yok, `.ics`
/// sistem paylaşım sayfasıyla verilir. Halka arz detayı metinli düğme
/// kullanıyor çünkü orada eylem satırı var; buradaki yüzeyler bilgi kartı,
/// metinli düğme kartın asıl sayısıyla yarışırdı → ikon + etiket.
///
/// **Uydurma tarih yok**: [etkinlikler] boşsa düğme hiç çizilmez; çağıran
/// bilinmeyen tarihi listeye koymaz.
class TakvimeEkleDugmesi extends StatelessWidget {
  const TakvimeEkleDugmesi({
    super.key,
    required this.etkinlikler,
    required this.dosyaAdi,
    required this.konu,
  });

  final List<TakvimEtkinligi> etkinlikler;

  /// Uzantısız geçici dosya adı (`sandik-mevduat-…`).
  final String dosyaAdi;

  /// Paylaşım sayfasının konu satırı (e-postayla paylaşılırsa başlık).
  final String konu;

  Future<void> _paylas(BuildContext context) async {
    final ics = takvimIcs(etkinlikler: etkinlikler, simdi: DateTime.now());
    if (ics == null) return;
    try {
      await takvimPaylas(
        ics: ics,
        dosyaAdi: dosyaAdi,
        konu: konu,
        origin: ShareCardService.originOf(context),
      );
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'takvime_ekle');
      if (context.mounted) showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (etkinlikler.isEmpty) return const SizedBox.shrink();
    // Builder: iPad'de paylaşım sayfası düğmenin kendisine bağlansın.
    return Builder(
      builder: (bc) => IconButton(
        tooltip: context.l10n.addToCalendar,
        icon: Icon(Icons.event_rounded, size: 20, color: context.c.amberText),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
            minWidth: SandikTouch.min, minHeight: SandikTouch.min),
        onPressed: () => _paylas(bc),
      ),
    );
  }
}
