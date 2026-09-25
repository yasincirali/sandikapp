import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/kripto_fiyat.dart';
import '../services/supabase_service.dart';

/// Kripto kataloğu (seçici ve takip listesi araması ortak kullanır).
///
/// autoDispose + 2 dk tutma: seçiciyi kapatıp hemen yeniden açan kullanıcı
/// ikinci isteği beklemez, ama katalogdaki fiyat da saatlerce eskimez
/// (sunucu dakikada bir yazar). Hata önbelleğe alınmaz; yeniden açılış
/// yeniden dener.
final kriptoKatalogProvider =
    FutureProvider.autoDispose<List<KriptoKatalogOgesi>>((ref) async {
  final liste = await SupabaseService.instance.kriptoKatalogu();
  final link = ref.keepAlive();
  final zamanlayici = Timer(const Duration(minutes: 2), link.close);
  ref.onDispose(zamanlayici.cancel);
  return liste;
});
