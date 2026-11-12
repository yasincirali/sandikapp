import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/cihaz_provider.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/tazelik_ritmi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Arka plandan kısa dönüşte zorla fiyat turu yok (performans, 2026-11-12).
///
/// iOS'ta Face ID istemi, bildirim merkezi, Kontrol Merkezi ve uygulama
/// değiştiriciye kısa bakış `inactive → resumed` üretir. Eskiden her
/// `resumed` zorla tam fiyat turu + tüm dinleyicileri tetikliyordu.
/// Ölçü gerçek `PriceService` ağ sayacıdır (`AgSayaci`): test bağlamında
/// HTTP istemcisi her isteğe yanıt verir, sayaç her isteği sayar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final nabiz = TazelikRitmi.nabiz;
  final aralik = TazelikRitmi.yuzey;

  late DateTime simdi;
  late int dinleyiciCagri;
  late VoidCallback birak;
  late VoidCallback bagiCoz;

  int istekSayisi() {
    final a = PriceService.instance.agSayaci.anlik();
    return a.hata + a.yanit;
  }

  Future<int> donusOlc(
      List<AppLifecycleState> ara, Duration uzaktaKalma) async {
    final once = istekSayisi();
    for (final s in ara) {
      nabiz.didChangeAppLifecycleState(s);
    }
    simdi = simdi.add(uzaktaKalma);
    nabiz.didChangeAppLifecycleState(AppLifecycleState.resumed);
    // Zorla tur arka planda koşar; HTTP yanıtı için kısa süre tanınır.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return istekSayisi() - once;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    simdi = DateTime(2026, 11, 12, 10);
    nabiz.saat = () => simdi;
    dinleyiciCagri = 0;
    bagiCoz = nabiz.fiyatTuruBagla(() => PriceService.instance
        .fetchQuotes(['THYAO.IS'], forceRefresh: true));
    birak = nabiz.dinle(() => dinleyiciCagri++);
    // Nabız bir kez atmış olsun: dönüş kararı son nabızdan geçen süreye bakar.
    await nabiz.atForTest();
    dinleyiciCagri = 0;
  });

  tearDown(() {
    birak();
    bagiCoz();
    nabiz.saat = DateTime.now;
  });

  test('kısa inactive → resumed (Face ID, bildirim merkezi): ağ isteği 0',
      () async {
    final istek = await donusOlc(
        [AppLifecycleState.inactive], const Duration(seconds: 3));
    expect(istek, 0, reason: 'kısa bakış ağ turu tetiklememeli');
    expect(dinleyiciCagri, 0, reason: 'dinleyiciler de yeniden koşmamalı');
  });

  test('kısa paused (< aralık) → resumed: ağ isteği 0', () async {
    final istek = await donusOlc([
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ], aralik - const Duration(seconds: 5));
    expect(istek, 0);
  });

  test('paused + aralık (30 sn) sonra dönüş: tek tur', () async {
    final istek = await donusOlc([
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ], aralik);
    expect(istek, greaterThan(0), reason: 'bayat rakam gösterilmemeli');
    expect(dinleyiciCagri, 1, reason: 'tek tur: dinleyiciler bir kez');
  });

  test('karar saf: son nabızdan geçen süre aralığı aştı mı', () {
    final t0 = DateTime(2026, 11, 12, 10);
    expect(TazelikNabzi.donusteTurGerekir(null, t0, aralik), isTrue,
        reason: 'hiç tur yoksa hemen');
    expect(
        TazelikNabzi.donusteTurGerekir(
            t0, t0.add(const Duration(seconds: 29)), aralik),
        isFalse);
    expect(TazelikNabzi.donusteTurGerekir(t0, t0.add(aralik), aralik), isTrue);
  });

  group('diğer öne dönüş işleyicileri', () {
    test('ortak listesi: yoklama aralığı (60 sn) dolmadan yeniden çekilmez',
        () {
      final t0 = DateTime(2026, 11, 12, 10);
      expect(PartnersNotifier.donusteYuklemeGerekir(null, t0), isTrue);
      expect(
          PartnersNotifier.donusteYuklemeGerekir(
              t0, t0.add(const Duration(seconds: 30))),
          isFalse,
          reason: 'kısa bakış (Face ID, bildirim merkezi) sorgu atmamalı');
      expect(
          PartnersNotifier.donusteYuklemeGerekir(
              t0, t0.add(const Duration(seconds: 60))),
          isTrue);
    });

    test('cihaz kapısı: yalnız arka plandan (paused) dönüşte sorar', () {
      expect(CihazKapisiNotifier.donusteSorGerekir(arkayaGitti: false),
          isFalse);
      expect(
          CihazKapisiNotifier.donusteSorGerekir(arkayaGitti: true), isTrue);
    });
  });
}
