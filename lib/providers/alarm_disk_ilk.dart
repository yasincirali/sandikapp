import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/alarm_onbellegi.dart';
import '../services/crash_reporter.dart';

/// Alarm sağlayıcılarının `build()`'i: cihazda kopya varsa ([disk]) onu
/// HEMEN döndürür ve sunucu okumasını ([sunucu]) arkada koşturup gelince
/// [taze] ile yerine koyar (Ar-Ge 29 Eki 20:45 #3; desen Performans'taki
/// "önce eski seri", #249). Kopya yoksa davranış birebir eski: sunucu
/// beklenir, hatası çağıranın kuralına gider.
///
/// Arka plandaki okuma hata verirse ekrandaki kopya kalır, hata
/// Crashlytics'e gider ve [AlarmOnbellegi.bayat] yanar.
Future<List<T>> diskIlkYukle<T>({
  required Ref ref,
  required Future<List<T>?> Function() disk,
  required Future<List<T>> Function() sunucu,
  required void Function(List<T>) taze,
  required String neden,
}) async {
  final kopya = await disk();
  if (kopya == null) return sunucu();
  var canli = true;
  ref.onDispose(() => canli = false);
  // Hata içeride yakalanır (kopya kalır, bayat yanar); `arkaPlan` yine de
  // beklenmeyen bir istisnayı çökme değil non-fatal kaydeder.
  CrashReporter.arkaPlan(() async {
    try {
      final t = await sunucu();
      if (canli) taze(t);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: neden);
      AlarmOnbellegi.bayat.value = true;
    }
  }(), reason: neden);
  return kopya;
}
