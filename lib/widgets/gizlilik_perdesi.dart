import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/preferences_provider.dart';
import '../services/notification_service.dart';
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
/// - Kilit ekranı açıkken perde YOK (yasin 2026-11-27: "açılışta splash az
///   durup sonra küçük logo gözüküyor"). Soğuk açılışta Face ID istemi
///   `inactive` getiriyor; perde 72'lik statik logoyu kilit ekranının 112'lik
///   animasyonlu açılış işaretinin üstüne çiziyordu, animasyon donmuş ve logo
///   küçülmüş görünüyordu. Kilit ekranı tutar göstermez, örtecek bir şey yok.
///   Değer build'de okunur, dinlenmez: kilit bayrağı alt ağacın build'i
///   içinde yazılıyor, burada setState o anda hata verirdi; perde zaten
///   yalnız yaşam döngüsü değişince yeniden çizilir.
class GizlilikPerdesi extends ConsumerStatefulWidget {
  final Widget child;

  /// Test için platform zorlaması; null ise gerçek platform.
  @visibleForTesting
  final bool? iosMu;

  /// Test için kilit ekranı durumu; null ise [NotificationService]'in
  /// kilit kapısı.
  @visibleForTesting
  final ValueListenable<bool>? kilitEkrani;

  const GizlilikPerdesi(
      {super.key, required this.child, this.iosMu, this.kilitEkrani});

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
    final kilitEkrani = (widget.kilitEkrani ??
            NotificationService.instance.kilitKapisi.kilitli)
        .value;
    final perde = _ios &&
        _arkada &&
        !kilitEkrani &&
        ref.watch(biometricLockProvider);
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
