import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../theme/sandik.dart';
import 'sandik_cam.dart';

/// Bağlam menüsündeki tek eylem.
class SandikBaglamEylemi {
  const SandikBaglamEylemi({
    required this.etiket,
    required this.ikon,
    required this.onSec,
    this.yikici = false,
  });

  final String etiket;
  final IconData ikon;
  final VoidCallback onSec;

  /// Sil gibi geri alınamayan eylem: kırmızı ve listenin sonunda.
  final bool yikici;
}

/// Satıra uzun basınca açılan kısayol menüsü (bayrak `goz_alici`, cam/HIG
/// incelemesi 2026-10-12).
///
/// - **iOS:** sistemin bağlam menüsü (`CupertinoContextMenu`): satır
///   önizlemesi büyür, arka plan bulanıklaşır, eylemler altında. HIG'in
///   "uzun bas → önizleme + eylemler" kalıbı; hareketi ve titreşimi
///   sistemin kendisi.
/// - **Android:** uzun basınca eylem listesi alt sayfada (`showSandikSheet`)
///   — Material'de uzun basmanın karşılığı.
///
/// Bu bir KISAYOL: aynı eylemler satırın kaydırma panelinde ve varlık
/// sayfasında da var; bilinen hiçbir kontrol yerinden oynamaz. VoiceOver /
/// TalkBack eylemleri "Eylemler" rotorundan okur ([Semantics] özel
/// eylemleri), uzun basma gerekmez.
///
/// Bayrak kapalıyken ya da eylem yokken çocuğu olduğu gibi döner.
class SandikBaglamMenusu extends StatelessWidget {
  const SandikBaglamMenusu({
    super.key,
    required this.baslik,
    required this.eylemler,
    required this.child,
  });

  /// Android alt sayfasının başlığı (varlığın adı).
  final String baslik;
  final List<SandikBaglamEylemi> eylemler;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!SandikCam.acik || eylemler.isEmpty) return child;
    final sirali = [
      ...eylemler.where((e) => !e.yikici),
      ...eylemler.where((e) => e.yikici),
    ];
    final govde = defaultTargetPlatform == TargetPlatform.iOS
        ? _iosMenusu(sirali)
        : GestureDetector(
            onLongPress: () => _androidSayfasi(context, sirali),
            child: child,
          );
    return Semantics(
      customSemanticsActions: {
        for (final e in sirali) CustomSemanticsAction(label: e.etiket): e.onSec,
      },
      child: govde,
    );
  }

  Widget _iosMenusu(List<SandikBaglamEylemi> sirali) {
    return CupertinoContextMenu.builder(
      enableHapticFeedback: true,
      actions: [
        for (final e in sirali)
          Builder(
            builder: (menu) => CupertinoContextMenuAction(
              isDestructiveAction: e.yikici,
              trailingIcon: e.ikon,
              onPressed: () {
                // Önce menü kapanır, eylem (diyalog/sheet) ekranın kendi
                // bağlamından açılır.
                Navigator.of(menu).pop();
                e.onSec();
              },
              child: Text(e.etiket),
            ),
          ),
      ],
      // Önizleme kök katmanda çizilir: ekranın `Material` atası orada yok.
      builder: (context, animasyon) =>
          Material(type: MaterialType.transparency, child: child),
    );
  }

  Future<void> _androidSayfasi(
      BuildContext context, List<SandikBaglamEylemi> sirali) async {
    SandikHaptic.medium.perform();
    final secilen = await showSandikSheet<SandikBaglamEylemi>(
      context: context,
      backgroundColor: context.c.surface1,
      builder: (sayfa) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: SandikSpace.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SandikTutamac(),
              Padding(
                padding: EdgeInsets.fromLTRB(SandikSpace.screenH(sayfa),
                    SandikSpace.xs, SandikSpace.screenH(sayfa), SandikSpace.sm),
                child: Text(
                  baslik,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sayfa.t.titleMedium
                      ?.copyWith(color: sayfa.c.text90),
                ),
              ),
              for (final e in sirali)
                ListTile(
                  minTileHeight: SandikTouch.min + SandikSpace.sm,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: SandikSpace.screenH(sayfa)),
                  leading: Icon(e.ikon,
                      color: e.yikici ? sayfa.c.danger : sayfa.c.text58),
                  title: Text(
                    e.etiket,
                    style: sayfa.t.bodyLarge?.copyWith(
                        color: e.yikici ? sayfa.c.danger : sayfa.c.text90),
                  ),
                  onTap: () => Navigator.of(sayfa).pop(e),
                ),
            ],
          ),
        ),
      ),
    );
    secilen?.onSec();
  }
}
