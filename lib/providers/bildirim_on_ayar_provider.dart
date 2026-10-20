import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset_type.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';
import 'preferences_provider.dart';
import 'sinyal_on_ayar_provider.dart';

/// Bildirimlerin TÜMÜ için tek seçici — "Az · Dengeli · Çok" (2026-10-20).
///
/// ## Neden
/// Müşteri gözüyle rapor (2026-10-20, fikir 4; yasin "yap"): Ayarlar ›
/// Bildirimler'de tek tek anahtarlar görünce kullanıcı hepsini kapatıp bir
/// daha açmıyor. Asıl soru "bu uygulama beni ne kadar rahatsız edecek?";
/// Sinyal Ayarları'nda bu soru [SinyalOnAyar] ile zaten çözülmüştü, burada
/// aynı desen bütün push türlerine yayılır.
///
/// ## Kapsam — yalnız "gürültü" olabilen push'lar
/// Ön ayar şunlara yazar: teknik sinyaller (ana anahtar + [SinyalOnAyar]),
/// ortak hareketi brifing satırı (`profiles.partner_activity_push`) ve
/// haftalık/aylık dönem özeti (`profiles.weekly_summary_push`).
///
/// BİLEREK dışında kalanlar:
///   · Fiyat alarmları — kullanıcı kendisi kurdu; "az" bile onları susturmaz.
///   · Günlük brifing — kapatma anahtarı yok, yalnız saati var; "Az"ın
///     tanımı "kurduğun alarmlar + günlük özet".
///   · Ortaklık daveti — tek seferlik ve kullanıcının beklediği bir işlem.
///   · Birikim hatırlatması — gün seçilerek açılan opt-in; ön ayar bir gün
///     uyduramaz.
///   · Takip listesi büyük hareket — kullanıcı anahtarı yok (sunucuda
///     tercih sütunu yok); eklemek ayrı, sunucu değişikliği isteyen iş.
///   · Sessiz saatler ve Canlı Etkinlik — sıklık değil zaman/biçim ayarı.
///
/// ## Saklama yok
/// Seçili ön ayar kayıtlı değerlerden TÜRETİLİR ([bildirimOnAyarEslesen]);
/// hiçbirine uymayan kullanıcı "Özel" görür ve hiçbir şey değişmez.
/// Ön ayar seçmek var olan notifier/servis yazmalarından ibarettir —
/// kullanıcının tercihi taşınmaz, sıfırlanmaz.
enum BildirimOnAyar { az, dengeli, cok }

/// Sunucuda duran iki bildirim tercihi. İkisi de `profiles` sütunu çünkü
/// push'u üreten edge function okuyor (bkz. `SupabaseService`).
typedef SunucuBildirimTercihleri = ({bool ortakHareketi, bool donemOzeti});

/// Eşleştirmenin girdisi: ön ayarın dokunduğu her değer.
typedef BildirimDurumu = ({
  bool sinyal,
  SinyalOnAyar? sinyalOnAyar,
  bool ortakHareketi,
  bool donemOzeti,
});

/// Bir ön ayarın yazdığı değerler. [sinyalOnAyar] `null` → sinyal
/// kategori ayarlarına dokunulmaz (sinyal zaten kapanıyor; kullanıcının
/// kendi eşik/göstergeleri bir gün yeniden açtığında yerinde dursun).
typedef BildirimOnAyarTanimi = ({
  bool sinyal,
  SinyalOnAyar? sinyalOnAyar,
  bool ortakHareketi,
  bool donemOzeti,
});

/// Ön ayar → değerler.
///
/// "Dengeli" UYDURULMAZ: bugünkü varsayılanların ta kendisidir (sinyaller
/// açık + Dengeli sinyal ön ayarı, sunucu sütunları `default true`). Hiç
/// dokunmamış kullanıcı ekranı açınca "Dengeli"yi seçili görür.
///
/// "Az": yalnız kendi kurduğun alarmlar ve günlük brifing kalır; sinyal,
/// ortak hareketi ve dönem özeti susar. "Çok": hepsi açık, sinyaller
/// Çok ön ayarıyla (2 saatte bir, %50'den itibaren).
BildirimOnAyarTanimi bildirimOnAyarTanimi(BildirimOnAyar a) => switch (a) {
      BildirimOnAyar.az => (
          sinyal: false,
          sinyalOnAyar: null,
          ortakHareketi: false,
          donemOzeti: false,
        ),
      BildirimOnAyar.dengeli => (
          sinyal: true,
          sinyalOnAyar: SinyalOnAyar.dengeli,
          ortakHareketi: true,
          donemOzeti: true,
        ),
      BildirimOnAyar.cok => (
          sinyal: true,
          sinyalOnAyar: SinyalOnAyar.cok,
          ortakHareketi: true,
          donemOzeti: true,
        ),
    };

/// Kayıtlı değerler hangi ön ayara BİREBİR uyuyor; uymuyorsa `null`
/// ("Özel"). Sinyal kapalıyken sinyal ön ayarı karşılaştırılmaz (Az onu
/// yazmaz; kullanıcının saklı kategori ayarı ne olursa olsun Az'dır).
BildirimOnAyar? bildirimOnAyarEslesen(BildirimDurumu d) {
  for (final a in BildirimOnAyar.values) {
    final t = bildirimOnAyarTanimi(a);
    if (d.sinyal != t.sinyal) continue;
    if (d.ortakHareketi != t.ortakHareketi) continue;
    if (d.donemOzeti != t.donemOzeti) continue;
    if (t.sinyalOnAyar != null && d.sinyalOnAyar != t.sinyalOnAyar) continue;
    return a;
  }
  return null;
}

/// Sunucudaki iki tercih — TEK kaynak. Ön ayar kartı ile "Ayrıntılı"
/// altındaki anahtarlar aynı değeri izler; biri yazınca öteki anında
/// görür (eskiden her anahtar kendi `State`'inde okuyordu, ön ayar
/// yazınca açık bir anahtar eski değerde kalırdı).
///
/// Okuma hatası `true` sayar — `SupabaseService.getPartnerActivityPush`
/// gerekçesi: sunucu varsayılanı açık, ağ hatası "kapattım" yanılgısı
/// vermesin.
class SunucuBildirimTercihleriNotifier
    extends AsyncNotifier<SunucuBildirimTercihleri> {
  @override
  Future<SunucuBildirimTercihleri> build() async {
    final uid = ref.watch(authProvider).valueOrNull?.id;
    if (uid == null) return (ortakHareketi: true, donemOzeti: true);
    final s = SupabaseService.instance;
    final sonuc = await Future.wait([
      s.getPartnerActivityPush(uid),
      s.getWeeklySummaryPush(uid),
    ]);
    return (ortakHareketi: sonuc[0], donemOzeti: sonuc[1]);
  }

  /// İyimser yazma: değer anında değişir, sunucu hatasında eskiye döner ve
  /// hata çağırana fırlatılır (ekran mesajı gösterir).
  Future<void> ayarla({bool? ortakHareketi, bool? donemOzeti}) async {
    final uid = ref.read(authProvider).valueOrNull?.id;
    if (uid == null) return;
    final onceki =
        state.valueOrNull ?? (ortakHareketi: true, donemOzeti: true);
    final yeni = (
      ortakHareketi: ortakHareketi ?? onceki.ortakHareketi,
      donemOzeti: donemOzeti ?? onceki.donemOzeti,
    );
    state = AsyncData(yeni);
    final s = SupabaseService.instance;
    try {
      if (ortakHareketi != null && ortakHareketi != onceki.ortakHareketi) {
        await s.setPartnerActivityPush(uid, ortakHareketi);
      }
      if (donemOzeti != null && donemOzeti != onceki.donemOzeti) {
        await s.setWeeklySummaryPush(uid, donemOzeti);
      }
    } catch (_) {
      state = AsyncData(onceki);
      rethrow;
    }
  }
}

final sunucuBildirimTercihleriProvider = AsyncNotifierProvider<
    SunucuBildirimTercihleriNotifier,
    SunucuBildirimTercihleri>(SunucuBildirimTercihleriNotifier.new);

/// Ekrandaki seçim. Sunucu tercihleri okunana kadar `AsyncLoading` —
/// kart yanlış bir ön ayarı bir an seçili göstermesin.
final bildirimOnAyarProvider = Provider<AsyncValue<BildirimOnAyar?>>((ref) {
  final sunucu = ref.watch(sunucuBildirimTercihleriProvider);
  final sinyal = ref.watch(signalNotificationsProvider);
  final sinyalOnAyar = ref.watch(sinyalOnAyarProvider);
  return sunucu.whenData((s) => bildirimOnAyarEslesen((
        sinyal: sinyal,
        sinyalOnAyar: sinyalOnAyar,
        ortakHareketi: s.ortakHareketi,
        donemOzeti: s.donemOzeti,
      )));
});

/// Ön ayarın sinyal kısmı ücretsiz günlük sınırı aşıyor mu (Premium
/// kapısı)? Sinyal Ayarları'ndaki kartla AYNI kural: sınırı aşan sıklık
/// Premium ister, hiçbir şey yazılmaz.
bool bildirimOnAyariPremiumIster(BildirimOnAyar a, int slot) {
  final s = bildirimOnAyarTanimi(a).sinyalOnAyar;
  if (s == null) return false;
  return sinyalOnAyarTanimi(s, AssetType.hisse).siklik.gunlukEnFazla > slot;
}

/// Ön ayarı VAR OLAN notifier/servisler üzerinden yazar.
///
/// Sıra: önce sunucu tercihleri (hata olursa hiçbir yerel değer
/// değişmemiş olur ve çağıran mesaj gösterir), sonra sinyal ana anahtarı
/// + sunucu eşitlemesi, en son sinyal ön ayarı (yalnız açılırken).
Future<void> bildirimOnAyariUygula(WidgetRef ref, BildirimOnAyar a) async {
  final t = bildirimOnAyarTanimi(a);
  await ref.read(sunucuBildirimTercihleriProvider.notifier).ayarla(
        ortakHareketi: t.ortakHareketi,
        donemOzeti: t.donemOzeti,
      );
  if (ref.read(signalNotificationsProvider) != t.sinyal) {
    await ref.read(signalNotificationsProvider.notifier).set(t.sinyal);
    await syncSignalsEnabledPreference(ref);
  }
  final s = t.sinyalOnAyar;
  if (s != null && ref.read(sinyalOnAyarProvider) != s) {
    await sinyalOnAyariUygula(ref, s);
  }
}
