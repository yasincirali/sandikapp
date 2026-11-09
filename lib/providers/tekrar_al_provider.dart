import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tekrar_al.dart';
import '../services/remote_config_service.dart';
import 'portfolio_provider.dart';

/// Varlık Ekle'nin "Tekrar al" çipleri (kural `tekrarAlAdaylari`). Hesap
/// burada, ekranın `build()`'inde değil: defter değişince bir kez yeniden
/// sıralanır. Sahip, portföy durumunun sahibi (ortağın lotu sayılmaz).
final tekrarAlProvider = Provider<List<TekrarAlAdayi>>((ref) {
  final durum = ref.watch(portfolioProvider).valueOrNull;
  if (durum == null) return const [];
  final rc = RemoteConfigService.instance;
  return tekrarAlAdaylari(
    durum.assets,
    sahip: durum.ownerId,
    turAcik: rc.turSecenegi,
    abdAcik: rc.abdHisse,
  );
});
