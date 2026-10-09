import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/position.dart' show aktifLotlar;
import '../providers/auth_provider.dart' show activePartnersProvider;
import '../providers/hafta_ozeti_provider.dart'
    show haftaOlagandisiSayisiProvider;
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/analytics_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../theme/sandik.dart';
import '../widgets/ilk_varlik_vitrini.dart' show IlkVarlikVitrini;
import '../widgets/seviye_anketi.dart';
import '../widgets/tour_anchor.dart';
import 'main_navigation_screen.dart';
import '../widgets/sekme_basa_don.dart';
import 'portfolio_performance_screen.dart';
import '../demo/demo_modu.dart';

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
  ///
  /// [seviyeSorusu] kısa turda yatırımcı seviyesi adımı (plan F2).
  /// Varsayılan `false`; ilk açılış giriş noktası (`_turuAc`) HER ZAMAN
  /// sorar (2026-10-05: `lock_offer_after_first_asset || seviye_anketi`
  /// idi, `seviye_anketi` kalıcı açık olunca koşul hep doğruydu). Testler
  /// iki hâli de açıkça seçer.
  static void baslatTur({
    required void Function(bool tamamlandi) onBitti,
    bool kisa = false,
    bool seviyeSorusu = false,
  }) {
    _Tur.baslat(onBitti: onBitti, kisa: kisa, seviyeSorusu: seviyeSorusu);
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
      seviyeSorusu: true,
      onBitti: (tamamlandi) async {
        // Kayıt hunisi (F11): tur KAPANDI — sonuna kadar gezildi ya da
        // atlandı. Atlama ayrıca `onboarding_skipped` ile ölçülüyor; huni
        // "kullanıcı turdan çıkıp ana ekrana ulaştı mı"yı sorar.
        unawaited(AnalyticsService.instance.logSignupStep('tour_done'));
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
    this.kosul,
    this.giris,
    this.devam,
    this.cikis,
    this.ek,
  });

  /// Gövdenin altına eklenen etkileşimli içerik (ör. seviye seçici).
  ///
  /// Tur "gerçek ekranın üstünde" ilkesiyle çalışır; kartın içinde kendi
  /// denetimi olan tek adım seviye sorusudur (F2) — anlatacağı bir ekran
  /// öğesi yok, bir tercih soruluyor. Seçim zorunlu değil: "Devam" her
  /// zaman açık, dokunulmazsa varsayılan (Orta) kalır.
  final WidgetBuilder? ek;

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

  /// Adımın anlattığı yüzey şu an çiziliyor mu? `false` → adım GÖSTERİLMEDEN
  /// geçilir, o anki dokunuşun yönünde ("Devam" ileri, "Geri" geri).
  ///
  /// Koşul, hedefi çizen ekranın KENDİ koşuluyla aynı olmalı (ör. "Bugün"
  /// kartı yalnız aktif lot varken). Karar dokunuş anında verilir, zamana
  /// bakılmaz. Eskiden hedefi gelmeyen adım 1,9 sn beklenip atlanıyordu —
  /// kullanıcı bunu "tıklamadan ilerliyor" diye gördü (2026-09-25/26).
  final bool Function(WidgetRef ref)? kosul;

  // `otoIlerle` (görev bitince 0,72 sn sonra kendiliğinden ilerle) 2026-09-26'da
  // kaldırıldı. Kullanıcı kararı: "sadece tıklayarak ilerleyebilmeli". Görev
  // tamamlanınca onay satırı görünür, tur "Devam"ı bekler.

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

/// Sekmeye geç ve listesini BAŞA kaydır — hedef listenin üstündeyse.
///
/// **Neden (2026-10-03, kullanıcı bildirimi):** "Dönem seç" ve "Kapsam ve
/// mod" metni çıkıyor ama oraya odaklanmıyordu. Performans listesi tembel;
/// sekme aşağıda bırakılmışsa (Zirve adımı da listeyi en alta indirir, oradan
/// "Geri" dönülebilir) en üstteki seçiciler sökülmüş oluyor, tur hedefi
/// bulamayıp kartı ortada gösteriyordu. Kanal sekmeye ikinci dokunuşla aynı
/// (`SekmeBasaDon`): yalnızca kaydırır, seçimlere dokunmaz.
void _sekmeyeGecBasa(int i) {
  _sekmeyeGec(i);
  SekmeBasaDon.yayinla(i);
}

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

/// Kendi defteri boş mu? Ana ekranın boşluk ölçüsüyle aynı (`aktifLotlar`).
bool _bosPortfoy(WidgetRef ref) => aktifLotlar(
        ref.read(portfolioProvider).valueOrNull?.assets ?? const [])
    .isEmpty;

/// Ana ekranda ₺0 kartı yerine vitrin mi çiziliyor? Kural tek yerde
/// (`IlkVarlikVitrini.toplamKartiYerine`), tur yalnızca sorar.
bool _vitrinKartYerine(WidgetRef ref) => IlkVarlikVitrini.toplamKartiYerine(
      bosKendi: _bosPortfoy(ref),
      ortakVar: ref.read(activePartnersProvider).isNotEmpty,
    );

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
      // Sıra Varlık Ekle çipleriyle aynı (`AssetType.eklemeSirasi`).
      govde: 'Hisse, döviz, altın, fon, kripto ve emtia; hepsi tek '
          'toplamda, tek para biriminde. Fiyatlar arka planda kendiliğinden güncellenir.\n\n'
          'Uygulamayı birlikte gezelim: her adımda gerçek ekranın üstünde '
          'tek bir tuş açık kalır. Dokun, dene.',
    ),
    const _Adim(
      id: 'alt_menu',
      hedef: TourTarget.altMenu,
      baslik: 'Beş tuş, tüm uygulama',
      // 2026-10-01: açık sekmeye yeniden dokunmak listeyi başa alır
      // (`SekmeBasaDon`) — alt menünün yeni davranışı, adımda söylenir.
      govde: 'Ana · Portföy · + · Performans · Profil. Ortadaki büyük tuş '
          'varlık ekler; en sık yapacağın iş bu. Açık sekmeye bir daha '
          'dokunursan liste en başa döner.',
      dokunulabilir: false,
    ),
    _Adim(
      id: 'hero',
      hedef: TourTarget.heroKart,
      baslik: 'Toplam net varlığın',
      govde: 'Tüm varlıkların tek toplamda; altındaki satır maliyetine göre '
          'kârını ya da zararını söyler. Ortağın varsa kartı '
          'sağa-sola kaydır: sıradaki kişinin kartı yandan gelir, alttaki '
          'noktalar kimde olduğunu gösterir. Başlıktaki çip de aynı işi '
          'yapar; listede herkesin toplamı yazar. İlk varlığını '
          'eklediğinde burası dolmaya başlar.',
      giris: (_) => _sekmeyeGec(0),
      dokunulabilir: false,
      // Vitrin ₺0 kartının yerini aldıysa anlatacak kart yok (bkz. 'vitrin').
      kosul: (ref) => !_vitrinKartYerine(ref),
    ),
    // Boş portföyde "Canlı fiyat vitrini" (2026-10-04; bayrak
    // `ilk_varlik_kolay` 2026-10-05'te kalktı). Tur metni arayüzle birlikte değişir kuralı: ₺0 kartı
    // gizlendiğinde 'hero' adımı boşluğu anlatırdı; bu adım yeni ekranı
    // anlatır. Koşul ekranın çizim koşuluyla aynı (`_EmptyPortfolioCta`).
    _Adim(
      id: 'vitrin',
      hedef: TourTarget.ilkVarlikVitrini,
      rozet: 'YENİ',
      baslik: 'Neye sahipsin?',
      govde: 'Sahip olduğun şeyin kutusuna dokun, yalnızca miktarını yaz: '
          'gram altın, dolar, euro ve çeyrek altının fiyatı kutuda canlı '
          'durur, kaydettiğin an toplamın hesaplanır. Fon ve hissede '
          'listeden seçersin. Kripto, emtia, mevduat ve BES alttaki '
          'bağlantıda; aracı kurum ekstren varsa "Ekstreden aktar" hepsini '
          'tek seferde getirir. İlk varlığından sonra burada toplam net '
          'varlığın görünür.',
      giris: (_) => _sekmeyeGec(0),
      dokunulabilir: false,
      kosul: _bosPortfoy,
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
    // Bayrak `genel_arama` açıkken aynı yuvada yenile değil büyüteç durur
    // (`home_screen`, sadeleştirme 2); tur gerçek ekranın üstünde çalıştığı
    // için metin bayrağa göre dallanır. Bayrak kapalıyken metin birebir eski.
    // Yenileme bilgisi kaybolmasın: aşağı çekme cümlesi yeni metinde de var.
    if (RemoteConfigService.instance.genelArama)
      const _Adim(
        id: 'yenile',
        hedef: TourTarget.yenileTusu,
        rozet: 'YENİ',
        baslik: 'Her şeyi ara',
        govde: 'Büyüteçle tek yerden ara: kendi varlıkların, piyasadaki '
            'hisse, fon ve altınlar, uygulamadaki yerler (fiyat alarmı, '
            'ekstreden aktar, tüm hareketler, ayarlar…). Fiyatlar arka '
            'planda güncelleniyor; hemen tazelemek için ekranı aşağı çek.',
      )
    else
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
      // 2026-10-01 "sakin pano" düzeni: satır listesi yerine üç kat.
      // 2026-10-02: enflasyon kutusu ölçüm aylarını yazar; ikinci kutu
      // (son 7 gün / artıdaki varlık) dönüşümlü — metin ikisini birden
      // vaat etmez.
      // 2026-10-04 (sadeleştirme 2, kullanıcı kararı): "piyasa etkisi" →
      // "fiyat etkisi"; Özet köprüsündeki aynı rakamla tek ad.
      // 2026-10-04 düzen H (bayrak `bugun_karti_kiyas`, 2026-10-05'te
      // kalktı): takvim yaprağı, son 7 gün, aylık özet ve olay ayak notu
      // yok.
      // 2026-10-09 benchmark düzeni (kullanıcı seçimi): hüküm kelimesi +
      // dolu renkli tutar rozeti, tam genişlik eğri, dönem çipleri,
      // oynayanlar sırası, "100 liran bugün kaç lira" kutusu, hedef satırı;
      // Getirin/TÜFE çubukları ve yüzde rozeti yok. Metin bunu anlatır.
      govde: 'Üstte gün ve seans durumu. Altında günün hükmü tek kelimeyle '
          '(Yükseldi, Geriledi, Yerinde saydı) ve yanında renkli rozette '
          'tutar: sadece fiyat etkisi, yatırdığın para sayılmaz. Eğri günün '
          'seyri, kesik çizgi gün başı seviyesi; Hafta, Ay, Yıl çipleri '
          'Özet\'in o dönemine götürür. Sonra bugün en çok oynayan '
          'varlıkların; "Paran fiyatlara yetişiyor mu?" kutusunda geçen '
          'yılki 100 liranın bugün kaç lira ettiği ve dolu çubuk; en altta '
          'hedefine kalan. Kutuya dokununca ayrıntı açılır. Ortağına ya da '
          'Birlikte\'ye geçince kart o defterin gününü anlatır.',
      rozet: 'YENİ',
      giris: (_) => _sekmeyeGec(0),
      dokunulabilir: false,
      // Ana ekran kartı yalnız aktif lot varken çizer (`home_screen.dart`).
      // İlk açılışta portföy boş: adım anlatacak kart yokken gösterilmez.
      kosul: (ref) => aktifLotlar(
              ref.read(portfolioProvider).valueOrNull?.assets ?? const [])
          .isNotEmpty,
    ),
    // Balina radarı (S10-A, 2026-10-05): şerit yalnız bayrak açık ve bu
    // hafta olağandışı hareket varken çizilir; anlatacak şerit yoksa adım
    // gösterilmez. Kısa turda yok: ilk açılışta portföy boş, radar susar.
    _Adim(
      id: 'radar',
      hedef: TourTarget.radarSeridi,
      baslik: 'Varlıklarında olağandışı bir şey var mı?',
      govde: 'Bu şerit yalnız söyleyecek bir şey olduğunda çıkar: fonuna '
          'büyük para girdiyse ya da çıktıysa, hissende hacim olağanın '
          'çok üstündeyse, kriptoda alıcılar ya da satıcılar belirgin '
          'biçimde istekliyse. Dokununca Haftanın özeti açılır; her '
          'varlığın satırında ne olduğu kısa bir etiketle yazar, '
          'ayrıntısı varlığın sayfasında. Yatırım tavsiyesi değildir.',
      rozet: 'YENİ',
      giris: (_) => _sekmeyeGec(0),
      dokunulabilir: false,
      kosul: (ref) => ref.read(haftaOlagandisiSayisiProvider) > 0,
    ),
    _Adim(
      id: 'piyasa',
      hedef: TourTarget.piyasaSeridi,
      baslik: 'Piyasa bir bakışta',
      govde: 'Dolar, euro, gram altın ve BIST 100 günlük değişimiyle en '
          'üstte. Şeride uzun basıp tut, sağa sola kaydır; bırakınca akmaya '
          'devam eder. Bir süre dokunulmazsa durur, dokununca yeniden akar. '
          'Sağ uçtaki "Ara" ile herhangi bir hisseyi, '
          'fonu, altını ya da kriptoyu ara; portföyüne eklemeden grafiğine '
          've istatistiklerine bak, istersen takibe al.',
      rozet: 'YENİ',
      giris: (_) => _sekmeyeGec(0),
      dokunulabilir: false,
    ),
    _Adim(
      id: 'islem_notu',
      hedef: TourTarget.hareketler,
      rozet: 'YENİ',
      baslik: 'İşlem notların',
      govde: 'Bir harekete dokun: o işleme not yaz ya da yazdığını oku '
          '("maaştan aldım", "hedef 400"). Notu olan işlemin tarihinin '
          "yanında küçük bir işaret durur. Notlar Portföy'de varlık kartını "
          "açınca da görünür, Tüm Hareketler'de aranır.",
      giris: (_) => _sekmeyeGec(0),
      dokunulabilir: false,
      // Hareket kabı yalnız kayıt varken çizilir (`home_screen.dart`).
      kosul: (ref) => aktifLotlar(
              ref.read(portfolioProvider).valueOrNull?.assets ?? const [])
          .isNotEmpty,
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
      // Koşul yok: zil 2026-10-04'ten beri her seviyede görünür (bayrak
      // `seviye_anketi` 2026-10-05'te kalktı, `zilGorunurProvider` ile).
    ),
    _Adim(
      id: 'sekme_portfoy',
      hedef: TourTarget.sekmePortfoy,
      baslik: 'Portföy sekmesi',
      // Tur metni arayüzle birlikte değişir (2026-09-21 kuralı): işlem
      // çubuğu (2026-10-04; bayrak `varlik_islem_cubugu` 2026-10-05'te
      // kalktı) Al/Sat/Temettü'nün yerini söyler.
      // Bayrak `portfoy_dagilim_cubugu` açıkken büyük halka yerini küçük
      // halka + lejanta bırakır (büyük halka küçüğe dokununca alt sayfada);
      // metin hangi yüzey görünüyorsa onu anlatır. Kapalıyken eski metin
      // birebir.
      // Bayrak `goz_alici` (2026-10-09): halkada dilime dokunmak o türü
      // seçer, seçili dilime ya da ortaya dokunmak büyütür.
      govde: RemoteConfigService.instance.portfoyDagilimCubugu &&
              RemoteConfigService.instance.gozAlici
          ? 'Varlıklarının listesi ve tür dağılımı burada; halkadaki bir '
              'dilime ya da yandaki türe dokununca liste o türe süzülür, '
              'halkanın ortasına dokununca büyür. Bir varlığa dokununca '
              'detayına inersin; alış, satış ve temettüyü oradaki alt '
              'çubuktan kaydedersin.'
          : RemoteConfigService.instance.portfoyDagilimCubugu
          ? 'Varlıklarının listesi ve tür dağılımı burada; yandaki bir türe '
              'dokununca liste o türe süzülür, halkaya dokununca büyür. Bir '
              'varlığa dokununca '
              'detayına inersin; alış, satış ve temettüyü oradaki alt '
              'çubuktan kaydedersin.'
          : 'Varlıklarının listesi ve dağılım halkası burada. Bir varlığa '
          'dokununca detayına inersin; alış, satış ve temettüyü oradaki '
          'alt çubuktan kaydedersin.',
      gorev: 'Portföy sekmesine dokun',
      gorevBitti: 'Portföy açıldı',
      bitti: (_) => _sekmede(1),
      devam: (_) => _sekmeyeGec(1),
    ),
    _Adim(
      id: 'takip',
      hedef: TourTarget.govdeSekmeleri,
      rozet: 'BİZE ÖZEL',
      baslik: 'Takip listesi',
      govde: 'Sahip OLMADIĞIN varlıkları da izleyebilirsin; portföyünün '
          'toplamına karışmaz. Bir satıra dokununca grafiği, dönem '
          'getirileri ve istatistikleri açılır, oradan portföyüne de '
          'eklersin. Sayaç kaç yerin kaldığını gösterir.',
      giris: (_) => _sekmeyeGec(1),
    ),
    _Adim(
      id: 'ekle',
      hedef: TourTarget.sekmeEkle,
      baslik: 'Varlık ekle',
      govde: 'Hisse mi, fon mu, altın mı, kripto mu? Tür seçtiğinde form '
          'ona göre değişir: altında gram, hissede adet sorulur. Seçim '
          'listesindeki grafik simgesi, seçmeden önce varlığa bakmanı sağlar.',
      gorev: '+ tuşuna dokun',
      gorevBitti: 'Varlık Ekle açıldı',
      bitti: (_) => TourTargets.mounted(TourTarget.hizliGiris),
      devam: (_) => _varlikEkleAc(),
    ),
    _Adim(
      id: 'kripto',
      hedef: TourTarget.turSecici,
      rozet: 'YENİ',
      baslik: 'Kripto da burada',
      // "Çiplerin sonunda" yazıyordu; 2026-09-25 sırasında Kripto Fon'dan
      // sonra, Emtia'dan önce (`AssetType.eklemeSirasi`). 2026-09-29'dan
      // beri çipler sarmalı (#29): Kripto dar ekranda Fon'la aynı satıra
      // düşmeyebilir, bu yüzden metin konum ("Fon'un yanında") söylemez.
      // 2026-10-08 (bayrak `tur_secici_izgara`): çipler yerine arama +
      // gruplu ızgara. Bayrak açıkken metin aramayı ve grubu anlatır
      // (tur metni arayüzle birlikte değişir); kapalıyken birebir eski.
      govde: RemoteConfigService.instance.turSeciciIzgara
          ? 'Üstteki aramaya sembolü ya da adı yaz (THYAO, BTC…): '
              'sonuca dokununca tür de varlık da seçilir. Aramadan seçmek '
              'istemezsen türler üç grupta durur; Kripto "Borsa ve fon" '
              'grubunda. Seçince ızgara tek satıra katlanır, "Değiştir" '
              'geri açar. Coin\'in fiyatı TL karşılığıyla kendiliğinden '
              'gelir, miktar gerektiği kadar ondalıkla tutulur (0,00045 BTC '
              'gibi); kripto 7/24 işlediği için grafikte hafta sonu da görünür.'
          : 'Tür çiplerinde Kripto da var: listeden coin\'i '
              'seç, fiyatı TL karşılığıyla kendiliğinden gelir. Miktar gerektiği kadar '
              'ondalıkla tutulur (0,00045 BTC gibi); kripto 7/24 işlediği için '
              'grafikte hafta sonu da görünür.',
      giris: (_) => _varlikEkleAc(),
      dokunulabilir: false,
    ),
    // Mevduat ve BES (2026-09-30): tür seçicide Fon'un arkasına iki çip
    // girdi (tur metni arayüzle birlikte değişir kuralı). Aynı hedefte
    // ikinci adım: kripto adımı kendi özelliğini anlatmaya devam eder.
    // 2026-10-01: BES formu ana para + getiri sorar, geçmiş düz çizilir
    // (2026-10-04: düz çizgi kalktı, fonun gerçek serisi — metin buna göre),
    // "Fon değiştir" eklendi — metin buna göre. Aynı gün: otomatik katkı
    // (0096) formda ve kartta; son cümle onu anlatır.
    // 2026-10-02: vadeli faiz vade sonunda eklenir, vade içinde oran
    // karttan güncellenir — mevduat cümlesi buna göre.
    _Adim(
      id: 'mevduat_bes',
      hedef: TourTarget.turSecici,
      rozet: 'YENİ',
      baslik: 'Mevduat ve BES',
      // Izgarada (bayrak `tur_secici_izgara`) Mevduat ve BES "Birikim"
      // grubunda; yalnız ilk cümlenin yeri söylenir, gerisi aynı.
      // 2026-10-09 (bayrak `mevduat_banka_secici`): banka listeden seçilir,
      // faiz vadeye göre piyasa ortalamasıyla önerilir, not yazılır — ilk
      // cümle buna göre; kapalıyken birebir eski.
      govde: '${RemoteConfigService.instance.turSeciciIzgara ? 'Birikim grubunda ' : ''}'
          '${RemoteConfigService.instance.mevduatBankaSecici ? "Mevduat'ı seç: bankanı listeden seç, tutarı ve vadeyi yaz; faiz piyasa ortalamasıyla gelir, sana özel oran verildiyse değiştirirsin, istersen not eklersin. Net getiriyi " : "Mevduat'ı seç: banka, tutar, faiz ve vadeyi yaz; net getiriyi "}'
          'stopajıyla birlikte biz hesaplarız. Faiz vade sonunda (günlük faizli '
          'hesapta her gün sonunda) eklenir; '
          'banka vade içinde oranı değiştirirse karttan güncellersin, kazanç '
          'son orana göre çıkar. Vade dolunca varlık sayfasından tek '
          "dokunuşla yenilersin. BES'i seç: şirketini, ana "
          'paranı, getirini ve fon dağılımını gir; grafik ve dönem getirileri '
          'emeklilik fonlarının gerçek fiyatıyla yürür. Fonunu değiştirince grafik yeni fonlarla devam eder; devlet '
          'katkısı hak ediş oranıyla ayrı görünür. Katkı gününü yazıp '
          'otomatik eklemeyi açarsan aylık katkın o gün kendiliğinden eklenir; '
          'tutar farklıysa kartta tek dokunuşla düzeltirsin.',
      giris: (_) => _varlikEkleAc(),
      dokunulabilir: false,
    ),
    _Adim(
      id: 'hizli_giris',
      hedef: TourTarget.hizliGiris,
      rozet: 'BİZE ÖZEL',
      baslik: 'Cümleyle ekle',
      // Sadeleştirme 2 (2026-10-04; bayrak `ilk_varlik_kolay` 2026-10-05'te
      // kalktı): aynı sayfa formun üstündeki "Yazarak ekle" düğmesiyle de
      // açılır; metin ikisini söyler.
      govde: '"Yazarak ekle" (ya da mikrofon) '
          'Hızlı Giriş\'i açar: "10 gram altın 4500 lira" ya da '
          '"GARAN 500 adet" yazman (veya söylemen) yeter. Her satır ayrı bir '
          'varlık olur; fiyat yazmazsan güncel fiyat kendiliğinden çekilir.',
      giris: (_) => _varlikEkleAc(),
      dokunulabilir: false,
    ),
    _Adim(
      id: 'toplu',
      hedef: TourTarget.topluEkle,
      baslik: 'Toplu ekle',
      // 2026-09-30 (karar 5.6): yapıştırma artık kurum sütun adlarını ve
      // satış satırlarını da okuyor; tur yüzeyin güncel hâlini anlatır.
      // 2026-10-01: ekstre dosyadan da okunuyor (PDF/Excel/CSV, evrensel
      // motor) — tur "dosyadan seç"i anlatır.
      // Sadeleştirme 2 (2026-10-04; bayrak `ilk_varlik_kolay` 2026-10-05'te
      // kalktı): hedef formdaki "Ekstreden aktar" düğmesi; metin oradan
      // başlar.
      govde: '"Ekstreden aktar": aracı kurum ya da banka ekstreni (PDF, Excel '
          'veya CSV) dosyadan seç ya da tabloyu yapıştır; sütunlar '
          'kendiliğinden tanınır, alışlar ve satışlar tarihleriyle gelir, '
          'tek onayda kaydedersin. Portföyünü ilk kez kurarken en hızlı '
          'yol bu.',
      giris: (_) => _varlikEkleAc(),
      dokunulabilir: false,
      cikis: (_) => _varlikEkleKapat(),
    ),
    _Adim(
      id: 'sekme_performans',
      hedef: TourTarget.sekmePerformans,
      baslik: 'Performans sekmesi',
      // 2026-10-01 (düzen A): Özet "BU DÖNEM / VARLIKLAR / DERİNLİK" idi;
      // soru sırasına (Sonuç → Neden → Ayrıntı) çevrildi, ana rakamın adı
      // "Paranın getirisi" oldu ve her yüzde aralık çipi taşıyor. Dönemler
      // 2026-09-28'den beri 5Y'ye kadar ("bir yıla kadar" eskimişti).
      // 2026-10-02 (müşteri testi sadeleştirmesi): enflasyon kartı tek sayı
      // söyler (kaç puan önde/geride), Grafik kartındaki yüzde yalnızca
      // piyasanın kattığıdır — tur metni de bunu söylüyor.
      // 2026-10-04 (sadeleştirme 2, jargon): ekrandaki adlar değişti —
      // "Piyasanın kattığı" → "Fiyat etkisi", Özet başlıkları "Ne oldu?" /
      // "Neden böyle?" / "Ayrıntılar" / "Daha fazlası". Tur aynı adları
      // kullanır, yoksa kullanıcı ekranda tarif edileni bulamaz.
      // Tek akış (bayrak `performans_tek_akis`, S2): Grafik | Özet anahtarı
      // yok, tek kaydırma. Bayrak kapalıyken eski metin birebir.
      govde: PortfolioPerformanceScreen.tekAkisAcik
          ? 'Kazancın tek sayfada, yukarıdan aşağı: en üstte seçtiğin '
              'dönemde paranın getirisi (yüzde yalnızca fiyat etkisidir; '
              'yatırdığın para alttaki cümlede ayrı yazılır), altında '
              'grafik, onun altında özet. Özet soru sırasıyla ilerler: '
              '"Ne oldu?" (enflasyona göre kaç puan önde ya da geride '
              'olduğun), "Neden böyle?" (nereden geldi, hangi varlıklar, '
              'türe göre döküm) ve "Ayrıntılar" (birikim düzenin; istersen '
              '"Daha fazlası"nı açarsın). Her yüzdenin yanındaki mavi çip '
              'ölçüldüğü aralığı yazar.'
          : 'Grafikler ve kâr/zarar dökümü. Gün içinden beş yıla kadar her '
          'dönemi görebilirsin. Grafik kartında yüzde yalnızca fiyat '
          'etkisidir; yatırdığın para ayrı yazılır. Özet soru sırasıyla '
          'ilerler: "Ne oldu?" (paranın getirisi ve enflasyona göre kaç puan '
          'önde ya da geride olduğun), "Neden böyle?" (nereden geldi, hangi '
          'varlıklar) ve "Ayrıntılar" (birikim düzenin; istersen "Daha '
          'fazlası"nı açarsın). Her yüzdenin yanındaki mavi çip ölçüldüğü '
          'aralığı yazar.',
      gorev: 'Performans sekmesine dokun',
      gorevBitti: 'Performans açıldı',
      bitti: (_) => _sekmede(3),
      giris: (_) => _varlikEkleKapat(),
      devam: (_) => _sekmeyeGec(3),
    ),
    _Adim(
      id: 'donem',
      hedef: TourTarget.donemSecici,
      baslik: 'Dönem seç',
      // 2026-09-28: 3A ve 5Y eklendi; aynı seçici artık Takip,
      // Karşılaştır ve varlık ekranlarında da var.
      // 2026-09-28: seçici üç grafik ekranında da grafiğin ÜSTÜNDE
      // (bkz. `kartlar.dart` kontrol yığını notu).
      // Tek akış (S2): seçici sayfanın tek kontrol satırında, sağında
      // Filtre çipi; seçim kartı, grafiği ve özeti birlikte değiştirir.
      // `donem_hafizasi` açıkken seçim ekranlar arasında taşınır — tur bunu
      // tek cümleyle söyler (yalnız o bayrak açıkken doğru).
      govde: (PortfolioPerformanceScreen.tekAkisAcik
              ? 'Sayfanın en üstündeki seçici: "Bugün" gün içini saat saat '
                  'çizer; 1 hafta, 1 ay, 3 ay, 6 ay, 1 yıl ve 5 yıl daha '
                  'geniş pencereler. Seçtiğin dönem üstteki kartı, grafiği '
                  've altındaki özeti birlikte değiştirir. Aynı seçici '
                  'aynı yerde Takip, Karşılaştır ve varlık ekranlarında da '
                  'var. Grafiği iki parmakla yakınlaştırabilir, bir noktaya '
                  'basılı tutarak o anın tarihini, saatini ve değerini '
                  'okuyabilirsin.'
              : 'Grafiğin üstündeki seçici: "Bugün" gün içini saat saat '
                  'çizer; 1 hafta, 1 ay, 3 ay, 6 ay, 1 yıl ve 5 yıl daha '
                  'geniş pencereler. Aynı seçici '
                  'aynı yerde Takip, Karşılaştır ve varlık ekranlarında da var. '
                  'Grafiği iki parmakla yakınlaştırabilir, bir noktaya '
                  'basılı tutarak o anın tarihini, saatini ve değerini '
                  'okuyabilirsin.') +
          (RemoteConfigService.instance.donemHafizasi
              ? ' Seçtiğin dönem her ekranda geçerli olur.'
              : ''),
      // 2026-09-15: bu adımın görevi kaldırıldı. Eski ölçüt "Gerçek /
      // Simülasyon anahtarı belirdi mi" idi; o anahtar artık kapsam
      // panelinin içinde, yani dönem değişimini ondan okuyamıyoruz
      // (2026-10-01'den beri panel kapalıyken ağaçta da değil —
      // `SandikAcilir`). Ölçemediğimiz bir görevi
      // "tamamlandı" diye göstermektense görevsiz anlatım dürüst.
      giris: (_) => _sekmeyeGecBasa(3),
    ),
    _Adim(
      id: 'kapsam',
      hedef: TourTarget.kapsamSecici,
      rozet: 'BİZE ÖZEL',
      // `performans_ayar_sade` (2026-10-04, madde 5; bayrak 2026-10-05'te
      // kalktı): mod anahtarı kapsam panelinden Ayarlar › Görünüm'e taşındı;
      // çip yalnız türü yazar, mod açıkken çipin altında "Bugünkü portföyle"
      // rozeti durur. Tur metni gerçek ekranı anlatmalı (tur metni arayüzle
      // değişir kuralı).
      baslik: PortfolioPerformanceScreen.tekAkisAcik ? 'Filtre' : 'Kapsam',
      // Tek akış (S2): hedef Filtre çipi (`_buildFiltreCipi`); kişi, tür ve
      // "Bugünkü portföyle" tek alt sayfada. Bayrak kapalıyken eski metin.
      govde: PortfolioPerformanceScreen.tekAkisAcik
          ? 'Dönem seçicinin sağındaki Filtre çipi neye baktığını belirler; '
              'dokununca bir sayfa açılır: ortağın varsa kimin portföyü, '
              'hangi varlık türü ve "Bugünkü portföyle". '
              // `goz_alici` (2026-10-09): sayfada her tür kaç varlık
              // olduğunu yazar; çip sayıyı değil seçilen türü gösterir.
              '${RemoteConfigService.instance.gozAlici ? 'Her türün yanında kaç varlığın olduğu ve portföydeki payı görünür; tür seçince çip onun adını yazar ("Fon").' : 'Varsayılan dışında bir seçim varsa çip sayısını yazar ("Filtre · 1").'}\n\n'
              'Grafik dönem içindeki her alım ve satımla gerçek geçmişini '
              'çizer. "Bugünkü portföyümü baştan elimde tutsaydım ne '
              'olurdu?" diye merak edersen aynı sayfada "Bugünkü portföyle '
              'göster"i aç; açıkken seçicinin altında rozet görünür.'
          : 'Bu çip hangi varlık türüne baktığını yazar; dokununca türler '
          'açılır. Kimin portföyü olduğunu başlıktaki kişi çipi '
          'seçer.\n\nGrafik dönem içindeki her alım ve satımla gerçek '
          'geçmişini çizer. "Bugünkü portföyümü baştan elimde tutsaydım '
          'ne olurdu?" diye merak edersen Ayarlar › Görünüm\'de '
          '"Bugünkü portföyle göster"i aç; açıkken bu çipin altında '
          'rozet görünür.',
      giris: (_) => _sekmeyeGecBasa(3),
    ),
    _Adim(
      id: 'zirve',
      hedef: TourTarget.zirveKarti,
      rozet: 'YENİ',
      baslik: 'Zirvedeki portföyler',
      // 2026-09-29: kart Yarış ekranından Performans'a taşındı, kendi
      // ekranı ve cetveli var. Tur uygulamanın güncel hâlini anlatmalı.
      // 2026-10-01 (0095): ölçü "seçimlerinin getirisi" (TWR) oldu; metin
      // neyin yarıştığını söyler — para ekleme zamanı değil, seçimler.
      // 2026-10-04 (sadeleştirme madde 8, bayrak `siralama_tek_sayfa`):
      // kart ayrı ekranı değil Sıralama sayfasının "Zirvedekiler" sekmesini
      // açar; Yarış da aynı sayfanın "Ortaklarım" sekmesi.
      // 2026-10-04 (bayrak `yaris_duello_arena`): tek ortaklı yarış liste
      // değil düello arenası; metin arenayı anlatır — tur gerçek ekranın
      // üstünde çalışır. İki bayrak 2026-10-05'te kalktı, metin kalıcı.
      // Tek akış (S2): kart özetin altında, sayfanın sonunda; tür dökümü
      // artık "Neden böyle?" bölümünde. Konum sözcüğü ona göre.
      govde: '${PortfolioPerformanceScreen.tekAkisAcik ? 'Sayfanın sonundaki' : 'Tür dökümünün altındaki'}'
          ' kart, dönemin en iyi seçimlerini yapan '
          'anonim portföyleri gösterir: her gün tutulan varlıklar piyasa '
          'fiyatıyla ölçülür, para ekleme zamanı sonucu değiştirmez. '
          'Dokununca Sıralama sayfasının Zirvedekiler sekmesi açılır: '
          'haftalık, aylık ve yıllık; herkes aynı çizgide, sen de '
          'üstünde. Ortaklarınla yarışın yanındaki Ortaklarım '
          'sekmesinde, aynı dönemle. Yarış\'ta tek ortağın varsa ikiniz '
          'düello arenasında karşılaşırsınız: getiriler yan yana akar, halat '
          'aradaki farkı, taç öndekini gösterir; altındaki şerit dönemin her '
          'günü kimin önde olduğunu. Katılım isteğe bağlı '
          've anonim: katılanlar birbirinin tür dağılımını ve getirisini '
          'görür; kimlik, miktar ve TL asla paylaşılmaz.',
      // Kartı GÖSTER (2026-10-03): kart Grafik yüzeyinde ve listenin en
      // altında; sekmeye geçmek yetmiyordu, metin boşluğun üstünde
      // kalıyordu. Ekran Grafik'e geçer ve kartı görünür alana getirir.
      giris: (_) {
        _sekmeyeGec(3);
        PortfolioPerformanceScreen.zirveIstegi.value = true;
      },
      // Kart yalnız küresel bayrak açıkken ve demoda değilken çizilir
      // (`kartlar.dart`); yokken adım gösterilmez.
      kosul: (_) =>
          RemoteConfigService.instance.globalLeaderboardEnabled &&
          !DemoModu.aktif,
    ),
    _Adim(
      id: 'sekme_profil',
      hedef: TourTarget.sekmeProfil,
      baslik: 'Profil sekmesi',
      // Tema 2026-10-04'e kadar Profil başlığında da bir düğmeydi; artık
      // yalnız Ayarlar'da. Metin neyin nerede olduğunu ayırır.
      govde: 'Ortaklık burada; bildirimler, sinyal ayarları, fiyat '
          'alarmları, tema ve yasal belgeler sağ üstteki Ayarlar\'da.',
      gorev: 'Profil sekmesine dokun',
      gorevBitti: 'Profil açıldı',
      bitti: (_) => _sekmede(4),
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
          'ana ekranda kartı kaydırarak aralarında geçersin. İstediğin an '
          'ortaklıktan ayrılabilirsin.',
      giris: (_) => _sekmeyeGec(4),
      dokunulabilir: false,
    ),
    _Adim(
      id: 'ayarlar',
      hedef: TourTarget.ayarlar,
      baslik: 'Ayarlar',
      // `performans_ayar_sade` (2026-10-04; bayrak 2026-10-05'te kalktı):
      // bölümler gruplu ve Performans'ın "Bugünkü portföyle" görünümü
      // Görünüm'de; metin bölüm adlarıyla anlatır ki kullanıcı ekranda aynı
      // başlıkları bulsun.
      govde: 'Dört bölüm: Görünüm (tema, yazı boyutu, dil, baz para birimi, '
          'yatırımcı seviyesi ve "Bugünkü portföyle" görünümü), '
          'Bildirimler (sinyal ayarları, fiyat alarmları, günlük '
          'brifingin saati, sessiz saatler), Hesap & Güvenlik '
          '(kullanıcı adın, kilit, kayıtlı cihazların, verilerin) ve '
          'Yardım & Yasal. '
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
List<_Adim> _kisaAdimlar({required bool seviyeSorusu}) {
  final tam = {for (final a in _adimlariKur()) a.id: a};
  return [
    const _Adim(
      id: 'karsilama',
      baslik: 'Sandığına hoş geldin',
      govde: 'Hisse, döviz, altın, fon, kripto; hepsi tek toplamda. Bir dakikada '
          'ilk varlığını girelim; gerisini uygulama kendi anlatır.',
    ),
    // Yatırımcı seviyesi (plan F2, 2026-09-29): tercih yalnız Ayarlar ›
    // Görünüm'de duruyordu ve yeni kullanıcı varlığından habersizdi;
    // Başlangıç seviyesinin sadeleştirdiği ekranları (teknik sinyaller,
    // bildirim zili) ilk günden görüyordu. Karşılamadan HEMEN sonra, hedefli
    // adımlardan önce: sonraki adımlar zaten gerçek ekranı gösterdiği için
    // ekran seçilen seviyeyle anlatılır. Ayrı bir ön ekran yerine tur adımı:
    // "Atla" ve ilerleme göstergesi bedava gelir, tur yapısı değişmez.
    //
    // Anket (2026-10-04; bayrak `seviye_anketi` 2026-10-05'te kalktı): üç
    // seçenekli etiket seçici (`_SeviyeSecici`) yerine davranışa dair üç
    // kısa soru; kullanıcı kendini "Başlangıç" diye etiketlemek zorunda
    // kalmaz. Cevaplamadan "Devam" denirse seviye değişmez (varsayılan Orta).
    if (seviyeSorusu)
      const _Adim(
        id: 'seviye',
        baslik: 'Ekranları sana göre ayarlayalım',
        govde: 'Üç kısa soru. Cevabına göre ekranlar sadeleşir ya da '
            "ayrıntılanır; Ayarlar › Görünüm'den istediğin an değiştirirsin.",
        ek: _seviyeAnketi,
      ),
    tam['hero']!,
    tam['vitrin']!,
    tam['bugun']!,
    tam['ekle']!,
    // Kripto ilk açılışta da anlatılır (kullanıcı kararı 2026-09-25):
    // yalnız tam turda (Ayarlar) olduğu için yeni kullanıcı kripto
    // eklenebildiğini karşılamadaki tek kelimeden öğreniyordu. Kısa tur
    // 5 → 6 kart; "Varlık Ekle" zaten açık olduğundan ek gezinme yok.
    tam['kripto']!,
    _Adim(
      id: 'toplu_son',
      hedef: TourTarget.topluEkle,
      baslik: 'Hazırsın',
      // Sadeleştirme 2 (2026-10-04; bayrak `ilk_varlik_kolay` 2026-10-05'te
      // kalktı): hedef formdaki "Ekstreden aktar" düğmesi.
      govde: 'En hızlı yol: "Ekstreden aktar". '
          'Kurumunun PDF, Excel ya da CSV ekstresini seç; her alış ve satış kendi '
          'tarihiyle deftere girer. Tek tek girmek istersen tür seçmen yeter, '
          'fiyat kendiliğinden gelir.',
      giris: (_) => _varlikEkleAc(),
      dokunulabilir: false,
    ),
  ];
}

Widget _seviyeAnketi(BuildContext context) => const SeviyeAnketi();

// ─── Tur denetleyicisi ───────────────────────────────────────────────────────

/// Açık tur oturumu — adımlar ve kapanış geri çağrısı.
class _Oturum {
  _Oturum({required this.adimlar, required this.onBitti});

  final List<_Adim> adimlar;
  final void Function(bool tamamlandi) onBitti;
}

/// Tek tur oturumu; [OnboardingTourHost] bunu dinler.
/// Tanıtım turu şu an ekranda mı — başka yüzeyler (kilometre taşı kutlaması)
/// turun ÜSTÜNE açılmasın diye okur.
bool get tanitimTuruAktif => _Tur.aktif;

abstract final class _Tur {
  static final oturum = ValueNotifier<_Oturum?>(null);

  static bool get aktif => oturum.value != null;

  static void baslat({
    required void Function(bool tamamlandi) onBitti,
    bool kisa = false,
    bool seviyeSorusu = false,
  }) {
    if (aktif) return;
    oturum.value = _Oturum(
      adimlar: kisa
          ? _kisaAdimlar(seviyeSorusu: seviyeSorusu)
          : _adimlariKur(),
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

/// Tur perdesi bulanık mı: yalnız iOS + açık tema (bkz. perde yorumu).
bool _turBulanik(BuildContext context) =>
    context.isLight && defaultTargetPlatform == TargetPlatform.iOS;

/// HIG'in en küçük dokunma hedefi: 44×44pt (Human Interface Guidelines →
/// Controls). Boşluk ölçeğine ait bir sayı DEĞİL — Apple'ın sabiti; bu
/// yüzden `SandikSpace` içinden seçilmez.
const double _higHedef = 44;

/// Uzun süreli hareketler için ölçek — hareket dili sabitlerinin katları,
/// böylece "hareketi azalt" koruması (`SandikMotion.of`) aynen çalışır.
abstract final class _Sahne {
  /// Kartın belirişi: 240 ms ([SandikMotion.surface]).
  ///
  /// Eskiden 480 ms'ydi ve her adımda saydamlık SIFIRDAN başlıyordu: hızlı
  /// "Devam"da kart her dokunuşta tamamen sönüp yeniden beliriyordu —
  /// göz kırpması gibi (animasyon denetimi 2026-10-01). Şimdi yarı süre ve
  /// adım değişiminde %30'dan başlar ([_TurKatmaniState._adimaGir]).
  static Duration get belir => SandikMotion.surface;

  /// Oyuğun hedefe yaklaşma zaman sabiti (sn). Adım değişince oyuk yeni
  /// hedefe KAYAR (tek karede atlamaz); ekran kayarken hedefi ~70 ms
  /// gecikmeyle izler — göz fark etmez, titreme de süzülür.
  static const double oyukTau = 0.07;

  /// Nabız halkası bir turu: 1.440ms.
  static Duration get nabiz => SandikMotion.surface * 6;

  /// Hedef beklenirken kart gizli; bu süre (1,9s) dolup hedef hâlâ yoksa
  /// kart HEDEFSİZ (ortada) gösterilir ve "Devam" beklenir. Adım ATLANMAZ:
  /// tur yalnız dokunuşla ilerler (kullanıcı kararı 2026-09-26). Eskiden bu
  /// süre dolunca adım kendiliğinden geçiyordu. Bilinen koşullu yüzeyler
  /// zaten [_Adim.kosul] ile dokunuş anında elenir; buraya düşen, beklenmedik
  /// bir durumdur (yavaş yükleme, değişmiş yerleşim).
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

  /// Bütün katmanın (karartma + bulanıklık + kart) giriş/çıkış solması.
  /// Eskiden tam ekran karartma tek karede açılıp kapanıyordu; yalnız kart
  /// soluyordu (animasyon denetimi 2026-10-01).
  late final AnimationController _perde = AnimationController(vsync: this);

  int _i = 0;

  /// ÇİZİLEN oyuk — hedefe [_Sahne.oyukTau] ile yaklaşır (bkz. [_yaklas]).
  Rect? _rect;
  Duration _oncekiTik = Duration.zero;

  /// Tamamlanan görevlerin adım kimlikleri.
  final Set<String> _tamamlanan = {};

  /// Adıma giriş anı — ticker zamanıyla; `Timer` kullanılmaz (katman
  /// kapanınca askıda kalır). Yalnız kartın hedefsiz gösterilme kararı için.
  Duration _girisAni = Duration.zero;
  Duration _simdi = Duration.zero;

  /// Hedef bekleme süresi doldu, hedef yok: kart ortada, "Devam" bekleniyor.
  bool _hedefsiz = false;
  bool _bitti = false;

  _Adim get _adim => widget.adimlar[_i];

  /// [bas]tan [yon] yönünde, koşulu tutan ilk adım; yoksa null.
  int? _gorunurAdim(int bas, int yon) {
    for (var j = bas; j >= 0 && j < widget.adimlar.length; j += yon) {
      if (widget.adimlar[j].kosul?.call(widget.ref) ?? true) return j;
    }
    return null;
  }

  /// İlerleme göstergesi için görünen adımların sırası.
  List<int> get _gorunurler => [
        for (var j = 0; j < widget.adimlar.length; j++)
          if (widget.adimlar[j].kosul?.call(widget.ref) ?? true) j,
      ];
  bool get _gorevBitti => _tamamlanan.contains(_adim.id);

  @override
  void initState() {
    super.initState();
    _ticker.start();
    _adimaGir(_gorunurAdim(0, 1) ?? 0, ilk: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _belir.duration = SandikMotion.of(context, _Sahne.belir);
    _perde.duration = SandikMotion.surfaceOf(context);
    if (!_bitti && !_perde.isAnimating && _perde.value == 0) _perde.forward();
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
    _perde.dispose();
    super.dispose();
  }

  // ── Adım akışı ──────────────────────────────────────────────────────────

  void _adimaGir(int i, {bool ilk = false}) {
    _i = i;
    _girisAni = _simdi;
    _hedefsiz = false;
    // `_rect` SIFIRLANMAZ: oyuk eski hedefte kalır ve yeni hedef ilk
    // ölçüldüğü karede oraya kayar (bkz. [_yaklas]). Yeni adımın hedefi
    // yoksa ya da henüz kurulmadıysa `_tik` oyuğu kendisi kaldırır.
    if (!ilk) {
      AnalyticsService.instance.logOnboardingStep(i);
      // Sıfırdan değil: içerik değişti, kart söner gibi olmasın.
      _belir.forward(from: math.min(_belir.value, 0.3));
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
    final dt = gecen - _oncekiTik;
    _oncekiTik = gecen;
    _simdi = gecen;
    final adim = _adim;

    // 1) Görev tamamlandı mı? Uygulamanın gerçek durumundan. Tamamlanınca
    // onay satırı görünür; tur İLERLEMEZ, "Devam"ı bekler.
    if (adim.bitti != null && !_gorevBitti && adim.bitti!(widget.ref)) {
      SandikHaptic.medium.perform();
      setState(() => _tamamlanan.add(adim.id));
    }

    // 2) Hedefin dikdörtgeni.
    final yeni = adim.hedef == null ? null : TourTargets.rect(adim.hedef!);
    if (adim.hedef != null && yeni == null) {
      // Hedef yok: kart gizli kalır; bekleme süresi dolunca hedefsiz
      // gösterilir. Adım ATLANMAZ (bkz. `_Sahne.hedefBekle`).
      final hedefsiz = gecen - _girisAni > _Sahne.hedefBekle;
      if (_rect != null || hedefsiz != _hedefsiz) {
        setState(() {
          _rect = null;
          _hedefsiz = hedefsiz;
        });
      }
      return;
    }
    if (!_ayni(yeni, _rect) || _hedefsiz) {
      setState(() {
        _rect = _yaklas(_rect, yeni, dt);
        _hedefsiz = false;
      });
    }
  }

  /// Çizilen oyuğu hedefe bir kare yaklaştırır (üstel süzme, kare
  /// süresinden bağımsız). İlk görünüşte, hedef kalkınca ve hareketi
  /// azalt açıkken doğrudan hedef.
  Rect? _yaklas(Rect? simdiki, Rect? hedef, Duration dt) {
    if (simdiki == null || hedef == null) return hedef;
    if (MediaQuery.disableAnimationsOf(context)) return hedef;
    final sn = dt.inMicroseconds / Duration.microsecondsPerSecond;
    final k = 1 - math.exp(-sn / _Sahne.oyukTau);
    final r = Rect.lerp(simdiki, hedef, k.clamp(0.0, 1.0))!;
    return _ayni(r, hedef) ? hedef : r;
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
    // Koşulu tutmayan adımlar bu dokunuşla birlikte geçilir (görünmeden).
    final j = _gorunurAdim(_i + 1, 1);
    if (j == null) {
      _kapat(tamamlandi: true);
      return;
    }
    setState(() => _adimaGir(j));
  }

  void _geri() {
    if (_bitti) return;
    final j = _gorunurAdim(_i - 1, -1);
    if (j == null) return;
    _adim.cikis?.call(widget.ref);
    setState(() => _adimaGir(j));
  }

  void _atla() {
    if (_bitti) return;
    AnalyticsService.instance.logOnboardingSkipped(_i);
    _kapat(tamamlandi: false);
  }

  Future<void> _kapat({required bool tamamlandi}) async {
    if (_bitti) return;
    _bitti = true;
    _ticker.stop();
    if (tamamlandi) unawaited(AnalyticsService.instance.logOnboardingCompleted());
    // Perde solarak kalkar, SONRA katman sökülür. Çıkış hızla başlar
    // (`exit`); hareketi azalt açıkken süre sıfır.
    if (_perde.duration != Duration.zero && _perde.value > 0) {
      try {
        await _perde
            .animateBack(0, curve: SandikMotion.exit)
            .orCancel;
      } on TickerCanceled {
        // Katman zaten sökülüyor.
      }
    }
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

    return FadeTransition(
      // Bütün katman (karartma + bulanıklık + kart) birlikte solar — bkz.
      // [_perde].
      opacity: _perde,
      child: Stack(
      fit: StackFit.expand,
      children: [
        // Karartma + blur; oyuk dışında dokunuşu YUTAR, oyukta geçirir
        // (RenderClipPath, kırpma yolunun dışını hit-test etmez).
        ClipPath(
          clipper: _OyukKirpici(oyuk),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            // Bulanıklık YALNIZ iOS + açık temada (animasyon denetimi
            // 2026-10-01): `BackdropFilter` bir kare çizildiği sürece HER
            // karede yeniden uygulanır ve turda nabız halkası sürekli döner —
            // blur tur boyunca kesintisiz GPU işi. Koyu temada perde %78
            // opak, blur zaten görünmüyordu; Android'de (Vulkan/Skia)
            // pahalı. Açık temada blur'suz hâlde ayrım kaybolmasın diye
            // perde biraz koyulaşır (0,42 → 0,50).
            child: _turBulanik(context)
                ? BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: ColoredBox(
                      color: p.text90.withValues(alpha: 0.42),
                    ),
                  )
                : ColoredBox(
                    // Light'ta zemin rengi karartmaz; koyu metin tonu.
                    color: context.isLight
                        ? p.text90.withValues(alpha: 0.50)
                        : p.background.withValues(alpha: 0.78),
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
        // Hedefli adımın kartı hedef BULUNUNCA çizilir. Önceden hedef
        // beklenirken (`hedefBekle`, 1,9s) kart ekranın ortasında duruyor,
        // hedef gelmeyince adım kendiliğinden geçiyordu: kullanıcı okurken
        // kart kayboluyordu (mağaza 1.0.5, kullanıcı bildirimi 2026-09-25 —
        // ilk açılışta boş portföyde "Bugün" kartı yok, kısa tur her yeni
        // kullanıcıda böyle atlıyordu). Kural: GÖRÜNEN adım dokunuşsuz
        // değişmez. Koşulu bilinen yüzeyler (`_Adim.kosul`) dokunuş anında
        // elenir; beklenmedik biçimde gelmeyen hedefte kart süre dolunca
        // ortada gösterilir ve dokunuş bekler (`_hedefsiz`). Ek kazanç:
        // sekme geçişinde kart önce ortada belirip hedefe zıplamıyor.
        if (adim.hedef == null || oyuk != null || _hedefsiz)
          _kart(context, mq, oyuk),
      ],
    ),
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
                sira: _gorunurler.indexOf(_i).clamp(0, 1 << 20),
                toplam: _gorunurler.length,
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
                    if (adim.ek case final ek?) ...[
                      const SizedBox(height: SandikSpace.smd),
                      ek(context),
                    ],
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
      switchOutCurve: SandikMotion.exit,
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
