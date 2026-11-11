import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/acilis_olcumu.dart';
import 'package:portfoy_takip/widgets/sekme_yigini.dart';
import 'package:portfoy_takip/widgets/tour_anchor.dart';

/// Portföy sekmesinin boşta önceden kurulumu (Ar-Ge 11 Kas 18:04 #3).
///
/// `MainNavigationScreen` testte kurulamıyor (Supabase, portföy, ağ); onun
/// kullandığı [SekmeYigini] gerçek hâliyle kurulur, sekmeler sahte.
///
/// Kilitlenen sözleşme:
///   1. İlk karede yalnız açılış sekmesi kurulu (ilk kareyle yarış yok).
///   2. İlk kare + boşta görevden sonra Portföy (1) Offstage kurulu,
///      Performans (3) hâlâ YOK (seri hesabı + ağ tetikler).
///   3. Önceden kurulan sekme "bekliyor" işaretini taşır; ilk geçişte
///      düşer ve state korunur (yeniden kurulmaz).
///   4. Koşan animasyon varken kurulum beklenir (tur, iskelet).
///   5. Offstage hedefin tur dikdörtgeni yok (spot boşluğa düşmez).
class _Sekme extends StatefulWidget {
  const _Sekme(this.ad);
  final String ad;

  static final kurulumlar = <String>[];

  @override
  State<_Sekme> createState() => _SekmeState();
}

class _SekmeState extends State<_Sekme> {
  @override
  void initState() {
    super.initState();
    _Sekme.kurulumlar.add(widget.ad);
  }

  @override
  Widget build(BuildContext context) {
    final bekliyor = SekmeOnKurulumu.bekliyor(context);
    return Center(
      child: TourAnchor(
        target: widget.ad == 'portfoy'
            ? TourTarget.govdeSekmeleri
            : TourTarget.heroKart,
        child: Text('${widget.ad}:${bekliyor ? 'bekliyor' : 'gorundu'}'),
      ),
    );
  }
}

Widget _kabuk(int index) => MaterialApp(
      home: SekmeYigini(
        index: index,
        onKurulacak: 1,
        children: const [
          _Sekme('ana'),
          _Sekme('portfoy'),
          _Sekme('ekle'),
          _Sekme('performans'),
          _Sekme('profil'),
        ],
      ),
    );

/// Kare sonu → ölçüm bekleme (ölçüm yok, hemen döner) → boşta görev
/// (`Timer.run`, sahte saatte süre geçmeden koşmaz) → kurulum karesi.
Future<void> _bostaGecsin(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  setUp(() {
    _Sekme.kurulumlar.clear();
    AcilisOlcumu.instance.sifirlaTest();
  });

  testWidgets('ilk kare + boşta: Portföy Offstage kurulu, Performans yok',
      (tester) async {
    await tester.pumpWidget(_kabuk(0));
    expect(_Sekme.kurulumlar, ['ana'],
        reason: 'İlk karede yalnız açılış sekmesi kurulmalı; önceden '
            'kurulum ana sayfanın ilk karesiyle yarışmamalı.');

    await _bostaGecsin(tester);

    expect(_Sekme.kurulumlar, containsAll(['ana', 'portfoy']));
    expect(_Sekme.kurulumlar, isNot(contains('performans')),
        reason: 'Performans seri hesabı ve ağ isteği tetikler; önceden '
            'kurulmaz.');
    expect(find.text('performans:gorundu', skipOffstage: false), findsNothing);

    // Ağaçta ama Offstage: çizilmiyor, ekranda bulunmuyor.
    expect(find.text('portfoy:bekliyor', skipOffstage: false), findsOneWidget);
    expect(find.text('portfoy:bekliyor'), findsNothing);
    final offstage = tester.widget<Offstage>(find
        .ancestor(
            of: find.text('portfoy:bekliyor', skipOffstage: false),
            matching: find.byType(Offstage, skipOffstage: false))
        .first);
    expect(offstage.offstage, isTrue);
    final ticker = tester.widget<TickerMode>(find
        .ancestor(
            of: find.text('portfoy:bekliyor', skipOffstage: false),
            matching: find.byType(TickerMode, skipOffstage: false))
        .first);
    expect(ticker.enabled, isFalse);

    // Tur: Offstage hedef "yok" sayılır.
    expect(TourTargets.mounted(TourTarget.govdeSekmeleri), isTrue);
    expect(TourTargets.rect(TourTarget.govdeSekmeleri), isNull);
  });

  testWidgets('ilk geçişte işaret düşer, sekme yeniden kurulmaz',
      (tester) async {
    await tester.pumpWidget(_kabuk(0));
    await _bostaGecsin(tester);
    expect(_Sekme.kurulumlar.where((a) => a == 'portfoy'), hasLength(1));

    await tester.pumpWidget(_kabuk(1));
    expect(find.text('portfoy:gorundu'), findsOneWidget);
    expect(_Sekme.kurulumlar.where((a) => a == 'portfoy'), hasLength(1),
        reason: 'Önceden kurulan state korunmalı; geçişte baştan '
            'kurulursa kazanç kaybolur.');
    expect(TourTargets.rect(TourTarget.govdeSekmeleri), isNotNull);
  });

  testWidgets('animasyon sürerken beklenir, bitince kurulur',
      (tester) async {
    final kontrol = AnimationController(
        vsync: const TestVSync(), duration: const Duration(seconds: 1));
    addTearDown(kontrol.dispose);
    await tester.pumpWidget(_kabuk(0));
    kontrol.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_Sekme.kurulumlar, isNot(contains('portfoy')),
        reason: 'Koşan animasyonun karesini kurulumla bölme.');

    await tester.pump(const Duration(seconds: 1)); // animasyon biter
    await _bostaGecsin(tester);
    expect(_Sekme.kurulumlar, contains('portfoy'));
  });

  testWidgets('doğrudan açılan sekmede işaret yok (eski davranış)',
      (tester) async {
    await tester.pumpWidget(_kabuk(1));
    expect(find.text('portfoy:gorundu'), findsOneWidget);
    await _bostaGecsin(tester);
    expect(_Sekme.kurulumlar, ['portfoy']);
  });
}
