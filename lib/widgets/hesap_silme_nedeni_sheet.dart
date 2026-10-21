import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/analytics_service.dart';
import '../theme/sandik.dart';

/// Hesap silindikten SONRA isteğe bağlı "neden?" sorusu (Ar-Ge 21 Eki 08:45
/// #1; yasin "şerh düştüklerim dışında yap", 2026-10-21).
///
/// ## Neden silmeden sonra
/// Apple 5.1.1(v) silmenin kolay olmasını ister: soru silme yolunda bir adım
/// bile eklemez. Silme bitmiş, "hesabın silindi" bilgisi bu sayfanın
/// başlığıdır (eski başarı diyaloğunun yerine); seçenekler altında durur,
/// "Kapat" her zaman bir dokunuş.
///
/// ## Neden yalnız analitik olayı
/// Müşteri raporu (21 Eki 09:15): yeni tablo, migration, GRANT yok. Olay
/// yalnız neden KODUNU taşır; serbest metin yok. Kimlik analitikten çağıran
/// tarafından silme anında düşürülür (`setUserId(null)`), olay hesaba
/// bağlanmaz — yasal metin değişmez.
enum HesapSilmeNedeni {
  kullanmiyorum,
  eksikOzellik,
  fiyatSorunu,
  baskaUygulama
}

extension on HesapSilmeNedeni {
  /// Analitik değeri — sabit, çeviriden bağımsız.
  String get kod => switch (this) {
        HesapSilmeNedeni.kullanmiyorum => 'kullanmiyorum',
        HesapSilmeNedeni.eksikOzellik => 'eksik_ozellik',
        HesapSilmeNedeni.fiyatSorunu => 'fiyat_sorunu',
        HesapSilmeNedeni.baskaUygulama => 'baska_uygulama',
      };
}

Future<void> hesapSilindiSayfasi(BuildContext context) => showSandikSheet<void>(
      context: context,
      backgroundColor: context.c.surface1,
      isScrollControlled: true,
      builder: (_) => const HesapSilmeNedeniSheet(),
    );

@visibleForTesting
String hesapSilmeNedeniKodu(HesapSilmeNedeni n) => n.kod;

class HesapSilmeNedeniSheet extends StatelessWidget {
  const HesapSilmeNedeniSheet({super.key});

  String _etiket(BuildContext context, HesapSilmeNedeni n) {
    final l = context.l10n;
    return switch (n) {
      HesapSilmeNedeni.kullanmiyorum => l.hsnKullanmiyorum,
      HesapSilmeNedeni.eksikOzellik => l.hsnEksikOzellik,
      HesapSilmeNedeni.fiyatSorunu => l.hsnFiyatSorunu,
      HesapSilmeNedeni.baskaUygulama => l.hsnBaskaUygulama,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    final l = context.l10n;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.lg, SandikSpace.sm2, SandikSpace.lg, SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: SandikTutamac()),
            const SizedBox(height: SandikSpace.md),
            Row(
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    color: c.gain, size: SandikSpace.lgs),
                const SizedBox(width: SandikSpace.smd),
                Expanded(
                  child: Text(l.accountDeletedTitle,
                      style: t.headlineSmall?.copyWith(color: c.text90)),
                ),
              ],
            ),
            const SizedBox(height: SandikSpace.xs),
            Text(l.accountDeletedBody,
                style: t.bodyMedium?.copyWith(color: c.text58)),
            const SizedBox(height: SandikSpace.lg),
            Text(l.hsnSoru, style: t.titleSmall?.copyWith(color: c.text90)),
            const SizedBox(height: SandikSpace.sm),
            for (final n in HesapSilmeNedeni.values) ...[
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: SandikTouch.minSize,
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () {
                  SandikHaptic.selection.perform();
                  AnalyticsService.instance.logHesapSilmeNedeni(n.kod);
                  Navigator.of(context).pop();
                },
                child: Text(_etiket(context, n)),
              ),
              const SizedBox(height: SandikSpace.xs2),
            ],
            const SizedBox(height: SandikSpace.xs),
            TextButton(
              style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.hsnKapat),
            ),
          ],
        ),
      ),
    );
  }
}
