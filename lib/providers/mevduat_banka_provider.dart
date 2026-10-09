import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mevduat_bankasi.dart';
import '../services/crash_reporter.dart';
import '../services/supabase_service.dart';

/// Mevduat formunun banka listesi + TCMB faiz ortalamaları (bayrak
/// `mevduat_banka_secici`, 0129).
///
/// ## Performans (yasin 2026-10-09: "performansı etkilemeyecek şekilde")
/// İki küçük tablo (≈30 + 5 satır), yalnız form açılınca ve oturumda BİR
/// kez okunur (başarıda keepAlive): liste yılda bir değişir, ortalama haftada bir.
/// Dış kaynağa telefon hiç gitmez.
///
/// ## Hata
/// Okuma düşerse boş döner: form bugünkü serbest metin + boş faiz
/// davranışına düşer, kullanıcı engellenmez. Hata önbelleğe alınmaz
/// (sonraki açılış yeniden dener) ve Crashlytics'e gider.
typedef MevduatKaynaklari = ({
  List<MevduatBankasi> bankalar,
  Map<String, MevduatFaizOrtalamasi> ortalamalar,
});

final mevduatKaynaklariProvider =
    FutureProvider.autoDispose<MevduatKaynaklari>((ref) async {
  try {
    final r = await Future.wait([
      SupabaseService.instance.mevduatBankalari(),
      SupabaseService.instance.mevduatFaizOrtalamalari(),
    ]);
    // Yalnız başarı oturum boyunca tutulur; boş dönen hata bir sonraki
    // form açılışında yeniden denenir.
    ref.keepAlive();
    return (
      bankalar: r[0] as List<MevduatBankasi>,
      ortalamalar: r[1] as Map<String, MevduatFaizOrtalamasi>,
    );
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'mevduatKaynaklariProvider');
    return (
      bankalar: const <MevduatBankasi>[],
      ortalamalar: const <String, MevduatFaizOrtalamasi>{}
    );
  }
});
