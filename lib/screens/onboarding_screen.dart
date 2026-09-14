import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/analytics_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

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

// ─── Akış ────────────────────────────────────────────────────────────────────
//
// Tanıtım "ekranı ANLAT" değil "ekranı DENET" ilkesiyle kuruldu (2026-09-14).
//
// ## Neden yeniden yazıldı
// Önceki sürüm her tuşu minyatür şemalarla, 22 adımda anlatıyordu. İki
// sorun vardı: şemalar uygulamaya benzemiyordu (kullanıcı "bu hangi ekran"
// diye soruyordu) ve kimse 22 açıklama kartını okumuyordu — okunmayan
// tanıtım, olmayan tanıtımdır.
//
// ## Şimdi ne var
// Her sayfa, uygulamanın GERÇEK görünümünde bir yüzey: aynı hero kart, aynı
// alt menü, aynı tipografi ve renk tokenları. Ve o yüzeyde tek bir küçük
// görev: göz simgesine dokun, cümleyle varlık ekle, grafiği kaydır, bildirimi
// aç, "Birlikte"ye geç. Kullanıcı okumaz, YAPAR — yapılan şey akılda kalır.
//
// ## Görev zorunlu değil
// "Devam" her zaman açık. Zorlamak, tanıtımı bir an önce geçmek isteyen
// kullanıcıyı cezalandırırdı; görev tamamlanınca yalnızca alttaki şerit
// onaylar ve kapanış sayfası neleri denediğini listeler.
//
// ## Neden minyatür/ekran görüntüsü değil, canlı widget
// Ekran görüntüsü ilk tema/dil değişiminde yalan söyler. Buradaki yüzeyler
// uygulamanın kendi tokenlarıyla çizilir: tema değişince onlar da değişir,
// marka rengi güncellenince onlar da. Üstelik dokunulabilirler.

/// Sayfadaki küçük görev. [yok] = görevsiz sayfa (karşılama, kapanış).
enum _Gorev { yok, tutarGizle, cumleyleEkle, donemSec, bildirimAc, birlikteGor }

class _Sayfa {
  const _Sayfa({
    required this.id,
    required this.baslik,
    required this.aciklama,
    this.rozet,
    this.gorev = _Gorev.yok,
    this.gorevMetni,
    this.gorevBitti,
  });

  /// Analytics adım kimliği için sıra dışı, okunabilir bir ad.
  final String id;
  final String baslik;
  final String aciklama;

  /// "BİZE ÖZEL" gibi üst etiket — başka uygulamalarda olmayanı işaretler.
  /// Her sayfaya konulsa hiçbir şey vurgulanmamış olurdu.
  final String? rozet;
  final _Gorev gorev;

  /// Alttaki şeritte görev tamamlanmadan önce görünen çağrı.
  final String? gorevMetni;

  /// Görev tamamlanınca şeritte ve kapanışta görünen onay.
  final String? gorevBitti;
}

/// Turun tamamı.
///
/// Kapalı bayrakların özellikleri ANLATILMAZ: olmayan bir tuşu tanıtmak,
/// tanıtımın tamamına olan güveni bozar.
List<_Sayfa> _sayfalariKur() {
  final rc = RemoteConfigService.instance;
  final turler = rc.depositsEnabled
      ? 'Hisse, fon, döviz, altın, emtia ve vadeli mevduat'
      : 'Hisse, fon, döviz, altın ve emtia';

  return [
    _Sayfa(
      id: 'karsilama',
      baslik: 'Tüm birikimin,\ntek ekranda',
      aciklama: '$turler — hepsi tek toplamda, tek para biriminde. '
          'Fiyatlar arka planda kendiliğinden güncellenir.',
    ),
    const _Sayfa(
      id: 'ana',
      baslik: 'Ana ekranın',
      aciklama: 'Toplam birikimin ve bugünkü değişimin seni burada karşılar. '
          'Otobüste ya da omzunun üstünden bakan biri varken tek dokunuşla '
          'gizle.',
      gorev: _Gorev.tutarGizle,
      gorevMetni: 'Göz simgesine dokunarak tutarları gizle',
      gorevBitti: 'Tutarları gizledin',
    ),
    const _Sayfa(
      id: 'hizli_giris',
      rozet: 'BİZE ÖZEL',
      baslik: 'Cümleyle varlık ekle',
      aciklama: 'Form doldurma yok: "10 gram altın 4500 lira" yazman ya da '
          'söylemen yeter. Fiyat yazmazsan güncel fiyat kendiliğinden '
          'çekilir.',
      gorev: _Gorev.cumleyleEkle,
      gorevMetni: 'Aşağıdaki cümlelerden birine dokun',
      gorevBitti: 'Cümleyle varlık ekledin',
    ),
    const _Sayfa(
      id: 'performans',
      rozet: 'BİZE ÖZEL',
      baslik: 'Getirini gör, geçmişe dokun',
      aciklama: 'Gün içinden bir yıla kadar her dönem. "Simülasyon", '
          'bugünkü portföyünü baştan elinde tutsaydın ne olurdu sorusunu '
          'yanıtlar.',
      gorev: _Gorev.donemSec,
      gorevMetni: 'Bir dönem seç, sonra grafiğe basılı tut',
      gorevBitti: 'Grafiği keşfettin',
    ),
    const _Sayfa(
      id: 'sinyal',
      rozet: 'BİZE ÖZEL',
      baslik: 'Göstergeler ne diyor?',
      aciklama: 'RSI, MACD, Bollinger ve diğerleri her varlık için tek tek '
          'listelenir. Yön değişince haber veririz; kararı kutuda '
          'saklamayız.',
      gorev: _Gorev.bildirimAc,
      gorevMetni: 'Sinyal bildirimini aç',
      gorevBitti: 'Sinyal bildirimini açtın',
    ),
    const _Sayfa(
      id: 'ortaklik',
      rozet: 'BİZE ÖZEL',
      baslik: 'Eşinle tek portföy',
      aciklama: 'Davet kodunu paylaş; portföyleriniz tek ekranda birleşsin. '
          '"Birlikte" ikinizin toplamı, "Ben" yalnız senin. Kimse diğerinin '
          'kaydını değiştiremez.',
      gorev: _Gorev.birlikteGor,
      gorevMetni: '"Birlikte"ye geç',
      gorevBitti: 'Ortak portföyü gördün',
    ),
    const _Sayfa(
      id: 'hazir',
      baslik: 'Hazırsın',
      // "Her kayıt geri alınabilir" gibi bir söz VERİLMEZ: uygulamada geri
      // alma yok, silme kalıcıdır. Tutulamayan söz, tanıtıma olan güveni bozar.
      aciklama: 'Alt menüdeki + tuşuna dokun ve ilk varlığını ekle; gerisi '
          'kendiliğinden gelir. Yanlış girdiğin bir şeyi Portföy\'deki kartı '
          'kaydırarak düzeltebilir ya da silebilirsin.',
    ),
  ];
}

/// HIG'in en küçük dokunma hedefi: 44×44pt (Human Interface Guidelines →
/// Controls). Boşluk ölçeğine ait bir sayı DEĞİL — Apple'ın sabiti; bu
/// yüzden `SandikSpace` içinden seçilmez.
const double _higHedef = 44;

/// Uzun süreli hareketler (sayaç, grafik çizimi, beliriş) için ölçek.
///
/// Hareket dili üç sabit tanıyor (press/state/surface); tanıtımdaki
/// "sayının 0'dan tırmanması" ya da "grafiğin soldan sağa çizilmesi" bir
/// durum geçişi değil, dikkat çekmesi gereken bir SAHNE. Çıplak
/// `Duration(milliseconds: …)` yazmak yerine dil sabitinin katları
/// kullanılır; böylece "hareketi azalt" koruması (`SandikMotion.of`) aynen
/// çalışır ve marka hızı bir yerden değişirse burası da değişir.
abstract final class _Sahne {
  /// Beliriş (fade + kayma): 480ms.
  static Duration get belir => SandikMotion.surface * 2;

  /// Sayaç, grafik çizimi, dağılım çubuğu: 960ms.
  static Duration get uzun => SandikMotion.surface * 4;

  /// Nabız halkası bir turu: 1.440ms.
  static Duration get nabiz => SandikMotion.surface * 6;
}

/// Turu süren durum.
class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final List<_Sayfa> _sayfalar = _sayfalariKur();
  late final PageController _pages = PageController();

  late AnimationController _anim;
  late Animation<double> _fade;

  int _sayfa = 0;

  /// Tamamlanan görevler — kapanış sayfası bunları listeler.
  final Set<_Gorev> _tamamlanan = {};

  _Sayfa get _aktif => _sayfalar[_sayfa];
  bool get _son => _sayfa == _sayfalar.length - 1;

  @override
  void initState() {
    super.initState();
    // Beliriş SAYFA BAŞINA DEĞİL, ekran açılışına aittir: `PageView` bir
    // sonraki sayfayı önden kurduğu için sayfa başına yapılırsa kullanıcı
    // parmağını sürerken sayfa yeniden belirir ve titrer.
    _anim = AnimationController(vsync: this, duration: SandikMotion.surface);
    _fade = CurvedAnimation(parent: _anim, curve: SandikMotion.enter);
    _anim.forward();
    AnalyticsService.instance.logOnboardingStep(0);
  }

  @override
  void dispose() {
    _pages.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _gorevBitti(_Gorev g) {
    if (_tamamlanan.contains(g)) return;
    SandikHaptic.medium.perform();
    setState(() => _tamamlanan.add(g));
  }

  Future<void> _ileri() async {
    if (_son) {
      AnalyticsService.instance.logOnboardingCompleted();
      await OnboardingScreen.markCompleted(widget.userId);
      if (mounted) widget.onComplete();
      return;
    }
    await _sayfayaKay(_sayfa + 1);
  }

  Future<void> _geri() async {
    if (_sayfa == 0) return;
    await _sayfayaKay(_sayfa - 1);
  }

  /// "Hareketi azalt" açıkken süre sıfırdır ve `animateToPage` sıfır süreyi
  /// KABUL ETMEZ (assert). O durumda doğrudan atlanır — sonuç aynı kare.
  Future<void> _sayfayaKay(int i) async {
    final sure = SandikMotion.surfaceOf(context);
    if (sure == Duration.zero) {
      _pages.jumpToPage(i);
      return;
    }
    await _pages.animateToPage(i, duration: sure, curve: SandikMotion.enter);
  }

  Future<void> _atla() async {
    AnalyticsService.instance.logOnboardingSkipped(_sayfa);
    await OnboardingScreen.markCompleted(widget.userId);
    if (mounted) widget.onComplete();
  }

  void _sayfaDegisti(int i) {
    AnalyticsService.instance.logOnboardingStep(i);
    setState(() => _sayfa = i);
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
      body: Stack(
        children: [
          const Positioned.fill(child: _ArkaPlanIsigi()),
          SafeArea(
            child: Column(
              children: [
                _ustCubuk(context),
                Expanded(
                  child: FadeTransition(
                    opacity: _fade,
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: _sayfalar.length,
                      onPageChanged: _sayfaDegisti,
                      itemBuilder: (context, i) => _SayfaGorunumu(
                        // Anahtar sayfa kimliğine bağlı: PageView komşu
                        // sayfayı önden kurar, beliriş animasyonu her sayfa
                        // için bir kez oynar.
                        key: ValueKey(_sayfalar[i].id),
                        sayfa: _sayfalar[i],
                        tamamlanan: _tamamlanan,
                        onGorev: _gorevBitti,
                      ),
                    ),
                  ),
                ),
                _gorevSeridi(context),
                _ileriButonu(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Üst çubuk: geri · ilerleme · atla ──────────────────────────────────
  //
  // İlerleme noktalarla değil BÖLMELİ ÇUBUKLA gösterilir: yedi kısa sayfa
  // için bölme sayısı tek bakışta "neredeyim" sorusunu yanıtlar ve dolum
  // animasyonu ileri/geri yönü hissettirir.
  Widget _ustCubuk(BuildContext context) {
    final p = context.c;
    return SizedBox(
      height: _higHedef + SandikSpace.sm,
      child: Row(
        children: [
          // Geri, yalnızca dönülecek bir sayfa varken yer kaplar.
          if (_sayfa > 0)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md),
              minimumSize: const Size(_higHedef, _higHedef),
              onPressed: _geri,
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: p.text58),
            )
          else
            const SizedBox(width: _higHedef + SandikSpace.md),
          Expanded(
            child: Semantics(
              label: '${_sayfa + 1}. sayfa, toplam ${_sayfalar.length}',
              child: Row(
                children: List.generate(_sayfalar.length, (i) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: SandikSpace.xxs),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(SandikRadius.sm),
                        child: SizedBox(
                          height: SandikSpace.xs,
                          child: Stack(
                            // expand: Stack çocuklara gevşek kısıt verir;
                            // çocuksuz ColoredBox o kısıtta sıfır boyuta
                            // çöker ve dolum hiç görünmez.
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(color: p.text20),
                              AnimatedFractionallySizedBox(
                                duration: SandikMotion.surfaceOf(context),
                                curve: SandikMotion.enter,
                                alignment: Alignment.centerLeft,
                                widthFactor: i <= _sayfa ? 1 : 0,
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

  // ── Görev şeridi ────────────────────────────────────────────────────────
  //
  // "Ne yapmam bekleniyor" sorusunun tek yanıtı burası: yüzeyin içine metin
  // gömülmez (gerçek ekrana benzerliği bozar), yüzeyin altında sabit bir
  // şerit durur. Görev tamamlanınca aynı şerit onaya döner.
  Widget _gorevSeridi(BuildContext context) {
    final p = context.c;
    final s = _aktif;
    final gorevVar = s.gorev != _Gorev.yok;
    final bitti = _tamamlanan.contains(s.gorev);
    return _BoyutGecisi(
      child: gorevVar
          ? Padding(
              padding: const EdgeInsets.fromLTRB(
                  SandikSpace.lg, SandikSpace.xs, SandikSpace.lg, 0),
              child: AnimatedSwitcher(
                duration: SandikMotion.stateOf(context),
                switchInCurve: SandikMotion.enter,
                switchOutCurve: SandikMotion.enter,
                child: Container(
                  key: ValueKey('${s.id}-$bitti'),
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.smd, vertical: SandikSpace.sm2),
                  decoration: BoxDecoration(
                    color: bitti
                        ? p.gain.withValues(alpha: 0.12)
                        : p.amberFill.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    border: Border.all(
                      color: bitti
                          ? p.gain.withValues(alpha: 0.45)
                          : p.amberFill.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        bitti
                            ? Icons.check_circle_rounded
                            : Icons.touch_app_rounded,
                        size: 18,
                        color: bitti ? p.gain : p.amberText,
                      ),
                      const SizedBox(width: SandikSpace.sm),
                      Expanded(
                        child: Text(
                          bitti ? s.gorevBitti! : 'Dene: ${s.gorevMetni}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.bodyMedium?.copyWith(
                            color: bitti ? p.gain : p.text90,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  Widget _ileriButonu(BuildContext context) {
    final p = context.c;
    final etiket = _son
        ? 'Sandığımı Aç'
        : _sayfa == 0
            ? 'Başlayalım'
            : 'Devam';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          SandikSpace.lg, SandikSpace.smd, SandikSpace.lg, SandikSpace.lg),
      child: SizedBox(
        width: double.infinity,
        child: CupertinoButton(
          onPressed: _ileri,
          padding: EdgeInsets.zero,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: p.amberGradient,
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    etiket,
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
                  _son ? Icons.lock_open_rounded : Icons.arrow_forward_rounded,
                  size: 18,
                  color: p.onAmber,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Zeminde yavaşça kayan iki marka ışığı — ekranı "boş form" değil "sahne"
/// hissettirir. Çok soluk tutulur (%8–10): içerik okunabilirliği önce gelir.
class _ArkaPlanIsigi extends StatefulWidget {
  const _ArkaPlanIsigi();

  @override
  State<_ArkaPlanIsigi> createState() => _ArkaPlanIsigiState();
}

class _ArkaPlanIsigiState extends State<_ArkaPlanIsigi>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _Sahne.nabiz * 4,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sürekli hareket yalnızca "hareketi azalt" kapalıyken; açıkken ışıklar
    // sabit durur (kaldırılmaz — kompozisyon aynı kalır).
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_c.value);
          return Stack(
            children: [
              Positioned(
                top: -80 + 40 * t,
                right: -60 - 30 * t,
                child: _isik(p.amberFill, 260),
              ),
              Positioned(
                bottom: 40 - 50 * t,
                left: -90 + 30 * t,
                child: _isik(p.gain, 220),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _isik(Color renk, double cap) {
    return Container(
      width: cap,
      height: cap,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            renk.withValues(alpha: context.isLight ? 0.10 : 0.14),
            renk.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

// ─── Sayfa ───────────────────────────────────────────────────────────────────

/// Tek bir sayfa: başlık bloğu + etkileşimli yüzey.
///
/// Kendi içinde kaydırılabilir. Sabit yükseklikli bir yığın, sistem yazı
/// tipi büyütülmüşken (erişilebilirlik ayarı) ya da kısa ekranlarda
/// RenderFlex taşması veriyordu; burada taşma yerine kaydırma olur.
class _SayfaGorunumu extends StatelessWidget {
  const _SayfaGorunumu({
    super.key,
    required this.sayfa,
    required this.tamamlanan,
    required this.onGorev,
  });

  final _Sayfa sayfa;
  final Set<_Gorev> tamamlanan;
  final ValueChanged<_Gorev> onGorev;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.lg, vertical: SandikSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Baslik(sayfa: sayfa),
          const SizedBox(height: SandikSpace.lgs),
          _yuzey(context),
        ],
      ),
    );
  }

  Widget _yuzey(BuildContext context) {
    final bitti = tamamlanan.contains(sayfa.gorev);
    switch (sayfa.gorev) {
      case _Gorev.tutarGizle:
        return _AnaEkranYuzeyi(
            bitti: bitti, onBitti: () => onGorev(_Gorev.tutarGizle));
      case _Gorev.cumleyleEkle:
        return _HizliGirisYuzeyi(
            bitti: bitti, onBitti: () => onGorev(_Gorev.cumleyleEkle));
      case _Gorev.donemSec:
        return _PerformansYuzeyi(
            bitti: bitti, onBitti: () => onGorev(_Gorev.donemSec));
      case _Gorev.bildirimAc:
        return _SinyalYuzeyi(
            bitti: bitti, onBitti: () => onGorev(_Gorev.bildirimAc));
      case _Gorev.birlikteGor:
        return _OrtaklikYuzeyi(
            bitti: bitti, onBitti: () => onGorev(_Gorev.birlikteGor));
      case _Gorev.yok:
        return sayfa.id == 'hazir'
            ? _Kapanis(tamamlanan: tamamlanan)
            : const _Karsilama();
    }
  }
}

/// Rozet, başlık, açıklama — kademeli belirir.
class _Baslik extends StatelessWidget {
  const _Baslik({required this.sayfa});

  final _Sayfa sayfa;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Semantics(
      // Sayfa değişince ekran okuyucu yeni başlığı kendiliğinden okusun.
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sayfa.rozet case final r?) ...[
            _Belir(sira: 0, child: _Rozet(metin: r)),
            const SizedBox(height: SandikSpace.smd),
          ],
          _Belir(
            sira: 1,
            child: Text(
              sayfa.baslik,
              style: context.t.headlineLarge?.copyWith(
                color: p.text90,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                height: 1.12,
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.sm2),
          _Belir(
            sira: 2,
            child: Text(
              sayfa.aciklama,
              style: context.t.bodyLarge?.copyWith(
                color: p.text58,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "BİZE ÖZEL" rozeti.
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

// ─── Hareket yardımcıları ────────────────────────────────────────────────────

/// Kademeli beliriş: [sira] arttıkça biraz daha geç, aşağıdan yukarı kayarak.
///
/// Sayfadaki her öğe aynı anda belirirse göz nereye bakacağını bilemez;
/// 60ms'lik kademe okuma sırasını (rozet → başlık → açıklama → yüzey)
/// hareketle de söyler. "Hareketi azalt" açıkken süre sıfırdır: her şey
/// anında yerinde.
class _Belir extends StatefulWidget {
  const _Belir({required this.sira, required this.child});

  final int sira;
  final Widget child;

  @override
  State<_Belir> createState() => _BelirState();
}

class _BelirState extends State<_Belir> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  late final CurvedAnimation _egri;
  late final Animation<Offset> _kayma;
  bool _basladi = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_basladi) return;
    _basladi = true;
    // Gecikme bir Timer DEĞİL, aynı animasyonun başındaki bekleme aralığı:
    // Timer, widget sayfa geçişinde erken sökülürse askıda kalır (testte
    // "timer still pending" olarak görünüyordu); Interval ise denetleyiciyle
    // birlikte yaşar ve ölür.
    final gecikme =
        SandikMotion.of(context, SandikMotion.state * widget.sira) ~/ 3;
    final sure = SandikMotion.of(context, _Sahne.belir);
    final toplam = gecikme + sure;
    _c.duration = toplam;
    final baslangic = toplam == Duration.zero
        ? 0.0
        : gecikme.inMicroseconds / toplam.inMicroseconds;
    _egri = CurvedAnimation(
      parent: _c,
      curve: Interval(baslangic, 1, curve: SandikMotion.enter),
    );
    _kayma = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(_egri);
    _c.forward();
  }

  @override
  void dispose() {
    _egri.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _egri,
      child: SlideTransition(position: _kayma, child: widget.child),
    );
  }
}

/// Yükseklik geçişi — "hareketi azalt" açıkken düz çocuk.
///
/// `AnimatedSize` sıfır süreyle çalıştırıldığında kendi `performLayout`'u
/// içinde kendini yeniden kirletir (Flutter assert'i: "RenderAnimatedSize was
/// mutated in its own performLayout"). Süre sıfırsa geçişe gerek de yok;
/// çocuk doğrudan yerleşir, son kare aynıdır.
class _BoyutGecisi extends StatelessWidget {
  const _BoyutGecisi({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sure = SandikMotion.surfaceOf(context);
    if (sure == Duration.zero) return child;
    return AnimatedSize(
      duration: SandikMotion.surfaceOf(context),
      curve: SandikMotion.enter,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

/// Dokunulacak hedefin çevresinde nabız gibi genişleyen halka.
///
/// Görev metni "göz simgesine dokun" der; halka o simgenin HANGİSİ olduğunu
/// gösterir. Görev bitince söner. Koordinat taşımaz — hedefi sarar, konumu
/// Flutter'ın yerleşimi belirler (metin ölçeği değişince kaymaz).
class _Isaret extends StatefulWidget {
  const _Isaret({required this.aktif, required this.child});

  final bool aktif;
  final Widget child;

  @override
  State<_Isaret> createState() => _IsaretState();
}

class _IsaretState extends State<_Isaret> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: _Sahne.nabiz);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _guncelle();
  }

  @override
  void didUpdateWidget(covariant _Isaret old) {
    super.didUpdateWidget(old);
    _guncelle();
  }

  void _guncelle() {
    final hareket = !MediaQuery.disableAnimationsOf(context);
    if (widget.aktif && hareket) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    final hareket = !MediaQuery.disableAnimationsOf(context);
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (widget.aktif)
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              // Hareket kapalıyken sabit, belirgin bir halka: hedef yine
              // işaretli kalır, yalnızca nabız atmaz.
              final t = hareket ? _c.value : 0.35;
              // Genişleme ÖLÇEKLE değil sabit payla: geniş bir hedefte
              // (tam satır çip, anahtar kartı) %55 ölçek halkayı yüzeyin
              // dışına taşırıp iki yatay çizgiye çeviriyordu.
              final pay = SandikSpace.xs + SandikSpace.smd * t;
              final alfa = hareket ? (1 - t) * 0.9 : 0.9;
              return Positioned(
                left: -pay,
                right: -pay,
                top: -pay,
                bottom: -pay,
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
          ),
        widget.child,
      ],
    );
  }
}

/// 0'dan hedefe tırmanan tutar. [gizli] iken noktalar.
///
/// Hedef değişince (Ben → Birlikte) mevcut değerden yeniye kayar; sıfırdan
/// başlamaz — kullanıcı "toplam arttı" ilişkisini görür.
class _SayacTutar extends StatelessWidget {
  const _SayacTutar({
    super.key,
    required this.deger,
    required this.stil,
    this.gizli = false,
  });

  final double deger;
  final TextStyle? stil;
  final bool gizli;

  @override
  Widget build(BuildContext context) {
    if (gizli) return Text('••••••', maxLines: 1, style: stil);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: deger),
      duration: SandikMotion.of(context, _Sahne.uzun),
      curve: SandikMotion.enter,
      builder: (context, v, _) => Text(fmtTRY(v), maxLines: 1, style: stil),
    );
  }
}

// ─── Gerçek görünümlü parçalar ───────────────────────────────────────────────
//
// Bunlar uygulamanın kendi bileşenlerinin BİREBİR görünümüdür (home_screen
// marka rozeti, portfolio_summary_widget hero kartı, main_navigation_screen
// alt menüsü). Gerçek widget'lar kullanılmıyor çünkü onlar provider/Supabase
// verisi ister; burada sabit örnek veri var. Görünüm oradan değişirse burası
// da güncellenmeli — kullanıcı burada gördüğünü orada arayacak.

/// Uygulama ekranı çerçevesi.
///
/// Metin ölçeği burada SINIRLANIR (1,3×). Yüzey bir uygulama ekranının
/// kopyasıdır; 2,0× sistem yazı tipinde beş sütunlu alt menü kırılır. Asıl
/// açıklama ([_Baslik]) tam ölçeğinde kalır, yani erişilebilirlik ayarından
/// bir şey kaybedilmez.
class _Telefon extends StatelessWidget {
  const _Telefon({required this.child, this.altMenu});

  final Widget child;

  /// Verilirse alt menü kopyası çerçevenin altına yapışır; index aktif sekme.
  final int? altMenu;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return _Belir(
      sira: 3,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.background,
            borderRadius: BorderRadius.circular(SandikRadius.lg),
            border: Border.all(color: p.hairline),
            boxShadow: [
              ...p.cardShadow,
              BoxShadow(
                color: p.amberFill.withValues(alpha: 0.10),
                blurRadius: 40,
                spreadRadius: -8,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(SandikSpace.md),
                child: child,
              ),
              if (altMenu case final i?) _AltMenu(aktif: i),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ana ekran üst çubuğundaki "sandık" marka rozeti.
class _MarkaRozeti extends StatelessWidget {
  const _MarkaRozeti();

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm2, vertical: SandikSpace.xs2),
      decoration: BoxDecoration(
        color: p.amberFill.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: p.amberFill.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_balance_wallet_rounded, size: 16, color: p.gold),
          const SizedBox(width: SandikSpace.xs2),
          Text(
            'sandık',
            style: context.t.titleMedium?.copyWith(
              color: p.gold,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Alt menü kopyası — beş tuş, ortada +.
class _AltMenu extends StatelessWidget {
  const _AltMenu({required this.aktif});

  final int aktif;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Container(
      decoration: BoxDecoration(
        color: p.overlay,
        border: Border(top: BorderSide(color: p.hairline)),
      ),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            _oge(context, 0, Icons.home_rounded, 'Ana'),
            _oge(context, 1, Icons.donut_large_rounded, 'Portföy'),
            Expanded(
              child: Center(
                child: Container(
                  width: SandikSpace.xxl,
                  height: SandikSpace.xxl,
                  decoration: BoxDecoration(
                    color: p.amberFill,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: p.amberFill.withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: -2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.add_rounded, color: p.onAmber, size: 32),
                ),
              ),
            ),
            _oge(context, 3, Icons.show_chart_rounded, 'Performans'),
            _oge(context, 4, Icons.person_rounded, 'Profil'),
          ],
        ),
      ),
    );
  }

  Widget _oge(BuildContext context, int i, IconData ikon, String etiket) {
    final p = context.c;
    final secili = i == aktif;
    final renk = secili ? p.amberText : p.text36;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(ikon, color: renk, size: 24),
          const SizedBox(height: SandikSpace.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              etiket,
              maxLines: 1,
              style: context.t.labelMedium?.copyWith(
                letterSpacing: 0,
                fontWeight: secili ? FontWeight.w700 : FontWeight.w500,
                color: renk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 44pt dokunma hedefli ikon tuşu; görsel kutu daha küçük.
class _IkonTus extends StatelessWidget {
  const _IkonTus({
    required this.ikon,
    required this.etiket,
    this.onTap,
    this.marka = false,
  });

  final IconData ikon;
  final String etiket;
  final VoidCallback? onTap;
  final bool marka;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return SandikTappable(
      onTap: onTap,
      semanticLabel: etiket,
      child: SizedBox(
        width: _higHedef,
        height: _higHedef,
        child: Center(
          child: Container(
            width: SandikSpace.xl + SandikSpace.xs,
            height: SandikSpace.xl + SandikSpace.xs,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: marka ? p.amberFill.withValues(alpha: 0.16) : p.surface1,
              borderRadius: BorderRadius.circular(SandikRadius.sm),
              border: Border.all(color: p.hairline),
            ),
            child: Icon(ikon, size: 20, color: marka ? p.amberText : p.text58),
          ),
        ),
      ),
    );
  }
}

/// Segmentli seçici (Birlikte/Ben, Gerçek/Simülasyon, dönemler).
class _Segment extends StatelessWidget {
  const _Segment({
    required this.etiketler,
    required this.secili,
    required this.onSec,
  });

  final List<String> etiketler;
  final int secili;
  final ValueChanged<int> onSec;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Container(
      padding: const EdgeInsets.all(SandikSpace.xxs),
      decoration: BoxDecoration(
        color: p.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          for (var i = 0; i < etiketler.length; i++)
            Expanded(
              child: SandikTappable(
                onTap: () => onSec(i),
                semanticLabel: etiketler[i],
                child: AnimatedContainer(
                  duration: SandikMotion.stateOf(context),
                  curve: SandikMotion.enter,
                  height: _higHedef - SandikSpace.sm,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == secili
                        ? p.amberFill
                        : p.amberFill.withValues(alpha: 0),
                    borderRadius: BorderRadius.circular(SandikRadius.sm + 2),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      etiketler[i],
                      maxLines: 1,
                      style: context.t.labelLarge?.copyWith(
                        color: i == secili ? p.onAmber : p.text58,
                        fontWeight:
                            i == secili ? FontWeight.w800 : FontWeight.w600,
                      ),
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

/// Varlık listesi satırı — Portföy ekranındaki kartın kısa hâli.
class _VarlikSatiri extends StatelessWidget {
  const _VarlikSatiri({
    required this.kod,
    required this.ad,
    required this.miktar,
    required this.deger,
    required this.degisim,
    this.gizli = false,
  });

  final String kod;
  final String ad;
  final String miktar;
  final double deger;
  final double degisim;
  final bool gizli;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    final renk = context.signColor(degisim);
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.sm),
      child: SandikCard(
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.smd, vertical: SandikSpace.sm2),
        child: Row(
          children: [
            Container(
              width: SandikSpace.xl + SandikSpace.xs,
              height: SandikSpace.xl + SandikSpace.xs,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.amberFill.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(SandikRadius.sm),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  kod,
                  style: context.t.labelLarge?.copyWith(
                    color: p.amberText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: SandikSpace.sm2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ad,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodyMedium?.copyWith(
                      color: p.text90,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    miktar,
                    maxLines: 1,
                    style: context.t.bodySmall?.copyWith(color: p.text36),
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
                  gizli ? '••••' : fmtTRY(deger),
                  maxLines: 1,
                  style: context.t.numSmall.copyWith(color: p.text90),
                ),
                Text(
                  // Yön hem renkle hem GLİFLE anlatılır: marka yeşili ile
                  // kırmızısı renk körlüğü altında yeterince ayrışmıyor.
                  '${degisim >= 0 ? '▲' : '▼'} ${fmtPct(degisim.abs())}',
                  maxLines: 1,
                  style: context.t.bodySmall?.copyWith(
                    color: renk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 1. Karşılama ────────────────────────────────────────────────────────────

/// Marka işareti + nabız halkaları + kayan varlık türü çipleri.
class _Karsilama extends StatefulWidget {
  const _Karsilama();

  @override
  State<_Karsilama> createState() => _KarsilamaState();
}

class _KarsilamaState extends State<_Karsilama>
    with SingleTickerProviderStateMixin {
  late final AnimationController _nabiz =
      AnimationController(vsync: this, duration: _Sahne.nabiz);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _nabiz.stop();
    } else if (!_nabiz.isAnimating) {
      _nabiz.repeat();
    }
  }

  @override
  void dispose() {
    _nabiz.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    final rc = RemoteConfigService.instance;
    final turler = <(IconData, String)>[
      (Icons.candlestick_chart_rounded, 'Hisse'),
      (Icons.pie_chart_rounded, 'Fon'),
      (Icons.currency_exchange_rounded, 'Döviz'),
      (Icons.workspace_premium_rounded, 'Altın'),
      (Icons.oil_barrel_rounded, 'Emtia'),
      if (rc.depositsEnabled) (Icons.savings_rounded, 'Mevduat'),
    ];

    return Column(
      children: [
        _Belir(
          sira: 3,
          child: SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // İki halka, yarım tur arayla: sürekli dışa yayılan bir
                // "canlı" his. Hareket kapalıyken ikisi de sabit, soluk.
                for (final faz in const [0.0, 0.5])
                  AnimatedBuilder(
                    animation: _nabiz,
                    builder: (context, _) {
                      final hareket =
                          !MediaQuery.disableAnimationsOf(context);
                      final t = hareket ? (_nabiz.value + faz) % 1 : faz;
                      return Container(
                        width: 110 + 110 * t,
                        height: 110 + 110 * t,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: p.amberFill.withValues(
                                alpha: (1 - t) * 0.45),
                            width: 1.5,
                          ),
                        ),
                      );
                    },
                  ),
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: p.amberGradient,
                    boxShadow: [
                      BoxShadow(
                        color: p.amberFill.withValues(alpha: 0.40),
                        blurRadius: 40,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(Icons.account_balance_wallet_rounded,
                      size: 52, color: p.onAmber),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: SandikSpace.sm,
          runSpacing: SandikSpace.sm,
          children: [
            for (var i = 0; i < turler.length; i++)
              _Belir(
                sira: 4 + i,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.smd, vertical: SandikSpace.sm),
                  decoration: BoxDecoration(
                    color: p.surface1,
                    borderRadius: BorderRadius.circular(SandikRadius.lg),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(turler[i].$1, size: 16, color: p.amberText),
                      const SizedBox(width: SandikSpace.xs2),
                      Text(
                        turler[i].$2,
                        style: context.t.bodyMedium?.copyWith(
                          color: p.text90,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ─── 2. Ana ekran ────────────────────────────────────────────────────────────

/// Ana ekran kopyası: marka rozeti, yenile/gizle tuşları, hero kart, şeritler,
/// iki varlık satırı ve alt menü. Görev: göz simgesine dokun.
class _AnaEkranYuzeyi extends StatefulWidget {
  const _AnaEkranYuzeyi({required this.bitti, required this.onBitti});

  final bool bitti;
  final VoidCallback onBitti;

  @override
  State<_AnaEkranYuzeyi> createState() => _AnaEkranYuzeyiState();
}

class _AnaEkranYuzeyiState extends State<_AnaEkranYuzeyi>
    with SingleTickerProviderStateMixin {
  bool _gizli = false;
  late final AnimationController _yenile = AnimationController(
    vsync: this,
    duration: _Sahne.uzun,
  );
  late final CurvedAnimation _yenileEgri =
      CurvedAnimation(parent: _yenile, curve: SandikMotion.move);

  static const double _toplam = 248350;
  static const double _gunluk = 3120;

  @override
  void dispose() {
    _yenileEgri.dispose();
    _yenile.dispose();
    super.dispose();
  }

  void _gizleToggle() {
    setState(() => _gizli = !_gizli);
    if (_gizli) widget.onBitti();
  }

  void _yenileBas() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _yenile.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    final rc = RemoteConfigService.instance;
    return _Telefon(
      altMenu: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _MarkaRozeti(),
                ),
              ),
              const Spacer(),
              RotationTransition(
                turns: _yenileEgri,
                child: _IkonTus(
                  ikon: Icons.refresh_rounded,
                  etiket: 'Fiyatları yenile',
                  onTap: _yenileBas,
                ),
              ),
              _Isaret(
                aktif: !widget.bitti,
                child: _IkonTus(
                  ikon: _gizli
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  etiket: _gizli ? 'Tutarları göster' : 'Tutarları gizle',
                  onTap: _gizleToggle,
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.smd),
          _heroKart(context),
          if (rc.realReturnEnabled) ...[
            const SizedBox(height: SandikSpace.sm),
            _serit(context, Icons.trending_up_rounded, 'Enflasyon üstü getiri',
                _gizli ? '••••' : fmtPct(12.4, showSign: true), p.gain),
          ],
          if (rc.percentileStripEnabled) ...[
            const SizedBox(height: SandikSpace.sm),
            _serit(context, Icons.emoji_events_rounded, 'Yarış · anonim',
                'İlk %18', p.amberText),
          ],
          const SizedBox(height: SandikSpace.md),
          const SandikSectionHeader(title: 'VARLIK DAĞILIMI', count: 3),
          const SizedBox(height: SandikSpace.sm2),
          _VarlikSatiri(
            kod: 'THY',
            ad: 'Türk Hava Yolları',
            miktar: '120 adet',
            deger: 38208,
            degisim: 2.1,
            gizli: _gizli,
          ),
          _VarlikSatiri(
            kod: 'AU',
            ad: 'Gram altın',
            miktar: '24 gram',
            deger: 106800,
            degisim: 0.6,
            gizli: _gizli,
          ),
          _VarlikSatiri(
            kod: 'AFA',
            ad: 'Ak Portföy Alt. Enerji',
            miktar: '1.200 adet',
            deger: 41560,
            degisim: -0.8,
            gizli: _gizli,
          ),
        ],
      ),
    );
  }

  /// `PortfolioSummaryWidget`'ın görünümü: dark'ta yarı saydam koyu yeşil
  /// cam, light'ta beyaz yüzey + gölge.
  Widget _heroKart(BuildContext context) {
    final p = context.c;
    return ClipRRect(
      borderRadius: BorderRadius.circular(SandikRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(SandikSpace.lgs),
          decoration: BoxDecoration(
            color: context.isLight
                ? p.surface2
                : p.gain.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(SandikRadius.lg),
            border: Border.all(
              color: context.isLight
                  ? p.hairline
                  : p.gain.withValues(alpha: 0.18),
            ),
            boxShadow: p.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOPLAM NET VARLIK',
                style: context.t.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: p.gain,
                ),
              ),
              const SizedBox(height: SandikSpace.xs2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: SandikMotion.stateOf(context),
                  switchInCurve: SandikMotion.enter,
                  switchOutCurve: SandikMotion.enter,
                  child: _SayacTutar(
                    key: ValueKey(_gizli),
                    deger: _toplam,
                    gizli: _gizli,
                    stil: context.t.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: p.gold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SandikSpace.sm),
              Row(
                children: [
                  if (!_gizli) ...[
                    Icon(Icons.arrow_drop_up_rounded, color: p.gain, size: 20),
                    Flexible(
                      child: Text(
                        '+${fmtTRY(_gunluk)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.numSmall.copyWith(color: p.gain),
                      ),
                    ),
                    const SizedBox(width: SandikSpace.sm2),
                    Text(
                      fmtPct(_gunluk / (_toplam - _gunluk) * 100),
                      maxLines: 1,
                      style: context.t.numSmall.copyWith(
                        color: p.gain,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ] else
                    Text(
                      '•••• / ••••',
                      style: context.t.numSmall.copyWith(
                        color: p.text36,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serit(BuildContext context, IconData ikon, String etiket,
      String deger, Color renk) {
    final p = context.c;
    return SandikCard(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.smd, vertical: SandikSpace.sm2),
      child: Row(
        children: [
          Icon(ikon, size: 18, color: renk),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Text(
              etiket,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodyMedium?.copyWith(
                color: p.text58,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            deger,
            maxLines: 1,
            style: context.t.numSmall.copyWith(color: renk),
          ),
        ],
      ),
    );
  }
}

// ─── 3. Hızlı Giriş ──────────────────────────────────────────────────────────

/// Örnek cümle ve ondan çözümlenen varlık kartı.
///
/// Çözümleme burada SABİT: gerçek ayrıştırıcıyı çağırmak tanıtımı servis
/// katmanına bağlar ve fiyat çekmeye kalkar. Tanıtımın amacı "bu cümle şu
/// karta dönüşür" ilişkisini göstermek; hangi ayrıştırıcının yaptığı değil.
class _Ornek {
  const _Ornek({
    required this.cumle,
    required this.ikon,
    required this.ad,
    required this.tur,
    required this.miktar,
    this.fiyat,
  });

  final String cumle;
  final IconData ikon;
  final String ad;
  final String tur;
  final String miktar;

  /// Yoksa "güncel fiyat çekilecek" gösterilir — cümlede fiyat yazmamanın
  /// ne anlama geldiğini kart kendisi söyler.
  final String? fiyat;
}

const _ornekler = <_Ornek>[
  _Ornek(
    cumle: '10 gram altın 4500 lira',
    ikon: Icons.workspace_premium_rounded,
    ad: 'Gram altın',
    tur: 'Altın',
    miktar: '10 gram',
    fiyat: '₺4.500 / gram',
  ),
  _Ornek(
    cumle: 'GARAN 500 adet',
    ikon: Icons.candlestick_chart_rounded,
    ad: 'Garanti BBVA',
    tur: 'Hisse · GARAN',
    miktar: '500 adet',
  ),
  _Ornek(
    cumle: '3000 dolar 41,20',
    ikon: Icons.currency_exchange_rounded,
    ad: 'Amerikan Doları',
    tur: 'Döviz · USD',
    miktar: '3.000 USD',
    fiyat: '₺41,20 / USD',
  ),
];

/// Varlık ekleme kopyası: cümle alanı (daktilo animasyonlu), örnek çipler ve
/// çözümlenen kart. Görev: bir örnek cümleye dokun.
class _HizliGirisYuzeyi extends StatefulWidget {
  const _HizliGirisYuzeyi({required this.bitti, required this.onBitti});

  final bool bitti;
  final VoidCallback onBitti;

  @override
  State<_HizliGirisYuzeyi> createState() => _HizliGirisYuzeyiState();
}

class _HizliGirisYuzeyiState extends State<_HizliGirisYuzeyi> {
  _Ornek? _secili;
  bool _yazildi = false;

  void _sec(_Ornek o) {
    if (_secili == o) return;
    setState(() {
      _secili = o;
      _yazildi = false;
    });
    widget.onBitti();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return _Telefon(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Hızlı Giriş',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.titleLarge?.copyWith(
                    color: p.text90,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              // Gerçek ekrandaki giriş noktası mikrofon; kullanıcı burada
              // gördüğü tuşu orada arayacak.
              const _IkonTus(
                  ikon: Icons.mic_rounded, etiket: 'Sesle yaz', marka: true),
              const _IkonTus(
                  ikon: Icons.playlist_add_rounded, etiket: 'Toplu ekle'),
            ],
          ),
          const SizedBox(height: SandikSpace.smd),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: SandikSpace.md2, vertical: SandikSpace.smd),
            decoration: BoxDecoration(
              color: p.surface1,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              border: Border.all(
                color: _secili == null ? p.hairline : p.amberFill,
                width: _secili == null ? 1 : 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_rounded, size: 18, color: p.text36),
                const SizedBox(width: SandikSpace.sm),
                Expanded(
                  child: _secili == null
                      ? Text(
                          'Örn. 10 gram altın 4500 lira',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.bodyLarge
                              ?.copyWith(color: p.text36),
                        )
                      : _Daktilo(
                          key: ValueKey(_secili!.cumle),
                          metin: _secili!.cumle,
                          stil: context.t.bodyLarge?.copyWith(
                            color: p.text90,
                            fontWeight: FontWeight.w600,
                          ),
                          onBitti: () {
                            if (mounted) setState(() => _yazildi = true);
                          },
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SandikSpace.smd),
          Text(
            'ÖRNEKLER',
            style: context.t.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: p.text58,
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          Wrap(
            spacing: SandikSpace.sm,
            runSpacing: SandikSpace.sm,
            children: [
              for (var i = 0; i < _ornekler.length; i++)
                _Isaret(
                  aktif: !widget.bitti && i == 0,
                  child: _cip(context, _ornekler[i]),
                ),
            ],
          ),
          _BoyutGecisi(
            child: _secili != null && _yazildi
                ? Padding(
                    padding: const EdgeInsets.only(top: SandikSpace.md),
                    child: _Belir(sira: 0, child: _cozumKarti(context, _secili!)),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _cip(BuildContext context, _Ornek o) {
    final p = context.c;
    final secili = _secili == o;
    return SandikTappable(
      onTap: () => _sec(o),
      semanticLabel: 'Örnek: ${o.cumle}',
      child: AnimatedContainer(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        constraints: const BoxConstraints(minHeight: _higHedef),
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.smd, vertical: SandikSpace.sm),
        decoration: BoxDecoration(
          color: secili ? p.amberFill : p.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.lg),
          border: Border.all(color: secili ? p.amberFill : p.hairline),
        ),
        alignment: Alignment.center,
        child: Text(
          '"${o.cumle}"',
          style: context.t.bodyMedium?.copyWith(
            color: secili ? p.onAmber : p.text90,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Cümleden çözümlenen varlık — Toplu Ekle sepetindeki kartın görünümü.
  Widget _cozumKarti(BuildContext context, _Ornek o) {
    final p = context.c;
    return SandikCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: SandikSpace.xl + SandikSpace.xs,
                height: SandikSpace.xl + SandikSpace.xs,
                decoration: BoxDecoration(
                  gradient: p.amberGradient,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Icon(o.ikon, size: 20, color: p.onAmber),
              ),
              const SizedBox(width: SandikSpace.sm2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodyLarge?.copyWith(
                        color: p.text90,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      o.tur,
                      maxLines: 1,
                      style: context.t.bodySmall?.copyWith(color: p.text36),
                    ),
                  ],
                ),
              ),
              Icon(Icons.check_circle_rounded, color: p.gain, size: 22),
            ],
          ),
          const SizedBox(height: SandikSpace.smd),
          Row(
            children: [
              Expanded(child: _alan(context, 'Miktar', o.miktar)),
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                child: _alan(
                  context,
                  'Fiyat',
                  o.fiyat ?? 'Güncel fiyat çekilecek',
                  vurgu: o.fiyat == null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _alan(BuildContext context, String etiket, String deger,
      {bool vurgu = false}) {
    final p = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm2, vertical: SandikSpace.sm),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiket,
            maxLines: 1,
            style: context.t.labelMedium?.copyWith(color: p.text36),
          ),
          const SizedBox(height: SandikSpace.xxs),
          Text(
            deger,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.bodyMedium?.copyWith(
              color: vurgu ? p.amberText : p.text90,
              fontWeight: FontWeight.w600,
              fontStyle: vurgu ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/// Harf harf beliren metin, sonunda yanıp sönen imleç.
class _Daktilo extends StatefulWidget {
  const _Daktilo({
    super.key,
    required this.metin,
    required this.stil,
    required this.onBitti,
  });

  final String metin;
  final TextStyle? stil;
  final VoidCallback onBitti;

  @override
  State<_Daktilo> createState() => _DaktiloState();
}

class _DaktiloState extends State<_Daktilo> with TickerProviderStateMixin {
  late final AnimationController _yaz = AnimationController(vsync: this);
  late final AnimationController _imlec =
      AnimationController(vsync: this, duration: SandikMotion.surface * 2);
  bool _basladi = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_basladi) return;
    _basladi = true;
    // Harf başına ~45ms: okunabilir ama sabırsız etmeyecek hız.
    _yaz.duration = SandikMotion.of(
        context, SandikMotion.state * widget.metin.length ~/ 4);
    _yaz.forward().whenComplete(() {
      if (mounted) widget.onBitti();
    });
    if (!MediaQuery.disableAnimationsOf(context)) {
      _imlec.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _yaz.dispose();
    _imlec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return AnimatedBuilder(
      animation: Listenable.merge([_yaz, _imlec]),
      builder: (context, _) {
        final n = (_yaz.value * widget.metin.length).round();
        return Text.rich(
          TextSpan(
            text: widget.metin.substring(0, n),
            style: widget.stil,
            children: [
              TextSpan(
                text: '|',
                style: widget.stil?.copyWith(
                  color: p.amberText.withValues(alpha: 0.4 + 0.6 * _imlec.value),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

// ─── 4. Performans ───────────────────────────────────────────────────────────

/// Performans kopyası: Birlikte/Ben, dönem seçici, çizgi grafik (dokununca
/// imleç), Gerçek/Simülasyon. Görev: bir dönem seç, grafiğe basılı tut.
class _PerformansYuzeyi extends StatefulWidget {
  const _PerformansYuzeyi({required this.bitti, required this.onBitti});

  final bool bitti;
  final VoidCallback onBitti;

  @override
  State<_PerformansYuzeyi> createState() => _PerformansYuzeyiState();
}

class _PerformansYuzeyiState extends State<_PerformansYuzeyi> {
  static const _donemler = ['GÜNLÜK', '1H', '1A', '6A', '1Y'];

  /// Dönem başına getiri yüzdesi — seri de bu hedefe tırmanacak şekilde üretilir.
  static const _getiriler = [1.27, 3.4, 6.8, 18.5, 41.2];

  int _donem = 2;
  int _mod = 0; // 0 gerçek, 1 simülasyon
  bool _donemSecildi = false;

  /// İmleç konumu (0..1) — null iken çizgi görünmez.
  double? _imlec;

  static const double _baslangic = 232000;

  double get _getiri => _getiriler[_donem] * (_mod == 1 ? 1.35 : 1.0);

  late List<double> _seri = _seriUret();

  /// Dönem+mod'a göre DETERMİNİSTİK seri: aynı dönem her açılışta aynı
  /// eğriyi verir; rastgelelik yalnızca "gerçekçi dalgalanma" içindir.
  List<double> _seriUret() {
    final r = math.Random(_donem * 10 + _mod);
    const n = 48;
    final out = <double>[];
    var v = 0.0;
    for (var i = 0; i < n; i++) {
      // Sürüklenme + gürültü, sonra 0..1 aralığına normalize.
      v += 1 / n + (r.nextDouble() - 0.5) * 0.12;
      out.add(v);
    }
    final min = out.reduce(math.min);
    final max = out.reduce(math.max);
    return [for (final x in out) (x - min) / (max - min)];
  }

  void _donemSec(int i) {
    setState(() {
      _donem = i;
      _donemSecildi = true;
      _seri = _seriUret();
      _imlec = null;
    });
  }

  void _modSec(int i) {
    setState(() {
      _mod = i;
      _seri = _seriUret();
      _imlec = null;
    });
  }

  void _imlecGuncelle(Offset yerel, double genislik) {
    final f = (yerel.dx / genislik).clamp(0.0, 1.0);
    setState(() => _imlec = f);
    // Görev iki parçalı: dönem seçildi VE grafiğe dokunuldu.
    if (_donemSecildi) widget.onBitti();
  }

  double _degerAt(double f) {
    final i = (f * (_seri.length - 1));
    final lo = i.floor();
    final hi = math.min(lo + 1, _seri.length - 1);
    final t = i - lo;
    final norm = _seri[lo] + (_seri[hi] - _seri[lo]) * t;
    return _baslangic * (1 + norm * _getiri / 100);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    final son = _baslangic * (1 + _getiri / 100);
    final okunan = _imlec == null ? son : _degerAt(_imlec!);
    return _Telefon(
      altMenu: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Segment(
            etiketler: const ['Birlikte', 'Ben'],
            secili: 1,
            onSec: (_) {},
          ),
          const SizedBox(height: SandikSpace.smd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _imlec == null
                          ? '${_donemler[_donem]} GETİRİ'
                          : 'SEÇİLİ NOKTA',
                      maxLines: 1,
                      style: context.t.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: p.text36,
                      ),
                    ),
                    const SizedBox(height: SandikSpace.xxs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: _imlec == null
                          ? _SayacTutar(
                              deger: son,
                              stil: context.t.numLarge.copyWith(color: p.gold),
                            )
                          : Text(
                              fmtTRY(okunan),
                              maxLines: 1,
                              style: context.t.numLarge.copyWith(color: p.gold),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SandikSpace.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: SandikSpace.sm, vertical: SandikSpace.xs),
                decoration: BoxDecoration(
                  color: p.gain.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Text(
                  '▲ ${fmtPct((okunan / _baslangic - 1) * 100)}',
                  maxLines: 1,
                  style: context.t.numSmall.copyWith(color: p.gain),
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.sm),
          _Isaret(
            aktif: !widget.bitti && _donemSecildi,
            child: LayoutBuilder(
              builder: (context, c) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: (d) =>
                    _imlecGuncelle(d.localPosition, c.maxWidth),
                onLongPressMoveUpdate: (d) =>
                    _imlecGuncelle(d.localPosition, c.maxWidth),
                onLongPressEnd: (_) => setState(() => _imlec = null),
                onHorizontalDragStart: (d) =>
                    _imlecGuncelle(d.localPosition, c.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _imlecGuncelle(d.localPosition, c.maxWidth),
                onHorizontalDragEnd: (_) => setState(() => _imlec = null),
                onTapDown: (d) => _imlecGuncelle(d.localPosition, c.maxWidth),
                onTapUp: (_) => setState(() => _imlec = null),
                child: SizedBox(
                  height: 150,
                  child: Semantics(
                    label: 'Portföy değer grafiği, ${_donemler[_donem]}',
                    child: _Grafik(
                      key: ValueKey('$_donem-$_mod'),
                      seri: _seri,
                      imlec: _imlec,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          _Isaret(
            aktif: !widget.bitti && !_donemSecildi,
            child: _Segment(
              etiketler: _donemler,
              secili: _donem,
              onSec: _donemSec,
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          _Segment(
            etiketler: const ['Gerçek', 'Simülasyon'],
            secili: _mod,
            onSec: _modSec,
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(
            _mod == 0
                ? 'Gerçek: dönem içindeki her alım ve satımla birlikte.'
                : 'Simülasyon: bugünkü portföyü baştan elinde tutsaydın.',
            style: context.t.bodySmall?.copyWith(color: p.text36),
          ),
        ],
      ),
    );
  }
}

/// Soldan sağa çizilen çizgi grafik + dolgu + imleç.
class _Grafik extends StatefulWidget {
  const _Grafik({super.key, required this.seri, required this.imlec});

  final List<double> seri;
  final double? imlec;

  @override
  State<_Grafik> createState() => _GrafikState();
}

class _GrafikState extends State<_Grafik> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _basladi = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_basladi) return;
    _basladi = true;
    _c.duration = SandikMotion.of(context, _Sahne.uzun);
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _GrafikBoyaci(
          seri: widget.seri,
          ilerleme: SandikMotion.enter.transform(_c.value),
          imlec: widget.imlec,
          renk: p.gain,
          izgara: p.hairline,
          zemin: p.background,
        ),
      ),
    );
  }
}

class _GrafikBoyaci extends CustomPainter {
  _GrafikBoyaci({
    required this.seri,
    required this.ilerleme,
    required this.imlec,
    required this.renk,
    required this.izgara,
    required this.zemin,
  });

  final List<double> seri;
  final double ilerleme;
  final double? imlec;
  final Color renk;
  final Color izgara;
  final Color zemin;

  Offset _nokta(int i, Size s) {
    final x = i / (seri.length - 1) * s.width;
    // Üstte %8, altta %10 pay: çizgi kenara yapışmasın.
    final y = s.height * 0.08 + (1 - seri[i]) * s.height * 0.82;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Izgara: üç yatay saç teli.
    final izgaraBoya = Paint()
      ..color = izgara
      ..strokeWidth = 1;
    for (final f in const [0.25, 0.5, 0.75]) {
      final y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), izgaraBoya);
    }

    if (seri.length < 2) return;

    // Yumuşatılmış yol: her nokta çifti arasında orta noktadan geçen
    // ikinci derece eğri — Catmull-Rom'un ucuz kardeşi, yeterince akıcı.
    final yol = Path()..moveTo(_nokta(0, size).dx, _nokta(0, size).dy);
    for (var i = 1; i < seri.length; i++) {
      final a = _nokta(i - 1, size);
      final b = _nokta(i, size);
      final orta = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      yol.quadraticBezierTo(a.dx, a.dy, orta.dx, orta.dy);
    }
    final sonNokta = _nokta(seri.length - 1, size);
    yol.lineTo(sonNokta.dx, sonNokta.dy);

    // Çizim ilerlemesi: yolun yalnızca ilk [ilerleme] kadarı görünür.
    final olcumler = yol.computeMetrics().toList();
    final toplam = olcumler.fold<double>(0, (t, m) => t + m.length);
    var kalan = toplam * ilerleme;
    final gorunen = Path();
    for (final m in olcumler) {
      if (kalan <= 0) break;
      final parca = math.min(kalan, m.length);
      gorunen.addPath(m.extractPath(0, parca), Offset.zero);
      kalan -= parca;
    }

    // Dolgu: görünen yolun altı, aşağı doğru sönen gradient.
    final ucNokta = gorunen.computeMetrics().fold<Offset?>(null, (_, m) {
      final t = m.getTangentForOffset(m.length);
      return t?.position;
    });
    if (ucNokta != null) {
      final dolgu = Path.from(gorunen)
        ..lineTo(ucNokta.dx, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        dolgu,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [renk.withValues(alpha: 0.28), renk.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }

    canvas.drawPath(
      gorunen,
      Paint()
        ..color = renk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Uç noktada parlayan nokta (çizim bittiğinde).
    if (ilerleme >= 1 && imlec == null) {
      canvas.drawCircle(
          sonNokta, 7, Paint()..color = renk.withValues(alpha: 0.25));
      canvas.drawCircle(sonNokta, 3.5, Paint()..color = renk);
    }

    // İmleç: dikey çizgi + eğri üstünde nokta.
    if (imlec case final f?) {
      final x = f * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = renk.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
      final i = f * (seri.length - 1);
      final lo = i.floor();
      final hi = math.min(lo + 1, seri.length - 1);
      final a = _nokta(lo, size);
      final b = _nokta(hi, size);
      final y = a.dy + (b.dy - a.dy) * (i - lo);
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = zemin);
      canvas.drawCircle(
        Offset(x, y),
        6,
        Paint()
          ..color = renk
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_GrafikBoyaci o) =>
      o.seri != seri ||
      o.ilerleme != ilerleme ||
      o.imlec != imlec ||
      o.renk != renk;
}

// ─── 5. Sinyaller ────────────────────────────────────────────────────────────

class _Gosterge {
  const _Gosterge(this.ad, this.deger, this.yon);
  final String ad;
  final String deger;

  /// 1 AL, -1 SAT, 0 NÖTR.
  final int yon;
}

const _gostergeler = <_Gosterge>[
  _Gosterge('RSI (14)', '41,2', 1),
  _Gosterge('MACD', '+0,84', 1),
  _Gosterge('Bollinger', 'Alt banda yakın', 1),
  _Gosterge('EMA 20/50', 'Yukarı kesişim', 1),
  _Gosterge('SMA 200', 'Fiyat altında', -1),
  _Gosterge('Stokastik', '52', 0),
];

/// Varlık detayındaki "TEKNİK SİNYALLER" bölümünün kopyası + bildirim
/// anahtarı. Görev: bildirimi aç.
class _SinyalYuzeyi extends StatefulWidget {
  const _SinyalYuzeyi({required this.bitti, required this.onBitti});

  final bool bitti;
  final VoidCallback onBitti;

  @override
  State<_SinyalYuzeyi> createState() => _SinyalYuzeyiState();
}

class _SinyalYuzeyiState extends State<_SinyalYuzeyi> {
  bool _bildirim = false;

  void _toggle(bool v) {
    setState(() => _bildirim = v);
    if (v) widget.onBitti();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    final al = _gostergeler.where((g) => g.yon > 0).length;
    final sat = _gostergeler.where((g) => g.yon < 0).length;
    final notr = _gostergeler.length - al - sat;

    return _Telefon(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Varlık başlığı — detay ekranının üstü.
          Row(
            children: [
              Container(
                width: SandikSpace.xl + SandikSpace.xs,
                height: SandikSpace.xl + SandikSpace.xs,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.amberFill.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Text(
                  'THY',
                  style: context.t.labelLarge?.copyWith(
                    color: p.amberText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: SandikSpace.sm2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Türk Hava Yolları',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.titleLarge?.copyWith(
                        color: p.text90,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'THYAO · BIST',
                      maxLines: 1,
                      style: context.t.bodySmall?.copyWith(color: p.text36),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fmtTRY(318.4, digits: 2),
                    maxLines: 1,
                    style: context.t.numMedium.copyWith(color: p.text90),
                  ),
                  Text(
                    '▲ ${fmtPct(2.1)}',
                    maxLines: 1,
                    style: context.t.bodySmall?.copyWith(
                      color: p.gain,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.md),
          SandikSectionHeader(title: 'TEKNİK SİNYALLER', count: _gostergeler.length),
          const SizedBox(height: SandikSpace.sm2),
          // Dağılım çubuğu: performans ekranındakinin aynısı, soldan sağa
          // dolarak belirir.
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: SandikMotion.of(context, _Sahne.uzun),
            curve: SandikMotion.enter,
            builder: (context, t, _) => ClipRRect(
              borderRadius: BorderRadius.circular(SandikRadius.sm),
              child: SizedBox(
                height: SandikSpace.sm2,
                child: Row(
                  children: [
                    Expanded(
                        flex: (al * 100 * t).round().clamp(1, 1000),
                        child: ColoredBox(color: p.gain)),
                    Expanded(
                        flex: (sat * 100 * t).round().clamp(1, 1000),
                        child: ColoredBox(color: p.loss)),
                    Expanded(
                        flex: (notr * 100 * t).round().clamp(1, 1000),
                        child: ColoredBox(color: p.text36)),
                    Expanded(
                        flex: (600 * (1 - t)).round().clamp(1, 1000),
                        child: ColoredBox(color: p.hairline)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          Wrap(
            spacing: SandikSpace.smd,
            runSpacing: SandikSpace.xs,
            children: [
              _lejant(context, '▲', 'AL $al', p.gain),
              _lejant(context, '▼', 'SAT $sat', p.loss),
              _lejant(context, '◆', 'NÖTR $notr', p.text36),
            ],
          ),
          const SizedBox(height: SandikSpace.smd),
          for (var i = 0; i < _gostergeler.length; i++)
            _Belir(sira: 4 + i, child: _satir(context, _gostergeler[i])),
          const SizedBox(height: SandikSpace.xs),
          _Isaret(
            aktif: !widget.bitti,
            child: SandikCard(
              elevated: true,
              padding: const EdgeInsets.symmetric(
                  horizontal: SandikSpace.smd, vertical: SandikSpace.sm),
              child: Row(
                children: [
                  Icon(
                    _bildirim
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    size: 20,
                    color: _bildirim ? p.amberText : p.text58,
                  ),
                  const SizedBox(width: SandikSpace.sm2),
                  Expanded(
                    child: Text(
                      'Yön değişince bildir',
                      maxLines: 2,
                      style: context.t.bodyMedium?.copyWith(
                        color: p.text90,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Semantics(
                    label: 'Sinyal bildirimi',
                    child: CupertinoSwitch(
                      value: _bildirim,
                      activeTrackColor: p.amberFill,
                      onChanged: _toggle,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _BoyutGecisi(
            child: _bildirim
                ? Padding(
                    padding: const EdgeInsets.only(top: SandikSpace.sm2),
                    child: _Belir(sira: 0, child: _bildirimOnizleme(context)),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: SandikSpace.sm2),
          Text(
            'Sinyaller yatırım tavsiyesi değildir.',
            style: context.t.bodySmall?.copyWith(color: p.text36),
          ),
        ],
      ),
    );
  }

  Widget _lejant(BuildContext context, String glif, String ad, Color renk) {
    final p = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(glif, style: context.t.labelSmall?.copyWith(color: renk)),
        const SizedBox(width: SandikSpace.xs),
        Text(ad,
            maxLines: 1,
            style: context.t.labelLarge?.copyWith(color: p.text58)),
      ],
    );
  }

  Widget _satir(BuildContext context, _Gosterge g) {
    final p = context.c;
    final (etiket, renk) = switch (g.yon) {
      > 0 => ('AL', p.gain),
      < 0 => ('SAT', p.loss),
      _ => ('NÖTR', p.text58),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.xs2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              g.ad,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodyMedium?.copyWith(
                color: p.text90,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              g.deger,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: context.t.bodySmall?.copyWith(color: p.text36),
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          Container(
            constraints: const BoxConstraints(minWidth: SandikSpace.xxl),
            padding: const EdgeInsets.symmetric(
                horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: renk.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(SandikRadius.sm),
            ),
            child: Text(
              etiket,
              maxLines: 1,
              style: context.t.labelLarge?.copyWith(
                color: renk,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Gelecek bildirimin önizlemesi — kilit ekranındaki gibi.
  Widget _bildirimOnizleme(BuildContext context) {
    final p = context.c;
    return Container(
      padding: const EdgeInsets.all(SandikSpace.smd),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: p.amberFill.withValues(alpha: 0.35)),
        boxShadow: p.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: SandikSpace.xl,
            height: SandikSpace.xl,
            decoration: BoxDecoration(
              gradient: p.amberGradient,
              borderRadius: BorderRadius.circular(SandikRadius.sm),
            ),
            child: Icon(Icons.account_balance_wallet_rounded,
                size: 18, color: p.onAmber),
          ),
          const SizedBox(width: SandikSpace.sm2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'sandık',
                        maxLines: 1,
                        style: context.t.labelLarge?.copyWith(
                          color: p.text58,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      'şimdi',
                      style: context.t.labelMedium?.copyWith(color: p.text36),
                    ),
                  ],
                ),
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  'THYAO · AL sinyali',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodyMedium?.copyWith(
                    color: p.text90,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '6 göstergeden 4\'ü AL diyor. Detay için dokun.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodySmall?.copyWith(color: p.text58),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 6. Ortaklık ─────────────────────────────────────────────────────────────

/// Birlikte/Ben seçici, iki kişilik toplam, davet kodu. Görev: "Birlikte"ye geç.
class _OrtaklikYuzeyi extends StatefulWidget {
  const _OrtaklikYuzeyi({required this.bitti, required this.onBitti});

  final bool bitti;
  final VoidCallback onBitti;

  @override
  State<_OrtaklikYuzeyi> createState() => _OrtaklikYuzeyiState();
}

class _OrtaklikYuzeyiState extends State<_OrtaklikYuzeyi> {
  int _sekme = 1; // 0 birlikte, 1 ben
  bool _kopyalandi = false;

  static const double _ben = 248350;
  static const double _es = 164550;

  void _sekmeSec(int i) {
    setState(() => _sekme = i);
    if (i == 0) widget.onBitti();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    final birlikte = _sekme == 0;
    return _Telefon(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Isaret(
            aktif: !widget.bitti,
            child: _Segment(
              etiketler: const ['Birlikte', 'Ben'],
              secili: _sekme,
              onSec: _sekmeSec,
            ),
          ),
          const SizedBox(height: SandikSpace.smd),
          SandikCard(
            elevated: true,
            padding: const EdgeInsets.all(SandikSpace.lgs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  birlikte ? 'ORTAK NET VARLIK' : 'TOPLAM NET VARLIK',
                  maxLines: 1,
                  style: context.t.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: p.gain,
                  ),
                ),
                const SizedBox(height: SandikSpace.xs2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _SayacTutar(
                    deger: birlikte ? _ben + _es : _ben,
                    stil: context.t.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: p.gold,
                    ),
                  ),
                ),
                const SizedBox(height: SandikSpace.smd),
                // Kimin ne kadarı: ortak görünümde iki pay çubuğu, tek
                // görünümde yalnızca sen. Yükseklik animasyonlu.
                _BoyutGecisi(
                  child: Column(
                    children: [
                      _pay(context, 'Sen', _ben, birlikte ? _ben + _es : _ben,
                          p.amberFill),
                      if (birlikte) ...[
                        const SizedBox(height: SandikSpace.sm),
                        _pay(context, 'Elif', _es, _ben + _es, p.info),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SandikSpace.smd),
          SandikCard(
            child: Row(
              children: [
                Container(
                  width: SandikSpace.xl + SandikSpace.xs,
                  height: SandikSpace.xl + SandikSpace.xs,
                  decoration: BoxDecoration(
                    color: p.amberFill.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  child: Icon(Icons.people_alt_rounded,
                      size: 20, color: p.amberText),
                ),
                const SizedBox(width: SandikSpace.sm2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Davet kodun',
                        maxLines: 1,
                        style: context.t.bodySmall?.copyWith(color: p.text36),
                      ),
                      Text(
                        'S7K-M2Q4',
                        maxLines: 1,
                        style: context.t.titleLarge?.copyWith(
                          color: p.text90,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                SandikTappable(
                  onTap: () => setState(() => _kopyalandi = true),
                  semanticLabel: 'Davet kodunu kopyala',
                  child: AnimatedContainer(
                    duration: SandikMotion.stateOf(context),
                    curve: SandikMotion.enter,
                    constraints: const BoxConstraints(minHeight: _higHedef),
                    padding: const EdgeInsets.symmetric(
                        horizontal: SandikSpace.smd),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _kopyalandi
                          ? p.gain.withValues(alpha: 0.14)
                          : p.amberFill,
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _kopyalandi
                              ? Icons.check_rounded
                              : Icons.copy_rounded,
                          size: 16,
                          color: _kopyalandi ? p.gain : p.onAmber,
                        ),
                        const SizedBox(width: SandikSpace.xs),
                        Text(
                          _kopyalandi ? 'Kopyalandı' : 'Kopyala',
                          maxLines: 1,
                          style: context.t.labelLarge?.copyWith(
                            color: _kopyalandi ? p.gain : p.onAmber,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SandikSpace.sm2),
          Text(
            'Kodu eşine gönder ya da onunkini gir; karşı taraf onaylayınca '
            'birleşir, istediğiniz an ayrılırsınız.',
            style: context.t.bodySmall?.copyWith(color: p.text36),
          ),
        ],
      ),
    );
  }

  Widget _pay(BuildContext context, String ad, double deger, double toplam,
      Color renk) {
    final p = context.c;
    return Row(
      children: [
        Container(
          width: SandikSpace.lg,
          height: SandikSpace.lg,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
          child: Text(
            ad.substring(0, 1),
            style: context.t.labelLarge?.copyWith(
              color: p.onAmber,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: SandikSpace.sm),
        SizedBox(
          width: SandikSpace.xxl,
          child: Text(
            ad,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.bodyMedium?.copyWith(
              color: p.text90,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SandikRadius.sm),
            child: SizedBox(
              height: SandikSpace.sm,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: p.hairline),
                  AnimatedFractionallySizedBox(
                    duration: SandikMotion.of(context, _Sahne.uzun),
                    curve: SandikMotion.enter,
                    alignment: Alignment.centerLeft,
                    widthFactor: (deger / toplam).clamp(0.0, 1.0),
                    child: ColoredBox(
                      color: renk,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: SandikSpace.sm),
        Text(
          fmtPct(deger / toplam * 100, digits: 0),
          maxLines: 1,
          style: context.t.numSmall.copyWith(color: p.text58),
        ),
      ],
    );
  }
}

// ─── 7. Kapanış ──────────────────────────────────────────────────────────────

/// Onay işareti + denenenlerin listesi.
class _Kapanis extends StatelessWidget {
  const _Kapanis({required this.tamamlanan});

  final Set<_Gorev> tamamlanan;

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    final sayfalar =
        _sayfalariKur().where((s) => s.gorev != _Gorev.yok).toList();
    final n = sayfalar.where((s) => tamamlanan.contains(s.gorev)).length;

    return Column(
      children: [
        _Belir(
          sira: 3,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.6, end: 1),
            duration: SandikMotion.of(context, _Sahne.belir),
            curve: Curves.elasticOut,
            builder: (context, t, child) =>
                Transform.scale(scale: t, child: child),
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: p.amberGradient,
                boxShadow: [
                  BoxShadow(
                    color: p.amberFill.withValues(alpha: 0.40),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(Icons.check_rounded, size: 60, color: p.onAmber),
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.lg),
        _Belir(
          sira: 4,
          child: SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SandikSectionHeader(
                  title: 'DENEDİKLERİN',
                  trailing: Text(
                    '$n / ${sayfalar.length}',
                    style: context.t.numSmall.copyWith(color: p.amberText),
                  ),
                ),
                const SizedBox(height: SandikSpace.sm2),
                for (final s in sayfalar)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SandikSpace.sm),
                    child: Row(
                      children: [
                        Icon(
                          tamamlanan.contains(s.gorev)
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 20,
                          color: tamamlanan.contains(s.gorev)
                              ? p.gain
                              : p.text20,
                        ),
                        const SizedBox(width: SandikSpace.sm2),
                        Expanded(
                          child: Text(
                            tamamlanan.contains(s.gorev)
                                ? s.gorevBitti!
                                : s.gorevMetni!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.bodyMedium?.copyWith(
                              color: tamamlanan.contains(s.gorev)
                                  ? p.text90
                                  : p.text58,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (n < sayfalar.length)
                  Text(
                    'Denemediklerini Profil → Tanıtım turunu yeniden izle '
                    'ile her zaman açabilirsin.',
                    style: context.t.bodySmall?.copyWith(color: p.text36),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
