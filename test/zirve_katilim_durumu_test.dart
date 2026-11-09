import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/zirve_portfoyler_screen.dart';
import 'package:portfoy_takip/services/leaderboard_service.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';

/// Zirve "Neden henüz havuzda değilsin?" kartı (0144, kullanıcı bulgusu
/// 2026-10-12): eski tarihli varlıkla açılan yeni hesap 7 gün şartına
/// takılıyordu ve ekran bunu söylemiyordu.
///
/// Kilitlenenler:
///   · şart satırları sunucudaki üç kapının (hesap 7 gün, ilk varlık
///     asgari gün, 2 varlık) ve dönemin ölçümünün sırasıyla yazılır;
///   · tahmini giriş: hesap şartı okuma anında, asgari süre ölçümde bakılır;
///   · havuzdaysan ya da sunucu eskiyse kart hiç çizilmez;
///   · 1×/2×/3,1× yazıda taşma yok.

final _simdi = DateTime.utc(2026, 10, 12, 22, 0);

ZirveKatilimDurumu _durum({
  DateTime? hesap,
  DateTime? varlik,
  DateTime? olcum,
  int? n = 4,
  bool olculdu = true,
  bool havuzda = false,
}) =>
    (
      hesapHazir: hesap,
      varlikHazir: varlik,
      olcumHazir: olcum,
      varlikSayisi: n,
      olculdu: olculdu,
      havuzda: havuzda,
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

Future<void> _pump(WidgetTester tester, ZirveKatilimDurumu? d,
    {double olcek = 1}) async {
  tester.view.physicalSize = const Size(320 * 3, 860 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(olcek)),
        child: child!,
      ),
      home: Scaffold(
        body: ZirveGovdesi(
          donem: ZirveDonem.ay,
          onDonem: (_) {},
          rizaYukleyici: () async => true,
          durumYukleyici: (_) async => d,
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('katilimSartlari', () {
    test('yeni hesap + eski tarihli varlık: yalnız hesap şartı eksik', () {
      final s = ZirveKiyas.katilimSartlari(
        _durum(
          hesap: DateTime.utc(2026, 10, 19, 17, 30),
          varlik: DateTime.utc(2025, 12, 1),
          olcum: DateTime.utc(2025, 12, 26),
        ),
        simdi: _simdi,
        asgariGun: 30,
        donem: ZirveDonem.ay,
      );
      expect(s.map((e) => e.tamam), [false, true, true, true]);
      expect(s.first.metin, contains("19 Ekim'de tamam"));
    });

    test('varlık yok: varlık eklemesi istenir, tarih uydurulmaz', () {
      final s = ZirveKiyas.katilimSartlari(
        _durum(hesap: DateTime.utc(2026, 9, 1), n: null, olculdu: false),
        simdi: _simdi,
        asgariGun: 30,
        donem: ZirveDonem.hafta,
      );
      expect(s[1].metin, 'Portföyüne en az bir varlık eklemelisin');
      expect(s[2].metin, contains('ilk ölçümde'));
      expect(s[3].metin, startsWith('Bu hafta getirin henüz ölçülmedi'));
    });

    test('tek varlık: şu anki sayı yazılır', () {
      final s = ZirveKiyas.katilimSartlari(
        _durum(
            hesap: DateTime.utc(2026, 9, 1),
            varlik: DateTime.utc(2026, 9, 1),
            olcum: DateTime.utc(2026, 9, 1),
            n: 1),
        simdi: _simdi,
        asgariGun: 30,
        donem: ZirveDonem.ay,
      );
      expect(s[2], (metin: 'En az 2 farklı varlığın olmalı · şu an 1', tamam: false));
    });

    test('ilk varlık satırı 5 gün ve asgari süreden geç dolanı yazar', () {
      final s = ZirveKiyas.katilimSartlari(
        _durum(
          hesap: DateTime.utc(2026, 9, 1),
          varlik: DateTime.utc(2026, 10, 14),
          olcum: DateTime.utc(2026, 11, 4, 10),
        ),
        simdi: _simdi,
        asgariGun: 30,
        donem: ZirveDonem.ay,
      );
      expect(s[1].metin, contains("4 Kasım'da tamam"));
    });
  });

  group('tahminiGiris', () {
    test('ölçüm sürmüş, hesap bekleniyor: hesap dolunca hemen', () {
      final hesap = DateTime.utc(2026, 10, 19, 17, 30);
      expect(
        ZirveKiyas.tahminiGiris(
            _durum(
                hesap: hesap,
                varlik: DateTime.utc(2025, 12, 1),
                olcum: DateTime.utc(2025, 12, 26)),
            simdi: _simdi),
        hesap,
      );
    });

    test('asgari süre bekleniyor: dolduktan sonraki ilk ölçüm (10:00/15:00 TR)',
        () {
      expect(
        ZirveKiyas.tahminiGiris(
            _durum(
                hesap: DateTime.utc(2026, 10, 5),
                varlik: DateTime.utc(2026, 10, 10),
                olcum: DateTime.utc(2026, 11, 4, 8),
                olculdu: false),
            simdi: _simdi),
        DateTime.utc(2026, 11, 4, 12),
      );
    });

    test('süre dolmuş ama dönem ölçülemiyor: tarih verilmez', () {
      final d = _durum(
          hesap: DateTime.utc(2026, 9, 1),
          varlik: DateTime.utc(2026, 9, 1),
          olcum: DateTime.utc(2026, 9, 1),
          olculdu: false);
      expect(ZirveKiyas.tahminiGiris(d, simdi: _simdi), isNull);
      expect(ZirveKiyas.girisCumlesi(d, simdi: _simdi),
          startsWith('Eksik şartlar tamamlanınca'));
    });

    test('sonrakiOlcum gün değiştirir', () {
      expect(ZirveKiyas.sonrakiOlcum(DateTime.utc(2026, 10, 12, 13)),
          DateTime.utc(2026, 10, 13, 7));
      expect(ZirveKiyas.sonrakiOlcum(DateTime.utc(2026, 10, 12, 7)),
          DateTime.utc(2026, 10, 12, 12));
    });
  });

  test('RPC satırı okunur', () {
    final d = LeaderboardService.zirveKatilimDurumuOku({
      'hesap_hazir_at': '2026-10-19T17:30:00+00:00',
      'varlik_hazir_at': null,
      'olcum_hazir_at': '2025-12-26T00:00:00+00:00',
      'varlik_sayisi': 3,
      'olculdu': true,
      'havuzda': false,
    });
    expect(d.hesapHazir, DateTime.utc(2026, 10, 19, 17, 30));
    expect(d.varlikHazir, isNull);
    expect(d.varlikSayisi, 3);
    expect(d.havuzda, isFalse);
  });

  group('kart', () {
    final eksik = _durum(
      hesap: DateTime.now().toUtc().add(const Duration(days: 6)),
      varlik: DateTime.utc(2025, 12, 1),
      olcum: DateTime.utc(2025, 12, 26),
    );

    for (final olcek in [1.0, 2.0, 3.1]) {
      testWidgets('havuzda değilsen görünür, ${olcek}x taşma yok',
          (tester) async {
        await _pump(tester, eksik, olcek: olcek);
        expect(find.text('Neden henüz havuzda değilsin?'), findsOneWidget);
        expect(find.textContaining('Hesabın en az 7 günlük olmalı'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('havuzdaysan çizilmez', (tester) async {
      await _pump(tester, _durum(havuzda: true));
      expect(find.text('Neden henüz havuzda değilsin?'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sunucu eski (null): çizilmez', (tester) async {
      await _pump(tester, null);
      expect(find.text('Neden henüz havuzda değilsin?'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
