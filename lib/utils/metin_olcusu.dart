import 'package:flutter/widgets.dart';

/// [stil]'in tek satırının yüksekliği, yazı ölçeğiyle (Dynamic Type)
/// birlikte.
///
/// Dönemden döneme değişen içerik (tutar, yüzde rozeti, "veri gelmedi"
/// cümlesi, `FittedBox` ile küçülen uzun fiyat) için ayrılan yuvalar sabit
/// pt ile değil bu ölçüyle kurulur (yasin 2026-11-11, "dönem değişince
/// grafik ve kâr/zarar yazısı yer değiştiriyor"): yuva içeriğe göre değil
/// stile göre boylanır, 2× yazıda da büyür, kırpmaz.
double tekSatirBoyu(BuildContext context, TextStyle? stil) {
  final tp = TextPainter(
    text: TextSpan(text: 'Ağ0', style: stil),
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final boy = tp.height;
  tp.dispose();
  return boy;
}
