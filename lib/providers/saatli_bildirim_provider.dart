import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/saatli_bildirim.dart';
import '../services/crash_reporter.dart';
import '../services/saatli_bildirim_service.dart';
import 'auth_provider.dart';
import 'preferences_provider.dart'
    show OzellikDurumu, paywallVisibleProvider, premiumErisimProvider;

/// Servis kapısı — testte sahte `SaatliBildirimStore`'lu servisle değişir.
final saatliBildirimServiceProvider =
    Provider<SaatliBildirimService>((_) => SaatliBildirimService.instance);

/// `saatli_bildirimler` bu sunucuda var mı (0188).
///
/// ## Neden (dağıtım güvenliği)
/// Bu build mağazaya migration'dan ÖNCE çıkabilir; tablo yokken bölüm,
/// zil menüsündeki satır ve Ayarlar satırı çizilseydi kullanıcı her
/// kaydette hata görürdü. "Yakında" yazmak da çıkmamış özelliği vaat etmek
/// olur. Karar: tablo yoksa HİÇBİR giriş noktası çizilmez. Tablo yok
/// (`PGRST205`/`42P01`) → false; başka hata (ağ, yetki) Crashlytics'e
/// non-fatal gider ve yine false (bilinmeyen durumda yeni yüzey gösterilmez).
/// Oturum başına bir kez sorulur; hesap değişince yeniden.
final saatliTabloVarProvider = FutureProvider<bool>((ref) async {
  final me = ref.watch(authProvider).valueOrNull;
  if (me == null) return false;
  try {
    return await ref.read(saatliBildirimServiceProvider).tabloVarMi();
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'saatliBildirim.tabloYoklama');
    return false;
  }
});

/// Saatli bildirimin bu kullanıcıdaki hâli.
///
/// Tablo yoksa ya da henüz bilinmiyorsa gizli. Sonrası
/// `gostergeParametreDurumuProvider` kuralı: paywall kapalıyken yalnız admin
/// görür (ödeme hazır olmadan herkese açılanı sonra kilitlemek verileni geri
/// almak olur), açıkken herkes görür, Premium erişimi olmayana kilitli.
/// Ücretsiz tadımlık YOK (yasin kararı bekleyen 1. soru, varsayılan hayır).
final saatliBildirimDurumuProvider = Provider<OzellikDurumu>((ref) {
  if (ref.watch(saatliTabloVarProvider).valueOrNull != true) {
    return OzellikDurumu.gizli;
  }
  return saatliDurumu(
    paywall: ref.watch(paywallVisibleProvider),
    admin: ref.watch(isPushAdminProvider).valueOrNull == true,
    premium: ref.watch(premiumErisimProvider),
  );
});

/// [saatliBildirimDurumuProvider]'ın saf kararı (tablo varken).
OzellikDurumu saatliDurumu({
  required bool paywall,
  required bool admin,
  required bool premium,
}) {
  if (!paywall) return admin ? OzellikDurumu.acik : OzellikDurumu.gizli;
  return premium ? OzellikDurumu.acik : OzellikDurumu.kilitli;
}

/// Kullanıcının saatli bildirimleri. Tablo yoksa boş; okuma hatası listeyi
/// düşürmez (boş + Crashlytics, `yuzdeAlarmlariProvider` gerekçesi:
/// yeni özellik Alarmlarım'ı hata ekranının arkasına saklamasın).
class SaatliBildirimlerNotifier extends AsyncNotifier<List<SaatliBildirim>> {
  SaatliBildirimService get _svc => ref.read(saatliBildirimServiceProvider);

  @override
  Future<List<SaatliBildirim>> build() async {
    final me = ref.watch(authProvider).valueOrNull;
    if (me == null) return const [];
    if (await ref.watch(saatliTabloVarProvider.future) != true) return const [];
    try {
      return await _svc.fetchAll(me.id);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'saatliBildirim.fetch');
      return const [];
    }
  }

  /// Sembolün kaydı varsa saatlerini günceller, yoksa yeni satır açar.
  /// Sunucu reddi (`saatli_siniri`) çağırana atılır.
  Future<SaatliBildirim> kaydet({
    required String userId,
    required String symbol,
    required String label,
    required List<int> saatler,
  }) async {
    final liste = state.valueOrNull ?? const <SaatliBildirim>[];
    final mevcut = liste.where((b) => b.symbol == symbol).firstOrNull;
    final sirali = [...saatler]..sort();
    final kayit = mevcut != null
        ? await _svc.saatleriGuncelle(mevcut.id, sirali)
        : await _svc.create(SaatliBildirim(
            id: '',
            userId: userId,
            symbol: symbol,
            label: label,
            saatler: sirali,
            createdAt: DateTime.now(),
          ));
    state = AsyncData([
      for (final b in liste)
        if (b.symbol != symbol) b,
      kayit,
    ]);
    return kayit;
  }

  Future<void> sil(String id) async {
    await _svc.delete(id);
    state = AsyncData([
      for (final b in state.valueOrNull ?? const <SaatliBildirim>[])
        if (b.id != id) b,
    ]);
  }
}

final saatliBildirimlerProvider =
    AsyncNotifierProvider<SaatliBildirimlerNotifier, List<SaatliBildirim>>(
        SaatliBildirimlerNotifier.new);

/// Yeni varlık eklenebilir mi (aktif satır sınırı, sunucuyla aynı).
bool saatliYeniVarlikEklenebilir(List<SaatliBildirim> liste, String symbol) =>
    liste.any((b) => b.symbol == symbol) ||
    liste.where((b) => b.aktif).length < SaatliBildirim.enFazlaVarlik;
