import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';
import 'auth_provider.dart';

/// Sessiz saatler — SUNUCUDA yaşar (`profiles.quiet_start/quiet_end`) çünkü
/// kararı push'u gönderen edge function veriyor; cihaz tercihi oradan
/// görünmez. `partner_activity_push` ile aynı gerekçe.
///
/// TR saati, 0-23. `null` = kapalı. Sarmalı pencere (22 → 7) geçerli.
class QuietHours {
  const QuietHours({this.start, this.end});
  final int? start;
  final int? end;
  bool get enabled => start != null && end != null && start != end;
}

class QuietHoursNotifier extends AsyncNotifier<QuietHours> {
  @override
  Future<QuietHours> build() async {
    final uid = ref.watch(authProvider).valueOrNull?.id;
    if (uid == null) return const QuietHours();
    try {
      final r = await SupabaseService.instance.getQuietHours(uid);
      return QuietHours(start: r.start, end: r.end);
    } catch (_) {
      // 0057 koşulmamışsa sütun yok → kapalı görünür, kırılmaz.
      return const QuietHours();
    }
  }

  Future<void> set({int? start, int? end}) async {
    final uid = ref.read(authProvider).valueOrNull?.id;
    if (uid == null) return;
    state = AsyncData(QuietHours(start: start, end: end));
    await SupabaseService.instance.setQuietHours(uid, start: start, end: end);
  }
}

final quietHoursProvider =
    AsyncNotifierProvider<QuietHoursNotifier, QuietHours>(
        QuietHoursNotifier.new);
