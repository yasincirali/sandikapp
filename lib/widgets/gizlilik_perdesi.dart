import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/preferences_provider.dart';
import '../theme/sandik.dart';

/// Uygulama değiştiricide portföy tutarlarını örten perde (Ar-Ge 5 Kas 21:20
/// #3, müşteri raporu YAP).
///
/// Neden: biyometrik kilit öne dönüşte soruluyor, ama iOS uygulama
/// değiştirici görüntüsünü `inactive` anında alıyor; o karede tutarlar açık
/// görünüyordu. Kilidi açan kullanıcı gizlilik istiyor, söz yarım kalıyordu.
/// Banka uygulamaları (İş Bankası, Papara, Revolut) aynı perdeyi kullanır.
///
/// Kararlar:
/// - Yalnız kilit AÇIKKEN. Kilidi kapalı kullanıcının deneyimi birebir aynı.
/// - Yalnız iOS. Android'in son uygulamalar görüntüsü `onPause`'da alınır ve
///   Flutter karesi o ana yetişmez; oranın doğru aracı `FLAG_SECURE`, o da
///   ekran görüntüsünü de yasaklar (ayrı karar). Android'de `inactive` bölünmüş
///   ekranda odak kaybında da gelir; perde orada kullanıcıyı rahatsız ederdi.
/// - Animasyon yok: perde ilk karede tam görünmeli, hareketi azalt da aynı.
/// - Bildirim merkezi, Face ID istemi gibi kısa `inactive` anlarında da
///   görünür; banka uygulamalarındaki davranış budur, öne dönünce hemen kalkar.
class GizlilikPerdesi extends ConsumerStatefulWidget {
  final Widget child;

  /// Test için platform zorlaması; null ise gerçek platform.
  @visibleForTesting
  final bool? iosMu;

  const GizlilikPerdesi({super.key, required this.child, this.iosMu});

  @override
  ConsumerState<GizlilikPerdesi> createState() => _GizlilikPerdesiState();
}

class _GizlilikPerdesiState extends ConsumerState<GizlilikPerdesi>
    with WidgetsBindingObserver {
  bool _arkada = false;

  bool get _ios =>
      widget.iosMu ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final arkada = state != AppLifecycleState.resumed;
    if (arkada != _arkada) setState(() => _arkada = arkada);
  }

  @override
  Widget build(BuildContext context) {
    final perde = _ios && _arkada && ref.watch(biometricLockProvider);
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        widget.child,
        if (perde)
          Positioned.fill(
            child: ColoredBox(
              key: const ValueKey('gizlilikPerdesi'),
              color: context.c.background,
              child: const Center(child: SandikLogo(size: 72)),
            ),
          ),
      ],
    );
  }
}
