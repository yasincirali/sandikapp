import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';

/// Ana ekran widget'ı — gizlilik değişmezleri.
///
/// Widget verisi cihaz genelinde okunabilir bir depoda durur (Android'de
/// `SharedPreferences`, iOS'ta App Group). Uygulama içindeki ekranların
/// aksine bu yüzey KİLİTSİZ görünür: telefon masadayken omzunun üstünden
/// bakan biri için widget uygulamadan daha kolay okunur.
///
/// Bu yüzden iki kural kilitleniyor:
///   1. Kullanıcı bakiyeyi gizlediyse tutar widget'a YAZILMAZ.
///   2. Widget'a asla varlık listesi / ticker / kullanıcı kimliği gitmez —
///      yalnızca ekranda zaten görünen özet.
///
/// Ayrıca oturum kapanışında verinin temizlendiği doğrulanır: çıkan
/// kullanıcının bakiyesi ana ekranda asılı kalmamalı.

/// `home_widget` platform kanalını yakalar — testte native taraf yok.
class _FakeHomeWidgetChannel {
  final Map<String, Object?> saved = {};
  int updateCount = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (call) async {
        switch (call.method) {
          case 'saveWidgetData':
            final args = (call.arguments as Map).cast<String, Object?>();
            saved[args['id'] as String] = args['data'];
            return true;
          case 'updateWidget':
            updateCount++;
            return true;
          case 'setAppGroupId':
            return true;
        }
        return null;
      },
    );
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
  }
}

PortfolioState _stateWithValue() => PortfolioState(
      assets: [
        Asset(
          id: 'a1',
          userId: 'u1',
          name: 'Türk Hava Yolları',
          ticker: 'THYAO',
          type: AssetType.hisse,
          quantity: 100,
          purchasePrice: 200,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 300,
          addedDate: DateTime(2026, 1, 1),
          kind: AssetKind.buy,
        ),
      ],
      usdTry: 42.0,
      eurTry: 46.0,
      gbpTry: 54.0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeHomeWidgetChannel channel;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  setUp(() {
    channel = _FakeHomeWidgetChannel()..install();
  });

  tearDown(() => channel.remove());

  group('bakiye gizliyken', () {
    test('TUTAR widget\'a yazılmaz', () async {
      final state = _stateWithValue();
      // Önce görünürken yazılan değeri öğren — testin anlamlı olması için
      // gizli halin ondan FARKLI olduğunu göstermeliyiz.
      await HomeWidgetService.instance.update(state, hideBalance: false);
      final visibleTotal = channel.saved['sandik_total'] as String;
      expect(visibleTotal, contains('30.000'),
          reason: '100 adet × ₺300 = ₺30.000 — kurulum doğru mu?');

      await HomeWidgetService.instance.update(state, hideBalance: true);
      final hiddenTotal = channel.saved['sandik_total'] as String;

      expect(hiddenTotal, isNot(contains('30.000')),
          reason: 'Kullanıcı bakiyeyi gizlemişken widget onu ifşa edemez');
      expect(hiddenTotal, '••••••');
    });

    test('değişim satırı da boşaltılır', () async {
      await HomeWidgetService.instance
          .update(_stateWithValue(), hideBalance: true);

      expect(channel.saved['sandik_change'], '',
          reason: 'Kâr/zarar tutarı da bakiyenin parçasıdır');
    });
  });

  group('bakiye görünürken', () {
    test('toplam yazılır', () async {
      await HomeWidgetService.instance
          .update(_stateWithValue(), hideBalance: false);

      expect(channel.saved['sandik_total'], contains('₺'));
      expect(channel.saved['sandik_has_data'], isTrue);
      // 100 × ₺300 = ₺30.000 net varlık.
      expect(channel.saved['sandik_total'], contains('30.000'));
    });

    test('gün içi seri YOKKEN değişim uydurulmaz', () async {
      // Widget GÜNLÜK değişim gösterir. Seri olmadan günlük ölçüm
      // yapılamaz ve rakam uydurulmaz.
      //
      // Eskiden burada `state.gainLoss` yazılıyordu — yani ÖMÜRLÜK getiri
      // (100 × (300−200) = +₺10.000, %50) "bugün" diye gösteriliyordu.
      // Kullanıcı %50'lik toplam kazancı günlük hareket sanıyordu.
      await HomeWidgetService.instance
          .update(_stateWithValue(), hideBalance: false);

      expect(channel.saved['sandik_change'], '—');
      expect(channel.saved['sandik_change'], isNot(contains('10.000')),
          reason: 'ömürlük getiri "bugün" diye gösterilemez');
    });

    test('gün içi seri VARKEN günlük değişim yazılır', () async {
      // Gün başı ₺28.000 → şimdi ₺30.000 (canlı toplam uca sabitlenir).
      // Bugün alım yok, dolayısıyla net akış sıfır: değişim +₺2.000.
      // Slotlar GEÇMİŞTE olmalı: `dayValues` gelecekteki slotları atar
      // (kaynak 24 saatlik grid üretir, günün geri kalanı henüz olmamıştır).
      final now = DateTime.now();
      final series = {
        now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch:
            28000.0,
        now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch:
            29000.0,
      };

      await HomeWidgetService.instance.update(
        _stateWithValue(),
        hideBalance: false,
        intraday: series,
      );

      final change = channel.saved['sandik_change'] as String;
      expect(change, contains('+'));
      expect(change, contains('2.000'),
          reason: '30.000 − 28.000 = +₺2.000 günlük');
      expect(channel.saved['sandik_is_positive'], isTrue);

      // Yüzde AYRI alana yazılır — kilit ekranındaki rozet düzeniyle
      // aynı. Tek metinde birleştirmek iki yüzeyi ayrıştırıyordu.
      final pct = channel.saved['sandik_change_pct'] as String;
      expect(pct, contains('%'));
      expect(pct, contains('Günlük'));
      expect(change, isNot(contains('%')),
          reason: 'yüzde tutar alanına girmemeli');
    });

    test('tarih ve piyasa durumu yazılır', () async {
      await HomeWidgetService.instance
          .update(_stateWithValue(), hideBalance: false);

      // Tarih kilit ekranıyla aynı biçimde: "16 Ağustos Pazar".
      final date = channel.saved['sandik_date'] as String;
      expect(date, isNotEmpty);
      // `\w` Türkçe harfleri kapsamaz (ğ, ü, ş, ı, ö, ç) — harf sınıfı
      // açıkça yazılır, aksi halde doğru çıktı testi kırar.
      expect(date, matches(RegExp(r'^\d{1,2} [A-Za-zÇĞİÖŞÜçğıöşü]+ '
          r'[A-Za-zÇĞİÖŞÜçğıöşü]+$')),
          reason: 'd MMMM EEEE biçimi — kilit ekranıyla aynı');

      // Piyasa durumu canlılık noktasının rengini sürer.
      expect(channel.saved['sandik_market_open'], isA<bool>());
    });

    test('widget yenileme sinyali gönderilir', () async {
      final before = channel.updateCount;
      await HomeWidgetService.instance
          .update(_stateWithValue(), hideBalance: false);

      expect(channel.updateCount, greaterThan(before),
          reason: 'Veri yazılıp widget yenilenmezse ekranda eski değer kalır');
    });
  });

  group('hassas veri sızıntısı', () {
    test('ticker / varlık adı / kullanıcı id widget\'a GİTMEZ', () async {
      await HomeWidgetService.instance
          .update(_stateWithValue(), hideBalance: false);

      final blob = channel.saved.values.join(' ');
      expect(blob, isNot(contains('THYAO')),
          reason: 'Portföy kompozisyonu kilitsiz yüzeyde görünmemeli');
      expect(blob, isNot(contains('Türk Hava Yolları')));
      expect(blob, isNot(contains('u1')),
          reason: 'Kullanıcı kimliği widget verisine sızmamalı');
    });
  });

  group('oturum kapanışı', () {
    test('clear() bakiyeyi siler ve has_data\'yı düşürür', () async {
      await HomeWidgetService.instance
          .update(_stateWithValue(), hideBalance: false);
      expect(channel.saved['sandik_has_data'], isTrue);

      await HomeWidgetService.instance.clear();

      expect(channel.saved['sandik_has_data'], isFalse,
          reason: 'Çıkış sonrası widget "veri yok" durumuna dönmeli');
      expect(channel.saved['sandik_total'], '',
          reason: 'Çıkan kullanıcının bakiyesi ana ekranda asılı kalamaz');
      expect(channel.saved['sandik_spark_points'], 0,
          reason: 'Grafik de sıfırlanmalı — çıkan kullanıcının gün içi '
              'eğrisi bir sonraki kullanıcıya görünemez');
    });
  });
}
