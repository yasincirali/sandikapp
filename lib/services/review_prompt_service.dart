import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/pref_keys.dart';
import '../providers/portfolio_provider.dart';
import 'analytics_service.dart';
import 'crash_reporter.dart';
import 'remote_config_service.dart';
import 'retention_tracker.dart';

/// Kullanıcının mağaza puanı istenebilecek "mutlu anları".
///
/// Her an, kullanıcının **kendi başlattığı ve olumlu biten** bir eylemin
/// sonudur. Pasif anlar (uygulama açıldı, ana ekran yeşil) bilinçli olarak
/// listede YOK: Apple HIG "kullanıcı bir işi bitirmişken, akışını
/// bölmeden" der; Google ise "kullanıcının doğal olarak durakladığı an"
/// ister. Açılışta ya da bir grafiğin ortasında çıkan istem her iki
/// mağazanın tavsiyesine de aykırıdır ve düşük puana davetiyedir.
enum ReviewAni {
  /// Kilometre taşı kutlaması KAPANDIKTAN sonra. Kutlama birikimi
  /// ödüllendirir (bkz. `MilestoneService`); kullanıcı o an kendini
  /// başarılı hissediyor — en güçlü aday.
  kilometreTasi,

  /// Paylaşım kartı başarıyla paylaşıldıktan ve sayfa kapandıktan sonra.
  /// Kullanıcı gördüğünü başkasına göstermek istediyse memnun demektir.
  paylasim,

  /// Toplu ekleme (CSV / sepet) hatasız bittikten sonra. Aracı kurumdan
  /// taşınan bir portföyün tek seferde girmesi rahatlama anıdır.
  topluEkleme,

  // ── 2026-10-04 genişletmesi (kullanıcı kararı: "daha fazla senaryoda
  // çıkarmalıyız"). İlk üç an nadirdi: kilometre taşı ayda bir, paylaşım
  // ve toplu ekleme çoğu kullanıcıda hiç yaşanmıyor — istem pratikte
  // görünmüyordu. Aşağıdakiler de kullanıcının KENDİ başlattığı ve olumlu
  // biten eylemlerdir; pasif an (açılış, ekran görüntüleme) yine yok.

  /// Tekli varlık ekleme başarıyla bitip ekran kapandıktan sonra. En sık
  /// yaşanan "iş bitti" anı; sıklık kapıları (erteleme, tavan) aşırıya
  /// kaçmasını önler.
  varlikEklendi,

  /// Portföy hedefi konduktan sonra. Hedef koyan kullanıcı uygulamayla
  /// uzun vadeli plan yapıyor demektir.
  hedefKondu,

  /// Fiyat alarmı başarıyla kurulduktan sonra.
  alarmKuruldu,

  /// Temettü kaydedildikten sonra — eline para geçmiş kullanıcı.
  temettuKaydi,

  /// Yıllık özet ("sandık Özeti") kapatıldıktan sonra, yıl artıdaysa.
  ozetGoruldu,
}

/// Kullanıcının istemle geçmişte ne yaptığı — karar fonksiyonunun girdisi.
@immutable
class ReviewDurumu {
  const ReviewDurumu({
    this.tamamlandi = false,
    this.sonSorulmaMs,
    this.sorulmaSayisi = 0,
    this.geriBildirimMs,
  });

  /// "Değerlendir" seçildi ve mağaza akışı açıldı. Bir daha sorulmaz.
  final bool tamamlandi;

  /// İstemin en son gösterildiği an (epoch ms). Hiç gösterilmediyse null.
  final int? sonSorulmaMs;

  /// Şimdiye kadar kaç kez gösterildi ("Sonra" dahil).
  final int sorulmaSayisi;

  /// "Bir sorun var" seçildi (epoch ms). Sorunu olan kullanıcıya yakın
  /// zamanda tekrar puan sormak hem kaba hem de düşük puan riski.
  final int? geriBildirimMs;

  static const bos = ReviewDurumu();
}

/// Değerlendirme istemi gösterilsin mi — **saf fonksiyon**.
///
/// Amaç yüksek puan DEĞİL, doğru anda sormaktır; yüksek puan bunun
/// sonucudur. Kurallar ve gerekçeleri:
///
/// 1. **Bir kez değerlendiren bir daha görmez.** Puan verdiği hâlde
///    yeniden sorulmak, uygulamanın kullanıcıyı tanımadığını söyler.
/// 2. **Yeni kullanıcıya sorulmaz:** kurulumdan en az [minKurulumGunu]
///    gün ve en az [minAktifGun] aktif gün. Üçüncü günde fikir oluşmamıştır;
///    ilk hafta kaybı yaşayanın puanı da uygulamaya değil piyasaya olur.
/// 3. **Portföy belirgin zarardaysa sorulmaz.** Kullanıcı o an uygulamaya
///    değil ekrandaki kırmızıya bakıyor; kırmızı ekranda istenen puan kırmızı
///    olur. Eşik [maxZararOrani]: 2026-10-04'e kadar "bir kuruş zarar"
///    bile kapıyı kapatıyordu ve düşen piyasada kullanıcıların çoğu hiç
///    görmüyordu; küçük eksi olağan dalgalanmadır, engel sayılmaz.
///    Hesaplanamıyorsa (null) engel sayılmaz — anın kendisi olumlu sinyaldir.
/// 4. **"Sonra" [ertelemeAraligi] sonra tekrar** — ama toplam [maxSorulma]
///    kezden fazla sorulmaz. Apple'ın yılda üç tavanı SİSTEM kartı içindir
///    ve onu işletim sistemi uygular; bizim ön sorumuz o kotayı harcamaz
///    (sistem kartı yalnızca "Evet" denince, bir kez istenir).
/// 5. **Sorun bildiren kullanıcıya [geriBildirimSonrasi] boyunca sorulmaz.**
///    Sorunu çözülmeden puan istemek, mağazada yazılı şikâyete dönüşür.
/// 6. **Bir kez aktif gün başına en fazla bir istem** — aynı gün iki mutlu
///    an art arda gelirse (paylaşım + toplu ekleme) ikincisi sessiz kalır;
///    kural 4 zaten erteleme aralığını kapsar, bu satır aynı günü belirtir.
bool degerlendirmeSorulsunMu({
  required ReviewAni an,
  required ReviewDurumu durum,
  required int kurulumGunu,
  required int aktifGun,
  required double? karZararOrani,
  required DateTime simdi,
}) {
  // (1) Zaten değerlendirdi.
  if (durum.tamamlandi) return false;

  // (2) Çok yeni.
  if (kurulumGunu < ReviewPromptService.minKurulumGunu) return false;
  if (aktifGun < ReviewPromptService.minAktifGun) return false;

  // (3) Kırmızı ekran.
  if (karZararOrani != null &&
      karZararOrani < -ReviewPromptService.maxZararOrani) {
    return false;
  }

  // (4) Tavan ve erteleme aralığı.
  if (durum.sorulmaSayisi >= ReviewPromptService.maxSorulma) return false;
  final son = durum.sonSorulmaMs;
  if (son != null) {
    final gecen = simdi.millisecondsSinceEpoch - son;
    if (gecen < ReviewPromptService.ertelemeAraligi.inMilliseconds) {
      return false;
    }
  }

  // (5) Yakın zamanda sorun bildirdi.
  final gb = durum.geriBildirimMs;
  if (gb != null) {
    final gecen = simdi.millisecondsSinceEpoch - gb;
    if (gecen < ReviewPromptService.geriBildirimSonrasi.inMilliseconds) {
      return false;
    }
  }

  return true;
}

/// Değerlendirme isteminin kalıcılığı ve mağaza köprüsü.
///
/// Karar [degerlendirmeSorulsunMu] içinde saf; burada yalnızca prefs
/// okuma/yazma, Remote Config bayrakları ve `in_app_review` çağrısı var.
/// Sheet'in kendisi `ReviewPromptSheet`; bu sınıf widget bilmez.
///
/// **Anahtarlar kullanıcıya ön eklenmez** (bkz. `RetentionTracker`): "bu
/// cihazda mağaza puanı istendi mi" cihaz gerçeğidir. Aynı cihazda hesap
/// değiştiren kullanıcıya yeniden sormak, mağazanın gözünde aynı kişiye
/// ikinci istemdir.
class ReviewPromptService {
  ReviewPromptService._();
  static final ReviewPromptService instance = ReviewPromptService._();

  // 2026-10-04 gevşetmesi (kullanıcı kararı: "daha kolaylaştırmalıyız").
  // Önceki değerler 3 gün / 3 aktif gün / 3 istem / 30 gün / sıfır zarar
  // toleransıydı; nadir tetikleyicilerle birleşince istem neredeyse hiç
  // görünmüyordu. İlk gün yine sorulmaz: fikir oluşmadan istenen puan
  // uygulamaya değil ilk izlenime verilir.
  static const int minKurulumGunu = 2;
  static const int minAktifGun = 2;
  static const int maxSorulma = 5;
  static const Duration ertelemeAraligi = Duration(days: 14);
  static const Duration geriBildirimSonrasi = Duration(days: 90);

  /// Toplam zarar maliyetin bu oranını aşarsa sorulmaz (0.10 = %10).
  static const double maxZararOrani = 0.10;

  /// App Store kimliği — `openStoreListing` iOS'ta bunu ister
  /// (bkz. memory `app_store_arama_sandik`).
  static const appStoreId = '6786837699';

  /// Test için saat enjeksiyonu — üretimde [DateTime.now].
  DateTime Function() now = DateTime.now;

  /// Aynı süreçte iki istem üst üste binmesin (iki tetikleyici aynı
  /// saniyede gelebilir; prefs yazımı asenkron olduğundan ikisi de
  /// "sorulmadı" okur).
  bool _gosteriliyor = false;

  Future<SharedPreferences> _p() => SharedPreferences.getInstance();

  Future<ReviewDurumu> durum() async {
    final prefs = await _p();
    return ReviewDurumu(
      tamamlandi: prefs.getBool(PrefKeys.reviewDone) ?? false,
      sonSorulmaMs: prefs.getInt(PrefKeys.reviewLastAskedMs),
      sorulmaSayisi: prefs.getInt(PrefKeys.reviewAskCount) ?? 0,
      geriBildirimMs: prefs.getInt(PrefKeys.reviewFeedbackMs),
    );
  }

  /// Bu anda istem gösterilmeli mi? Tüm kapıları (bayrak, saf karar,
  /// üst üste binme) geçerse `true` döner ve gösterimi KAYDETMEZ —
  /// kayıt [gosterildi] ile, sheet gerçekten açıldığında yapılır.
  Future<bool> sorulsunMu(ReviewAni an, PortfolioState state) async {
    if (!RemoteConfigService.instance.reviewPromptEnabled) return false;
    if (_gosteriliyor) return false;
    final d = await durum();
    final rt = RetentionTracker.instance;
    return degerlendirmeSorulsunMu(
      an: an,
      durum: d,
      kurulumGunu: await rt.daysSinceInstall(),
      aktifGun: await rt.activeDayCount(),
      // Maliyet yoksa (boş portföy, yalnız bedelsiz kalem) oran tanımsız.
      karZararOrani: state.assets.isEmpty || state.totalCost <= 0
          ? null
          : (state.totalValue - state.totalCost) / state.totalCost,
      simdi: now(),
    );
  }

  /// Ön sorumuz gösterilsin mi, yoksa doğrudan mağaza akışı mı?
  ///
  /// Google Play tasarım kılavuzu "karttan önce soru sormayın" der; Apple
  /// bu konuda sessizdir. Bayrak kapatıldığında ön soru atlanır ve
  /// [degerlendir] doğrudan çağrılır — mağaza incelemesinde sorun çıkarsa
  /// yayın beklemeden geri alınabilsin diye.
  bool get onSoruAcik => RemoteConfigService.instance.reviewPromptSoftGate;

  /// Sheet açıldı — sayaç ve zaman damgası. Açılışta yazılır: kullanıcı
  /// kapatmadan uygulama ölürse istem bir sonraki mutlu anda YİNE çıkardı
  /// ve "hep karşıma çıkıyor" hissi tam olarak kaçınmak istediğimiz şey.
  Future<void> gosterildi(ReviewAni an) async {
    _gosteriliyor = true;
    final prefs = await _p();
    await prefs.setInt(PrefKeys.reviewLastAskedMs, now().millisecondsSinceEpoch);
    await prefs.setInt(
        PrefKeys.reviewAskCount, (prefs.getInt(PrefKeys.reviewAskCount) ?? 0) + 1);
    unawaited(AnalyticsService.instance
        .logReviewPrompt(action: 'shown', moment: an.name));
  }

  /// Sheet kapandı (hangi seçenekle olursa olsun).
  void kapandi() => _gosteriliyor = false;

  Future<void> ertelendi(ReviewAni an) async {
    unawaited(AnalyticsService.instance
        .logReviewPrompt(action: 'later', moment: an.name));
  }

  Future<void> sorunBildirildi(ReviewAni an) async {
    final prefs = await _p();
    await prefs.setInt(PrefKeys.reviewFeedbackMs, now().millisecondsSinceEpoch);
    unawaited(AnalyticsService.instance
        .logReviewPrompt(action: 'feedback', moment: an.name));
  }

  /// Mağaza puan akışını açar ve "tamamlandı" işaretler.
  ///
  /// `requestReview` sonucu bildirmez: iOS/Android akışı kullanıcının
  /// gerçekten puan verip vermediğini uygulamaya söylemez, kota dolduysa
  /// hiç görünmeyebilir. Bu yüzden "tamamlandı" = "akış istendi"; daha
  /// fazlasını bilemeyiz ve bilmediğimizi tekrar sorarak telafi etmeyiz.
  /// Sistem kartı kullanılamıyorsa (Play Store yok, iOS kotası) mağaza
  /// sayfası açılır — kullanıcı "değerlendir" dedi, boş ekran bırakılmaz.
  Future<void> degerlendir(ReviewAni an, {required String source}) async {
    final prefs = await _p();
    await prefs.setBool(PrefKeys.reviewDone, true);
    unawaited(AnalyticsService.instance
        .logReviewPrompt(action: 'review', moment: an.name, source: source));
    try {
      final r = InAppReview.instance;
      if (await r.isAvailable()) {
        await r.requestReview();
      } else {
        await r.openStoreListing(appStoreId: appStoreId);
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'in-app review');
    }
  }

  /// Ayarlar'daki "sandık'ı değerlendir" satırı: kapı yok, doğrudan mağaza.
  /// Kullanıcı bilerek geliyor; onu bir daha kendiliğinden rahatsız etmeyiz.
  Future<void> magazayiAc() async {
    final prefs = await _p();
    await prefs.setBool(PrefKeys.reviewDone, true);
    unawaited(AnalyticsService.instance
        .logReviewPrompt(action: 'review', moment: 'settings', source: 'settings'));
    try {
      await InAppReview.instance.openStoreListing(appStoreId: appStoreId);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'open store listing');
    }
  }

  /// Test/geliştirme için: tüm izleri sil.
  Future<void> sifirla() async {
    final prefs = await _p();
    await prefs.remove(PrefKeys.reviewDone);
    await prefs.remove(PrefKeys.reviewLastAskedMs);
    await prefs.remove(PrefKeys.reviewAskCount);
    await prefs.remove(PrefKeys.reviewFeedbackMs);
    _gosteriliyor = false;
  }
}
