import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/live_activity_service.dart';

/// iOS Live Activity — seans yaşam döngüsü ve gizlilik değişmezleri.
///
/// Kilit ekranı, telefon AÇILMADAN görülebilen bir yüzeydir; buradaki
/// gizlilik kuralı ana ekran widget'ınınkinden daha sıkıdır. İki şey
/// kilitleniyor:
///
///   1. **Gösterim penceresi dışında oturum açılmaz.** Pencere kullanıcı
///      tarafından ayarlanabilir (varsayılan 10:00–18:10, hafta sonu
///      dahil). Apple oturumu 8 saatte sonlandırdığı için gerçek 7/24
///      mümkün değildir; `sessionEnd` iki sınırın erkenini alır.
///   2. **Bakiye gizliyken gerçek rakam cihaza HİÇ gitmez.** Maskeleme
///      sunum katmanında değil kaynakta yapılır.

/// MethodChannel'ı yakalar — testte native ActivityKit yok.
class _FakeLiveActivityChannel {
  final List<({String method, Map<String, Object?> args})> calls = [];
  bool supported = true;

  static const _channel = MethodChannel('com.sandik.app/live_activity');

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'isSupported') return supported;
      calls.add((
        method: call.method,
        args: ((call.arguments as Map?) ?? {}).cast<String, Object?>(),
      ));
      return true;
    });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  /// Tutar taşıyan çağrıların tüm metin alanları — gizlilik taraması için.
  Iterable<String> get allText => calls.expand(
      (c) => c.args.values.whereType<String>());
}

PortfolioState _state() => PortfolioState(
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

/// Seans içi bir an — Salı 14:30.
final _duringSession = DateTime(2026, 8, 11, 14, 30);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLiveActivityChannel channel;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    // Servis platformu `defaultTargetPlatform` ile kontrol ediyor; testler
    // masaüstünde koştuğu için iOS'a zorlanmalı, yoksa hepsi erken döner.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  setUp(() {
    channel = _FakeLiveActivityChannel()..install();
    // Servis singleton — önceki testin `_sessionActive` durumu taşmasın.
    LiveActivityService.instance.resetForTest();
  });
  tearDown(() => channel.remove());

  group('seans saatleri', () {
    test('hafta içi 10:00-18:10 arası AÇIK', () {
      // Salı.
      expect(LiveActivityService.isMarketOpen(DateTime(2026, 8, 11, 10, 0)),
          isTrue);
      expect(LiveActivityService.isMarketOpen(DateTime(2026, 8, 11, 14, 30)),
          isTrue);
      expect(LiveActivityService.isMarketOpen(DateTime(2026, 8, 11, 18, 9)),
          isTrue);
    });

    test('açılıştan önce ve kapanıştan sonra KAPALI', () {
      expect(LiveActivityService.isMarketOpen(DateTime(2026, 8, 11, 9, 59)),
          isFalse);
      // Kapanış anı dahil değil — 18:10'da seans bitmiştir.
      expect(LiveActivityService.isMarketOpen(DateTime(2026, 8, 11, 18, 10)),
          isFalse);
      expect(LiveActivityService.isMarketOpen(DateTime(2026, 8, 11, 23, 0)),
          isFalse);
    });

    test('hafta sonu her saat KAPALI', () {
      // 2026-08-15 Cumartesi, 2026-08-16 Pazar.
      expect(LiveActivityService.isMarketOpen(DateTime(2026, 8, 15, 14, 0)),
          isFalse);
      expect(LiveActivityService.isMarketOpen(DateTime(2026, 8, 16, 14, 0)),
          isFalse);
    });

    test('sessionEnd varsayılan pencerede o günün kapanışını verir', () {
      final svc = LiveActivityService.instance;
      expect(
        svc.sessionEnd(DateTime(2026, 8, 11, 10, 30)),
        DateTime(2026, 8, 11, 18, 10),
      );
    });
  });

  group('ayarlanabilir gösterim penceresi', () {
    late LiveActivityService svc;

    setUp(() {
      svc = LiveActivityService.instance;
      // Her test varsayılandan başlasın — singleton, ayarlar taşar.
      // `resetForTest` tek kaynak: varsayılan değiştiğinde testler de
      // otomatik takip eder, elle atama listesi bayatlamaz.
      svc.resetForTest();
    });

    test('varsayılan pencere BIST seansıdır', () {
      expect(svc.isWithinWindow(DateTime(2026, 8, 11, 14, 0)), isTrue);
      expect(svc.isWithinWindow(DateTime(2026, 8, 11, 22, 0)), isFalse);
    });

    test('kullanıcı geceyi kapsayan pencere seçebilir', () {
      // 22:00–06:00 — gece yarısını SARAR. Naif start<=x<end
      // karşılaştırması burada hiçbir zaman doğru olmazdı.
      svc.startMinute = 22 * 60;
      svc.endMinute = 6 * 60;

      expect(svc.isWithinWindow(DateTime(2026, 8, 11, 23, 0)), isTrue,
          reason: 'gece yarısından önce');
      expect(svc.isWithinWindow(DateTime(2026, 8, 12, 2, 0)), isTrue,
          reason: 'gece yarısından sonra');
      expect(svc.isWithinWindow(DateTime(2026, 8, 11, 12, 0)), isFalse,
          reason: 'öğlen pencere dışı');
    });

    test('başlangıç == bitiş → 7/24', () {
      svc.startMinute = 0;
      svc.endMinute = 0;
      expect(svc.isWithinWindow(DateTime(2026, 8, 11, 3, 0)), isTrue);
      expect(svc.isWithinWindow(DateTime(2026, 8, 11, 15, 0)), isTrue);
    });

    test('hafta sonu varsayılan olarak AÇIK', () {
      // Kullanıcı kararı: hafta sonu BIST kapalı olsa da portföyünü
      // görebilmeli. Banner "Piyasa kapalı" etiketiyle rakamın neden
      // sabit olduğunu zaten söylüyor.
      expect(svc.includeWeekend, isTrue);
      expect(svc.isWithinWindow(DateTime(2026, 8, 15, 14, 0)), isTrue,
          reason: 'Cumartesi 14:00 varsayılan pencerede');
    });

    test('hafta sonu kapatılabilir', () {
      svc.includeWeekend = false;
      expect(svc.isWithinWindow(DateTime(2026, 8, 15, 14, 0)), isFalse);
      expect(svc.isWithinWindow(DateTime(2026, 8, 16, 14, 0)), isFalse);
    });

    test('hafta sonu kapalıyken hafta içi etkilenmez', () {
      svc.includeWeekend = false;
      expect(svc.isWithinWindow(DateTime(2026, 8, 11, 14, 0)), isTrue);
    });
  });

  group('Apple 8 saat limiti', () {
    late LiveActivityService svc;

    setUp(() {
      svc = LiveActivityService.instance;
      svc.startMinute = LiveActivityService.defaultStartMinute;
      svc.endMinute = LiveActivityService.defaultEndMinute;
      svc.includeWeekend = false;
    });

    test('7/24 pencerede oturum 8 saatle sınırlanır', () {
      // Apple oturumu 8 saat sonra ZORLA kapatır; staleDate'i ondan
      // sonraya koymak kullanıcıya "hâlâ canlı" yanılsaması verirdi.
      svc.startMinute = 0;
      svc.endMinute = 0;
      final now = DateTime(2026, 8, 11, 9, 0);
      expect(svc.sessionEnd(now), now.add(const Duration(hours: 8)));
    });

    test('geniş pencerede erken sınır kazanır', () {
      // 08:00–23:00 = 15 saat; 8 saatlik limit daha erken.
      svc.startMinute = 8 * 60;
      svc.endMinute = 23 * 60;
      final now = DateTime(2026, 8, 11, 9, 0);
      expect(svc.sessionEnd(now), now.add(const Duration(hours: 8)));
    });

    test('dar pencerede takvim sınırı kazanır', () {
      // 10:00–14:00; 12:00'de bakınca bitişe 2 saat var.
      svc.startMinute = 10 * 60;
      svc.endMinute = 14 * 60;
      expect(
        svc.sessionEnd(DateTime(2026, 8, 11, 12, 0)),
        DateTime(2026, 8, 11, 14, 0),
      );
    });

    test('geceyi saran pencerede bitiş YARINA taşınır', () {
      svc.startMinute = 22 * 60;
      svc.endMinute = 2 * 60;
      // 23:00'te bakınca bitiş ertesi gün 02:00 olmalı — bugün 02:00
      // çoktan geçti.
      expect(
        svc.sessionEnd(DateTime(2026, 8, 11, 23, 0)),
        DateTime(2026, 8, 12, 2, 0),
      );
    });
  });

  group('piyasa kapalı etiketi', () {
    test('gösterim penceresinden BAĞIMSIZ hesaplanır', () async {
      final svc = LiveActivityService.instance;
      // Kullanıcı 7/24 seçti — ama gece piyasa yine de kapalı.
      svc.startMinute = 0;
      svc.endMinute = 0;
      svc.includeWeekend = true;
      addTearDown(() {
        svc.startMinute = LiveActivityService.defaultStartMinute;
        svc.endMinute = LiveActivityService.defaultEndMinute;
        svc.includeWeekend = false;
      });

      await svc.sync(_state(),
          hideBalance: false, now: DateTime(2026, 8, 11, 23, 0));

      expect(channel.calls, isNotEmpty, reason: '7/24 pencerede gösterilmeli');
      expect(channel.calls.first.args['isMarketOpen'], isFalse,
          reason: 'gece piyasa kapalı — banner bunu söylemeli');
    });

    test('seans içinde açık raporlanır', () async {
      await LiveActivityService.instance
          .sync(_state(), hideBalance: false, now: _duringSession);
      expect(channel.calls.first.args['isMarketOpen'], isTrue);
    });
  });

  group('oturum yaşam döngüsü', () {
    test('seans açıkken START gönderilir', () async {
      await LiveActivityService.instance
          .sync(_state(), hideBalance: false, now: _duringSession);

      expect(channel.calls.single.method, 'start');
      expect(channel.calls.single.args['sessionName'], 'Piyasa Seansı');
    });

    test('gösterim penceresi DIŞINDA hiç oturum açılmaz', () async {
      // Salı 23:00 — varsayılan pencere (10:00–18:10) dışında.
      //
      // Not: hafta sonu artık pencere dışı SAYILMAZ (varsayılan açık),
      // bu yüzden gece saati kullanılıyor.
      await LiveActivityService.instance.sync(
        _state(),
        hideBalance: false,
        now: DateTime(2026, 8, 11, 23, 0),
      );

      expect(channel.calls, isEmpty,
          reason: 'pencere dışında kilit ekranına hiçbir şey gitmemeli');
    });

    test('aynı içerik tekrar gönderilmez (pil/throttle)', () async {
      final svc = LiveActivityService.instance;
      await svc.sync(_state(), hideBalance: false, now: _duringSession);
      await svc.sync(_state(), hideBalance: false, now: _duringSession);

      expect(channel.calls.length, 1,
          reason: 'değişmeyen portföy için ikinci çağrı elenmeli');
    });

    test('endAll oturumu kapatır', () async {
      await LiveActivityService.instance.endAll();
      expect(channel.calls.single.method, 'endAll');
    });

    test('içerik aynı olsa bile sync çökmeden tamamlanır', () async {
      // Özet yazımı artık ActivityKit çağrısından BAĞIMSIZ ve erken
      // çıkıştan ÖNCE yapılıyor. Testte Supabase başlatılmadığı için
      // `_writeSummary` fırlatır; `sync`'in bunu yutup normal akışa
      // devam ettiğini kilitler (Live Activity ikincil yüzey — hiçbir
      // hata uygulamanın akışını bozmamalı).
      final svc = LiveActivityService.instance;
      await svc.sync(_state(), hideBalance: false, now: _duringSession);
      await svc.sync(_state(), hideBalance: false, now: _duringSession);

      expect(channel.calls.length, 1,
          reason: 'değişmeyen portföy için ikinci ActivityKit çağrısı elenmeli');
    });
  });

  group('özet şema sürümü', () {
    // `live_activity_sessions.summary` alan ADLARI iki sürümde aynı ama
    // ANLAMLARI farklı: v1'de `changeText` ömürlük getiriydi, v2'de
    // günlük değişim. Damga olmadan sunucu ikisini ayırt edemez ve
    // uygulamasını güncellemiş kullanıcı, DB'de duran eski özet yüzünden
    // kilit ekranında ömürlük getiriyi "Bugün" diye görmeye devam eder.

    test('güncel sürüm 3 — nakit akışından arındırılmış günlük değişim', () {
      expect(LiveActivityService.summarySchemaVersion, 3);
    });

    test('sunucudaki sabitle aynı olmalı', () {
      // Edge function'daki SUMMARY_SCHEMA_VERSION ile birebir aynı
      // olmalı. Ayrışırlarsa ya tüm push'lar sessizce atlanır (sunucu
      // ileride) ya da eski özetler push'lanır (istemci ileride).
      final fn = File('supabase/functions/push-live-activity/index.ts')
          .readAsStringSync();
      final match =
          RegExp(r'SUMMARY_SCHEMA_VERSION = (\d+)').firstMatch(fn);

      expect(match, isNotNull,
          reason: 'sunucu tarafındaki sabit bulunamadı');
      expect(int.parse(match!.group(1)!),
          LiveActivityService.summarySchemaVersion,
          reason: 'istemci ve sunucu şema sürümü ayrışmış');
    });
  });

  group('gizlilik değişmezi', () {
    test('bakiye gizliyken GERÇEK RAKAM cihaza gitmez', () async {
      await LiveActivityService.instance
          .sync(_state(), hideBalance: true, now: _duringSession);

      expect(channel.calls, isNotEmpty);

      // Portföy: 100 × 300 = 30.000 TL değer, 10.000 TL kâr.
      // Bu sayıların hiçbir biçimi gönderilen metinlerde geçmemeli.
      for (final text in channel.allText) {
        expect(text, isNot(contains('30.000')));
        expect(text, isNot(contains('10.000')));
        expect(text, isNot(contains('30000')));
        expect(text, isNot(contains('10000')));
      }

      final args = channel.calls.first.args;
      expect(args['isHidden'], isTrue);
      expect(args['totalText'], '••••••');
      expect(args['changeText'], '••••••');
    });

    test('gizliyken yön bilgisi de sızmaz', () async {
      await LiveActivityService.instance
          .sync(_state(), hideBalance: true, now: _duringSession);

      // `isPositive` sabitlenir: kâr/zarar durumu renk üstünden okunamamalı.
      expect(channel.calls.first.args['isPositive'], isTrue);
    });

    test('varlık listesi / ticker ASLA gönderilmez', () async {
      await LiveActivityService.instance
          .sync(_state(), hideBalance: false, now: _duringSession);

      for (final text in channel.allText) {
        expect(text, isNot(contains('THYAO')));
        expect(text, isNot(contains('Türk Hava')));
        expect(text, isNot(contains('u1')));
        expect(text, isNot(contains('a1')));
      }
    });
  });

  group('kilit ekranı tutar gizleme', () {
    // iOS kilitli/açık ayrımı VERMEZ (ActivityKit'te böyle bir sinyal
    // yok). Bu yüzden "kilitliyken gizle" davranışı kurulamaz; yerine
    // kullanıcı tercihi taşınır ve varsayılanı KAPALI'dır.

    test('varsayılan KAPALI — tutar kilit ekranında görünmez', () async {
      final svc = LiveActivityService.instance;
      expect(svc.showAmountsOnLockScreen, isFalse,
          reason: 'gizlilik kararlarında güvenli taraf');

      await svc.sync(_state(), hideBalance: false, now: _duringSession);
      expect(channel.calls.first.args['showAmounts'], isFalse);
    });

    test('açıkken bayrak native tarafa geçer', () async {
      final svc = LiveActivityService.instance;
      svc.showAmountsOnLockScreen = true;
      addTearDown(() => svc.showAmountsOnLockScreen = false);

      await svc.sync(_state(), hideBalance: false, now: _duringSession);
      expect(channel.calls.first.args['showAmounts'], isTrue);
    });

    test('bakiye gizliyken tercih ne olursa olsun tutar gitmez', () async {
      // İki ayrı mekanizma: `hideBalance` uygulama içi göz ikonu,
      // `showAmounts` kilit ekranı tercihi. Göz ikonu daha güçlüdür.
      final svc = LiveActivityService.instance;
      svc.showAmountsOnLockScreen = true;
      addTearDown(() => svc.showAmountsOnLockScreen = false);

      await svc.sync(_state(), hideBalance: true, now: _duringSession);
      final args = channel.calls.first.args;
      expect(args['showAmounts'], isFalse);
      expect(args['totalText'], '••••••');
    });
  });

  group('sparkline', () {
    test('normalize edilir — ham TUTAR taşımaz', () async {
      await LiveActivityService.instance
          .sync(_state(), hideBalance: false, now: _duringSession);

      final spark = channel.calls.first.args['sparkline'] as List;
      // Ağ yok → seri boş gelir; asıl kilitlenen değişmez şu: gelen her
      // değer 0…1 aralığında olmalı, TL büyüklüğü ASLA sızmamalı.
      for (final v in spark) {
        expect(v, isA<num>());
        expect(v as num, inInclusiveRange(0, 1));
      }
    });

    test('bakiye gizliyken grafik HİÇ gönderilmez', () async {
      await LiveActivityService.instance
          .sync(_state(), hideBalance: true, now: _duringSession);

      // Grafiğin şekli bile bir sinyaldir: gün içi yükseliş/düşüş
      // deseni, tutar gizliyken de bilgi sızdırır.
      expect(channel.calls.first.args['sparkline'], isEmpty);
    });
  });

  group('biçimlendirme', () {
    test('Türkçe para biçimi kullanılır', () async {
      await LiveActivityService.instance
          .sync(_state(), hideBalance: false, now: _duringSession);

      final args = channel.calls.first.args;
      // 100 × 300 = 30.000 TL → binlik ayracı nokta, ondalık virgül.
      expect(args['totalText'], contains('₺'));
      expect(args['totalText'], contains('30.000'));
      expect(args['isHidden'], isFalse);
      // Saat HH:mm.
      expect(args['updatedAtText'], matches(RegExp(r'^\d{2}:\d{2}$')));
    });

    test('tarih gönderilir — gün adı dahil', () async {
      await LiveActivityService.instance
          .sync(_state(), hideBalance: false, now: _duringSession);

      // Live Activity gece yarısını geçebilir; yalnızca saat gören
      // kullanıcı rakamın hangi güne ait olduğunu bilemez.
      expect(channel.calls.first.args['dateText'], '11 Ağustos Salı');
    });

    test('bakiye gizliyken de tarih gönderilir', () async {
      // Tarih portföy bilgisi DEĞİLDİR — gizlemek için sebep yok, ve
      // olmadan kilit ekranı "hangi güne bakıyorum" sorusunu yanıtlayamaz.
      await LiveActivityService.instance
          .sync(_state(), hideBalance: true, now: _duringSession);

      expect(channel.calls.first.args['dateText'], '11 Ağustos Salı');
    });

    test('seans bitişi staleDate olarak gönderilir', () async {
      await LiveActivityService.instance
          .sync(_state(), hideBalance: false, now: _duringSession);

      expect(
        channel.calls.first.args['sessionEndsAtMs'],
        DateTime(2026, 8, 11, 18, 10).millisecondsSinceEpoch,
      );
    });
  });

  group('günlük kâr/zarar', () {
    // Kilit ekranındaki etiketler "Bugün" / "Bugünkü Değişim" / "Günlük"
    // diyor. Oraya `state.gainLoss` (varlığın alındığı GÜNDEN BUGÜNE tüm
    // getiri, temettü dahil) basılıyordu — kullanıcı %40'lık ömürlük
    // kazancı günlük hareket sanıyordu.

    test('ömürlük getiri günlük diye gösterilmez', () async {
      // Portföy: 100 × 300 = 30.000 TL değer, maliyet 20.000 → ömürlük
      // kâr 10.000 TL (%50). Bu rakam ESKİDEN kilit ekranına "Bugünkü Net
      // Kazanç" olarak basılıyordu.
      //
      // Testte ağ yok; gün içi seri her slotta seed fiyata (currentPrice)
      // düşer, yani gün DÜMDÜZ geçmiş sayılır → günlük değişim 0.
      // Uygulamanın "Bugünkü değişim" kartı da bu durumda "Değişim yok"
      // diyor; kilit ekranı da aynı şeyi söylemeli.
      await LiveActivityService.instance
          .sync(_state(), hideBalance: false, now: _duringSession);

      // Ömürlük kâr hiçbir alanda geçmemeli.
      for (final text in channel.allText) {
        expect(text, isNot(contains('10.000')),
            reason: 'ömürlük getiri günlük diye gösterilemez');
        expect(text, isNot(contains('%50')));
      }

      final args = channel.calls.first.args;
      expect(args['changePctText'], '%0,00',
          reason: 'düz gün → sıfır değişim');
    });

    test('gün içi seri HİÇ yoksa uydurma rakam gitmez', () async {
      // Varlığın `currentPrice`'ı da yoksa seed üretilemez → seri boş.
      // Bu durumda ömürlük getiriye düşmek yanlış bilgi olurdu; "—" gider.
      final noPrice = PortfolioState(
        assets: [
          Asset(
            id: 'a1',
            userId: 'u1',
            name: 'Fiyatsız',
            ticker: 'YOK',
            type: AssetType.hisse,
            quantity: 100,
            purchasePrice: 200,
            currency: 'TRY',
            notes: '',
            isManualPrice: false,
            currentPrice: 0,
            addedDate: DateTime(2026, 1, 1),
            kind: AssetKind.buy,
          ),
        ],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );

      await LiveActivityService.instance
          .sync(noPrice, hideBalance: false, now: _duringSession);

      final args = channel.calls.first.args;
      expect(args['changeText'], '—');
      expect(args['changePctText'], '—');
    });

    test('bugün yapılan alım KÂR gibi görünmez', () {
      // Gerçek kullanıcı hatası: uygulama %0,03 derken kilit ekranı
      // %6,19 "kâr" gösteriyordu. Sebep, ham uçtan uca farkın bugün
      // yatırılan parayı da içermesiydi — hiçbir fiyat hareketi olmasa
      // bile alım tutarı "kazanç" sayılıyordu.
      //
      // `todayInflow` uygulamanın `_flowOf`'uyla aynı kuralı uygular;
      // `_todayChange` bu tutarı farktan çıkarır.
      final today = DateTime(2026, 8, 11, 14, 30);
      final bought = Asset(
        id: 'b1',
        userId: 'u1',
        name: 'Bugün Alınan',
        ticker: 'YENI',
        type: AssetType.hisse,
        quantity: 100,
        purchasePrice: 200,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 200,
        addedDate: today,
        kind: AssetKind.buy,
      );

      // 100 × 200 = 20.000 TL giriş.
      expect(LiveActivityService.todayInflow([bought], today), 20000.0);
    });

    test('dünkü alım bugünün akışına GİRMEZ', () {
      // Yalnızca BUGÜN eklenen lot'lar sayılır; dün alınan bir varlık
      // bugünün değişimini etkilemez (o para dünkü gün başı değerinde
      // zaten var).
      final today = DateTime(2026, 8, 11, 14, 30);
      final old = Asset(
        id: 'o1',
        userId: 'u1',
        name: 'Dün Alınan',
        ticker: 'ESKI',
        type: AssetType.hisse,
        quantity: 100,
        purchasePrice: 200,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 220,
        addedDate: DateTime(2026, 8, 10, 11, 0),
        kind: AssetKind.buy,
      );

      expect(LiveActivityService.todayInflow([old], today), 0.0);
    });

    test('değişim gün içi serinin İLK ve SON noktasından çıkar', () {
      // Uygulamanın "Bugünkü değişim" kartıyla aynı mantık: son − ilk.
      final base = DateTime(2026, 8, 11, 10).millisecondsSinceEpoch;
      final series = {
        for (var i = 0; i < 5; i++) base + i * 5 * 60 * 1000: 1000.0 + i * 50,
      };

      final values = LiveActivityService.dayValues(
          series, DateTime(2026, 8, 11, 14, 30), 0);

      expect(values.first, 1000.0);
      expect(values.last, 1200.0);
    });
  });

  group('grafik — günlük grafikle aynı kurallar', () {
    // Kilit ekranındaki sparkline ile uygulamadaki GÜNLÜK grafik aynı
    // seriden ve aynı kurallarla çıkmalı; ayrışırlarsa kullanıcı hangisine
    // güveneceğini bilemez.

    final base = DateTime(2026, 8, 11, 0).millisecondsSinceEpoch;
    int slot(int i) => base + i * 5 * 60 * 1000;

    test('sıfır değerli slotlar atlanır', () {
      // Borsa açılmadan önceki boş slotlar. Bırakılırsa normalize aralık
      // 0'dan başlar ve gerçek gün içi hareket düz çizgiye ezilirdi —
      // grafiğin "hep aynı" görünmesinin sebebi buydu.
      final series = {
        slot(0): 0.0,
        slot(1): 0.0,
        slot(2): 1000.0,
        slot(3): 1100.0,
      };

      final values = LiveActivityService.dayValues(
          series, DateTime(2026, 8, 11, 14, 30), 0);

      expect(values, [1000.0, 1100.0]);
    });

    test('gelecekteki slotlar kırpılır', () {
      // Kaynak 24 saatlik grid üretir; günün geri kalanı henüz olmamıştır.
      final series = {
        slot(120): 1000.0, // 10:00
        slot(121): 1050.0, // 10:05
        slot(200): 9999.0, // 16:40 — "şimdi"den sonra
      };

      final values = LiveActivityService.dayValues(
          series, DateTime(2026, 8, 11, 10, 7), 0);

      expect(values, [1000.0, 1050.0],
          reason: 'olmamış bir saatin değeri grafiğe girmemeli');
    });

    test('son nokta canlı toplama sabitlenir', () {
      // Ekrandaki grafik bunu `currentTotalOverride` ile yapıyor; burada
      // yapılmazsa kilit ekranı son 5 dakikalık slotta donmuş görünür.
      final series = {slot(120): 1000.0, slot(121): 1050.0};

      final values = LiveActivityService.dayValues(
          series, DateTime(2026, 8, 11, 10, 7), 1234.0);

      expect(values.last, 1234.0);
    });

    test('hiç geçerli nokta yoksa boş döner', () {
      final series = {slot(0): 0.0, slot(1): 0.0};

      expect(
        LiveActivityService.dayValues(
            series, DateTime(2026, 8, 11, 14, 30), 0),
        isEmpty,
        reason: 'tek/hiç noktalı "çizgi" yanıltıcı olurdu',
      );
    });
  });
}
