import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/saatli_bildirim.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart'
    show denemeHakkiGunuProvider;
import 'package:portfoy_takip/providers/saatli_bildirim_provider.dart';
import 'package:portfoy_takip/services/saatli_bildirim_service.dart';
import 'package:portfoy_takip/widgets/saatli_bildirim.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Saatli fiyat bildirimi istemcisi (0188): şekil kuralı sunucuyla aynı,
/// tablo yokken hiçbir giriş çizilmez, kilit/limit davranışı.
void main() {
  group('model', () {
    test('saat kuralı sunucu tetikleyicisiyle aynı', () {
      expect(SaatliBildirim.saatlerGecerli([540, 900]), isTrue);
      expect(SaatliBildirim.saatlerGecerli([]), isFalse);
      expect(SaatliBildirim.saatlerGecerli([0, 15, 30, 45, 60]), isTrue);
      expect(SaatliBildirim.saatlerGecerli([0, 15, 30, 45, 60, 75]), isFalse,
          reason: '6. saat');
      expect(SaatliBildirim.saatlerGecerli([545]), isFalse, reason: '15 katı');
      expect(SaatliBildirim.saatlerGecerli([1440]), isFalse);
      expect(SaatliBildirim.saatlerGecerli([1425]), isTrue);
      expect(SaatliBildirim.saatlerGecerli([540, 540]), isFalse);
      expect(SaatliBildirim.tumSaatler, hasLength(96));
    });

    test('saat metni ve sessiz pencere (sarmalı dahil)', () {
      expect(SaatliBildirim.saatMetni(545 - 5), '09:00');
      expect(SaatliBildirim.saatMetni(1425), '23:45');
      expect(SaatliBildirim.sessizPencerede(23 * 60, 22, 7), isTrue);
      expect(SaatliBildirim.sessizPencerede(6 * 60 + 45, 22, 7), isTrue);
      expect(SaatliBildirim.sessizPencerede(7 * 60, 22, 7), isFalse);
      expect(SaatliBildirim.sessizPencerede(13 * 60, 12, 14), isTrue);
      expect(SaatliBildirim.sessizPencerede(13 * 60, null, 14), isFalse);
      expect(SaatliBildirim.sessizPencerede(13 * 60, 5, 5), isFalse);
    });

    test('satır okunur, saatler sıralanır', () {
      final b = SaatliBildirim.fromMap({
        'id': 'x',
        'user_id': 'u',
        'symbol': 'ALTIN_GRAM',
        'label': 'Gram altın',
        'saatler': [900, 540],
        'gunler': 127,
        'aktif': true,
        'created_at': '2026-11-26T10:00:00Z',
      });
      expect(b.saatler, [540, 900]);
      expect(b.toInsertMap()['saatler'], [540, 900]);
    });
  });

  group('kapı', () {
    test('ücretsiz tadımlık yok: paywall açıkken Premium dışı kilitli', () {
      expect(saatliDurumu(paywall: true, admin: false, premium: false),
          OzellikDurumu.kilitli);
      expect(saatliDurumu(paywall: true, admin: false, premium: true),
          OzellikDurumu.acik);
      // Paywall kapalıyken yalnız admin (gostergeParametreDurumu kuralı).
      expect(saatliDurumu(paywall: false, admin: false, premium: false),
          OzellikDurumu.gizli);
      expect(saatliDurumu(paywall: false, admin: true, premium: false),
          OzellikDurumu.acik);
    });

    test('beş varlık sınırı; var olan varlığı düzenlemek sayılmaz', () {
      final bes = [for (var i = 0; i < 5; i++) _b('S$i')];
      expect(saatliYeniVarlikEklenebilir(bes, 'YENI'), isFalse);
      expect(saatliYeniVarlikEklenebilir(bes, 'S2'), isTrue);
      expect(saatliYeniVarlikEklenebilir(bes.take(4).toList(), 'YENI'), isTrue);
    });

    test('sunucu reddi işaretle tanınır, başka 54000 değil', () {
      expect(
          saatliSiniriHatasiMi(const PostgrestException(
              message: 'saatli_siniri: en fazla 5 aktif saatli bildirim',
              code: '54000')),
          isTrue);
      expect(
          saatliSiniriHatasiMi(
              const PostgrestException(message: 'cihaz_siniri', code: '54000')),
          isFalse);
      expect(saatliSiniriHatasiMi(Exception('saatli_siniri')), isFalse);
    });
  });

  group('tablo yoklaması (dağıtım güvenliği)', () {
    test('PGRST205 / 42P01 → yok; başka hata yukarı atılır', () async {
      expect(await SaatliBildirimService(_Store(yok: 'PGRST205')).tabloVarMi(),
          isFalse);
      expect(await SaatliBildirimService(_Store(yok: '42P01')).tabloVarMi(),
          isFalse);
      expect(await SaatliBildirimService(_Store()).tabloVarMi(), isTrue);
      expect(SaatliBildirimService(_Store(yok: '42501')).tabloVarMi(),
          throwsA(isA<PostgrestException>()));
    });

    test('yoklama hatası (ağ/yetki) da gizler', () async {
      final c = await _kap(store: _Store(yok: '42501'));
      addTearDown(c.dispose);
      expect(await c.read(saatliTabloVarProvider.future), isFalse);
      expect(c.read(saatliBildirimDurumuProvider), OzellikDurumu.gizli);
    });

    test('kayıt yoksa yeni satır, varsa saat güncellemesi', () async {
      final store = _Store();
      final c = await _kap(store: store);
      addTearDown(c.dispose);
      await c.read(saatliBildirimlerProvider.future);
      final n = c.read(saatliBildirimlerProvider.notifier);
      await n.kaydet(
          userId: 'u', symbol: 'ALTIN_GRAM', label: 'Gram altın', saatler: [900, 540]);
      expect(store.eklenen.single['saatler'], [540, 900]);
      await n.kaydet(
          userId: 'u', symbol: 'ALTIN_GRAM', label: 'Gram altın', saatler: [600]);
      expect(store.eklenen, hasLength(1));
      expect(store.guncellenen, [600]);
      expect(c.read(saatliBildirimlerProvider).value!.single.saatler, [600]);
    });
  });

  group('bölüm', () {
    testWidgets('tablo yokken hiç çizilmez (yakında yazısı da yok)', (t) async {
      await t.pumpWidget(_ekran(store: _Store(yok: 'PGRST205'), premium: true));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('saatliBolumu')), findsNothing);
      expect(find.textContaining('Saatli'), findsNothing);
    });

    testWidgets('Premium: başlık, ekle düğmesi, boş satır', (t) async {
      await t.pumpWidget(_ekran(store: _Store(), premium: true));
      await t.pumpAndSettle();
      expect(find.text('Saatli bildirimler'), findsOneWidget);
      expect(find.byKey(const ValueKey('saatliEkle')), findsOneWidget);
      expect(find.text('Saatli bildirim ekle'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    });

    testWidgets('ücretsiz, kayıtsız: tek kilit satırı', (t) async {
      await t.pumpWidget(_ekran(store: _Store(), premium: false));
      await t.pumpAndSettle();
      expect(find.text('Seçtiğin saatte fiyat bildirimi Premium\'da'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('saatliEkle')), findsNothing);
    });

    testWidgets('Premium\'u biten: satırlar görünür, yeniden gönderilir kilidi',
        (t) async {
      await t.pumpWidget(_ekran(
          store: _Store(satirlar: [_b('ALTIN_GRAM').toMap()]), premium: false));
      await t.pumpAndSettle();
      expect(find.text('Gram altın ALTIN_GRAM'), findsOneWidget);
      expect(find.text('09:00 · 15:00'), findsOneWidget);
      expect(find.text('Premium\'la yeniden gönderilir'), findsOneWidget);
      expect(find.byKey(const ValueKey('saatliEkle')), findsNothing);
    });

    testWidgets('satırlar en az 44 pt', (t) async {
      await t.pumpWidget(_ekran(
          store: _Store(satirlar: [_b('ALTIN_GRAM').toMap()]), premium: true));
      await t.pumpAndSettle();
      final boy = t.getSize(find.ancestor(
          of: find.text('Gram altın ALTIN_GRAM'),
          matching: find.byType(ConstrainedBox)).first);
      expect(boy.height, greaterThanOrEqualTo(44));
    });
  });
}

SaatliBildirim _b(String s) => SaatliBildirim(
      id: 'id_$s',
      userId: 'u',
      symbol: s,
      label: 'Gram altın $s',
      saatler: const [540, 900],
      createdAt: DateTime(2026, 11, 26),
    );

extension on SaatliBildirim {
  Map<String, dynamic> toMap() => {
        ...toInsertMap(),
        'id': id,
        'created_at': createdAt.toIso8601String(),
      };
}

class _Store implements SaatliBildirimStore {
  _Store({this.yok, this.satirlar = const []});
  final String? yok;
  final List<Map<String, dynamic>> satirlar;
  final eklenen = <Map<String, dynamic>>[];
  List<int>? guncellenen;

  @override
  Future<void> yoklama() async {
    if (yok != null) throw PostgrestException(message: 'x', code: yok);
  }

  @override
  Future<List<Map<String, dynamic>>> select(String userId) async => satirlar;

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row) async {
    eklenen.add(row);
    return {...row, 'id': 'yeni', 'created_at': '2026-11-26T10:00:00Z'};
  }

  @override
  Future<Map<String, dynamic>> updateSaatler(String id, List<int> saatler) async {
    guncellenen = saatler;
    return {
      ...eklenen.last,
      'id': id,
      'saatler': saatler,
      'created_at': '2026-11-26T10:00:00Z'
    };
  }

  @override
  Future<void> delete(String id) async {}
}

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u',
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

List<Override> _overrides(SaatliBildirimStore store, {bool premium = true}) => [
      authProvider.overrideWith(_Auth.new),
      saatliBildirimServiceProvider
          .overrideWithValue(SaatliBildirimService(store)),
      paywallVisibleProvider.overrideWithValue(true),
      premiumErisimProvider.overrideWithValue(premium),
      isPushAdminProvider.overrideWith((ref) async => false),
      denemeHakkiGunuProvider.overrideWith((ref) async => null),
    ];

Future<ProviderContainer> _kap({required SaatliBildirimStore store}) async {
  final c = ProviderContainer(overrides: _overrides(store));
  await c.read(authProvider.future);
  return c;
}

Widget _ekran({required SaatliBildirimStore store, required bool premium}) =>
    ProviderScope(
      overrides: _overrides(store, premium: premium),
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: SaatliBildirimBolumu())),
      ),
    );
