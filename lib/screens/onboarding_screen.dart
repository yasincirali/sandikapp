import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/analytics_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../theme/sandik.dart';

/// Yeni kullanıcılara gösterilen interaktif demo.
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
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    if (serverError != null) {
      debugPrint(
          'OnboardingScreen.markCompleted server write failed: $serverError');
    }
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}


// ─── Tur içeriği ─────────────────────────────────────────────────────────────
//
// Tanıtım ekran ekran ve TUŞ TUŞ ilerler. Her [_Sahne] bir ekranın
// minyatürünü çizer; sahnenin [_Adim]'ları o minyatürdeki tek bir öğeyi
// sırayla vurgular. "İleri" bir sonraki TUŞA, parmakla kaydırma bir sonraki
// EKRANA geçirir.
//
// ## Neden minyatür, ekran görüntüsü değil
// Ekran görüntüsü ilk tema/dil/yerleşim değişiminde yalan söylemeye başlar
// ve kimse fark etmez. Minyatürler uygulamanın KENDİ tokenlarıyla çizilir:
// tema değişince onlar da değişir, marka rengi güncellenince onlar da.
//
// ## Neden vurgu koordinatla değil, widget'la
// Hotspot'lar piksel koordinatı taşımaz; vurgulanacak öğe [_Vurgu] ile
// sarılır, konumunu Flutter'ın yerleşimi belirler. Metin ölçeği ya da ekran
// genişliği değişince halka kendiliğinden doğru yerde kalır.
//
// ## Neden sıra alt menüyle başlıyor
// Kullanıcının önce HARİTAYA ihtiyacı var: beş tuşun ne olduğunu bilmeden
// ekranları gezmek, gezdiği yeri bir daha bulamamak demek. Alt menüden
// sonra sahneler menünün kendi sırasını izler (Ana → Portföy → + →
// Performans → Profil), böylece tur bittiğinde kullanıcının kafasındaki
// sıra uygulamadakiyle aynı olur.

enum _MockTur {
  yok,
  altMenu,
  anaEkran,
  portfoy,
  varlikEkle,
  performans,
  sinyal,
  profil,
}

class _Adim {
  const _Adim({
    required this.baslik,
    required this.govde,
    this.vurgu,
    this.rozet,
  });

  final String baslik;
  final String govde;

  /// Minyatürde vurgulanacak öğenin [_Vurgu] indeksi.
  final int? vurgu;

  /// "BİZE ÖZEL" gibi bir üst etiket — bizi ayırt eden özellikleri
  /// işaretler. Kullanıcı hangi kısmın başka uygulamalarda olmadığını
  /// görmeli.
  final String? rozet;
}

class _Sahne {
  const _Sahne({
    required this.ekran,
    required this.mock,
    required this.adimlar,
    this.ikon,
  });

  /// Üst çubukta görünen ekran adı — kullanıcı hangi ekranı öğrendiğini
  /// bilsin.
  final String ekran;
  final _MockTur mock;
  final List<_Adim> adimlar;

  /// [_MockTur.yok] sahnelerinde minyatür yerine gösterilen simge.
  final IconData? ikon;
}

/// Turun tamamı.
///
/// Kapalı bayrakların özellikleri ANLATILMAZ: olmayan bir tuşu tanıtmak,
/// tanıtımın tamamına olan güveni bozar. Bayrak kapalıyken adım listeden
/// düşer, minyatürdeki öğe de çizilmez — vurgu indeksleri bu yüzden sabit
/// tutulur, kaydırılmaz.
List<_Sahne> _turuKur() {
  final rc = RemoteConfigService.instance;
  final mevduat = rc.depositsEnabled;
  final yarisVar = rc.percentileStripEnabled;
  final tufeVar = rc.realReturnEnabled;
  final premiumVar = rc.paywallEnabled && rc.premiumEnabled;

  final turler = mevduat
      ? 'Hisse, fon, döviz, altın, emtia ve vadeli mevduat'
      : 'Hisse, fon, döviz, altın ve emtia';

  return [
    // ── 1. Karşılama ─────────────────────────────────────────────────────
    _Sahne(
      ekran: 'sandık',
      mock: _MockTur.yok,
      ikon: Icons.account_balance_wallet_rounded,
      adimlar: [
        _Adim(
          baslik: 'Sandığınıza hoş geldiniz',
          govde: '$turler — hepsi tek ekranda, tek para biriminde. Fiyatlar '
              'arka planda kendiliğinden güncellenir.\n\n'
              'Şimdi uygulamayı birlikte gezelim. Her ekranı ve her tuşu tek '
              'tek göstereceğim; "İleri" bir sonraki tuşa geçer.',
        ),
      ],
    ),

    // ── 2. Alt menü: beş tuş, tek tek ────────────────────────────────────
    const _Sahne(
      ekran: 'Alt menü',
      mock: _MockTur.altMenu,
      adimlar: [
        _Adim(
          vurgu: 0,
          baslik: 'Ana',
          govde: 'Toplam birikimin, günlük değişimin ve özet kartların. '
              'Uygulamayı her açtığında burası karşılar.',
        ),
        _Adim(
          vurgu: 1,
          baslik: 'Portföy',
          govde: 'Varlıklarının listesi ve dağılım halkası. Bir varlığa '
              'dokunduğunda detayına inersin.',
        ),
        _Adim(
          vurgu: 2,
          baslik: 'Ortadaki + tuşu',
          govde: 'Yeni varlık ekleme. Menünün ortasında ve diğerlerinden '
              'büyük duruyor — en sık yapacağın iş bu.',
        ),
        _Adim(
          vurgu: 3,
          baslik: 'Performans',
          govde: 'Grafikler ve kâr/zarar dökümü. Gün içinden bir yıla kadar '
              'her dönemi görebilirsin.',
        ),
        _Adim(
          vurgu: 4,
          baslik: 'Profil',
          govde: 'Ortaklık, bildirimler, sinyal ayarları, fiyat alarmları, '
              'tema ve yasal belgeler burada.',
        ),
      ],
    ),

    // ── 3. Ana ekran ─────────────────────────────────────────────────────
    _Sahne(
      ekran: 'Ana',
      mock: _MockTur.anaEkran,
      adimlar: [
        const _Adim(
          vurgu: 0,
          baslik: 'Toplam birikimin',
          govde: 'Tüm varlıkların tek toplamda. Altındaki satır bugün ne '
              'kadar kazandığını ya da kaybettiğini söyler.',
        ),
        const _Adim(
          vurgu: 1,
          baslik: 'Yenile',
          govde: 'Fiyatlar zaten arka planda güncelleniyor; bu tuş "şimdi '
              'çek" demek. Ekranı aşağı çekerek de yapabilirsin.',
        ),
        const _Adim(
          vurgu: 2,
          baslik: 'Tutarları gizle',
          govde: 'Göz simgesi bakiyeleri gizler. Toplu taşımada ya da omzunun '
              'üstünden bakan biri varken tek dokunuş yeter.',
        ),
        if (tufeVar)
          const _Adim(
            vurgu: 3,
            rozet: 'BİZE ÖZEL',
            baslik: 'Enflasyonu geçtin mi?',
            govde: 'Getirini TÜFE ile karşılaştırıyoruz. "%40 kazandım" tek '
                'başına bir şey söylemez; asıl soru enflasyonun kaç puan '
                'üstünde kaldığın.',
          ),
        if (yarisVar)
          const _Adim(
            vurgu: 4,
            rozet: 'BİZE ÖZEL',
            baslik: 'Yarış',
            govde: 'Getirini diğer kullanıcılarla ANONİM olarak karşılaştır — '
                'hangi yüzdelik dilimdesin? Kimse senin tutarlarını görmez, '
                'sen de kimseninkini.',
          ),
      ],
    ),

    // ── 4. Portföy ───────────────────────────────────────────────────────
    const _Sahne(
      ekran: 'Portföy',
      mock: _MockTur.portfoy,
      adimlar: [
        _Adim(
          vurgu: 0,
          baslik: 'Dağılım halkası',
          govde: 'Paran hangi türde ne kadar? Bir türe dokunarak alttaki '
              'listeyi ona göre süzebilirsin.',
        ),
        _Adim(
          vurgu: 1,
          baslik: 'Varlık kartını aç',
          // Yön ÖNEMLİ: sağa kaydırma Al/Sat/Temettü panelini, sola
          // kaydırma yalnızca Sil'i açar (bkz. charts_screen.dart →
          // startActionPane / endActionPane). Tek bir "kaydır" demek,
          // kullanıcının yanlış yöne kaydırıp hiçbir şey bulamaması
          // demekti.
          govde: 'Karttaki oka dokun: son bir ayın fiyat eğrisi, ortalama '
              'maliyetin ve tahsil ettiğin temettü açılır. Kartı sağa '
              'kaydırınca Al / Sat / Temettü, sola kaydırınca Sil çıkar.',
        ),
        _Adim(
          vurgu: 2,
          baslik: 'Takip listesi',
          govde: 'Sahip OLMADIĞIN varlıkları da izleyebilirsin. Almayı '
              'düşündüğün hisseyi listeye at, fiyat alarmı kur; portföyünün '
              'toplamına karışmaz.',
        ),
      ],
    ),

    // ── 5. Varlık ekleme ─────────────────────────────────────────────────
    const _Sahne(
      ekran: 'Varlık ekle',
      mock: _MockTur.varlikEkle,
      adimlar: [
        _Adim(
          vurgu: 0,
          baslik: 'Önce türü seç',
          govde: 'Hisse mi, fon mu, altın mı? Tür seçtiğinde form ona göre '
              'değişir — altında gram, hissede adet sorulur.',
        ),
        _Adim(
          vurgu: 1,
          baslik: 'Miktar ve maliyet',
          govde: 'Ne kadar aldığını ve kaça aldığını gir. Anlık değer ile '
              'kâr/zarar bundan sonra kendiliğinden hesaplanır.',
        ),
        _Adim(
          vurgu: 2,
          rozet: 'BİZE ÖZEL',
          baslik: 'Hızlı Giriş — cümleyle ekle',
          govde: 'Üstteki mikrofon tuşu Hızlı Giriş\'i açar: "10 gram altın '
              '4500 lira" ya da "GARAN 500 adet" yazman (veya söylemen) '
              'yeter. Her satır ayrı bir varlık olur; fiyat yazmazsan güncel '
              'fiyat kendiliğinden çekilir.',
        ),
        _Adim(
          vurgu: 3,
          baslik: 'Toplu Ekle — sepet',
          govde: 'Birden çok varlığı sepete atıp tek onayda kaydedebilirsin. '
              'Portföyünü ilk kez kurarken en hızlı yol bu.',
        ),
      ],
    ),

    // ── 6. Performans ────────────────────────────────────────────────────
    const _Sahne(
      ekran: 'Performans',
      mock: _MockTur.performans,
      adimlar: [
        _Adim(
          vurgu: 0,
          baslik: 'Dönem seç',
          govde: 'GÜNLÜK gün içini saat saat çizer; 1H / 1A / 6A / 1Y daha '
              'geniş pencereler. Grafiği iki parmakla yakınlaştırabilir, bir '
              'noktaya basılı tutarak o anın değerini okuyabilirsin.',
        ),
        _Adim(
          vurgu: 1,
          rozet: 'BİZE ÖZEL',
          baslik: 'Gerçek / Simülasyon',
          govde: 'Gerçek, dönem içindeki her alım ve satımla birlikte gerçek '
              'geçmişini çizer. Simülasyon ise "bugünkü portföyümü baştan '
              'elimde tutsaydım ne olurdu?" sorusunu yanıtlar.',
        ),
        _Adim(
          vurgu: 2,
          rozet: 'BİZE ÖZEL',
          baslik: 'Birlikte / Ben',
          govde: 'Eşinle ya da iş ortağınla portföylerinizi tek ekranda '
              'görebilirsiniz. "Birlikte" ikinizin toplamı, "Ben" yalnız '
              'senin. Kimse diğerinin kaydını değiştiremez.',
        ),
      ],
    ),

    // ── 7. Teknik sinyaller ──────────────────────────────────────────────
    const _Sahne(
      ekran: 'Sinyaller',
      mock: _MockTur.sinyal,
      adimlar: [
        _Adim(
          vurgu: 0,
          rozet: 'BİZE ÖZEL',
          baslik: 'Hangi gösterge ne diyor?',
          govde: 'RSI, MACD, Bollinger, EMA ve diğerleri her varlığın '
              'performans ekranında tek tek listelenir: kaçı AL, kaçı SAT '
              'diyor, hangi değerle. Kararı kutunun içinde saklamıyoruz.',
        ),
        _Adim(
          vurgu: 1,
          baslik: 'Yön değişince haber ver',
          govde: 'Portföyün düzenli olarak analiz edilir; sinyal yön '
              'değiştirdiğinde bildirim gelir. Hangi göstergelerin '
              'çalışacağını Profil → Sinyal Ayarları\'ndan sen seçersin.\n\n'
              'Bunlar yatırım tavsiyesi değildir.',
        ),
      ],
    ),

    // ── 8. Profil ────────────────────────────────────────────────────────
    _Sahne(
      ekran: 'Profil',
      mock: _MockTur.profil,
      adimlar: [
        const _Adim(
          vurgu: 0,
          rozet: 'BİZE ÖZEL',
          baslik: 'Ortaklık — davet kodun',
          govde: 'Kodunu eşine gönder ya da onunkini gir. Karşı taraf '
              'onayladığında portföyleriniz tek ekranda birleşir — istediğiniz '
              'an ayırabilirsiniz.',
        ),
        _Adim(
          vurgu: 1,
          baslik: premiumVar ? 'Premium ve ayarlar' : 'Ayarlar burada',
          govde: premiumVar
              ? 'Ücretsiz plan ${rc.freeAssetLimit} varlıkla sınırlı; Premium '
                  'sınırsız varlık ve gelişmiş göstergeler açar. Bildirimler, '
                  'sinyal ayarları, fiyat alarmları ve yasal belgeler ise '
                  'Ayarlar\'ın altında.'
              : 'Ayarlar\'a buradan girilir: bildirimler, sinyal ayarları, '
                  'fiyat alarmları, tema ve yasal belgeler.',
        ),
      ],
    ),

    // ── 9. Kapanış ───────────────────────────────────────────────────────
    const _Sahne(
      ekran: 'Hazırsın',
      mock: _MockTur.yok,
      ikon: Icons.check_circle_rounded,
      adimlar: [
        _Adim(
          baslik: 'İlk varlığını ekleyelim',
          // "Her kayıt geri alınabilir" gibi bir söz VERİLMEZ: uygulamada
          // geri alma yok, silme kalıcıdır. Tanıtımda verilen tutulamayan
          // söz, tanıtımın tamamına olan güveni bozar.
          govde: 'Alttaki + tuşuna dokun ve bir varlık ekle; gerisi '
              'kendiliğinden gelir.\n\n'
              'Bir şeyi yanlış girdiysen Portföy\'deki kartı kaydırıp '
              'düzeltebilir ya da silebilirsin. Takıldığın yerde her ekranın '
              'kendi açıklaması var.',
        ),
      ],
    ),
  ];
}

/// HIG'in en küçük dokunma hedefi: 44×44pt (Human Interface Guidelines →
/// Controls). Boşluk ölçeğine ait bir sayı DEĞİL — Apple'ın sabiti; bu
/// yüzden `SandikSpace` içinden seçilmez.
const double _higHedef = 44;

/// Turu süren durum.
///
/// İki eksen var ve karıştırılmamalı:
/// - **Sahne** = ekran. `PageView` sayfası; parmakla kaydırılır, alttaki
///   noktalar bunları sayar.
/// - **Adım** = o ekrandaki tek bir tuş. "İleri" bunu ilerletir; sahne
///   değişmeden vurgu bir sonraki öğeye geçer.
///
/// Kullanıcının isteği "her tuşu tek tek tanıt" idi; tek eksenli bir
/// PageView'da bu 22 sayfa ve 22 nokta demekti — ilerleme çubuğu hiç
/// bitmiyormuş gibi görünür. İki eksen, "9 ekran öğreniyorum, bu ekranın
/// 3. tuşundayım" duygusunu verir.
class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final List<_Sahne> _sahneler = _turuKur();
  late final PageController _pages = PageController();

  late AnimationController _anim;
  late Animation<double> _fade;

  int _sahne = 0;
  int _adim = 0;

  _Sahne get _aktifSahne => _sahneler[_sahne];

  bool get _ilkAdim => _sahne == 0 && _adim == 0;
  bool get _sonAdim =>
      _sahne == _sahneler.length - 1 && _adim == _aktifSahne.adimlar.length - 1;

  /// Analytics için düz sayaç — `logOnboardingSkipped` "kaçıncı adımda
  /// bıraktı" sorusunu yanıtlıyor, sahne indeksi bunu yanıtlamaz.
  int get _duzAdim {
    var n = _adim;
    for (var i = 0; i < _sahne; i++) {
      n += _sahneler[i].adimlar.length;
    }
    return n;
  }

  @override
  void initState() {
    super.initState();
    // Beliriş SAYFA BAŞINA DEĞİL, ekran açılışına aittir: `PageView` bir
    // sonraki sayfayı önden kurduğu için sayfa başına yapılırsa kullanıcı
    // parmağını sürerken sayfa yeniden belirir ve titrer.
    _anim = AnimationController(vsync: this, duration: SandikMotion.surface);
    _fade = CurvedAnimation(parent: _anim, curve: SandikMotion.enter);
    _anim.forward();
  }

  @override
  void dispose() {
    _pages.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _ileri() async {
    // Önce o ekranın tuşlarını bitir, sonra ekranı değiştir.
    if (_adim < _aktifSahne.adimlar.length - 1) {
      setState(() => _adim++);
      return;
    }
    if (_sahne == _sahneler.length - 1) {
      AnalyticsService.instance.logOnboardingCompleted();
      await OnboardingScreen.markCompleted(widget.userId);
      if (mounted) widget.onComplete();
      return;
    }
    await _pages.nextPage(
      duration: SandikMotion.surfaceOf(context),
      curve: SandikMotion.enter,
    );
  }

  Future<void> _geriAl() async {
    if (_adim > 0) {
      setState(() => _adim--);
      return;
    }
    if (_sahne == 0) return;
    await _pages.previousPage(
      duration: SandikMotion.surfaceOf(context),
      curve: SandikMotion.enter,
    );
  }

  Future<void> _atla() async {
    AnalyticsService.instance.logOnboardingSkipped(_duzAdim);
    await OnboardingScreen.markCompleted(widget.userId);
    if (mounted) widget.onComplete();
  }

  void _sayfaDegisti(int i) {
    setState(() {
      // Geriye gidiliyorsa o ekranın SON tuşuna dön: kullanıcı bıraktığı
      // yere döner, ekranın başına fırlatılmaz.
      final geri = i < _sahne;
      _sahne = i;
      _adim = geri ? _sahneler[i].adimlar.length - 1 : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    // Zemin TEMADAN gelir: bu ekran bir overlay değil, tam sayfadır
    // (bkz. `main.dart` — açılış akışında `MainNavigationScreen` yerine
    // döner). Sabit koyu bir zemin, açık temada uygulamanın geri kalanıyla
    // hiç uyuşmayan bir giriş yaratıyordu.
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Column(
          children: [
            _ustCubuk(context),
            Expanded(
              child: FadeTransition(
                opacity: _fade,
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _sahneler.length,
                  onPageChanged: _sayfaDegisti,
                  itemBuilder: (context, i) => _SahneGorunumu(
                    sahne: _sahneler[i],
                    // Komşu sayfalar önden kurulur; onlar kendi ilk
                    // adımlarını göstersin.
                    adimIndex: i == _sahne ? _adim : 0,
                  ),
                ),
              ),
            ),
            _noktalar(context),
            _ileriButonu(context),
          ],
        ),
      ),
    );
  }

  // ── Üst çubuk: geri · nerede olduğun · atla ────────────────────────────
  //
  // Ortadaki etiket "hangi ekranı öğreniyorum ve bu ekranın kaçıncı
  // tuşundayım" sorusunu yanıtlar. Kullanıcının isteği tanıtımın "kafada
  // soru işareti bırakmaması" idi; konum belirsizliği bu soruların en
  // yaygını.
  Widget _ustCubuk(BuildContext context) {
    final p = context.c;
    final toplam = _aktifSahne.adimlar.length;
    final etiket =
        toplam > 1 ? '${_aktifSahne.ekran} · ${_adim + 1}/$toplam' : _aktifSahne.ekran;

    return SizedBox(
      height: _higHedef,
      child: Row(
        children: [
          // Geri, yalnızca dönülecek bir adım varken yer kaplar.
          if (!_ilkAdim)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md),
              minimumSize: const Size(_higHedef, _higHedef),
              onPressed: _geriAl,
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: p.text58),
            )
          else
            const SizedBox(width: _higHedef),
          Expanded(
            child: Center(
              child: Text(
                etiket,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelLarge?.copyWith(
                  color: p.text36,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          CupertinoButton(
            // HIG 44pt: metin 14pt olduğu için sıfır padding'de dokunma
            // hedefi ~18pt'ye düşüyordu.
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md),
            minimumSize: const Size(_higHedef, _higHedef),
            onPressed: _atla,
            child: Text(
              'Atla',
              style: context.t.titleMedium?.copyWith(color: p.text58),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sahne noktaları ────────────────────────────────────────────────────
  //
  // Nokta sayısı EKRAN sayısıdır. Aktif nokta bir çubuğa uzar ve içi o
  // ekranda kaç tuş geçildiğine göre dolar — böylece hem "9 ekrandan
  // 4.'sindeyim" hem "bu ekranın 2/5'indeyim" tek bir öğeden okunur.
  Widget _noktalar(BuildContext context) {
    final p = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_sahneler.length, (i) {
          final aktif = i == _sahne;
          final dolu = aktif
              ? (_adim + 1) / _sahneler[i].adimlar.length
              : (i < _sahne ? 1.0 : 0.0);
          return AnimatedContainer(
            duration: SandikMotion.stateOf(context),
            curve: SandikMotion.enter,
            margin: const EdgeInsets.symmetric(horizontal: SandikSpace.xxs),
            width: aktif ? 28 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: p.text20,
              borderRadius: BorderRadius.circular(SandikRadius.sm),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: dolu,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.amberFill,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _ileriButonu(BuildContext context) {
    final p = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          SandikSpace.lg, SandikSpace.lgs, SandikSpace.lg, SandikSpace.lg),
      child: SizedBox(
        width: double.infinity,
        child: CupertinoButton(
          onPressed: _ileri,
          padding: EdgeInsets.zero,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: p.amberFill,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              boxShadow: [
                BoxShadow(
                  color: p.amberFill.withValues(alpha: 0.28),
                  blurRadius: 18,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              _sonAdim ? 'Sandığımı Aç' : 'İleri',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: p.onAmber,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tek bir sahne: minyatür + o adımın açıklaması.
///
/// Kendi içinde kaydırılabilir. Sabit yükseklikli bir yığın, sistem yazı
/// tipi büyütülmüşken (erişilebilirlik ayarı) ya da kısa ekranlarda
/// RenderFlex taşması veriyordu; burada taşma yerine kaydırma olur.
class _SahneGorunumu extends StatelessWidget {
  const _SahneGorunumu({required this.sahne, required this.adimIndex});

  final _Sahne sahne;
  final int adimIndex;

  @override
  Widget build(BuildContext context) {
    final adim = sahne.adimlar[adimIndex];
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.lg, vertical: SandikSpace.md),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Mock(tur: sahne.mock, ikon: sahne.ikon, vurgu: adim.vurgu),
            const SizedBox(height: SandikSpace.lgs),
            _AdimKarti(adim: adim),
          ],
        ),
      ),
    );
  }
}

/// Adım metni — rozet, başlık, gövde.
class _AdimKarti extends StatelessWidget {
  const _AdimKarti({required this.adim});

  final _Adim adim;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Semantics(
      // Adım değişince ekran okuyucu yeni metni kendiliğinden okusun:
      // görme engelli kullanıcı "İleri"ye bastığında sayfa değişmiyor,
      // yalnızca bu blok değişiyor.
      liveRegion: true,
      child: AnimatedSize(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(SandikSpace.lg),
          decoration: BoxDecoration(
            color: p.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.lg),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (adim.rozet case final r?) ...[
                _Rozet(metin: r),
                const SizedBox(height: SandikSpace.smd),
              ],
              Text(
                adim.baslik,
                style: context.t.headlineSmall?.copyWith(
                  color: p.text90,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: SandikSpace.sm),
              Text(
                adim.govde,
                style: context.t.titleMedium?.copyWith(
                  color: p.text58,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "BİZE ÖZEL" rozeti.
///
/// Kullanıcının isteğinde ayrı bir madde: "bizi diğer uygulamalardan ayırt
/// eden özelliklerimiz özellikle vurgulanmalı". Rozet yalnızca o
/// özelliklerde çıkar — her adıma konulsa hiçbir şey vurgulanmamış olurdu.
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
          color: p.amberFill,
          borderRadius: BorderRadius.circular(SandikRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 12, color: p.onAmber),
            const SizedBox(width: SandikSpace.xs2),
            // Flexible şart: `Wrap`/`Row` çocuğa kendi genişliğini üst sınır
            // olarak verir, `mainAxisSize.min` taşmayı engellemez.
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

// ─── Vurgu ───────────────────────────────────────────────────────────────────

/// Minyatürdeki tek bir öğeyi öne çıkaran sarmalayıcı.
///
/// Vurgu bir piksel koordinatı ya da `Positioned` DEĞİL: vurgulanacak öğe
/// doğrudan bununla sarılır. Böylece metin ölçeği, ekran genişliği veya
/// yazı tipi değişse de halka her zaman doğru öğenin çevresinde kalır —
/// koordinatlı bir "spotlight" ilk Dynamic Type kademesinde kayardı.
///
/// Pasif öğeler silinmez, SÖNÜKLEŞİR: kullanıcı tuşun ekrandaki
/// komşularını görmeye devam eder, yoksa öğrendiği şeyin nerede durduğunu
/// bilemez.
class _Vurgu extends StatelessWidget {
  const _Vurgu({required this.aktif, required this.child});

  final bool aktif;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return AnimatedOpacity(
      duration: SandikMotion.stateOf(context),
      curve: SandikMotion.enter,
      opacity: aktif ? 1 : 0.32,
      child: AnimatedContainer(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        // Dolgu her durumda var: yalnızca aktifken eklenseydi vurgu her
        // adımda yerleşimi oynatır, minyatür zıplardı.
        padding: const EdgeInsets.all(SandikSpace.xs),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SandikRadius.sm),
          color: aktif
              ? p.amberFill.withValues(alpha: 0.14)
              : const Color(0x00000000),
          border: Border.all(
            color: aktif ? p.amberFill : const Color(0x00000000),
            width: 1.5,
          ),
        ),
        child: child,
      ),
    );
  }
}

// ─── Minyatür ekranlar ───────────────────────────────────────────────────────

/// Sahnenin minyatürü.
///
/// Metin ölçeği burada SINIRLANIR (1,2×). Minyatür bir diyagramdır,
/// okunacak gövde metni değil — 2,0× sistem yazı tipinde şema kırılır ve
/// hiçbir şey anlatmaz. Asıl açıklama ([_AdimKarti]) tam ölçeğinde kalır,
/// yani erişilebilirlik ayarından bir şey kaybedilmez.
class _Mock extends StatelessWidget {
  const _Mock({required this.tur, required this.vurgu, this.ikon});

  final _MockTur tur;
  final int? vurgu;
  final IconData? ikon;

  bool _v(int i) => vurgu == i;

  @override
  Widget build(BuildContext context) {
    if (tur == _MockTur.yok) {
      return _Spot(ikon: ikon ?? Icons.savings_rounded);
    }
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: _Cerceve(child: _icerik(context)),
    );
  }

  Widget _icerik(BuildContext context) {
    switch (tur) {
      case _MockTur.altMenu:
        return _altMenu(context);
      case _MockTur.anaEkran:
        return _anaEkran(context);
      case _MockTur.portfoy:
        return _portfoy(context);
      case _MockTur.varlikEkle:
        return _varlikEkle(context);
      case _MockTur.performans:
        return _performans(context);
      case _MockTur.sinyal:
        return _sinyal(context);
      case _MockTur.profil:
        return _profil(context);
      case _MockTur.yok:
        return const SizedBox.shrink();
    }
  }

  // ── Alt menü ─────────────────────────────────────────────────────────
  Widget _altMenu(BuildContext context) {
    final p = context.c;
    return Column(
      children: [
        // Menünün üstünde ne olduğu belli olsun diye soluk bir gövde
        // taslağı: çubuk tek başına havada dursa "ekranın neresi burası"
        // sorusu doğar.
        const _Iskelet(satir: 3),
        const SizedBox(height: SandikSpace.smd),
        Divider(height: 1, thickness: 1, color: p.hairline),
        const SizedBox(height: SandikSpace.sm),
        Row(
          children: [
            Expanded(
              child: _Vurgu(
                aktif: _v(0),
                child: _navOge(context, Icons.home_rounded, 'Ana', secili: true),
              ),
            ),
            Expanded(
              child: _Vurgu(
                aktif: _v(1),
                child: _navOge(context, Icons.donut_large_rounded, 'Portföy'),
              ),
            ),
            Expanded(
              child: _Vurgu(aktif: _v(2), child: _fabOge(context)),
            ),
            Expanded(
              child: _Vurgu(
                aktif: _v(3),
                child: _navOge(context, Icons.show_chart_rounded, 'Performans'),
              ),
            ),
            Expanded(
              child: _Vurgu(
                aktif: _v(4),
                child: _navOge(context, Icons.person_rounded, 'Profil'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _navOge(BuildContext context, IconData ikon, String etiket,
      {bool secili = false}) {
    final p = context.c;
    final renk = secili ? p.amberText : p.text36;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ikon, size: 20, color: renk),
        const SizedBox(height: SandikSpace.xs),
        // Dar cihazda 'Performans' beş sütunun birine sığmaz; kırpmak
        // yerine küçültülür — etiketin tamamı okunabilir kalır.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            etiket,
            maxLines: 1,
            style: context.t.labelSmall?.copyWith(color: renk),
          ),
        ),
      ],
    );
  }

  Widget _fabOge(BuildContext context) {
    final p = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: p.amberFill,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.add_rounded, size: 20, color: p.onAmber),
        ),
        const SizedBox(height: SandikSpace.xs),
        // FAB'ın etiketi yok; boşluk, diğer dört sütunla aynı yüksekliği
        // tutar — yoksa çubuk dişli görünür.
        Text(' ', style: context.t.labelSmall),
      ],
    );
  }

  // ── Ana ekran ────────────────────────────────────────────────────────
  Widget _anaEkran(BuildContext context) {
    final p = context.c;
    final rc = RemoteConfigService.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'sandık',
              style: context.t.titleMedium?.copyWith(
                color: p.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            _Vurgu(
              aktif: _v(1),
              child: _ikonKare(context, Icons.refresh_rounded),
            ),
            const SizedBox(width: SandikSpace.xs),
            _Vurgu(
              aktif: _v(2),
              child: _ikonKare(context, Icons.visibility_rounded),
            ),
          ],
        ),
        const SizedBox(height: SandikSpace.sm),
        _Vurgu(aktif: _v(0), child: _bakiye(context)),
        if (rc.realReturnEnabled) ...[
          const SizedBox(height: SandikSpace.xs2),
          _Vurgu(
            aktif: _v(3),
            child: _serit(context, Icons.trending_up_rounded,
                'Enflasyon üstü getiri', '+%12,4', p.gain),
          ),
        ],
        if (rc.percentileStripEnabled) ...[
          const SizedBox(height: SandikSpace.xs2),
          _Vurgu(
            aktif: _v(4),
            child: _serit(context, Icons.emoji_events_rounded, 'Yarış',
                'İlk %18', p.amberText),
          ),
        ],
      ],
    );
  }

  Widget _bakiye(BuildContext context) {
    final p = context.c;
    return _Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Toplam Birikim',
              style: context.t.labelMedium?.copyWith(color: p.text36)),
          const SizedBox(height: SandikSpace.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '₺248.350',
              style: context.t.headlineSmall?.copyWith(
                color: p.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            // Yön hem renkle hem GLİFLE anlatılır: marka yeşili ile
            // kırmızısı renk körlüğü altında yeterince ayrışmıyor.
            '▲ ₺3.120 · %1,27',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.labelLarge?.copyWith(color: p.gain),
          ),
        ],
      ),
    );
  }

  Widget _serit(BuildContext context, IconData ikon, String etiket,
      String deger, Color renk) {
    final p = context.c;
    return _Tile(
      child: Row(
        children: [
          Icon(ikon, size: 14, color: renk),
          const SizedBox(width: SandikSpace.xs2),
          Expanded(
            child: Text(
              etiket,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.labelLarge?.copyWith(color: p.text58),
            ),
          ),
          Text(
            deger,
            maxLines: 1,
            style: context.t.labelLarge?.copyWith(
              color: renk,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── Portföy ──────────────────────────────────────────────────────────
  Widget _portfoy(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Gerçek ekranda takip listesi seçicisi gövdenin EN ÜSTÜNDE durur;
        // minyatür de aynı yerde göstermeli, yoksa kullanıcı tuşu
        // aradığında bulamaz.
        _Vurgu(
          aktif: _v(2),
          child: _segment(context, const ['Varlıklarım', 'Takip Listesi'], 0),
        ),
        const SizedBox(height: SandikSpace.sm),
        _Vurgu(aktif: _v(0), child: _halka(context)),
        const SizedBox(height: SandikSpace.xs2),
        _Vurgu(aktif: _v(1), child: _varlikSatiri(context)),
      ],
    );
  }

  Widget _halka(BuildContext context) {
    final p = context.c;
    final dilimler = <(String, String, Color)>[
      ('Hisse', '%46', p.amberFill),
      ('Fon', '%31', p.info),
      ('Altın', '%23', p.gold),
    ];
    return _Tile(
      child: Row(
        children: [
          SizedBox(
            width: SandikSpace.xxl,
            height: SandikSpace.xxl,
            child: CircularProgressIndicator(
              value: 0.46,
              strokeWidth: 7,
              color: p.amberFill,
              backgroundColor: p.hairline,
            ),
          ),
          const SizedBox(width: SandikSpace.smd),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (ad, pay, renk) in dilimler)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SandikSpace.xxs),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration:
                              BoxDecoration(color: renk, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: SandikSpace.xs2),
                        Expanded(
                          child: Text(
                            ad,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.labelLarge
                                ?.copyWith(color: p.text58),
                          ),
                        ),
                        Text(
                          pay,
                          style: context.t.labelLarge?.copyWith(color: p.text90),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _varlikSatiri(BuildContext context) {
    final p = context.c;
    return _Tile(
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.amberFill.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(SandikRadius.sm),
            ),
            child: Text(
              'THY',
              style: context.t.labelSmall?.copyWith(
                color: p.amberText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Türk Hava Yolları',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelLarge?.copyWith(color: p.text90),
                ),
                Text(
                  '120 adet',
                  maxLines: 1,
                  style: context.t.labelSmall?.copyWith(color: p.text36),
                ),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '₺38.208',
                maxLines: 1,
                style: context.t.labelLarge?.copyWith(color: p.text90),
              ),
              Text(
                '▲ %2,1',
                maxLines: 1,
                style: context.t.labelSmall?.copyWith(color: p.gain),
              ),
            ],
          ),
          Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: p.text36),
        ],
      ),
    );
  }

  // ── Varlık ekle ──────────────────────────────────────────────────────
  Widget _varlikEkle(BuildContext context) {
    final p = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Varlık Ekle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.titleMedium?.copyWith(color: p.text90),
              ),
            ),
            // Minyatürdeki simgeler GERÇEK ekrandakilerle aynı olmalı:
            // kullanıcı burada gördüğü tuşu orada arayacak. Hızlı Giriş'in
            // giriş noktası mikrofon (⚡ sheet'in kendi başlığında),
            // toplu ekleme ise liste simgesi.
            _Vurgu(
              aktif: _v(2),
              child: _ikonKare(context, Icons.mic_none_rounded, marka: true),
            ),
            const SizedBox(width: SandikSpace.xs),
            _Vurgu(
              aktif: _v(3),
              child: _ikonKare(context, Icons.playlist_add_rounded),
            ),
          ],
        ),
        const SizedBox(height: SandikSpace.sm),
        _Vurgu(
          aktif: _v(0),
          child: Wrap(
            spacing: SandikSpace.xs2,
            runSpacing: SandikSpace.xs2,
            children: [
              for (final (ad, secili) in const [
                ('Hisse', true),
                ('Fon', false),
                ('Altın', false),
                ('Döviz', false),
              ])
                _cip(context, ad, secili: secili),
            ],
          ),
        ),
        const SizedBox(height: SandikSpace.sm),
        _Vurgu(
          aktif: _v(1),
          child: Column(
            children: [
              _alan(context, 'Miktar', '120'),
              const SizedBox(height: SandikSpace.xs2),
              _alan(context, 'Alış fiyatı', '₺311,80'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _alan(BuildContext context, String etiket, String deger) {
    final p = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm2, vertical: SandikSpace.sm),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              etiket,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.labelLarge?.copyWith(color: p.text36),
            ),
          ),
          Text(
            deger,
            maxLines: 1,
            style: context.t.labelLarge?.copyWith(color: p.text90),
          ),
        ],
      ),
    );
  }

  // ── Performans ───────────────────────────────────────────────────────
  Widget _performans(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Vurgu(
          aktif: _v(2),
          child: _segment(context, const ['Birlikte', 'Ben'], 1),
        ),
        const SizedBox(height: SandikSpace.sm),
        _Vurgu(
          aktif: _v(0),
          child: _segment(context, const ['GÜNLÜK', '1H', '1A', '1Y'], 1),
        ),
        const SizedBox(height: SandikSpace.sm),
        _grafik(context),
        const SizedBox(height: SandikSpace.sm),
        _Vurgu(
          aktif: _v(1),
          child: _segment(context, const ['Gerçek', 'Simülasyon'], 0),
        ),
      ],
    );
  }

  /// Süs grafiği — bir adımı temsil etmez, minyatürün "performans ekranı"
  /// olduğunu tek bakışta anlatır.
  Widget _grafik(BuildContext context) {
    final p = context.c;
    const oranlar = [0.35, 0.5, 0.42, 0.62, 0.55, 0.74, 0.68, 0.86, 1.0];
    return SizedBox(
      height: SandikSpace.xxl,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final o in oranlar)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xxs),
                child: FractionallySizedBox(
                  heightFactor: o,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.gain.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Sinyaller ────────────────────────────────────────────────────────
  Widget _sinyal(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Vurgu(aktif: _v(0), child: _dagilim(context)),
        const SizedBox(height: SandikSpace.sm),
        _Vurgu(aktif: _v(1), child: _bildirim(context)),
      ],
    );
  }

  Widget _dagilim(BuildContext context) {
    final p = context.c;
    // Performans ekranındaki gerçek dağılım çubuğunun küçük kardeşi —
    // aynı glif + metin ikili kodlaması, aynı renkler.
    final paylar = <(int, String, String, Color)>[
      (4, '▲', 'AL', p.gain),
      (2, '▼', 'SAT', p.loss),
      (1, '◆', 'NÖTR', p.text36),
    ];
    return _Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 10,
            child: Row(
              children: [
                for (final (pay, _, _, renk) in paylar)
                  Expanded(
                    flex: pay,
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: SandikSpace.xxs),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: renk,
                          borderRadius: BorderRadius.circular(SandikRadius.sm),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          Wrap(
            spacing: SandikSpace.smd,
            runSpacing: SandikSpace.xs,
            children: [
              for (final (pay, glif, ad, renk) in paylar)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(glif,
                        style: context.t.labelSmall?.copyWith(color: renk)),
                    const SizedBox(width: SandikSpace.xs),
                    Text(
                      '$ad $pay',
                      maxLines: 1,
                      style: context.t.labelLarge?.copyWith(color: p.text58),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bildirim(BuildContext context) {
    final p = context.c;
    return _Tile(
      child: Row(
        children: [
          Icon(Icons.notifications_active_rounded, size: 16, color: p.amberText),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'THYAO · AL sinyali',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelLarge?.copyWith(color: p.text90),
                ),
                Text(
                  '6 göstergeden 4\'ü AL diyor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelSmall?.copyWith(color: p.text36),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Profil ───────────────────────────────────────────────────────────
  Widget _profil(BuildContext context) {
    final p = context.c;
    final rc = RemoteConfigService.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Vurgu(
          aktif: _v(0),
          child: _Tile(
            child: Row(
              children: [
                Icon(Icons.people_alt_rounded, size: 16, color: p.amberText),
                const SizedBox(width: SandikSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Davet kodun',
                        maxLines: 1,
                        style:
                            context.t.labelSmall?.copyWith(color: p.text36),
                      ),
                      Text(
                        'S7K-M2Q4',
                        maxLines: 1,
                        style: context.t.labelLarge?.copyWith(
                          color: p.text90,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.copy_rounded, size: 14, color: p.text36),
              ],
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.xs2),
        _Vurgu(
          aktif: _v(1),
          child: Column(
            children: [
              if (rc.paywallEnabled && rc.premiumEnabled)
                _profilSatiri(
                    context, Icons.workspace_premium_rounded, 'Premium'),
              // Bunlar Profil'in ALTINDAKİ Ayarlar sayfasında; minyatür de
              // onları oraya götüren satırlar olarak gösteriyor.
              _profilSatiri(context, Icons.settings_rounded, 'Ayarlar'),
              _profilSatiri(context, Icons.insights_rounded, 'Sinyal ayarları'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _profilSatiri(BuildContext context, IconData ikon, String ad) {
    final p = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.xs),
      child: _Tile(
        child: Row(
          children: [
            Icon(ikon, size: 15, color: p.text58),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: Text(
                ad,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelLarge?.copyWith(color: p.text90),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: p.text36),
          ],
        ),
      ),
    );
  }

  // ── Ortak parçalar ───────────────────────────────────────────────────
  Widget _ikonKare(BuildContext context, IconData ikon, {bool marka = false}) {
    final p = context.c;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: marka ? p.amberFill.withValues(alpha: 0.18) : p.background,
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        border: Border.all(color: p.hairline),
      ),
      child: Icon(ikon, size: 15, color: marka ? p.amberText : p.text58),
    );
  }

  Widget _cip(BuildContext context, String ad, {bool secili = false}) {
    final p = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm2, vertical: SandikSpace.xs2),
      decoration: BoxDecoration(
        color: secili ? p.amberFill : p.background,
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        border: Border.all(color: p.hairline),
      ),
      child: Text(
        ad,
        maxLines: 1,
        style: context.t.labelLarge?.copyWith(
          color: secili ? p.onAmber : p.text58,
          fontWeight: secili ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, List<String> etiketler, int seciliIdx) {
    final p = context.c;
    return Container(
      padding: const EdgeInsets.all(SandikSpace.xxs),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          for (var i = 0; i < etiketler.length; i++)
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: SandikSpace.xs2),
                alignment: Alignment.center,
                decoration: i == seciliIdx
                    ? BoxDecoration(
                        color: p.surface2,
                        borderRadius: BorderRadius.circular(SandikRadius.sm),
                      )
                    : null,
                // Dört dönem etiketi dar cihazda sığmaz; kırpmak yerine
                // küçültülür.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    etiketler[i],
                    maxLines: 1,
                    style: context.t.labelLarge?.copyWith(
                      color: i == seciliIdx ? p.text90 : p.text36,
                      fontWeight:
                          i == seciliIdx ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Minyatürün çerçevesi — bir uygulama ekranı olduğunu belli eder.
class _Cerceve extends StatelessWidget {
  const _Cerceve({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Container(
      padding: const EdgeInsets.all(SandikSpace.smd),
      decoration: BoxDecoration(
        color: p.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        border: Border.all(color: p.hairline),
      ),
      child: child,
    );
  }
}

/// Çerçeve içindeki tek bir kart/satır.
class _Tile extends StatelessWidget {
  const _Tile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Container(
      padding: const EdgeInsets.all(SandikSpace.sm2),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        border: Border.all(color: p.hairline),
      ),
      child: child,
    );
  }
}

/// İçeriği olmayan gövde taslağı — "burada bir liste var" demenin en ucuz
/// yolu. Sahte veri uydurmaz, bu yüzden yanlış da olamaz.
class _Iskelet extends StatelessWidget {
  const _Iskelet({required this.satir});

  final int satir;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Column(
      children: [
        for (var i = 0; i < satir; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: SandikSpace.xs2),
            child: Row(
              children: [
                Expanded(
                  flex: 3 + i,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                    ),
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
      ],
    );
  }
}

/// Minyatürü olmayan sahnelerin (karşılama, kapanış) simgesi.
class _Spot extends StatelessWidget {
  const _Spot({required this.ikon});

  final IconData ikon;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.amberFill.withValues(alpha: 0.12),
          border: Border.all(
            color: p.amberFill.withValues(alpha: 0.40),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: p.amberFill.withValues(alpha: 0.25),
              blurRadius: 40,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Icon(ikon, size: 48, color: p.amberText),
      ),
    );
  }
}
