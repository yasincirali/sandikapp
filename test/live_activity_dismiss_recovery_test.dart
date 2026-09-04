import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/live_activity_service.dart';

/// **Kullanıcı banner'ı silince oturum geri gelmeli.**
///
/// ## Ölçülen hata
/// `_sessionActive` yalnızca başarıda `true` yapılıyor, başarısızlıkta hiç
/// düşürülmüyordu. Kullanıcı Live Activity'yi kilit ekranından kaydırıp
/// attığında ActivityKit oturumu kapatır ama Dart'taki bayrak `true` kalır.
/// Sonraki her senkron `'update'` çağırır, native taraf aktif oturum
/// bulamayıp `false` döner, bayrak yine düşmez — **banner bir daha asla
/// açılmaz.** Bayrak süreç belleğinde yaşadığı için ancak uygulama tamamen
/// kapatılıp açılınca kurtuluyordu.
///
/// Kullanıcı bulgusu: "şimdi silince bir daha da gelmedi".
///
/// ## Bu testin sınırı
/// Native ActivityKit yok; `MethodChannel` taklit ediliyor. Doğrulanan şey
/// Dart tarafının `'start'`/`'update'` KARARI — banner'ın gerçekten çizilip
/// çizilmediği değil.
class _FakeLiveActivityChannel {
  final List<String> methods = [];

  /// `'update'` çağrısı başarısız dönsün mü? Native taraf yalnızca tek bir
  /// sebeple `false` döner: ActivityKit'te aktif oturum yok
  /// (`LiveActivityPlugin.update` → `resolveCurrent()` nil). Kullanıcının
  /// banner'ı silmesi tam olarak bu durumu yaratır.
  bool updateFails = false;

  static const _channel = MethodChannel('com.sandik.app/live_activity');

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'isSupported') return true;
      methods.add(call.method);
      if (call.method == 'update' && updateFails) return false;
      return true;
    });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

PortfolioState _state(double price) => PortfolioState(
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
          currentPrice: price,
          addedDate: DateTime(2026, 1, 1),
          kind: AssetKind.buy,
        ),
      ],
      usdTry: 42.0,
      eurTry: 46.0,
      gbpTry: 54.0,
    );

/// Seans içi bir an — hafta içine kaydırılır, yoksa `isMarketOpen` eler.
final _duringSession = () {
  var d = DateTime.now();
  if (d.weekday == DateTime.saturday) {
    d = d.subtract(const Duration(days: 1));
  } else if (d.weekday == DateTime.sunday) {
    d = d.subtract(const Duration(days: 2));
  }
  return DateTime(d.year, d.month, d.day, 14, 30);
}();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLiveActivityChannel channel;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  setUp(() {
    channel = _FakeLiveActivityChannel()..install();
    LiveActivityService.instance.resetForTest();
  });
  tearDown(() => channel.remove());

  Future<void> sync(double price) => LiveActivityService.instance.sync(
        _state(price),
        hideBalance: false,
        now: _duringSession,
      );

  test('silinen banner bir sonraki senkronda YENİDEN açılır', () async {
    // 1) İlk senkron oturumu açar.
    await sync(300);
    expect(channel.methods, ['start'],
        reason: 'ilk senkron oturumu başlatmalı');

    // 2) İçerik değişince tazelenir — buraya kadar doğru davranış.
    await sync(310);
    expect(channel.methods.last, 'update');

    // 3) Kullanıcı banner'ı kilit ekranından siler. Native taraf artık
    //    aktif oturum bulamıyor ve `update` false dönüyor.
    channel.updateFails = true;
    await sync(320);
    expect(channel.methods.last, 'update',
        reason: 'servis oturumun silindiğini bu çağrıyla ÖĞRENİR');

    // 4) ASIL İDDİA: bir sonraki senkron `start` olmalı, `update` değil.
    //    Hatalı sürümde burası sonsuza kadar `update` dönüyordu.
    channel.updateFails = false;
    await sync(330);
    expect(channel.methods.last, 'start',
        reason: 'başarısız update sonrası oturum YOK sayılmalı; aksi halde '
            'banner bir daha hiç açılmaz');
  });

  test('başarısız update dedup anahtarını da düşürür', () async {
    // `_lastPayloadKey` sıfırlanmazsa `unchanged` erken çıkışı yeni
    // `start`'ı yutar: kullanıcı banner'ı sildikten sonra rakam değişmezse
    // oturum hiç geri gelmez. Gerçek hayatta en olası senaryo bu —
    // piyasa kapanışa yakınken rakamlar dakikalarca sabit kalır.
    await sync(300);
    expect(channel.methods, ['start']);

    channel.updateFails = true;
    await sync(310);
    expect(channel.methods.last, 'update');

    // AYNI içerikle tekrar senkron. Anahtar düşürülmemiş olsaydı bu çağrı
    // hiç native'e inmezdi.
    channel.updateFails = false;
    await sync(310);
    expect(channel.methods.last, 'start',
        reason: 'içerik değişmese bile silinmiş oturum yeniden açılmalı');
  });
}
