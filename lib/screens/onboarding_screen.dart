import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/preferences_provider.dart';
import '../services/analytics_service.dart';
import '../services/supabase_service.dart';
import '../theme/sandik.dart';
import '../widgets/tour_anchor.dart';
import 'main_navigation_screen.dart';

/// Yeni kullanıcılara gösterilen interaktif tanıtım.
///
/// Gösterim politikası: yalnızca **hesap başına bir kez** — yeni kayıt olan
/// kullanıcı ilk kez giriş yaptığında gösterilir, sonraki giriş/açılışlarda
/// asla. Karar Supabase profil `onboarding_completed` alanı üzerindendir.
///
/// - Aynı hesapla farklı cihazlarda tekrar gösterilmez (server-truth).
/// - Silinip tekrar yüklenen aynı hesapta gösterilmez.
/// - Yeni kayıt olan başka bir hesap kendi ilk açılışında görür.
///
/// Ek olarak per-user bir cihaz cache'i tutulur (`onboarding_seen_${userId}`)
/// → server yazımı fail etse bile aynı cihazda tekrar açılmaz. Bu, "sürekli
/// gösteriliyor" bug'ını (network hatasında infinite loop) engeller.
///
/// ## Nasıl gösterilir (2026-09-14)
/// Bu widget ayrı bir ekran DEĞİLDİR: gerçek [MainNavigationScreen]'i kurar
/// ve [OnboardingTourHost] üzerinden bir tur katmanı ([_TurKatmani]) açar.
/// Katman ekranı karartır, o adımın hedefini oyukla açıkta bırakır;
/// kullanıcı oyuğun içindeki GERÇEK tuşa dokunur. Böylece tanıtımdaki
/// hiçbir şey uygulamadan farklı görünemez — çünkü uygulamanın kendisidir.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final String userId;

  const OnboardingScreen({super.key, required this.onComplete, required this.userId});

  static String _deviceCacheKey(String userId) => 'onboarding_seen_$userId';

  /// Kullanıcı için onboarding daha önce tamamlanmış mı?
  /// Sıra: (1) per-user cihaz cache, (2) Supabase profil flag.
  /// Sorgu başarısız olursa "gösterildi" say — agresif yeniden gösterme
  /// önlenir, kullanıcı kayıt akışını rahatsız eden loop'a girmez.
  static Future<bool> isCompleted(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_deviceCacheKey(userId)) == true) return true;
      final profile = await SupabaseService.instance.getProfile(userId);
      final serverDone = profile?.onboardingCompleted ?? false;
      if (serverDone) {
        await prefs.setBool(_deviceCacheKey(userId), true);
        return true;
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  /// Onboarding'i tamamla — server flag'ini yaz + per-user cihaz cache'i set
  /// et. Cache önce yazılır; server yazımı başarısız olsa bile aynı cihazda
  /// tekrar açılmaz.
  ///
  /// Debug reinstall / cihaz değişikliği senaryolarında SharedPreferences
  /// silinir ve `isCompleted` server'a bakar → bu yüzden server yazımı
  /// **kritik** ve retry'lı yapılır. update fail ederse (satır yoksa) upsert
  /// fallback'i devreye girer.
  static Future<void> markCompleted(String userId) async {
    // Cache — 3 denemeye kadar tekrar.
    Object? cacheError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_deviceCacheKey(userId), true);
        cacheError = null;
        break;
      } catch (e) {
        cacheError = e;
      }
    }
    if (cacheError != null) {
      debugPrint(
          'OnboardingScreen.markCompleted cache write failed: $cacheError');
    }

    // Server yazımı — reinstall/cihaz değişikliği sonrası true dönebilmek
    // için garanti altına alınmalı. 3 kez retry + exponential backoff.
    Object? serverError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await SupabaseService.instance.markOnboardingCompleted(userId);
        serverError = null;
        break;
      } catch (e) {
        serverError = e;
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    if (serverError != null) {
      debugPrint(
          'OnboardingScreen.markCompleted server write failed: $serverError');
    }
  }

  /// Turu var olan uygulama ekranının üstünde başlatır.
  ///
  /// Katman [OnboardingTourHost] içinde açılır; tur zaten açıksa ikinci kez
  /// açılmaz. [onBitti] turun nasıl kapandığını söyler: `true` sonuna kadar
  /// gezildi, `false` "Atla" ile bırakıldı.
  static void baslatTur({
    required void Function(bool tamamlandi) onBitti,
    bool kisa = false,
  }) {
    _Tur.baslat(onBitti: onBitti, kisa: kisa);
  }

  /// Tur açıksa KAPATIR — yalnızca entegrasyon testi için.
  ///
  /// `integration_test/smoke_test.dart` gerçek uygulamayı açıyor ve tur
  /// katmanı `OnboardingTourHost` içinde Navigator'ı SARIYOR, yani her
  /// rotanın üstünde duruyor ve dokunmaları yutuyor. Tohum kullanıcısı
  /// `onboarding_completed = true` taşısa bile tur başka bir yoldan
  /// açılırsa (sürüm notu, "yenilikler" akışı) duman testi sessizce
  /// bloklanır — CI'da tam olarak bu yaşandı (2026-09-15).
  ///
  /// `onBitti` ÇAĞRILMAZ: bu bir kullanıcı eylemi değil, test kurulumu.
  /// Çağırmak `markCompleted` yazımını tetikler ve testin ölçtüğü akışı
  /// kirletirdi.
  @visibleForTesting
  static void turuKapatTestIcin() {
    _Tur.oturum.value = null;
  }

  /// Ayarlar → "Tanıtım turunu yeniden izle".
  ///
  /// Tur gerçek sekmelerin üstünde çalıştığı için önce köke dönülür; aksi
  /// halde Ayarlar rotası hedefleri örter ve ilk adım "alt menü" bulunamaz.
  static void yenidenBaslat(BuildContext context) {
    final nav = Navigator.of(context, rootNavigator: true);
    nav.popUntil((r) => r.isFirst);
    // Rota kapanışı bir kare sürer; hedefler o kareden sonra ölçülebilir.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _Tur.baslat(onBitti: (_) {});
    });
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _acildi = false;

  @override
  void initState() {
    super.initState();
    // Overlay'e girmek için ağaç kurulmuş olmalı; ilk kareden sonra.
    SchedulerBinding.instance.addPostFrameCallback((_) => _turuAc());
  }

  void _turuAc() {
    if (!mounted || _acildi) return;
    _acildi = true;
    // İlk açılış KISA tur (bkz. `_kisaAdimlar`); tam tur Ayarlar'dan.
    _Tur.baslat(
      kisa: true,
      onBitti: (tamamlandi) async {
        await OnboardingScreen.markCompleted(widget.userId);
        if (mounted) widget.onComplete();
      },
    );
  }

  @override
  Widget build(BuildContext context) => const MainNavigationScreen();
}

// ─── Adımlar ─────────────────────────────────────────────────────────────────
//
// Tanıtım "ekranı ANLAT" değil "ekranı DENET" ilkesiyle kuruldu ve gerçek
// ekranın üstünde çalışır (2026-09-14, kullanıcı geri bildirimi: kopya
// yüzeyler "font ve bileşenler yine farklı duruyor" — haklıydı; kopyayı
// birebir tutmak imkânsız, uygulamanın kendisini göstermek bedava).
//
// Her adım bir hedefe ([TourTarget]) spot düşürür; hedef gerçek ekranın
// gerçek widget'ıdır, oyuğun içinde dokunulabilir kalır. Görevli adımlar
// uygulamanın GERÇEK durumundan tamamlanmayı okur: göz tuşu → gizleme
// tercihi, sekme tuşu → aktif sekme, + tuşu → Varlık Ekle ekranı ağaçta.
//
// Görev zorunlu değil: "Devam" her zaman açık; görevin gerektirdiği geçişi
// (sekme değiştir, ekranı aç) o zaman tur kendisi yapar. Zorlamak,
// tanıtımı bir an önce geçmek isteyen kullanıcıyı cezalandırırdı.

class _Adim {
  const _Adim({
    required this.id,
    required this.baslik,
    required this.govde,
    this.hedef,
    this.rozet,
    this.gorev,
    this.gorevBitti,
    this.bitti,
    this.dokunulabilir = true,
    this.otoIlerle = false,
    this.giris,
    this.devam,
    this.cikis,
  });

  final String id;
  final String baslik;
  final String govde;

  /// Spot düşürülecek gerçek öğe; null ise kart ekranın ortasında durur.
  final TourTarget? hedef;

  /// "BİZE ÖZEL" gibi üst etiket — başka uygulamalarda olmayanı işaretler.
  final String? rozet;

  /// Görev çağrısı ("Göz simgesine dokun") ve tamamlanınca onayı.
  final String? gorev;
  final String? gorevBitti;

  /// Görev tamamlandı mı? Uygulamanın gerçek durumundan okunur.
  final bool Function(WidgetRef ref)? bitti;

  /// Oyuk dokunuşa açık mı? Kapalıysa hedef yalnızca GÖSTERİLİR. Dokunuşu
  /// bir sheet/rota açan (mikrofon, davet kodu üret) hedeflerde kapalı:
  /// açılan yüzey karartmanın ALTINDA kalır ve kullanıcı kilitlenmiş sanır.
  final bool dokunulabilir;

  /// Görev bitince kısa bir onaydan sonra kendiliğinden ilerle. Sekme
  /// geçişleri için: kullanıcı sekmeye dokundu, yeni ekran açıldı — bir de
  /// "Devam"a basmasını istemek gereksiz.
  final bool otoIlerle;

  /// Adıma girerken gereken ön koşulu kur (doğru sekmede ol, ekran açık
  /// olsun). Kullanıcı tur sırasında başka yere gittiyse ya da "Geri"
  /// dediyse burası yolu düzeltir.
  final void Function(WidgetRef ref)? giris;

  /// Görev yapılmadan "Devam"a basıldığında görevi turun kendisi yapar.
  final void Function(WidgetRef ref)? devam;

  /// Adımdan çıkarken (ileri ya da geri) temizlik — açılan ekranı kapat.
  final void Function(WidgetRef ref)? cikis;
}

/// Gerçek alt menüde sekmeye geç; `+` için Varlık Ekle'yi aç.
void _sekmeyeGec(int i) => MainNavigationScreen.sekmeIstegi.value = i;

bool _sekmede(int i) => MainNavigationScreen.aktifSekme.value == i;

void _varlikEkleAc() {
  if (!TourTargets.mounted(TourTarget.hizliGiris)) _sekmeyeGec(2);
}

/// Varlık Ekle'yi yalnızca EN ÜSTTEKİ rota oysa kapatır.
///
/// Körlemesine `pop` tehlikeli: ekran zaten kapanmaktayken ikinci çağrı
/// alttaki kök rotayı (ana ekranı) kapatmaya kalkar — Android'de "çıkmak
/// istiyor musun" diyaloğu, en kötüsü uygulama kapanması.
void _varlikEkleKapat() {
  final c = TourTargets.context(TourTarget.hizliGiris);
  if (c == null) return;
  if (ModalRoute.of(c)?.isCurrent != true) return;
  Navigator.of(c).pop();
}

/// Turun tamamı.
///
/// Kapalı bayrakların özellikleri ANLATILMAZ; ekranda olmayan bir hedefe
/// spot düşürülemez zaten — hedefi bulunamayan adım kendiliğinden atlanır
/// (bkz. [_TurKatmaniState._tik]).
List<_Adim> _adimlariKur() {
  // Vadeli mevduat 2026-09-14'te kaldırıldı; tür listesi artık sabit metin.
  return [
    const _Adim(
      id: 'karsilama',
      baslik: 'Sandığına hoş geldin',
      govde: 'Hisse, fon, döviz, altın ve emtia — hepsi tek toplamda, tek '
          'para biriminde. Fiyatlar arka planda kendiliğinden güncellenir.\n\n'
          'Uygulamayı birlikte gezelim: her adımda gerçek ekranın üstünde '
          'tek bir tuş açık kalır. Dokun, dene.',
    ),
    const _Adim(
      id: 'alt_menu',
      hedef: TourTarget.altMenu,
      baslik: 'Beş tuş, tüm uygulama',
      govde: 'Ana · Portföy · + · Performans · Profil. Ortadaki büyük tuş '
          'varlık ekler; en sık yapacağın iş bu.',
      dokunulabilir: false,
    ),
    _Adim(
      id: 'hero',
      hedef: TourTarget.heroKart,
      baslik: 'Toplam net varlığın',
      govde: 'Tüm varlıkların tek toplamda; altındaki satır bugün ne kadar '
          'kazandığını ya da kaybettiğini söyler. Ortağın varsa kartı '
          'sağa-sola kaydır: sıradaki kişinin kartı yandan gelir, alttaki '
          'noktalar kimde olduğunu gösterir. Başlıktaki çip de aynı işi '
          'yapar; listede herkesin toplamı yazar. İlk varlığını '
          'eklediğinde burası dolmaya başlar.',
      giris: (_) => _sekmeyeGec(0),
      dokunulabilir: false,
    ),
    _Adim(
      id: 'gizle',
      hedef: TourTarget.gizleTusu,
      baslik: 'Tutarları gizle',
      govde: 'Otobüste ya da omzunun üstünden bakan biri varken tek dokunuş '
          'yeter. Tekrar dokununca açılır.',
      gorev: 'Göz simgesine dokun',
      gorevBitti: 'Tutarlar gizlendi',
      bitti: (ref) => ref.read(balanceHiddenProvider),
      giris: (_) => _sekmeyeGec(0),
    ),
    const _Adim(
      id: 'yenile',
      hedef: TourTarget.yenileTusu,
      baslik: 'Fiyatları yenile',
      govde: 'Fiyatlar zaten arka planda güncelleniyor; bu tuş "şimdi çek" '
          'demek. Ekranı aşağı çekerek de yapabilirsin.',
    ),
    // 1.2.0'da eklendi. Tur, uygulamanın GÜNCEL hâlini anlatmalı: yeni
    // kullanıcı yalnızca eski sürümde var olan özellikleri öğrenip en
    // yenisini kaçırmamalı (bkz. `config/surum_notlari.dart` — `onemli`
    // işaretli sürümler tura girmeye adaydır).
    _Adim(
      id: 'bugun',
      hedef: TourTarget.bugunKarti,
      baslik: 'Bugün ne oldu?',
      govde: 'Solda tarih, yanında günün hareketi — sadece piyasa etkisi, '
          'yatırdığın para sayılmaz. Altındaki satırlar: enflasyona göre '
          'durumun, geçen hafta, hedefine kalan ve artıdaki varlıkların; en '
          'altta yaklaşan tarih. Her satırın altında ne anlama geldiği '
          'yazar; dokununca ayrıntı açılır. Ortağına ya da Birlikte\'ye '
          'geçince kart o defterin gününü anlatır, başında kimin olduğu '
          'yazar.',
      rozet: 'YENİ',
      giris: (_) => _sekmeyeGec(0),
      dokunulabilir: false,
    ),
    _Adim(
      id: 'piyasa',
      hedef: TourTarget.piyasaSeridi,
      baslik: 'Piyasa bir bakışta',
      govde: 'Dolar, euro, gram altın ve BIST 100 günlük değişimiyle en '
          'üstte. Portföyüne bakmadan önce piyasanın nerede olduğunu gör.',
      rozet: 'YENİ',
      giris: (_) => _sekmeyeGec(0),
      dokunulabilir: false,
    ),
    _Adim(
      id: 'bildirimler',
      hedef: TourTarget.bildirimCani,
      rozet: 'YENİ',
      baslik: 'Bildirim merkezi',
      govde: 'Teknik sinyaller ve tetiklenen fiyat alarmların burada '
          'toplanır; üstteki "Alarmlarım" tüm alarmlarını listeler. Bir '
          'varlığın ekranındaki zilden fiyat alarmı '
          'kurabilirsin: hedeflediğin fiyata gelince haber verir, '
          'uygulama kapalıyken de çalışır.',
      giris: (_) => _sekmeyeGec(0),
      dokunulabilir: false,
    ),
    _Adim(
      id: 'sekme_portfoy',
      hedef: TourTarget.sekmePortfoy,
      baslik: 'Portföy sekmesi',
      govde: 'Varlıklarının listesi ve dağılım halkası burada. Bir varlığa '
          'dokununca detayına inersin.',
      gorev: 'Portföy sekmesine dokun',
      gorevBitti: 'Portföy açıldı',
      bitti: (_) => _sekmede(1),
      otoIlerle: true,
      devam: (_) => _sekmeyeGec(1),
    ),
    _Adim(
      id: 'takip',
      hedef: TourTarget.govdeSekmeleri,
      rozet: 'BİZE ÖZEL',
      baslik: 'Takip listesi',
      govde: 'Sahip OLMADIĞIN varlıkları da izleyebilirsin. Almayı '
          'düşündüğün hisseyi listeye at, fiyat alarmı kur; portföyünün '
          'toplamına karışmaz.',
      giris: (_) => _sekmeyeGec(1),
    ),
    _Adim(
      id: 'ekle',
      hedef: TourTarget.sekmeEkle,
      baslik: 'Varlık ekle',
      govde: 'Hisse mi, fon mu, altın mı? Tür seçtiğinde form ona göre '
          'değişir — altında gram, hissede adet sorulur.',
      gorev: '+ tuşuna dokun',
      gorevBitti: 'Varlık Ekle açıldı',
      bitti: (_) => TourTargets.mounted(TourTarget.hizliGiris),
      otoIlerle: true,
      devam: (_) => _varlikEkleAc(),
    ),
    _Adim(
      id: 'hizli_giris',
      hedef: TourTarget.hizliGiris,
      rozet: 'BİZE ÖZEL',
      baslik: 'Cümleyle ekle',
      govde: 'Mikrofon Hızlı Giriş\'i açar: "10 gram altın 4500 lira" ya da '
          '"GARAN 500 adet" yazman (veya söylemen) yeter. Her satır ayrı bir '
          'varlık olur; fiyat yazmazsan güncel fiyat kendiliğinden çekilir.',
      giris: (_) => _varlikEkleAc(),
      dokunulabilir: false,
    ),
    _Adim(
      id: 'toplu',
      hedef: TourTarget.topluEkle,
      baslik: 'Toplu ekle',
      govde: 'Birden çok varlığı sepete atıp tek onayda kaydet; CSV '
          'yapıştırarak da içe aktarabilirsin. Portföyünü ilk kez kurarken '
          'en hızlı yol bu.',
      giris: (_) => _varlikEkleAc(),
      dokunulabilir: false,
      cikis: (_) => _varlikEkleKapat(),
    ),
    _Adim(
      id: 'sekme_performans',
      hedef: TourTarget.sekmePerformans,
      baslik: 'Performans sekmesi',
      govde: 'Grafikler ve kâr/zarar dökümü. Gün içinden bir yıla kadar her '
          'dönemi görebilirsin. Özet üç başlıkta: BU DÖNEM, VARLIKLAR ve '
          'istersen açtığın DERİNLİK.',
      gorev: 'Performans sekmesine dokun',
      gorevBitti: 'Performans açıldı',
      bitti: (_) => _sekmede(3),
      otoIlerle: true,
      giris: (_) => _varlikEkleKapat(),
      devam: (_) => _sekmeyeGec(3),
    ),
    _Adim(
      id: 'donem',
      hedef: TourTarget.donemSecici,
      baslik: 'Dönem seç',
      govde: 'GÜNLÜK gün içini saat saat çizer; 1H / 1A / 6A / 1Y daha geniş '
          'pencereler. Grafiği iki parmakla yakınlaştırabilir, bir noktaya '
          'basılı tutarak o anın değerini okuyabilirsin.',
      // 2026-09-15: bu adımın görevi kaldırıldı. Eski ölçüt "Gerçek /
      // Simülasyon anahtarı belirdi mi" idi; o anahtar artık kapsam
      // panelinin içinde ve panel kapalıyken de ağaçta duruyor, yani
      // dönem değişimini ondan okuyamıyoruz. Ölçemediğimiz bir görevi
      // "tamamlandı" diye göstermektense görevsiz anlatım dürüst.
      giris: (_) => _sekmeyeGec(3),
    ),
    _Adim(
      id: 'kapsam',
      hedef: TourTarget.kapsamSecici,
      rozet: 'BİZE ÖZEL',
      baslik: 'Kapsam ve mod',
      govde: 'Bu çip ne gördüğünü yazar: hangi varlık türü ve hangi mod; '
          'dokununca ikisi de açılır. Kimin portföyü olduğunu başlıktaki '
          'kişi çipi seçer.\n\nGerçek mod dönem '
          'içindeki her alım ve satımla gerçek geçmişini çizer; Simülasyon '
          '"bugünkü portföyümü baştan elimde tutsaydım ne olurdu?" sorusunu '
          'yanıtlar.',
      giris: (_) => _sekmeyeGec(3),
    ),
    _Adim(
      id: 'sekme_profil',
      hedef: TourTarget.sekmeProfil,
      baslik: 'Profil sekmesi',
      govde: 'Ortaklık, bildirimler, sinyal ayarları, fiyat alarmları, tema '
          've yasal belgeler burada.',
      gorev: 'Profil sekmesine dokun',
      gorevBitti: 'Profil açıldı',
      bitti: (_) => _sekmede(4),
      otoIlerle: true,
      devam: (_) => _sekmeyeGec(4),
    ),
    _Adim(
      id: 'ortaklik',
      hedef: TourTarget.davetKodu,
      rozet: 'BİZE ÖZEL',
      baslik: 'Eşinle tek portföy',
      govde: 'Kodunu eşine gönder ya da onunkini gir. Karşı taraf '
          'onayladığında portföyleriniz tek ekranda birleşir; "Birlikte" '
          'herkesin toplamı, "Ben" yalnız senin. Birden çok ortağın olabilir; '
          'ana ekranda kartı kaydırarak aralarında geçersin. İstediğiniz an '
          'ayrılırsınız.',
      giris: (_) => _sekmeyeGec(4),
      dokunulabilir: false,
    ),
    _Adim(
      id: 'ayarlar',
      hedef: TourTarget.ayarlar,
      baslik: 'Ayarlar',
      govde: 'Bildirimler, sinyal ayarları, günlük brifingin saati (sabah / '
          'akşam), fiyat alarmları, tema, sessiz saatler ve yasal belgeler. '
          'Bu turu da buradan yeniden izleyebilirsin.',
      giris: (_) => _sekmeyeGec(4),
      dokunulabilir: false,
    ),
    _Adim(
      id: 'hazir',
      hedef: TourTarget.sekmeEkle,
      baslik: 'Hazırsın',
      // "Her kayıt geri alınabilir" gibi bir söz VERİLMEZ: uygulamada geri
      // alma yok, silme kalıcıdır. Tutulamayan söz, tanıtıma olan güveni bozar.
      govde: '+ tuşuna dokun ve ilk varlığını ekle; gerisi kendiliğinden '
          'gelir. Yanlış girdiğin bir şeyi Portföy\'deki kartı kaydırarak '
          'düzeltebilir ya da silebilirsin.',
      gorev: 'İlk varlığını eklemek için + tuşuna dokun',
      gorevBitti: 'Varlık Ekle açıldı',
      bitti: (_) => TourTargets.mounted(TourTarget.hizliGiris),
      otoIlerle: true,
      giris: (_) => _sekmeyeGec(0),
    ),
  ];
}

/// İLK AÇILIŞ turu — beş adım (2026-09-20).
///
/// Tam tur 19 adım ve yeni kullanıcının ilk on dakikasını yiyordu; ölçü
/// "kaç özellik anlattık" değil "ilk varlık ne kadar çabuk girildi". Bu tur
/// yalnızca o yola çıkarır: toplam → bugün kartı → + tuşu → ekstre yapıştır.
/// Kalan her şey Ayarlar › "Tanıtım turunu yeniden izle" ile tam tur olarak
/// açılır ([OnboardingScreen.yenidenBaslat]) — uygulamanın güncel hâlini
/// anlatma sorumluluğu (sürüm notu kuralı) tam turda kalır.
///
/// Son adım Varlık Ekle'yi AÇIK bırakır: "Sandığımı Aç" dendiğinde kullanıcı
/// zaten yapıştırma tuşunun önündedir; tam turdaki gibi kapatıp "+ tuşuna
/// dokun" demek bir adım geri gitmek olurdu.
List<_Adim> _kisaAdimlar() {
  final tam = {for (final a in _adimlariKur()) a.id: a};
  return [
    const _Adim(
      id: 'karsilama',
      baslik: 'Sandığına hoş geldin',
      govde: 'Hisse, fon, döviz, altın — hepsi tek toplamda. Bir dakikada '
          'ilk varlığını girelim; gerisini uygulama kendi anlatır.',
    ),
    tam['hero']!,
    tam['bugun']!,
    tam['ekle']!,
    _Adim(
      id: 'toplu_son',
      hedef: TourTarget.topluEkle,
      baslik: 'Hazırsın',
      govde: 'En hızlı yol: aracı kurum ekstreni kopyala, "Toplu ekle" › '
          'yapıştır; her satır bir varlık olur. Tek tek girmek istersen tür '
          'seçmen yeter, fiyat kendiliğinden gelir.',
      giris: (_) => _varlikEkleAc(),
      dokunulabilir: false,
    ),
  ];
}

// ─── Tur denetleyicisi ───────────────────────────────────────────────────────

/// Açık tur oturumu — adımlar ve kapanış geri çağrısı.
class _Oturum {
  _Oturum({required this.adimlar, required this.onBitti});

  final List<_Adim> adimlar;
  final void Function(bool tamamlandi) onBitti;
}

/// Tek tur oturumu; [OnboardingTourHost] bunu dinler.
abstract final class _Tur {
  static final oturum = ValueNotifier<_Oturum?>(null);

  static bool get aktif => oturum.value != null;

  static void baslat({
    required void Function(bool tamamlandi) onBitti,
    bool kisa = false,
  }) {
    if (aktif) return;
    oturum.value = _Oturum(
      adimlar: kisa ? _kisaAdimlar() : _adimlariKur(),
      onBitti: onBitti,
    );
    AnalyticsService.instance.logOnboardingStep(0);
  }

  static void kapat(_Oturum o, bool tamamlandi) {
    if (oturum.value != o) return;
    oturum.value = null;
    o.onBitti(tamamlandi);
  }
}

/// Tur katmanının ev sahibi — `MaterialApp.builder` içinde Navigator'ı sarar.
///
/// ## Neden Overlay değil
/// İlk sürüm katmanı kök `Overlay`'e ekliyordu. Navigator her yeni rotayı
/// Overlay'in EN ÜSTÜNE koyar: tur "+ tuşuna dokun" dediğinde açılan
/// Varlık Ekle ekranı turun üstüne biniyor, karartma ve kart görünmez
/// oluyordu. Navigator'ın kendisini saran bir katman ise her rotanın
/// üstünde kalır; açılan/kapanan hiçbir ekran sırayı değiştiremez.
class OnboardingTourHost extends StatelessWidget {
  const OnboardingTourHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_Oturum?>(
      valueListenable: _Tur.oturum,
      builder: (context, o, altAgac) => Stack(
        fit: StackFit.expand,
        children: [
          altAgac!,
          if (o != null)
            Consumer(
              builder: (context, ref, _) => _TurKatmani(
                key: ObjectKey(o),
                ref: ref,
                adimlar: o.adimlar,
                onBitti: (tamamlandi) => _Tur.kapat(o, tamamlandi),
              ),
            ),
        ],
      ),
      child: child,
    );
  }
}

/// HIG'in en küçük dokunma hedefi: 44×44pt (Human Interface Guidelines →
/// Controls). Boşluk ölçeğine ait bir sayı DEĞİL — Apple'ın sabiti; bu
/// yüzden `SandikSpace` içinden seçilmez.
const double _higHedef = 44;

/// Uzun süreli hareketler için ölçek — hareket dili sabitlerinin katları,
/// böylece "hareketi azalt" koruması (`SandikMotion.of`) aynen çalışır.
abstract final class _Sahne {
  /// Kartın belirişi: 480ms.
  static Duration get belir => SandikMotion.surface * 2;

  /// Nabız halkası bir turu: 1.440ms.
  static Duration get nabiz => SandikMotion.surface * 6;

  /// Görev bittikten sonra kendiliğinden ilerlemeden önceki onay süresi.
  static Duration get onay => SandikMotion.surface * 3;

  /// Hedefi bulunamayan adımın atlanmasından önce beklenen süre (1,9s):
  /// sekme geçişi + ekran kurulumu + liste kaydırması birkaç kare sürer,
  /// hemen atlamak yanlış olur; çok beklemek de kullanıcıyı boş karartmada
  /// bırakır.
  static Duration get hedefBekle => SandikMotion.surface * 8;
}

/// Karartma, oyuk, halka, kart ve üst çubuk — turun görünen katmanı.
///
/// Her karede ([_tik]) hedefin dikdörtgenini yeniden ölçer: hedef kayan bir
/// listede olabilir, sekme geçişinde solabilir, ekran dönebilir. Ölçüm
/// ucuz (bir `localToGlobal`), yeniden çizim yalnızca dikdörtgen değişince.
class _TurKatmani extends StatefulWidget {
  const _TurKatmani({
    super.key,
    required this.ref,
    required this.adimlar,
    required this.onBitti,
  });

  final WidgetRef ref;
  final List<_Adim> adimlar;
  final void Function(bool tamamlandi) onBitti;

  @override
  State<_TurKatmani> createState() => _TurKatmaniState();
}

class _TurKatmaniState extends State<_TurKatmani>
    with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tik);
  late final AnimationController _nabiz =
      AnimationController(vsync: this, duration: _Sahne.nabiz);
  late final AnimationController _belir = AnimationController(vsync: this);

  int _i = 0;
  Rect? _rect;

  /// Tamamlanan görevlerin adım kimlikleri.
  final Set<String> _tamamlanan = {};

  /// Adıma giriş anı ve (varsa) planlı otomatik ilerleme anı — ikisi de
  /// ticker zamanıyla; `Timer` kullanılmaz (katman kapanınca askıda kalır).
  Duration _girisAni = Duration.zero;
  Duration? _otoIlerleAni;
  Duration _simdi = Duration.zero;
  bool _bitti = false;

  _Adim get _adim => widget.adimlar[_i];
  bool get _son => _i == widget.adimlar.length - 1;
  bool get _gorevBitti => _tamamlanan.contains(_adim.id);

  @override
  void initState() {
    super.initState();
    _ticker.start();
    _adimaGir(0, ilk: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _belir.duration = SandikMotion.of(context, _Sahne.belir);
    // Sürekli hareket yalnızca "hareketi azalt" kapalıyken; açıkken halka
    // sabit durur (kaldırılmaz — hedef yine işaretli kalır).
    if (MediaQuery.disableAnimationsOf(context)) {
      _nabiz.stop();
    } else if (!_nabiz.isAnimating) {
      _nabiz.repeat();
    }
    if (!_belir.isAnimating && _belir.value == 0) _belir.forward();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _nabiz.dispose();
    _belir.dispose();
    super.dispose();
  }

  // ── Adım akışı ──────────────────────────────────────────────────────────

  void _adimaGir(int i, {bool ilk = false}) {
    _i = i;
    _girisAni = _simdi;
    _otoIlerleAni = null;
    _rect = null;
    if (!ilk) {
      AnalyticsService.instance.logOnboardingStep(i);
      _belir.forward(from: 0);
    }
    // Ön koşul (`giris`) BİR KARE SONRA: "Devam"ın açtığı rota daha
    // kurulmadan hedef "yok" görünür ve ön koşul aynı ekranı ikinci kez
    // açardı (ölçüldü: iki Varlık Ekle üst üste). Kaydırma ise ondan da bir
    // kare sonra — sekme geçişi önce yerleşmeli.
    final adim = _adim;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _bitti || _adim != adim) return;
      adim.giris?.call(widget.ref);
      SchedulerBinding.instance.addPostFrameCallback((_) => _hedefiGoster());
    });
  }

  void _hedefiGoster() {
    if (!mounted || _bitti) return;
    final hedef = _adim.hedef;
    if (hedef == null) return;
    final c = TourTargets.context(hedef);
    if (c == null) return;
    Scrollable.ensureVisible(
      c,
      alignment: 0.3,
      duration: SandikMotion.surfaceOf(context),
      curve: SandikMotion.enter,
    );
  }

  void _tik(Duration gecen) {
    if (_bitti) return;
    _simdi = gecen;
    final adim = _adim;

    // 1) Görev tamamlandı mı? Uygulamanın gerçek durumundan.
    if (adim.bitti != null && !_gorevBitti && adim.bitti!(widget.ref)) {
      SandikHaptic.medium.perform();
      setState(() => _tamamlanan.add(adim.id));
      if (adim.otoIlerle) _otoIlerleAni = gecen + _Sahne.onay;
    }
    if (_otoIlerleAni case final t? when gecen >= t) {
      _otoIlerleAni = null;
      _ileri();
      return;
    }

    // 2) Hedefin dikdörtgeni.
    final yeni = adim.hedef == null ? null : TourTargets.rect(adim.hedef!);
    if (adim.hedef != null && yeni == null) {
      // Hedef bekleme süresi dolunca bulunamadıysa adım atlanır: kapalı
      // bayrak, değişmiş yerleşim ya da kullanıcı ekranı kapatmış olabilir.
      // Kullanıcıyı boş bir karartmada bırakmak en kötü sonuç.
      if (gecen - _girisAni > _Sahne.hedefBekle) _ileri();
      if (_rect != null) setState(() => _rect = null);
      return;
    }
    if (!_ayni(yeni, _rect)) setState(() => _rect = yeni);
  }

  static bool _ayni(Rect? a, Rect? b) {
    if (a == null || b == null) return a == b;
    return (a.left - b.left).abs() < 0.5 &&
        (a.top - b.top).abs() < 0.5 &&
        (a.width - b.width).abs() < 0.5 &&
        (a.height - b.height).abs() < 0.5;
  }

  void _ileri() {
    if (_bitti) return;
    final adim = _adim;
    if (adim.bitti != null && !_gorevBitti) adim.devam?.call(widget.ref);
    adim.cikis?.call(widget.ref);
    if (_son) {
      _kapat(tamamlandi: true);
      return;
    }
    setState(() => _adimaGir(_i + 1));
  }

  void _geri() {
    if (_bitti || _i == 0) return;
    _adim.cikis?.call(widget.ref);
    setState(() => _adimaGir(_i - 1));
  }

  void _atla() {
    if (_bitti) return;
    AnalyticsService.instance.logOnboardingSkipped(_i);
    _kapat(tamamlandi: false);
  }

  void _kapat({required bool tamamlandi}) {
    if (_bitti) return;
    _bitti = true;
    _ticker.stop();
    if (tamamlandi) AnalyticsService.instance.logOnboardingCompleted();
    widget.onBitti(tamamlandi);
  }

  // ── Görünüm ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    final adim = _adim;
    final rect = _rect;
    // Oyuk hedeften biraz geniş: dokunma hedefi görsel kutudan büyük olabilir
    // ve kenar halkası hedefe yapışmamalı.
    final oyuk = rect?.inflate(SandikSpace.xs2);
    final mq = MediaQuery.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Karartma + blur; oyuk dışında dokunuşu YUTAR, oyukta geçirir
        // (RenderClipPath, kırpma yolunun dışını hit-test etmez).
        ClipPath(
          clipper: _OyukKirpici(oyuk),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: ColoredBox(
                // Light'ta zemin rengi karartmaz; koyu metin tonu kullanılır.
                color: context.isLight
                    ? p.text90.withValues(alpha: 0.42)
                    : p.background.withValues(alpha: 0.78),
              ),
            ),
          ),
        ),
        // Dokunuşa kapalı hedef: oyuk görünür ama altına geçirmez.
        if (oyuk != null && !adim.dokunulabilir)
          Positioned.fromRect(
            rect: oyuk,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
            ),
          ),
        if (oyuk != null) _halka(context, oyuk),
        _kart(context, mq, oyuk),
      ],
    );
  }

  /// Oyuğun çevresinde nabız gibi genişleyen halka.
  ///
  /// Görev bitince söner: ok işareti işini yaptı. Genişleme ÖLÇEKLE değil
  /// sabit payla — geniş bir hedefte (alt menünün tamamı) ölçek halkayı
  /// ekranın dışına taşırdı.
  Widget _halka(BuildContext context, Rect oyuk) {
    final p = context.c;
    if (_gorevBitti) return const SizedBox.shrink();
    final hareket = !MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _nabiz,
      builder: (context, _) {
        final t = hareket ? _nabiz.value : 0.35;
        final pay = SandikSpace.xs + SandikSpace.smd * t;
        final alfa = hareket ? (1 - t) * 0.9 : 0.9;
        return Positioned.fromRect(
          rect: oyuk.inflate(pay),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(SandikRadius.md + pay),
                border: Border.all(
                  color: p.amberFill.withValues(alpha: alfa),
                  width: 2,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Kart ────────────────────────────────────────────────────────────────
  //
  // Hedefin boş kalan tarafına yerleşir: hedef ekranın üst yarısındaysa
  // altına, alt yarısındaysa üstüne. Kalan alana sığmazsa içi kayar —
  // büyük sistem yazı tipinde kartın hedefi örtmesi ya da taşması yerine.
  Widget _kart(BuildContext context, MediaQueryData mq, Rect? oyuk) {
    final ekran = mq.size;
    final ustSinir = mq.padding.top + SandikSpace.md;
    final altSinir = ekran.height - mq.padding.bottom - SandikSpace.md;

    double? top;
    double? bottom;
    double maxYukseklik;
    if (oyuk == null) {
      top = ustSinir;
      bottom = ekran.height - altSinir;
      maxYukseklik = altSinir - ustSinir;
    } else {
      final ustAlan = oyuk.top - SandikSpace.md - ustSinir;
      final altAlan = altSinir - (oyuk.bottom + SandikSpace.md);
      final asagi = oyuk.center.dy < ekran.height / 2 || altAlan > ustAlan;
      if (asagi) {
        top = oyuk.bottom + SandikSpace.md;
        maxYukseklik = altAlan;
      } else {
        bottom = ekran.height - (oyuk.top - SandikSpace.md);
        maxYukseklik = ustAlan;
      }
    }
    // Hedef ekranın kenarındaysa boşluk çok dar olabilir; kartın en azından
    // okunabilir bir yüksekliği olsun — gerekirse hedefin üstüne biner.
    maxYukseklik = maxYukseklik.clamp(200.0, ekran.height);

    final egri = CurvedAnimation(parent: _belir, curve: SandikMotion.enter);
    return Positioned(
      left: SandikSpace.md,
      right: SandikSpace.md,
      top: top,
      bottom: bottom,
      child: Align(
        alignment: oyuk == null
            ? Alignment.center
            : (top != null ? Alignment.topCenter : Alignment.bottomCenter),
        child: FadeTransition(
          opacity: egri,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, top != null ? -0.04 : 0.04),
              end: Offset.zero,
            ).animate(egri),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxYukseklik),
              child: _AdimKarti(
                adim: _adim,
                bitti: _gorevBitti,
                sira: _i,
                toplam: widget.adimlar.length,
                onGeri: _geri,
                onIleri: _ileri,
                onAtla: _atla,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Karartmada hedefi açıkta bırakan kırpma yolu.
///
/// `RenderClipPath` yolun dışını hit-test etmez: oyuğun içine dokunuş
/// katmandan geçip alttaki GERÇEK widget'a ulaşır. Spot ışığının bütün
/// sırrı bu.
class _OyukKirpici extends CustomClipper<Path> {
  const _OyukKirpici(this.oyuk);

  final Rect? oyuk;

  @override
  Path getClip(Size size) {
    final tum = Path()..addRect(Offset.zero & size);
    if (oyuk == null) return tum;
    final delik = Path()
      ..addRRect(RRect.fromRectAndRadius(
          oyuk!, const Radius.circular(SandikRadius.md)));
    return Path.combine(PathOperation.difference, tum, delik);
  }

  @override
  bool shouldReclip(_OyukKirpici old) => old.oyuk != oyuk;
}

/// Adımın açıklama kartı: ilerleme + Atla, rozet, başlık, gövde, görev
/// şeridi, tuşlar.
///
/// İlerleme çubuğu ve "Atla" KARTIN İÇİNDE, ekranın üstünde sabit değil:
/// sabit bir üst çubuk, uygulama çubuğundaki hedeflerin (mikrofon, toplu
/// ekle) tam üstüne biniyor ve oyuğa dokunuş "Atla"ya gidiyordu. Kart
/// hedefin boş tarafına yerleştiği için hedefle asla çakışmaz.
class _AdimKarti extends StatelessWidget {
  const _AdimKarti({
    required this.adim,
    required this.bitti,
    required this.sira,
    required this.toplam,
    required this.onGeri,
    required this.onIleri,
    required this.onAtla,
  });

  final _Adim adim;
  final bool bitti;
  final int sira;
  final int toplam;
  final VoidCallback onGeri;
  final VoidCallback onIleri;
  final VoidCallback onAtla;

  bool get ilkAdim => sira == 0;
  bool get sonAdim => sira == toplam - 1;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Semantics(
      // Adım değişince ekran okuyucu yeni kartı kendiliğinden okusun.
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: p.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.lg),
          border: Border.all(color: p.hairline),
          boxShadow: [
            ...p.cardShadow,
            BoxShadow(
              color: p.amberFill.withValues(alpha: 0.12),
              blurRadius: 32,
              spreadRadius: -6,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ilerleme(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    SandikSpace.lgs, SandikSpace.xs, SandikSpace.lgs, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (adim.rozet case final r?) ...[
                      _Rozet(metin: r),
                      const SizedBox(height: SandikSpace.sm2),
                    ],
                    Text(
                      adim.baslik,
                      style: context.t.headlineSmall?.copyWith(
                        color: p.text90,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: SandikSpace.sm),
                    Text(
                      adim.govde,
                      style: context.t.bodyMedium?.copyWith(
                        color: p.text58,
                        height: 1.5,
                      ),
                    ),
                    if (adim.gorev != null) ...[
                      const SizedBox(height: SandikSpace.smd),
                      _GorevSeridi(
                        metin: bitti ? adim.gorevBitti! : adim.gorev!,
                        bitti: bitti,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SandikSpace.smd, SandikSpace.smd, SandikSpace.smd, SandikSpace.smd),
              child: Row(
                children: [
                  if (!ilkAdim)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(_higHedef, _higHedef),
                      onPressed: onGeri,
                      child: Icon(Icons.arrow_back_rounded,
                          size: 22, color: p.text58),
                    ),
                  // Expanded + Align, Spacer DEĞİL: Row esnek olmayan çocuğa
                  // sınırsız genişlik verir; 2,0× yazı tipinde tuş satırı
                  // 44px taşıyordu. Align gevşek ama SINIRLI kısıt geçirir,
                  // içerideki Flexible metin kısalır.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(_higHedef, _higHedef),
                    onPressed: onIleri,
                    child: Container(
                      height: _higHedef,
                      padding: const EdgeInsets.symmetric(
                          horizontal: SandikSpace.lgs),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: p.amberGradient,
                        borderRadius: BorderRadius.circular(SandikRadius.md),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              sonAdim
                                  ? 'Sandığımı Aç'
                                  : ilkAdim
                                      ? 'Başlayalım'
                                      : 'Devam',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.t.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: p.onAmber,
                              ),
                            ),
                          ),
                          const SizedBox(width: SandikSpace.xs2),
                          Icon(
                            sonAdim
                                ? Icons.lock_open_rounded
                                : Icons.arrow_forward_rounded,
                            size: 18,
                            color: p.onAmber,
                          ),
                        ],
                      ),
                    ),
                  ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// İlerleme bölmeleri + Atla — kartın başlığı.
extension on _AdimKarti {
  Widget _ilerleme(BuildContext context) {
    final p = context.c;
    return Padding(
      padding: const EdgeInsets.only(left: SandikSpace.lgs),
      child: SizedBox(
        height: _higHedef,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label: '${sira + 1}. adım, toplam $toplam',
                child: Row(
                  children: List.generate(toplam, (i) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: SandikSpace.xxs / 2),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(SandikRadius.sm),
                          child: SizedBox(
                            height: SandikSpace.xs,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(color: p.text20),
                                AnimatedFractionallySizedBox(
                                  duration: SandikMotion.surfaceOf(context),
                                  curve: SandikMotion.enter,
                                  alignment: Alignment.centerLeft,
                                  widthFactor: i <= sira ? 1 : 0,
                                  child: ColoredBox(
                                    color: p.amberFill,
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            CupertinoButton(
              // HIG 44pt: metin 14pt olduğu için sıfır padding'de dokunma
              // hedefi ~18pt'ye düşüyordu.
              padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md),
              minimumSize: const Size(_higHedef, _higHedef),
              onPressed: onAtla,
              child: Text(
                'Atla',
                style: context.t.titleMedium?.copyWith(
                  color: p.text58,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Dene: …" çağrısı; görev bitince onaya döner.
class _GorevSeridi extends StatelessWidget {
  const _GorevSeridi({required this.metin, required this.bitti});

  final String metin;
  final bool bitti;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return AnimatedSwitcher(
      duration: SandikMotion.stateOf(context),
      switchInCurve: SandikMotion.enter,
      switchOutCurve: SandikMotion.enter,
      child: Container(
        key: ValueKey(bitti),
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.sm2, vertical: SandikSpace.sm),
        decoration: BoxDecoration(
          color: bitti
              ? p.gain.withValues(alpha: 0.12)
              : p.amberFill.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(SandikRadius.sm),
          border: Border.all(
            color: bitti
                ? p.gain.withValues(alpha: 0.45)
                : p.amberFill.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          children: [
            Icon(
              bitti ? Icons.check_circle_rounded : Icons.touch_app_rounded,
              size: 18,
              color: bitti ? p.gain : p.amberText,
            ),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: Text(
                bitti ? metin : 'Dene: $metin',
                style: context.t.bodyMedium?.copyWith(
                  color: bitti ? p.gain : p.text90,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "BİZE ÖZEL" rozeti — yalnızca bizi ayırt eden özelliklerde; her adıma
/// konulsa hiçbir şey vurgulanmamış olurdu.
class _Rozet extends StatelessWidget {
  const _Rozet({required this.metin});

  final String metin;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.sm2, vertical: SandikSpace.xs2),
        decoration: BoxDecoration(
          // Zemin amberFill, metin onAmber — amberText bir METİN rengidir,
          // zemin olarak kullanılırsa üstündeki yazı görünmez olur.
          gradient: p.amberGradient,
          borderRadius: BorderRadius.circular(SandikRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 12, color: p.onAmber),
            const SizedBox(width: SandikSpace.xs2),
            Flexible(
              child: Text(
                metin,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelLarge?.copyWith(
                  color: p.onAmber,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
