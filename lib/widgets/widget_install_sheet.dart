import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/remote_config_service.dart';
import '../services/retention_tracker.dart';
import '../theme/sandik.dart';

/// Ana ekran widget'ı kurulum önerisi.
///
/// **Neden var:** widget, bildirim izni GEREKTİRMEYEN ikinci bir geri
/// getirme kanalı — push'u kapatan kullanıcıya ulaşan tek yüzey. Ama
/// kullanıcı çoğu uygulamada widget olduğunu bilmez; kurulum adımları
/// platforma özgü ve keşfedilmesi zordur.
///
/// **Neden ilk varlık eklendikten sonra:** öncesinde widget BOŞ görünürdü
/// ("—") ve kullanıcı işe yaramadığını düşünüp kaldırırdı. İlk varlıktan
/// sonra widget'ın gösterecek bir rakamı var.
///
/// **Bir kez gösterilir.** İkinci kez sorulması, kabul etmeyen kullanıcı
/// için taciz olur; `RetentionTracker` işareti bunu garanti eder.
class WidgetInstallSheet extends StatelessWidget {
  const WidgetInstallSheet({super.key});

  static const _gosterildiIsareti = 'widget_prompt_shown';

  /// Koşullar sağlanıyorsa öneriyi gösterir.
  ///
  /// Üç kapı: Remote Config bayrağı, daha önce gösterilmemiş olması ve
  /// platformun widget desteklemesi. Hiçbiri sağlanmazsa sessizce döner —
  /// çağıran tarafın koşul bilmesine gerek yok.
  static Future<void> maybeShow(BuildContext context) async {
    if (!RemoteConfigService.instance.widgetPromptEnabled) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;
    if (await RetentionTracker.instance.hasActivation(_gosterildiIsareti)) {
      return;
    }
    // İşaret, gösterime KARAR VERİLDİKTEN sonra harcanır. Önce işaretleyip
    // sonra `context.mounted` kontrolüne takılsaydık tek seferlik hak
    // sessizce yanardı ve öneri hiç gösterilmezdi.
    if (!context.mounted) return;
    await RetentionTracker.instance.markActivation(_gosterildiIsareti);

    // İkinci kontrol ZORUNLU: yukarıdaki `markActivation` bir `await`'tir ve
    // o sırada ekran kapanmış olabilir. `context`'i await sonrası kullanmak
    // sökülmüş bir element üzerinde çalışmak demektir (analyzer:
    // `use_build_context_synchronously`). İşaret zaten harcandığı için
    // burada dönmek doğru: öneri bir sonraki uygun anda değil, hiç
    // gösterilmez — tek seferlik hakkın anlamı budur.
    if (!context.mounted) return;

    AnalyticsService.instance.logScreenView(screenName: 'widget_install_sheet');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const WidgetInstallSheet(),
    );
  }

  /// Platforma özgü adımlar.
  ///
  /// Metinler iki işletim sisteminin KENDİ sözcükleriyle yazılır
  /// ("Düzenle" / "basılı tut"); genel bir tarif kullanıcıyı ekranda
  /// aradığı düğmeyi bulamaz hâlde bırakır.
  static List<String> adimlar() => Platform.isIOS
      ? const [
          'Ana ekranda boş bir yere basılı tut',
          'Sol üstteki + işaretine dokun',
          'Listeden "sandık"ı seç ve ekle',
        ]
      : const [
          'Ana ekranda boş bir yere basılı tut',
          '"Widget\'lar"a dokun',
          '"sandık"ı bulup ana ekrana sürükle',
        ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.text20,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.widgets_rounded, size: 22, color: c.amberText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Portföyünü ana ekranda gör',
                  style: context.t.headlineSmall?.copyWith(color: c.text90),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Uygulamayı açmadan toplamını ve günlük değişimini görürsün.',
            style: context.t.bodyLarge?.copyWith(color: c.text58),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < adimlar().length; i++) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Numaralandırma burada BİLGİ taşır: adımların sırası
                  // gerçekten bağlayıcı, süsleme değil.
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.amberFill,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: context.t.labelLarge?.copyWith(
                        color: c.onAmber,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      adimlar()[i],
                      style: context.t.bodyLarge?.copyWith(color: c.text90),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.amberFill,
                foregroundColor: c.onAmber,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Anladım'),
            ),
          ),
        ],
      ),
    );
  }
}
