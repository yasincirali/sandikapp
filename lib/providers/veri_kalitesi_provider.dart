import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../services/veri_kalitesi.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';

export '../services/veri_kalitesi.dart';

/// "Bugün" — test ve ekran görüntüsü deterministik olsun diye override
/// edilebilir (`halkaArzSaatProvider` emsali).
final veriKalitesiSaatProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Kullanıcının KENDİ bugünkü pozisyonlarındaki eksik bilgi
/// (`veri_kalitesi.dart`). Ortağın lotları girmez: düzeltme yalnız kendi
/// kaydında yapılabilir (`xrayPozisyonlariProvider` ile aynı süzgeç).
final veriEksikleriProvider = Provider<List<VeriEksigi>>((ref) {
  final uid = ref.watch(authProvider).valueOrNull?.id;
  final lotlar = ref.watch(
      portfolioProvider.select((s) => s.valueOrNull?.assets ?? const []));
  if (uid == null) return const [];
  final pozisyonlar = aggregatePositions(
      aktifLotlar(lotlar.where((a) => a.userId == uid)).toList());
  return veriEksikleri(pozisyonlar,
      simdi: ref.watch(veriKalitesiSaatProvider)());
});

/// Pozisyon anahtarı → kendi pozisyonunun eksikleri (Portföy satırı
/// etiketi). Ana ekrandaki satırla AYNI liste; tek hesap. Anahtar sahip
/// içermez: çağıran satırın kendi pozisyonu olduğunu doğrular
/// ([pozisyonunEksikleri]) — ortağın eksiğini kullanıcı düzeltemez.
///
/// Aile (`family`) değil, tek harita: Position her fiyat turunda yeniden
/// kurulur; nesneyle anahtarlanan aile her tikte yeni sağlayıcı açıp
/// fazladan kare çizdiriyordu (`tik_maliyeti_test`).
final pozisyonEksikleriProvider =
    Provider<Map<String, List<VeriEksigi>>>((ref) {
  final m = <String, List<VeriEksigi>>{};
  for (final e in ref.watch(veriEksikleriProvider)) {
    m.putIfAbsent(e.pozisyon.key, () => []).add(e);
  }
  return m;
});

/// [p] kullanıcının kendi pozisyonuysa eksikleri, değilse boş.
List<VeriEksigi> pozisyonunEksikleri(
        Map<String, List<VeriEksigi>> harita, Position p, String? uid) =>
    uid != null && p.lots.every((l) => l.userId == uid)
        ? harita[p.key] ?? const []
        : const [];
