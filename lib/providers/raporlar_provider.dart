import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analiz_provider.dart';
import 'fon_akisi_provider.dart';
import 'hafta_ozeti_provider.dart';

/// Raporlar kapısının (bayrak `raporlar_kapisi`, sadeleştirme 2 S6) veri
/// kapıları.
///
/// Kapı yalnızca yolu toplar; raporların kendisi değişmez. Bir satırın
/// gösterilip gösterilmeyeceği, o raporun BUGÜN başka bir yerden açılabildiği
/// koşulun aynısıdır — kapı yeni bir erişim kuralı icat etmez:
///   · Haftanın özeti → `balina_radari_acik` (ana ekran şeridi, fon kartı
///     bağlantısı ve bildirimle aynı bayrak);
///   · Aylık rapor → Haftanın özeti ekranındaki aylık satırın koşulu (en az
///     bir aylık not), aşağıda [aylikRaporDonemiProvider];
///   · Yıl özeti → `recap_enabled` + anlamlı veri (`yilOzetiProvider`,
///     `recap_screen.dart`: hesap afişle aynı dosyada, aynı işlevde).

/// Aylık raporun açılacağı ay (ayın 1'i) ya da `null` (rapor yok).
///
/// `hafta_ozeti_screen.dart` aylık satırıyla AYNI hesap: haftanın satırlarının
/// anahtarlarıyla aylık notlar istenir, en yeni ay seçilir. Ayrı bir sorgu
/// yazılmaz — `notOzetleriProvider` aynı anahtarla önbellekten döner.
final aylikRaporDonemiProvider = Provider.autoDispose<DateTime?>((ref) {
  if (!ref.watch(balinaRadariAcikProvider)) return null;
  final liste = ref.watch(haftaOzetiProvider).valueOrNull;
  if (liste == null || liste.isEmpty) return null;
  final anahtarlar = [for (final s in liste) s.anahtar];
  final notlar = ref
      .watch(notOzetleriProvider(notKumesi(anahtarlar, 'aylik')))
      .valueOrNull;
  if (notlar == null || notlar.isEmpty) return null;
  return notlar.values
      .map((n) => n.donem)
      .reduce((a, b) => a.isAfter(b) ? a : b);
});
