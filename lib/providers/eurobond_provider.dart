import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/eurobond.dart';
import '../services/supabase_service.dart';

/// Eurobond kataloğu + son fiyat (ekleme seçicisi).
///
/// Kripto kataloğuyla aynı karar (`kriptoKatalogProvider`): autoDispose +
/// 2 dk tutma — seçiciyi kapatıp yeniden açan beklemez, fiyat da saatlerce
/// eskimez (sunucu hafta içi 20 dk'da bir yazar). Hata önbelleğe alınmaz.
/// Ekranlar `SupabaseService`'e doğrudan gitmez (katmanlama kuralı).
final eurobondKatalogProvider = FutureProvider.autoDispose<
    List<(EurobondSozlesmesi, EurobondFiyati?)>>((ref) async {
  final liste = await SupabaseService.instance.eurobondKatalogu();
  final link = ref.keepAlive();
  final zamanlayici = Timer(const Duration(minutes: 2), link.close);
  ref.onDispose(zamanlayici.cancel);
  return liste;
});

/// Tek tahvilin sözleşmesi + son fiyatı (varlık ekranı, düzenleme formu).
/// Katalogda yoksa (pasife alınmış, bozuk satır) `null` — kart çizilmez,
/// sayı uydurulmaz.
final eurobondProvider = FutureProvider.autoDispose
    .family<(EurobondSozlesmesi, EurobondFiyati?)?, String>((ref, isin) async {
  final r = await SupabaseService.instance.eurobondlar([isin]);
  return r[isin];
});
