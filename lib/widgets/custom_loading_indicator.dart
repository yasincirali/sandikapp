import 'package:flutter/material.dart';
import '../theme/sandik.dart';
import '../theme/yukleme_isareti.dart';

/// Uygulama genelinde tek yükleme göstergesi — açılış işaretini temel alır.
///
/// Neden merkezi: 36 ayrı `CircularProgressIndicator` çağrısı farklı boyut ve
/// renklerle dağılmıştı. Tek kaynak, her yükleme anında aynı marka hissini verir.
///
/// 2026-09-24: GIF yerine vektör ([YuklemeIsareti]). GIF'in 200×200 tuvalinde
/// içerik 150×150'deydi ve `_gifOverdraw` çarpanıyla telafi ediliyordu; şimdi
/// işaret [size] kutusunu tam doldurur, çarpan yok. Gerekçe ve ölçümler
/// `yukleme_isareti.dart` başında.
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

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      // Dış ölçü istenen boyutta kilitli — layout kayması olmaz.
      child: YuklemeIsareti(size: size),
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
