import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/bulk_cart_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/veri_kalitesi_provider.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/supabase_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/veri_kalitesi_seridi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'helpers/kaynak.dart';
import 'helpers/yazi_olcegi.dart';

/// "N varlıkta bilgi eksik" (2026-10-20): alış fiyatı okunamayan lot (0162)
/// + 30 günden eski elle fiyat tek satırda; Portföy etiketi; ekleme yolu
/// ölçümü; tam tur ölçümü.
const _uid = 'u1';
final _simdi = DateTime(2026, 10, 20, 14);

Asset _lot(
  String id, {
  String ticker = 'THYAO.IS',
  String ad = 'THY',
  AssetType tur = AssetType.hisse,
  bool elle = false,
  bool? maliyetBilinmiyor,
  DateTime? lastUpdated,
  DateTime? createdAt,
  DateTime? addedDate,
  String? sozlesmeId,
  String userId = _uid,
}) =>
    Asset(
      id: id,
      userId: userId,
      name: ad,
      ticker: ticker,
      type: tur,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: elle,
      currentPrice: 110,
      lastUpdated: lastUpdated,
      createdAt: createdAt,
      addedDate: addedDate ?? DateTime(2026, 1, 5),
      sozlesmeId: sozlesmeId,
      maliyetBilinmiyor: maliyetBilinmiyor,
    );

List<Position> _poz(List<Asset> l) => aggregatePositions(l);

void main() {
  group('Asset.maliyetBilinmiyor (0162)', () {
    test('null iken anahtar gövdeye HİÇ yazılmaz (sütunsuz sunucu)', () {
      expect(_lot('a').toSupabase().containsKey('maliyet_bilinmiyor'),
          isFalse);
    });
    test('true/false doluyken yazılır ve geri okunur', () {
      for (final v in [true, false]) {
        final g = _lot('a', maliyetBilinmiyor: v).toSupabase();
        expect(g['maliyet_bilinmiyor'], v);
        final okunan = Asset.fromSupabase({...g, 'created_at': null});
        expect(okunan.maliyetBilinmiyor, v);
      }
    });
    test('kopyalar işareti taşır', () {
      final a = _lot('a', maliyetBilinmiyor: true);
      expect(a.copyWithDeletedAt(null).maliyetBilinmiyor, isTrue);
      expect(a.copyWithPortfoy(null).maliyetBilinmiyor, isTrue);
      expect(a.copyWithNotes('x').maliyetBilinmiyor, isTrue);
    });
  });

  group('veriEksikleri', () {
    test('maliyeti bilinmeyen lot → alış fiyatı eksik', () {
      final e = veriEksikleri(_poz([
        _lot('a', maliyetBilinmiyor: true),
        _lot('b', ticker: 'ASELS.IS', maliyetBilinmiyor: false),
      ]), simdi: _simdi);
      expect(e, hasLength(1));
      expect(e.single.tur, VeriEksigiTuru.alisFiyati);
      expect(e.single.lotlar.map((l) => l.id), ['a']);
    });

    test('elle fiyat 31 gün → eksik, 30 gün → değil', () {
      final e = veriEksikleri(_poz([
        _lot('a',
            ticker: '', ad: 'Arsa', tur: AssetType.diger, elle: true,
            lastUpdated: DateTime(2026, 9, 19, 23)),
        _lot('b',
            ticker: '', ad: 'Tablo', tur: AssetType.diger, elle: true,
            lastUpdated: DateTime(2026, 9, 20, 8)),
      ]), simdi: _simdi);
      expect(e, hasLength(1));
      expect(e.single.tur, VeriEksigiTuru.eskiFiyat);
      expect(e.single.gun, 31);
    });

    test('tarih sırası: son güncelleme > giriş anı > alış tarihi', () {
      // Geriye tarihli alım (alış 2025) ama fiyat dün girildi: eksik değil.
      expect(
          veriEksikleri(_poz([
            _lot('a',
                ticker: '', tur: AssetType.diger, elle: true,
                addedDate: DateTime(2025, 1, 1),
                createdAt: DateTime(2026, 10, 19)),
          ]), simdi: _simdi),
          isEmpty);
      expect(
          elleFiyatTarihi(_lot('a', addedDate: DateTime(2025, 1, 1))),
          DateTime(2025, 1, 1));
    });

    test('piyasa fiyatlı varlık yaşından dolayı eksik sayılmaz', () {
      expect(
          veriEksikleri(_poz([_lot('a', addedDate: DateTime(2024, 1, 1))]),
              simdi: _simdi),
          isEmpty);
    });

    test('sözleşmeli (mevduat/BES) dışarıda', () {
      expect(
          veriEksikleri(_poz([
            _lot('m',
                ticker: 'MEVDUAT:s1', tur: AssetType.mevduat, elle: true,
                sozlesmeId: 's1', maliyetBilinmiyor: true,
                addedDate: DateTime(2025, 1, 1)),
          ]), simdi: _simdi),
          isEmpty);
    });

    test('iki eksik tek pozisyonda: sayı pozisyon başına bir', () {
      final e = veriEksikleri(_poz([
        _lot('a',
            ticker: '', ad: 'Arsa', tur: AssetType.diger, elle: true,
            maliyetBilinmiyor: true, addedDate: DateTime(2025, 1, 1)),
      ]), simdi: _simdi);
      expect(e, hasLength(2));
      expect(eksikPozisyonSayisi(e), 1);
    });

    test('kapatılan anahtarlar satırı gizler, yeni eksik geri getirir', () {
      final e = veriEksikleri(_poz([_lot('a', maliyetBilinmiyor: true)]),
          simdi: _simdi);
      expect(veriSeridiGorunur(e, {}), isTrue);
      final kapali = {for (final x in e) x.anahtar};
      expect(veriSeridiGorunur(e, kapali), isFalse);
      final yeni = veriEksikleri(
          _poz([
            _lot('a', maliyetBilinmiyor: true),
            _lot('b', ticker: 'ASELS.IS', maliyetBilinmiyor: true),
          ]),
          simdi: _simdi);
      expect(veriSeridiGorunur(yeni, kapali), isTrue);
      expect(veriSeridiGorunur(const [], kapali), isFalse);
    });
  });

  group('SupabaseService.sutunsuzYenidenDene', () {
    test('bilinmeyen sütunda isteğe bağlı anahtarsız bir kez yeniden dener',
        () async {
      final gonderilen = <Map<String, dynamic>>[];
      await SupabaseService.sutunsuzYenidenDene(
          {'id': 'a', 'maliyet_bilinmiyor': true}, (b) async {
        gonderilen.add(b);
        if (gonderilen.length == 1) {
          throw const PostgrestException(message: 'x', code: 'PGRST204');
        }
      });
      expect(gonderilen, hasLength(2));
      expect(gonderilen.last.containsKey('maliyet_bilinmiyor'), isFalse);
      expect(gonderilen.last['id'], 'a');
    });

    test('başka hata ya da isteğe bağlı anahtar yoksa hata yukarı çıkar',
        () async {
      Future<void> dene(Map<String, dynamic> g, String kod) =>
          SupabaseService.sutunsuzYenidenDene(g, (_) async {
            throw PostgrestException(message: 'x', code: kod);
          });
      await expectLater(dene({'maliyet_bilinmiyor': true}, '42501'),
          throwsA(isA<PostgrestException>()));
      await expectLater(dene({'id': 'a'}, 'PGRST204'),
          throwsA(isA<PostgrestException>()));
    });
  });

  group('ekleme yolu (asset_added.yol)', () {
    test('ekstre satırı ekstre, Toplu Ekle varsayılanı toplu', () {
      final r = CsvImportService.parse('THYAO;10;300');
      expect(r.rows, isNotEmpty);
      expect(r.rows.first.yol, 'ekstre');
      final k = BulkCartItem(
        id: 'x',
        type: AssetType.hisse,
        name: 'THY',
        ticker: 'THYAO.IS',
        quantity: 1,
        price: 0,
        currency: 'TRY',
        addedDate: DateTime(2026, 10, 20),
      );
      expect(k.yol, 'toplu');
      expect(k.copyWith(price: 5).yol, 'toplu');
      expect(k.copyWith(yol: 'ekran_goruntusu').yol, 'ekran_goruntusu');
    });

    test('her logAssetAdded çağrısı yol taşır', () {
      for (final yol in [
        'lib/providers/portfolio_provider.dart',
      ]) {
        final k = ekranKaynagiSync(yol);
        final cagrilar = RegExp(r'logAssetAdded\(([^;]*)\)\);')
            .allMatches(k)
            .map((m) => m.group(1)!)
            .toList();
        expect(cagrilar, hasLength(2));
        for (final c in cagrilar) {
          expect(c, contains('yol:'), reason: c);
        }
      }
      // Ekleme yolları kendi değerini verir (varsayılan `form`a düşmez).
      expect(ekranKaynagiSync('lib/screens/add_asset_screen.dart'),
          contains("yol: 'hizli_metin'"));
      expect(ekranKaynagiSync('lib/screens/bulk_add_asset_screen.dart'),
          contains('yol: item.yol'));
      expect(ekranKaynagiSync('lib/screens/watchlist_screen.dart'),
          contains("ekleYolu: 'takip'"));
    });

    test('tam tur ölçümü: başladı / atlandı / bitti', () {
      final k = ekranKaynagiSync('lib/screens/onboarding_screen.dart');
      for (final olay in [
        'logTamTurBasladi',
        'logTamTurAtlandi',
        'logTamTurBitti',
      ]) {
        expect(k, contains(olay), reason: olay);
      }
    });
  });

  group('VeriKalitesiSeridi', () {
    setUpAll(() async {
      await initializeDateFormatting('tr_TR');
      DbLogger.silentInTests = true;
    });
    tearDownAll(() => DbLogger.silentInTests = false);
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
    });

    Future<ProviderContainer> ac(WidgetTester t, List<Asset> lotlar) async {
      final c = ProviderContainer(overrides: [
        portfolioProvider.overrideWith(() => _Portfoy(lotlar)),
        authProvider.overrideWith(_Auth.new),
        veriKalitesiSaatProvider.overrideWithValue(() => _simdi),
      ]);
      addTearDown(c.dispose);
      await c.read(portfolioProvider.future);
      await c.read(authProvider.future);
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: const Scaffold(
            body: SingleChildScrollView(child: VeriKalitesiSeridi()),
          ),
        ),
      ));
      await t.pumpAndSettle();
      return c;
    }

    testWidgets('eksik yoksa yer kaplamaz', (t) async {
      await ac(t, [_lot('a', maliyetBilinmiyor: false)]);
      expect(find.byType(SandikCard), findsNothing);
    });

    testWidgets('sayar, kapatılınca kalkar ve kalıcı kaydeder', (t) async {
      final c = await ac(t, [
        _lot('a', maliyetBilinmiyor: true),
        _lot('b',
            ticker: '', ad: 'Arsa', tur: AssetType.diger, elle: true,
            addedDate: DateTime(2025, 1, 1)),
      ]);
      expect(find.text('2 varlıkta bilgi eksik'), findsOneWidget);
      // Kapat düğmesi HIG dokunma alanı.
      final kapat = find.byTooltip('Bilgi eksik satırını kapat');
      expect(t.getSize(kapat).width, greaterThanOrEqualTo(SandikTouch.min));
      expect(t.getSize(kapat).height, greaterThanOrEqualTo(SandikTouch.min));
      await t.tap(kapat);
      await t.pumpAndSettle();
      expect(find.text('2 varlıkta bilgi eksik'), findsNothing);
      expect(c.read(veriKalitesiKapatilanProvider), hasLength(2));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('pref_veri_kalitesi_kapatilan'),
          hasLength(2));
    });

    yaziOlcegiEkseni(() {
      testWidgets('büyük yazıda taşmaz, satır ≥44pt', (t) async {
        yaziOlceginiUygula(t);
        t.view.physicalSize = const Size(320 * 3, 900 * 3);
        t.view.devicePixelRatio = 3.0;
        addTearDown(t.view.reset);
        await ac(t, [_lot('a', maliyetBilinmiyor: true)]);
        expect(t.takeException(), isNull);
        expect(t.getSize(find.byType(SandikCard)).height,
            greaterThanOrEqualTo(SandikTouch.min));
      });
    });
  });
}

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: lotlar, usdTry: 42, eurTry: 46, gbpTry: 54);
}
