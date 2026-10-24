import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:portfoy_takip/config/destek.dart';
import 'package:portfoy_takip/services/destek_maili.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';
import 'package:portfoy_takip/widgets/sandik_error_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/kaynak.dart';

/// Hata ekranında "Sorun sürüyorsa bize yaz" (2026-10-24, rapor
/// 2026-10-24_2115 §2).
///
/// Değişmezler:
///   1. E-postada yalnız sürüm + build, platform, ekran ve hata SINIFI var;
///      hata metni, tutar, sembol, e-posta YOK.
///   2. Bağlantı ilk hatada görünmez; "Tekrar dene" denenip yine hata
///      gelince görünür (görünüm yeniden kurulsa da).
///   3. E-posta açılamazsa adres seçilebilir metin + kopyala.

/// Mesajında kişisel/finansal veri taşıyan bir hata: sızarsa test yakalar.
class _SizanHata implements Exception {
  @override
  String toString() =>
      'Exception: ₺12.345,67 THYAO ali@ornek.com token=abc123 SocketYok';
}

String _cozulmus(Uri u) => Uri.decodeComponent(u.toString());

void main() {
  group('hataSinifi', () {
    test('friendlyError dallarıyla aynı sınıflar', () {
      expect(hataSinifi(null), 'bilinmeyen');
      expect(hataSinifi(const SocketException('x')), 'baglanti');
      expect(hataSinifi(TimeoutException('x')), 'baglanti');
      expect(hataSinifi(const FormatException('x')), 'veri_okuma');
      expect(hataSinifi(const AuthException('x')), 'kimlik');
      expect(hataSinifi(const PostgrestException(message: 'm', code: '23505')),
          'kayit_var');
      expect(hataSinifi(const PostgrestException(message: 'm', code: '42501')),
          'yetki');
      expect(hataSinifi(const PostgrestException(message: 'm', code: 'X')),
          'veri_islemi');
      expect(hataSinifi(const StorageException('x')), 'dosya');
      expect(hataSinifi(_SizanHata()), 'diger');
    });
  });

  group('destekHataMaili', () {
    Uri kur(Object e, {String? ekran = 'asset_detail'}) => destekHataMaili(
          error: e,
          surum: '1.4.2',
          build: '57',
          platform: 'ios',
          ekran: ekran,
        );

    test('adres, konu ve dört bilgi', () {
      final u = kur(const SocketException('x'));
      expect(u.scheme, 'mailto');
      expect(u.path, kDestekEposta);
      final m = _cozulmus(u);
      expect(m, contains('Sürüm: 1.4.2 (57)'));
      expect(m, contains('Platform: ios'));
      expect(m, contains('Ekran: asset_detail'));
      expect(m, contains('Hata sınıfı: baglanti'));
      expect(m, contains('hata bildirimi (baglanti)'));
    });

    test('hata metni, tutar, sembol, e-posta gövdeye GİRMEZ', () {
      final e = _SizanHata();
      final m = _cozulmus(kur(e));
      for (final sizinti in [
        e.toString(),
        '₺',
        '12.345',
        'THYAO',
        'ali@ornek.com',
        'token',
        'abc123',
        friendlyError(e),
      ]) {
        expect(m, isNot(contains(sizinti)), reason: sizinti);
      }
      expect(m, contains('Hata sınıfı: diger'));
    });

    test('ekran adı yoksa "-"; serbest metin süzülür', () {
      expect(_cozulmus(kur(const FormatException('x'), ekran: null)),
          contains('Ekran: -'));
      final m = _cozulmus(kur(const FormatException('x'),
          ekran: 'ekran ₺5.000 <ali@ornek.com>'));
      expect(m, isNot(contains('₺')));
      expect(m, isNot(contains('@ornek')));
    });

    test('kaynak: gövde hata nesnesini yalnız hataSinifi ile okur', () {
      final src = ekranKaynagiSync('lib/services/destek_maili.dart');
      expect(src, contains('hataSinifi(error)'));
      expect(src, isNot(contains('error.toString')));
      expect(src, isNot(contains(r'$error')));
      expect(src, isNot(contains('friendlyError(')));
      // Hata görünümü de e-postayı yalnız bu kurucuyla kurar.
      final view = ekranKaynagiSync('lib/widgets/sandik_error_view.dart');
      expect(view, contains('destekHataMaili('));
      expect(view, isNot(contains("scheme: 'mailto'")));
    });
  });

  group('HataDenemeKaydi', () {
    tearDown(HataDenemeKaydi.sifirlaTest);

    test('deneme görünümden önce ve pencere içinde → göster', () {
      var saat = DateTime(2026, 10, 24, 12);
      HataDenemeKaydi.now = () => saat;
      expect(HataDenemeKaydi.bagGorunsunMu('a', saat), isFalse);
      HataDenemeKaydi.denendi('a');
      saat = saat.add(const Duration(seconds: 5));
      expect(HataDenemeKaydi.bagGorunsunMu('a', saat), isTrue);
      // Başka ekranın denemesi sayılmaz.
      expect(HataDenemeKaydi.bagGorunsunMu('b', saat), isFalse);
      // Denemeden ÖNCE kurulmuş görünüm sonucu bilmez.
      expect(
          HataDenemeKaydi.bagGorunsunMu(
              'a', saat.subtract(const Duration(minutes: 1))),
          isFalse);
      // Pencere dışı: eski deneme sayılmaz.
      expect(
          HataDenemeKaydi.bagGorunsunMu('a', saat.add(HataDenemeKaydi.pencere)),
          isFalse);
    });
  });

  group('SandikErrorView', () {
    late DateTime saat;
    setUp(() {
      saat = DateTime(2026, 10, 24, 12);
      HataDenemeKaydi.now = () => saat;
      PackageInfo.setMockInitialValues(
        appName: 'sandık',
        packageName: 'com.sandik.app',
        version: '1.4.2',
        buildNumber: '57',
        buildSignature: '',
      );
    });
    tearDown(HataDenemeKaydi.sifirlaTest);

    /// Gerçek çağıranlar gibi: denemede yükleniyor, sonra YENİ bir hata
    /// görünümü (State kaybolur).
    Widget sahne() => MaterialApp(
          home: Scaffold(body: _Yeniden(saatIlerlet: () {
            saat = saat.add(const Duration(seconds: 3));
          })),
        );

    testWidgets('ilk hatada bağlantı yok; deneme sonrası var', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(sahne());
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('hata-bize-yaz')), findsNothing);
      expect(find.text('Tekrar Dene'), findsOneWidget);

      await t.tap(find.text('Tekrar Dene'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('hata-bize-yaz')), findsOneWidget);
      expect(find.text('Sorun sürüyorsa bize yaz'), findsOneWidget);
      // Ana eylem kalır.
      expect(find.text('Tekrar Dene'), findsOneWidget);
      // ≥44 pt ve etiketli.
      final r = t.getRect(find.byKey(const ValueKey('hata-bize-yaz')));
      expect(r.height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel(RegExp('Sorun sürüyorsa bize e-posta yaz')),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('retry denenmeden aynı görünüm yeniden çizilse de yok',
        (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SandikErrorView(error: Exception('x'), onRetry: () {}),
        ),
      ));
      await t.pumpAndSettle();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SandikErrorView(error: Exception('y'), onRetry: () {}),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('hata-bize-yaz')), findsNothing);
    });

    testWidgets('e-posta açılamazsa adres + kopyala', (t) async {
      String? pano;
      t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          pano = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await t.pumpWidget(sahne());
      await t.pumpAndSettle();
      await t.tap(find.text('Tekrar Dene'));
      await t.pumpAndSettle();
      // Testte e-posta eklentisi yok: açılış başarısız olur.
      await t.tap(find.byKey(const ValueKey('hata-bize-yaz')));
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('hata-adres-kutusu')), findsOneWidget);
      expect(find.text(kDestekEposta), findsOneWidget);
      await t.tap(find.text('Adresi kopyala'));
      await t.pump();
      expect(pano, kDestekEposta);
      await t.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}

/// Yükleniyor ↔ hata: her denemede hata görünümü yeniden KURULUR.
class _Yeniden extends StatefulWidget {
  const _Yeniden({required this.saatIlerlet});
  final VoidCallback saatIlerlet;
  @override
  State<_Yeniden> createState() => _YenidenState();
}

class _YenidenState extends State<_Yeniden> {
  bool _yukleniyor = false;
  int _n = 0;

  Future<void> _dene() async {
    setState(() => _yukleniyor = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    widget.saatIlerlet();
    if (mounted) {
      setState(() {
        _yukleniyor = false;
        _n++;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _yukleniyor
      ? const SizedBox.shrink()
      : SandikErrorView(
          key: ValueKey(_n),
          error: Exception('hata $_n'),
          onRetry: _dene,
          ekranAdi: 'deneme_ekrani',
        );
}
