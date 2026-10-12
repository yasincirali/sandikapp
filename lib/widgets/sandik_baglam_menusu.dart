import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        ? _iosMenusu(context, sirali)
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

  Widget _iosMenusu(BuildContext context, List<SandikBaglamEylemi> sirali) {
    // Önizleme kök katmanda (rota üstünde) çizilir; satırın atası olan
    // sağlayıcı kabı orada yok. Demo kabuğu kendi kabını iç içe kurar —
    // kökten okunsa önizleme gerçek veriyi gösterirdi. Satırın kabı taşınır.
    ProviderContainer? kap;
    try {
      kap = ProviderScope.containerOf(context, listen: false);
    } catch (_) {
      kap = null;
    }
    final kayit = _BoyutKaydi();
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
      builder: (ctx, animasyon) {
        // Önizleme kök katmanda çizilir: ekranın `Material` atası orada yok.
        Widget onizleme =
            Material(type: MaterialType.transparency, child: child);
        if (kap != null) {
          onizleme = UncontrolledProviderScope(container: kap, child: onizleme);
        }
        // Menü açılırken önizlemeye satırın genişliği verilmez (sınırsız
        // yükseklik, dar genişlik): satır kendi boyunda kurulup ölçeklenir —
        // sistemdeki önizleme de bir küçültülmüş anlık görüntüdür. İlk
        // karede boyut henüz yoksa satır yerinde olduğu gibi.
        final boyut = kayit.boyut;
        if (boyut == null) return onizleme;
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox.fromSize(size: boyut, child: onizleme),
        );
      },
    ).boyutuKaydet(kayit);
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
                  style: sayfa.t.titleMedium?.copyWith(color: sayfa.c.text90),
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

/// Satırın yerindeki boyutu (önizleme aynı boyda kurulup ölçeklensin).
class _BoyutKaydi {
  Size? boyut;
}

extension on Widget {
  Widget boyutuKaydet(_BoyutKaydi kayit) =>
      _BoyutKaydeden(kayit: kayit, child: this);
}

class _BoyutKaydeden extends SingleChildRenderObjectWidget {
  const _BoyutKaydeden({required this.kayit, super.child});

  final _BoyutKaydi kayit;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _BoyutKaydedenRender(kayit);

  @override
  void updateRenderObject(
      BuildContext context, _BoyutKaydedenRender renderObject) {
    renderObject.kayit = kayit;
  }
}

class _BoyutKaydedenRender extends RenderProxyBox {
  _BoyutKaydedenRender(this.kayit);

  _BoyutKaydi kayit;

  @override
  void performLayout() {
    super.performLayout();
    kayit.boyut = size;
  }
}
