import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/main_navigation_screen.dart';
import 'package:portfoy_takip/screens/onboarding_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/tour_anchor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// İlk girişte gösterilen spot ışığı turu.
///
/// 2026-09-14: tur artık ayrı bir ekran değil, gerçek ekranın üstündeki bir
/// katman. Karartma düşer, o adımın hedefi oyukla açıkta kalır ve kullanıcı
/// oyuğun içindeki GERÇEK tuşa dokunur.
///
/// ## Neden sahte ev sahibi
/// Gerçek `MainNavigationScreen` Supabase ve beş ekranın provider'larını
/// ister; testte kurulamaz. Katmanın sözleşmesi ise ekrandan bağımsız:
/// "[TourAnchor] ile işaretli hedefi bul, oyuk aç, dokunuşu geçir, görevi
/// uygulamanın durumundan oku". Buradaki ev sahibi tam olarak o sözleşmeyi
/// sağlar — hedefler sahte tuşlar, sekme/ekran durumu gerçek statik
/// kanallar (`MainNavigationScreen.aktifSekme` / `sekmeIstegi`, gerçek
/// `balanceHiddenProvider`, gerçek bir rota push'u).
///
/// ## Ne ölçülüyor
///   1. **Oyuk dokunuşu geçiriyor, karartma yutuyor.** Hedefe dokunuş alta
///      ulaşır, hedef dışına dokunuş ulaşmaz.
///   2. **Görevler gerçek durumdan okunuyor.** Göz → tercih, sekme → aktif
///      sekme, + → açılan rota; sekme görevleri kendiliğinden ilerler.
///   3. **"Devam" görevi turun kendisine yaptırıyor.** Sekme değişir, ekran
///      açılır/kapanır.
///   4. **Bulunamayan hedef atlanıyor**, boş karartmada kalınmıyor.
///   5. **Taşma yok** — dar ekran, büyük yazı tipi, hareket azalt.
///   6. **Akış bozulmadı** (kaynak denetimi).

// ── Sahte ev sahibi ─────────────────────────────────────────────────────────

/// Hedef başına dokunuş sayacı — "dokunuş alta ulaştı mı" sorusunun ölçüsü.
final _dokunus = <TourTarget, int>{};

class _EvSahibi extends StatefulWidget {
  const _EvSahibi({this.davetKoduVar = true});

  final bool davetKoduVar;

  @override
  State<_EvSahibi> createState() => _EvSahibiState();
}

class _EvSahibiState extends State<_EvSahibi> {
  bool _donemSecildi = false;

  @override
  void initState() {
    super.initState();
    MainNavigationScreen.sekmeIstegi.addListener(_istek);
  }

  @override
  void dispose() {
    MainNavigationScreen.sekmeIstegi.removeListener(_istek);
    super.dispose();
  }

  /// Gerçek `MainNavigationScreen._sekmeIstegiGeldi`'nin sahtesi.
  void _istek() {
    final i = MainNavigationScreen.sekmeIstegi.value;
    if (i == null) return;
    MainNavigationScreen.sekmeIstegi.value = null;
    if (i == 2) {
      _ekleAc();
    } else {
      MainNavigationScreen.aktifSekme.value = i;
    }
  }

  void _ekleAc() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _SahteVarlikEkle()),
    );
  }

  Widget _tus(TourTarget t, String etiket, {VoidCallback? ek}) {
    return TourAnchor(
      target: t,
      child: SizedBox(
        height: 48,
        child: TextButton(
          onPressed: () {
            _dokunus[t] = (_dokunus[t] ?? 0) + 1;
            ek?.call();
          },
          child: Text(etiket),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          const TourAnchor(
            target: TourTarget.heroKart,
            child: SizedBox(height: 120, child: Text('HERO')),
          ),
          // "Bugün" kartı — gerçek ekranda hero'nun altında (2026-09-20).
          _tus(TourTarget.bugunKarti, 'bugün'),
          _tus(TourTarget.piyasaSeridi, 'piyasa'),
          Row(
            children: [
              Expanded(child: _tus(TourTarget.yenileTusu, 'yenile')),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) => _tus(
                    TourTarget.gizleTusu,
                    'gizle',
                    ek: () => ref
                        .read(balanceHiddenProvider.notifier)
                        .set(!ref.read(balanceHiddenProvider)),
                  ),
                ),
              ),
            ],
          ),
          _tus(TourTarget.govdeSekmeleri, 'sekmeler'),
          _tus(TourTarget.donemSecici, 'dönem',
              ek: () => setState(() => _donemSecildi = true)),
          // Gerçek ekranda kapsam çipi (tür/ortak/mod) dönem satırının
          // üstünde durur; burada dönem tuşuna dokununca belirir.
          if (_donemSecildi) _tus(TourTarget.kapsamSecici, 'kapsam'),
          if (widget.davetKoduVar) _tus(TourTarget.davetKodu, 'davet'),
          _tus(TourTarget.ayarlar, 'ayarlar'),
          const SizedBox(height: 400),
        ],
      ),
      bottomNavigationBar: TourAnchor(
        target: TourTarget.altMenu,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (final (i, t, ad) in const [
                (0, TourTarget.sekmeAna, 'Ana'),
                (1, TourTarget.sekmePortfoy, 'Portföy'),
                (2, TourTarget.sekmeEkle, '+'),
                (3, TourTarget.sekmePerformans, 'Performans'),
                (4, TourTarget.sekmeProfil, 'Profil'),
              ])
                Expanded(
                  child: _tus(
                    t,
                    ad,
                    ek: () {
                      if (i == 2) {
                        _ekleAc();
                      } else {
                        MainNavigationScreen.aktifSekme.value = i;
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gerçek `AddAssetScreen`'in sahtesi: ayrı bir rota, iki hedef.
class _SahteVarlikEkle extends StatelessWidget {
  const _SahteVarlikEkle();

  @override
  Widget build(BuildContext context) {
    Widget tus(TourTarget t, String ad) => TourAnchor(
          target: t,
          child: SizedBox(
            height: 48,
            child: TextButton(
              onPressed: () => _dokunus[t] = (_dokunus[t] ?? 0) + 1,
              child: Text(ad),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Varlık Ekle'),
        actions: [tus(TourTarget.topluEkle, 'toplu'), tus(TourTarget.hizliGiris, 'mik')],
      ),
      // Gerçek ekranda tür çipleri gövdenin başında (2026-09-25, kripto adımı).
      body: Align(
        alignment: Alignment.topLeft,
        child: tus(TourTarget.turSecici, 'türler'),
      ),
    );
  }
}

// ── Yardımcılar ─────────────────────────────────────────────────────────────

bool? _sonuc;

Future<void> _pump(
  WidgetTester tester, {
  double width = 375,
  double height = 812,
  double textScale = 1.0,
  Brightness parlaklik = Brightness.dark,
  bool hareketiAzalt = false,
  bool kisa = false,
  bool davetKoduVar = true,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final palet =
      parlaklik == Brightness.light ? SandikPalette.light : SandikPalette.dark;

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData(brightness: parlaklik, extensions: [palet]),
        // Gerçek uygulamadaki gibi: katman Navigator'ı sarar.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: hareketiAzalt,
          ),
          child: OnboardingTourHost(child: child!),
        ),
        home: _EvSahibi(davetKoduVar: davetKoduVar),
      ),
    ),
  );
  await tester.pump();
  OnboardingScreen.baslatTur(onBitti: (t) => _sonuc = t, kisa: kisa);
  await _bekle(tester);
}

/// `pumpAndSettle` KULLANILMAZ: nabız halkası sonsuz döngüdür. Sabit süre
/// ilerletilir (1,35s); görev onayı (720ms) bu sürede biter, hedef bekleme
/// süresi (1,9s) bitmez — atlanma ayrıca [_uzunBekle] ile ölçülür.
Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 450));
  }
}

Future<void> _uzunBekle(WidgetTester tester) async {
  await _bekle(tester);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Finder get _ileri => find.text('Devam').evaluate().isNotEmpty
    ? find.text('Devam')
    : find.text('Başlayalım');

Future<void> _devam(WidgetTester tester) async {
  await tester.tap(_ileri);
  await _bekle(tester);
}

/// Turu sonuna kadar gez — SON tuşa BASMADAN.
Future<int> _turuGez(WidgetTester tester) async {
  var adim = 0;
  while (find.text('Sandığımı Aç').evaluate().isEmpty) {
    expect(tester.takeException(), isNull, reason: '$adim. adımda taşma');
    await _devam(tester);
    adim++;
    if (adim > 30) fail('Tur bitmedi — "Sandığımı Aç" hiç gelmedi.');
  }
  expect(tester.takeException(), isNull, reason: 'son adımda taşma');
  return adim;
}

Future<void> _adimaGit(WidgetTester tester, String baslik) async {
  for (var i = 0; i < 30; i++) {
    if (find.text(baslik).evaluate().isNotEmpty) return;
    await _devam(tester);
  }
  fail('"$baslik" adımına ulaşılamadı.');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _dokunus.clear();
    _sonuc = null;
    MainNavigationScreen.aktifSekme.value = 0;
    MainNavigationScreen.sekmeIstegi.value = null;
  });

  group('katman', () {
    testWidgets('karşılama kartı, ilerleme ve Atla', (tester) async {
      await _pump(tester);
      expect(find.text('Sandığına hoş geldin'), findsOneWidget);
      expect(find.text('Başlayalım'), findsOneWidget);
      expect(find.text('Atla'), findsOneWidget);
      // İlk adımda geri yok.
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    });

    testWidgets('Atla turu kapatır ve "tamamlanmadı" der', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Atla'));
      await _bekle(tester);
      expect(_sonuc, isFalse);
      expect(find.text('Atla'), findsNothing);
      // Ev sahibi olduğu gibi duruyor; karartma kalktı, tuşlar dokunulabilir.
      await tester.tap(find.text('yenile'));
      expect(_dokunus[TourTarget.yenileTusu], 1);
    });

    testWidgets('tur baştan sona gezilir; son tuş "tamamlandı" der',
        (tester) async {
      await _pump(tester);
      final adim = await _turuGez(tester);
      expect(adim, greaterThan(10));
      await tester.tap(find.text('Sandığımı Aç'));
      await _bekle(tester);
      expect(_sonuc, isTrue);
    });

    testWidgets('geri, bir önceki adıma döner', (tester) async {
      await _pump(tester);
      await _adimaGit(tester, 'Tutarları gizle');
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await _bekle(tester);
      expect(find.text('Toplam net varlığın'), findsOneWidget);
    });
  });

  group('kısa tur — ilk açılış', () {
    // 2026-09-20: ilk açılış 19 adımdan 5'e indi. Ölçü "ilk varlık ne
    // kadar çabuk girildi"; tam tur Ayarlar'dan (`yenidenBaslat`) açılır.
    // 2026-09-25: 6 kart — kripto adımı eklendi (kullanıcı kararı:
    // "tanıtımda kriptodan da bahsedilmeli").
    //
    // Oturum STATİK (`_Tur.oturum`): önceki test turu kapatmadan bitmişse
    // `baslat` erken döner ve eski (tam) tur görünür. Temiz başla.
    setUp(OnboardingScreen.turuKapatTestIcin);

    testWidgets('altı kartta biter ve "Hazırsın" ile kapanır', (tester) async {
      await _pump(tester, kisa: true);
      expect(find.text('Sandığına hoş geldin'), findsOneWidget);
      final adim = await _turuGez(tester);
      expect(adim, 5, reason: 'karşılama + 5 adım = 6 kart');
      expect(find.text('Hazırsın'), findsOneWidget);
      await tester.tap(find.text('Sandığımı Aç'));
      await _bekle(tester);
      expect(_sonuc, isTrue);
    });

    testWidgets(
        'kısa tur "Bugün" kartını, + tuşunu ve kriptoyu anlatır, göz tuşunu '
        'anlatmaz',
        (tester) async {
      await _pump(tester, kisa: true);
      var bugun = false, gizle = false, kripto = false;
      for (var i = 0; i < 8; i++) {
        if (find.text('Bugün ne oldu?').evaluate().isNotEmpty) bugun = true;
        if (find.text('Tutarları gizle').evaluate().isNotEmpty) gizle = true;
        if (find.text('Kripto da burada').evaluate().isNotEmpty) kripto = true;
        if (find.text('Sandığımı Aç').evaluate().isNotEmpty) break;
        await _devam(tester);
      }
      expect(bugun, isTrue, reason: 'En yeni yüzey ilk turda anlatılmalı.');
      expect(kripto, isTrue,
          reason: 'Kripto ilk açılışta anlatılmalı (kullanıcı kararı '
              '2026-09-25).');
      expect(gizle, isFalse, reason: 'İkincil özellikler tam tura ait.');
    });

    testWidgets('tam tur (Ayarlar) hâlâ uzun', (tester) async {
      await _pump(tester);
      expect(await _turuGez(tester), greaterThan(10));
    });
  });

  group('oyuk — dokunuş geçişi', () {
    testWidgets('hedefe dokunuş alta ulaşır, hedef dışı yutulur',
        (tester) async {
      await _pump(tester);
      await _adimaGit(tester, 'Tutarları gizle');

      // Hedef DIŞI: yenile tuşu karartmanın altında; dokunuş ulaşmamalı.
      await tester.tap(find.text('yenile'), warnIfMissed: false);
      await _bekle(tester);
      expect(_dokunus[TourTarget.yenileTusu], isNull);

      // Hedef: göz tuşu oyukta; dokunuş GERÇEK tuşa ulaşır.
      await tester.tap(find.text('gizle'));
      await _bekle(tester);
      expect(_dokunus[TourTarget.gizleTusu], 1);
      expect(find.text('Tutarlar gizlendi'), findsOneWidget,
          reason: 'Görev gerçek tercihten (balanceHiddenProvider) okunmalı.');
      expect(find.textContaining('Dene:'), findsNothing);
    });

    testWidgets('dokunuşa kapalı hedef: oyuk görünür ama geçirmez',
        (tester) async {
      await _pump(tester);
      await _adimaGit(tester, 'Beş tuş, tüm uygulama');
      await tester.tap(find.text('Portföy'), warnIfMissed: false);
      await _bekle(tester);
      expect(_dokunus[TourTarget.sekmePortfoy], isNull);
      expect(MainNavigationScreen.aktifSekme.value, 0);
    });
  });

  group('görevler — gerçek durumdan', () {
    testWidgets('sekme görevi: dokununca kendiliğinden ilerler',
        (tester) async {
      await _pump(tester);
      await _adimaGit(tester, 'Portföy sekmesi');
      expect(find.textContaining('Dene:'), findsOneWidget);

      await tester.tap(find.text('Portföy'));
      await _bekle(tester);
      expect(MainNavigationScreen.aktifSekme.value, 1);
      // Onay süresi geçti → sonraki adım (takip listesi) açıldı.
      expect(find.text('Takip listesi'), findsOneWidget);
    });

    testWidgets('"Devam" görevi turun kendisine yaptırır: sekme değişir',
        (tester) async {
      await _pump(tester);
      await _adimaGit(tester, 'Portföy sekmesi');
      await _devam(tester);
      expect(MainNavigationScreen.aktifSekme.value, 1,
          reason: 'Kullanıcı dokunmadıysa tur sekmeyi kendisi açmalı.');
      expect(find.text('Takip listesi'), findsOneWidget);
    });

    testWidgets('+ görevi: gerçek rota açılır, mikrofon adımı gelir',
        (tester) async {
      await _pump(tester);
      await _adimaGit(tester, 'Varlık ekle');
      await tester.tap(find.text('+'));
      await _bekle(tester);
      await _bekle(tester);
      expect(find.text('Varlık Ekle'), findsOneWidget,
          reason: 'Sahte AddAssetScreen rotası açılmalı.');
      // Kripto adımı (YENİ) tür çiplerini gösterir; dokunuşa kapalı.
      expect(find.text('Kripto da burada'), findsOneWidget);
      await tester.tap(find.text('türler'), warnIfMissed: false);
      await _bekle(tester);
      expect(_dokunus[TourTarget.turSecici], isNull);
      await _devam(tester);
      expect(find.text('Cümleyle ekle'), findsOneWidget);

      // Mikrofon dokunuşa kapalı: sheet açılıp karartmanın altında kalmasın.
      await tester.tap(find.text('mik'), warnIfMissed: false);
      await _bekle(tester);
      expect(_dokunus[TourTarget.hizliGiris], isNull);

      // Toplu ekle adımından çıkınca rota kapanır, Performans adımı gelir.
      await _devam(tester);
      expect(find.text('Toplu ekle'), findsOneWidget);
      await _devam(tester);
      await _bekle(tester);
      expect(find.text('Varlık Ekle'), findsNothing,
          reason: 'Tur açtığı ekranı arkasında bırakmamalı.');
      expect(find.text('Performans sekmesi'), findsOneWidget);
    });

    // 2026-09-15: dönem adımı görevsiz (bkz. onboarding_screen.dart).
    // Ölçü artık "görev tamamlandı mı" değil, "görevsiz adım da akışı
    // sürdürüyor mu": Dene: satırı çizilmez, Devam kapsam adımına geçer.
    testWidgets('dönem adımı görevsiz — akış kapsam adımına geçer',
        (tester) async {
      await _pump(tester);
      await _adimaGit(tester, 'Dönem seç');
      expect(find.textContaining('Dene:'), findsNothing);
      await tester.tap(find.text('dönem'));
      await _bekle(tester);
      await _devam(tester);
      expect(find.text('Kapsam ve mod'), findsOneWidget);
    });
  });

  group('hedef bulunamazsa', () {
    testWidgets('adım atlanır, boş karartmada kalınmaz', (tester) async {
      await _pump(tester, davetKoduVar: false);
      await _adimaGit(tester, 'Profil sekmesi');
      await _devam(tester); // ortaklık adımı — hedefi yok
      await _uzunBekle(tester);
      expect(find.text('Eşinle tek portföy'), findsNothing);
      expect(find.text('Ayarlar'), findsOneWidget);
    });
  });

  group('taşma — dar ekran ve büyük yazı tipi', () {
    for (final genislik in [320.0, 375.0, 430.0]) {
      for (final olcek in [1.0, 1.5, 2.0]) {
        testWidgets('${genislik.toInt()}pt @ $olcek× — tur boyunca taşmaz',
            (tester) async {
          await _pump(tester, width: genislik, textScale: olcek);
          await _turuGez(tester);
        });
      }
    }

    testWidgets('açık temada da taşmaz', (tester) async {
      await _pump(tester,
          width: 320, textScale: 1.5, parlaklik: Brightness.light);
      await _turuGez(tester);
    });

    testWidgets('kısa ekranda (SE boyu) taşmaz', (tester) async {
      await _pump(tester, width: 375, height: 667, textScale: 1.3);
      await _turuGez(tester);
    });

    testWidgets('"hareketi azalt" açıkken tur çalışır', (tester) async {
      await _pump(tester, hareketiAzalt: true);
      await _adimaGit(tester, 'Tutarları gizle');
      await tester.tap(find.text('gizle'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Tutarlar gizlendi'), findsOneWidget);
      await _turuGez(tester);
    });
  });

  group('akış korundu — kaynak denetimi', _akisTestleri);
}

// ── Akış bozulmamalı ─────────────────────────────────────────────────────────
//
// Bu ekranın dışa dönük yüzeyi `main.dart`'ın açılış akışına bağlı:
//
//   OnboardingScreen(onComplete: …, userId: …)
//   OnboardingScreen.isCompleted(uid)   → gösterilsin mi?
//   OnboardingScreen.markCompleted(uid) → bir daha gösterilmesin
//
// Bunlar widget testiyle doğrulanamıyor (Supabase + SharedPreferences
// istiyorlar), bu yüzden kaynak metni denetleniyor; projede aynı örüntü var
// (bkz. varlik_sinyal_karti_test.dart, sinyal_dagilimi_test.dart).
void _akisTestleri() {
  final kaynak = File('lib/screens/onboarding_screen.dart').readAsStringSync();

  test('dışa dönük imza aynen duruyor', () {
    expect(
      kaynak.contains(
          'const OnboardingScreen({super.key, required this.onComplete, required this.userId});'),
      isTrue,
      reason: 'Yapıcı imzası değişmiş — main.dart açılışta kırılır.',
    );
    expect(kaynak.contains('static Future<bool> isCompleted(String userId)'),
        isTrue);
    expect(kaynak.contains('static Future<void> markCompleted(String userId)'),
        isTrue);
  });

  test('tamamlama ve atlama hâlâ işaretleniyor', () {
    // Bu çağrılar düşerse tanıtım HER açılışta tekrar gösterilir.
    expect(kaynak.contains('OnboardingScreen.markCompleted(widget.userId)'),
        isTrue);
    expect(kaynak.contains('logOnboardingCompleted()'), isTrue);
    expect(kaynak.contains('logOnboardingSkipped('), isTrue);
    expect(kaynak.contains('logOnboardingStep('), isTrue);
    expect(kaynak.contains('widget.onComplete()'), isTrue);
  });

  test('"Atla" hâlâ var — tur zorunlu değil', () {
    expect(kaynak.contains("'Atla'"), isTrue);
  });

  test('ekran okuyucu adım değişimini duyuruyor', () {
    expect(kaynak.contains('liveRegion: true'), isTrue);
  });

  test('hareket, azaltılmış hareket ayarına saygı duyuyor', () {
    expect(kaynak.contains('SandikMotion.stateOf(context)'), isTrue);
    expect(kaynak.contains('SandikMotion.surfaceOf(context)'), isTrue);
    expect(kaynak.contains('disableAnimationsOf(context)'), isTrue);
  });

  test('tur gerçek ekranın üstünde çalışır — kopya yüzey yok', () {
    // Kullanıcı geri bildirimi (2026-09-14): kopya yüzeyler "font ve
    // bileşenler yine farklı duruyor". Tur MainNavigationScreen'i kurar ve
    // Overlay'e girer; kendi sahte hero kartını / alt menüsünü çizmez.
    expect(kaynak.contains('const MainNavigationScreen()'), isTrue);
    expect(kaynak.contains('TOPLAM NET VARLIK'), isFalse,
        reason: 'Hero kart kopyası geri gelmiş.');
    // Katman Navigator'ı sarmalı; aksi halde açılan rotalar turun üstüne
    // biner (ilk sürümde Overlay ile tam olarak bu oldu).
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('OnboardingTourHost(child: child!)'), isTrue,
        reason: 'MaterialApp.builder tur katmanını sarmıyor.');
  });

  test('her tur hedefi gerçek bir ekranda işaretli', () {
    // Tur, ekranda olmayan bir hedefe spot düşüremez: adım sessizce atlanır
    // ve kimse fark etmez. Her hedefin lib/screens altında bir TourAnchor'ı
    // olmalı.
    final ekranlar = Directory('lib/screens')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    for (final t in TourTarget.values) {
      expect(ekranlar.contains('TourTarget.${t.name}'), isTrue,
          reason: 'TourTarget.${t.name} hiçbir ekranda işaretli değil.');
    }
  });
}
