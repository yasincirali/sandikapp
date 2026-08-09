import 'package:flutter/material.dart';
import '../theme/sandik.dart';

/// Uygulama genelinde tek yükleme göstergesi — açılış GIF'ini temel alır.
///
/// Neden merkezi: 36 ayrı `CircularProgressIndicator` çağrısı farklı boyut ve
/// renklerle dağılmıştı. Tek kaynak, her yükleme anında aynı marka hissini verir.
///
/// GIF notları (assets/images/loading.gif):
/// - 200×200 tuval, içerik yalnızca ortadaki 150×150'de. Kalan %25 boş dolgu,
///   bu yüzden ham `size` görsel olarak %25 küçük görünür; [_gifOverdraw] ile
///   telafi edilir.
/// - Alfa kanalı 1-bit (yalnız 0 ve 255). GIF formatı yarı saydamlığı
///   desteklemez, dolayısıyla kenarlar testere dişi olur. `FilterQuality.high`
///   ölçekleme sırasında bunu yumuşatır.
/// - Arka planı şeffaf; zemin rengi neyse ona oturur. Ayrı bir maskeye gerek yok
///   — GIF'i opak bir kutuya koymak tam tersine çerçeve oluştururdu.
class CustomLoadingIndicator extends StatelessWidget {
  const CustomLoadingIndicator({
    super.key,
    this.size = medium,
    this.semanticLabel = 'Yükleniyor',
  });

  /// Satır içi, buton içi — metinle aynı hizada durur.
  static const double small = 20;

  /// Varsayılan: liste/kart yükleme durumları.
  static const double medium = 40;

  /// Tam ekran boş durumlar.
  static const double large = 60;

  /// Açılış ekranı.
  static const double splash = 140;

  /// GIF'in şeffaf kenar dolgusunu telafi eden çarpan (200/150).
  static const double _gifOverdraw = 200 / 150;

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final drawSize = size * _gifOverdraw;

    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      child: SizedBox(
        // Dış ölçü istenen boyutta kilitli — layout kayması olmaz.
        width: size,
        height: size,
        child: Center(
          child: SizedBox(
            width: drawSize,
            height: drawSize,
            child: Image.asset(
              'assets/images/loading.gif',
              width: drawSize,
              height: drawSize,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              // GIF yüklenemezse yükleme durumu görünmez kalmasın.
              errorBuilder: (_, __, ___) => SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  strokeWidth: size <= small ? 2 : 3,
                  valueColor: AlwaysStoppedAnimation(context.c.amberText),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ortalanmış tam alan yükleme — `Center(child: CustomLoadingIndicator())`
/// tekrarını kısaltır.
class CustomLoadingView extends StatelessWidget {
  const CustomLoadingView({
    super.key,
    this.size = CustomLoadingIndicator.large,
    this.message,
  });

  final double size;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomLoadingIndicator(size: size),
          if (message != null) ...[
            const SizedBox(height: SandikSpace.md),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
          ],
        ],
      ),
    );
  }
}
