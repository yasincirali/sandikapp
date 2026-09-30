import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/islem_notu.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/islem_notu_sheet.dart';
import 'package:portfoy_takip/widgets/transaction_row.dart';

/// İşlem notu — yazılıp hiçbir yerde okunmayan not (kullanıcı bildirimi
/// 2026-09-29: "not kayboluyor") artık hareket satırında ikon, dokununca
/// not sayfası, Tüm Hareketler aramasında eşleşme olarak görünür.
Asset _kayit(
  String id, {
  AssetKind kind = AssetKind.buy,
  String notes = '',
  String userId = 'u1',
  String ticker = 'THYAO.IS',
  DateTime? silindi,
}) =>
    Asset(
      id: id,
      userId: userId,
      name: 'Türk Hava Yolları',
      ticker: ticker,
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 300,
      currency: 'TRY',
      notes: notes,
      isManualPrice: false,
      addedDate: DateTime(2026, 3, 12),
      kind: kind,
      deletedAt: silindi,
    );

Future<void> _pump(WidgetTester tester, Widget w) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: Scaffold(body: w),
      ),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 't@e.com',
        displayName: 'T',
        createdAt: DateTime(2026),
      );
}

/// `updateNotes` çağrılarını kaydeder; sunucuya gitmez.
class _NotYazan extends PortfolioNotifier {
  final yazilan = <String>[];

  @override
  Future<PortfolioState> build() async => const PortfolioState();

  @override
  Future<void> updateNotes(Asset asset, String notes) async =>
      yazilan.add(notes);
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('islemNotu — hangi not görünür', () {
    test('boş / yalnızca boşluk → yok', () {
      expect(islemNotu(_kayit('a', notes: '  '), const []), isNull);
    });

    test('alış notu görünür, kırpılmış', () {
      expect(islemNotu(_kayit('a', notes: ' maaştan '), const []), 'maaştan');
    });

    test('silme kaydı (mezar taşı) hiçbir zaman not göstermez', () {
      final t = _kayit('t', kind: AssetKind.deleteLog, notes: 'maaştan');
      expect(islemNotu(t, [t]), isNull);
    });

    test('satış, aynı varlığın alış notuyla aynıysa eski kopyadır → gizli',
        () {
      final al = _kayit('a', notes: 'maaştan');
      final sat = _kayit('s', kind: AssetKind.sell, notes: 'maaştan');
      expect(islemNotu(sat, [al, sat]), isNull);
      // Alışın kendisi etkilenmez.
      expect(islemNotu(al, [al, sat]), 'maaştan');
    });

    test('satışa yazılmış farklı not görünür', () {
      final al = _kayit('a', notes: 'maaştan');
      final sat = _kayit('s', kind: AssetKind.sell, notes: 'kâr al');
      expect(islemNotu(sat, [al, sat]), 'kâr al');
    });

    test('başka varlığın aynı notu satışı gizlemez', () {
      final al = _kayit('a', notes: 'maaştan', ticker: 'SISE.IS');
      final sat = _kayit('s', kind: AssetKind.sell, notes: 'maaştan');
      expect(islemNotu(sat, [al, sat]), 'maaştan');
    });

    test('arama görünen notta, küçük harfle', () {
      final al = _kayit('a', notes: 'Maaştan aldım');
      expect(islemNotuEslesir(al, [al], 'maaş'), isTrue);
      expect(islemNotuEslesir(al, [al], 'ikramiye'), isFalse);
      // Gizlenen kopya aramada da bulunmaz.
      final sat = _kayit('s', kind: AssetKind.sell, notes: 'Maaştan aldım');
      expect(islemNotuEslesir(sat, [al, sat], 'maaş'), isFalse);
    });
  });

  group('islemNotuDuzenlenebilir', () {
    test('yalnızca sahibi, silinmemiş, mezar taşı olmayan kayıt', () {
      expect(islemNotuDuzenlenebilir(_kayit('a'), benimId: 'u1'), isTrue);
      expect(islemNotuDuzenlenebilir(_kayit('a', kind: AssetKind.sell),
          benimId: 'u1'), isTrue);
      expect(islemNotuDuzenlenebilir(_kayit('a', userId: 'ortak'),
          benimId: 'u1'), isFalse);
      expect(islemNotuDuzenlenebilir(_kayit('a'), benimId: null), isFalse);
      expect(islemNotuDuzenlenebilir(
          _kayit('a', silindi: DateTime(2026, 9, 1)), benimId: 'u1'), isFalse);
      expect(islemNotuDuzenlenebilir(_kayit('a', kind: AssetKind.deleteLog),
          benimId: 'u1'), isFalse);
    });
  });

  test('copyWithNotes taze kopya döner, aslını değiştirmez', () {
    final a = _kayit('a', notes: 'eski');
    final b = a.copyWithNotes('yeni');
    expect(a.notes, 'eski');
    expect(b.notes, 'yeni');
    expect(b.toSupabase()..remove('notes'), a.toSupabase()..remove('notes'));
  });

  group('TransactionRow not işareti', () {
    testWidgets('not varsa ikon var, satır yüksekliği değişmez',
        (tester) async {
      final a = _kayit('a', notes: 'maaştan');
      await _pump(
          tester,
          TransactionRow(
              asset: a, portfolioState: const PortfolioState()));
      final yalin = tester.getSize(find.byType(TransactionRow)).height;
      expect(find.byIcon(Icons.notes_rounded), findsNothing);

      await _pump(
          tester,
          TransactionRow(
              asset: a,
              portfolioState: const PortfolioState(),
              not: 'maaştan'));
      expect(find.byIcon(Icons.notes_rounded), findsOneWidget);
      // Not metni satırda YAZMAZ — yalnızca işaret.
      expect(find.text('maaştan'), findsNothing);
      expect(tester.getSize(find.byType(TransactionRow)).height, yalin);
    });

    testWidgets('onTap verilirse satır dokunulur', (tester) async {
      var dokunuldu = 0;
      await _pump(
          tester,
          TransactionRow(
            asset: _kayit('a'),
            portfolioState: const PortfolioState(),
            onTap: () => dokunuldu++,
          ));
      await tester.tap(find.byType(TransactionRow));
      await tester.pump(const Duration(milliseconds: 300));
      expect(dokunuldu, 1);
    });

    testWidgets('dar ekran + uzun tarih + ikon taşmaz', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _pump(
          tester,
          TransactionRow(
            asset: _kayit('a', silindi: DateTime(2026, 9, 3)),
            portfolioState: const PortfolioState(),
            silinenGorunumu: true,
            not: 'not',
          ));
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.notes_rounded), findsOneWidget);
    });
  });

  group('IslemNotuSheet', () {
    testWidgets('düzenlenebilir: alan notla dolu, Kaydet metni döndürür',
        (tester) async {
      String? sonuc;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                sonuc = await showModalBottomSheet<String>(
                  context: context,
                  builder: (_) => IslemNotuSheet(
                    asset: _kayit('a', notes: 'maaştan'),
                    not: 'maaştan',
                    duzenlenebilir: true,
                  ),
                );
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'maaştan'), findsOneWidget);
      expect(find.text('Notu sil'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ikramiyeden');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(sonuc, 'ikramiyeden');
    });

    testWidgets('notsuz kayıtta "Notu sil" yok', (tester) async {
      await _pump(
          tester,
          IslemNotuSheet(
              asset: _kayit('a'), not: null, duzenlenebilir: true));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Notu sil'), findsNothing);
    });

    testWidgets('ortak kaydı salt okunur: alan yok, neden yazılı',
        (tester) async {
      await _pump(
          tester,
          IslemNotuSheet(
            asset: _kayit('a', userId: 'ortak', notes: 'onun notu'),
            not: 'onun notu',
            duzenlenebilir: false,
            ortakKaydi: true,
          ));
      expect(find.byType(TextField), findsNothing);
      expect(find.text('onun notu'), findsOneWidget);
      expect(find.textContaining('ortağına ait'), findsOneWidget);
    });
  });

  group('Notu sil — geri alınabilir (#25)', () {
    // Emülatör testi #25 (2026-09-29): "Notu sil" onaysız ve geri
    // alınamıyordu. Onay diyaloğu yerine snackbar'da "Geri al".
    testWidgets('silince "Geri al" eski notu geri yazar', (tester) async {
      final portfoy = _NotYazan();
      final kayit = _kayit('a', notes: 'maaştan');
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(() => portfoy),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                // Oturum çözülsün: düzenlenebilirlik sahibine bakar.
                ref.watch(authProvider);
                return TextButton(
                  onPressed: () => showIslemNotuSheet(context, ref,
                      asset: kayit, not: 'maaştan'),
                  child: const Text('aç'),
                );
              },
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notu sil'));
      await tester.pumpAndSettle();
      expect(portfoy.yazilan, ['']);
      expect(find.text('Not silindi'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(portfoy.yazilan, ['', 'maaştan']);
    });

    testWidgets('not DÜZENLENİNCE "Geri al" yok (yalnız silme geri alınır)',
        (tester) async {
      final portfoy = _NotYazan();
      final kayit = _kayit('a', notes: 'maaştan');
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(() => portfoy),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                // Oturum çözülsün: düzenlenebilirlik sahibine bakar.
                ref.watch(authProvider);
                return TextButton(
                  onPressed: () => showIslemNotuSheet(context, ref,
                      asset: kayit, not: 'maaştan'),
                  child: const Text('aç'),
                );
              },
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ikramiyeden');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(portfoy.yazilan, ['ikramiyeden']);
      expect(find.text('Geri al'), findsNothing);
    });
  });
}
