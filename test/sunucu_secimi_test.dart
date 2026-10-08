import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/legal_doc_screen.dart';
import 'package:portfoy_takip/services/sunucu_secimi.dart';
import 'package:portfoy_takip/widgets/sunucu_kapisi.dart';

/// Köprü sürümü (K1) — sunucu seçimi, zorunlu güncelleme kapısı, rıza metni.
///
/// Geçiş gecesi Firebase Console'da tek anahtar (`sunucu`) çevrilir. Bu
/// dosya o anahtarın ne yaptığını ve ne YAPMADIĞINI kilitler: yazım hatası
/// kimseyi bilinmeyen yere göndermez, EU'suz derleme bayraktan etkilenmez,
/// Supabase başka bir yerden başlatılmaz.

const _tokyo = 'https://ybdbzouzhzwthjgwlbmk.supabase.co';
const _frankfurt = 'https://ynwymnpdiwudrlxfrmuo.supabase.co';

SunucuYapilandirmasi? _sec(String istenen, {bool eu = true, bool birincil = true}) => sunucuSec(
      istenen: istenen,
      birincilUrl: birincil ? _tokyo : '',
      birincilKey: birincil ? 'anon-t' : '',
      euUrl: eu ? _frankfurt : '',
      euKey: eu ? 'anon-f' : '',
    );

void main() {
  group('sunucuSec — saf karar', () {
    test('varsayılan (bayrak yok) → birincil', () {
      expect(_sec('')!.url, _tokyo);
      expect(_sec('tokyo')!.url, _tokyo);
    });

    test('frankfurt + EU derlemede → Frankfurt, kendi anahtarıyla', () {
      final s = _sec('frankfurt')!;
      expect(s.url, _frankfurt);
      expect(s.anonKey, 'anon-f');
    });

    test('büyük/küçük harf ve boşluk affedilir', () {
      expect(_sec(' Frankfurt ')!.url, _frankfurt);
    });

    test('yazım hatası kimseyi bilinmeyen yere göndermez → birincil', () {
      expect(_sec('frankfrut')!.url, _tokyo);
      expect(_sec('eu')!.url, _tokyo);
    });

    test('EU derlenmemişse bayrak ETKİSİZ (yerel yığın, CI, K5 sonrası)', () {
      expect(_sec('frankfurt', eu: false)!.url, _tokyo);
    });

    test('yalnız EU derlenmişse → EU', () {
      expect(_sec('', birincil: false)!.url, _frankfurt);
    });

    test('hiçbiri yoksa null → yapılandırma hatası ekranı', () {
      expect(_sec('frankfurt', eu: false, birincil: false), isNull);
    });
  });

  group('SunucuYapilandirmasi — ülke (rıza metni)', () {
    test('bilinen projeler gerçek ülkeyi söyler', () {
      final t = _sec('')!;
      final f = _sec('frankfurt')!;
      expect((t.ad, t.ulke, t.ulkede), ('tokyo', 'Japonya', "Japonya'da"));
      expect((f.ad, f.ulke, f.ulkede), ('frankfurt', 'Almanya (AB)', "Almanya'da (AB)"));
    });

    test('bilinmeyen proje için ülke UYDURULMAZ', () {
      const s = SunucuYapilandirmasi(url: 'http://127.0.0.1:54321', anonKey: 'x');
      expect(s.ad, 'bilinmiyor');
      expect(s.ulke, isNull);
    });
  });

  group('guncellemeGerekliMi — zorunlu güncelleme kapısı', () {
    test('min build altındaysa kilitler', () {
      expect(guncellemeGerekliMi(mevcutBuild: 7, minBuild: 8), isTrue);
    });
    test('eşit ya da üstündeyse geçer', () {
      expect(guncellemeGerekliMi(mevcutBuild: 8, minBuild: 8), isFalse);
      expect(guncellemeGerekliMi(mevcutBuild: 120, minBuild: 8), isFalse);
    });
    test('kapı kapalıyken (0) kimseyi kilitlemez', () {
      expect(guncellemeGerekliMi(mevcutBuild: 7, minBuild: 0), isFalse);
    });
    test('build okunamadıysa (0) kilitlemez — bilinmeyende kilit açık bırakmaktan kötü', () {
      expect(guncellemeGerekliMi(mevcutBuild: 0, minBuild: 999), isFalse);
    });
  });

  group('rıza metni verinin gerçek ülkesini söyler', () {
    String metin(List<LegalBlock> b) =>
        b.map((x) => '${x.text} ${x.cells.join(' ')}').join('\n');

    test('Tokyo: Japonya — "ABD" Supabase için artık yazmıyor', () {
      SunucuSecimi.instance.testIcinKur(_sec('')!);
      final p = metin(LegalDocs.privacy);
      expect(p, contains("Supabase veritabanı Japonya'da, Firebase ABD'de"));
      expect(p, contains('Supabase: Japonya; Firebase ve RevenueCat: ABD'));
      expect(p, isNot(contains('ABD (AWS)')));
      expect(metin(LegalDocs.kvkk), contains('Japonya'));
      expect(metin(LegalDocs.acikRiza),
          contains("sunucuları Japonya'da bulunan Supabase Inc."));
    });

    test('Frankfurt: Almanya (AB)', () {
      SunucuSecimi.instance.testIcinKur(_sec('frankfurt')!);
      expect(metin(LegalDocs.privacy),
          contains("Supabase veritabanı Almanya'da (AB), Firebase ABD'de"));
      expect(metin(LegalDocs.acikRiza),
          contains("sunucuları Almanya'da (AB) bulunan Supabase Inc."));
    });

    test('yer tutucu hiçbir koşulda ekrana sızmaz', () {
      SunucuSecimi.instance.testIcinKur(_sec('')!);
      for (final b in [
        LegalDocs.privacy,
        LegalDocs.kvkk,
        LegalDocs.terms,
        LegalDocs.acikRiza,
      ]) {
        expect(metin(b), isNot(contains('{SUPABASE')));
      }
    });
  });

  group('SunucuKapisi', () {
    Future<void> pump(WidgetTester t) => t.pumpWidget(MaterialApp(
          builder: (_, child) => SunucuKapisi(child: child!),
          home: const Scaffold(body: Text('UYGULAMA')),
        ));

    setUp(() => SunucuSecimi.instance.testIcinKur(_sec('')!));

    testWidgets('normalde uygulama çizilir', (t) async {
      await pump(t);
      expect(find.text('UYGULAMA'), findsOneWidget);
    });

    testWidgets('sunucu değişince uygulama yerine "yeniden başlat"', (t) async {
      await pump(t);
      SunucuSecimi.instance.yenidenBaslatGerekli.value = true;
      await t.pump();
      expect(find.text('UYGULAMA'), findsNothing,
          reason: 'dondurulmuş Tokyo\'ya yazmaya çalışan yarım ekran kalmamalı');
      expect(find.text('Sandık yenilendi'), findsOneWidget);
    });

    testWidgets('güncelleme kapısı yeniden başlatmadan ÖNCELİKLİ', (t) async {
      await pump(t);
      SunucuSecimi.instance.yenidenBaslatGerekli.value = true;
      SunucuSecimi.instance.guncellemeGerekli.value = true;
      await t.pump();
      expect(find.text('Güncelleme gerekli'), findsOneWidget);
      expect(find.text('Sandık yenilendi'), findsNothing);
    });

    testWidgets('Android: "Uygulamayı kapat" İŞLEMİ bitirir (pop değil)', (t) async {
      // SystemNavigator.pop() aktiviteyi kapatıp Dart tarafını canlı
      // bırakabiliyordu → yeniden açılışta aynı kapı, aynı eski sunucu.
      // Platform değişkeni GÖVDEDE sıfırlanmalı: çerçeve değişmezleri
      // tearDown'dan önce denetliyor.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var kapandi = false;
      final onceki = SunucuKapisi.kapat;
      SunucuKapisi.kapat = () => kapandi = true;
      try {
        await pump(t);
        SunucuSecimi.instance.yenidenBaslatGerekli.value = true;
        await t.pump();
        await t.tap(find.text('Uygulamayı kapat'));
        expect(kapandi, isTrue);
      } finally {
        SunucuKapisi.kapat = onceki;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('iOS: kapatma düğmesi YOK (App Store yönergesi), yalnız anlatım', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pump(t);
        SunucuSecimi.instance.yenidenBaslatGerekli.value = true;
        await t.pump();
        expect(find.text('Uygulamayı kapat'), findsNothing);
        expect(find.textContaining('yukarı kaydırarak'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('rcGuncellendi: yalnız FARKLI sunucu kapıyı kaldırır', (t) async {
      await pump(t);
      SunucuSecimi.instance.rcGuncellendi(istenen: 'tokyo', minBuild: 0);
      await t.pump();
      expect(find.text('UYGULAMA'), findsOneWidget, reason: 'aynı sunucu → kapı yok');
    });
  });

  test('Supabase YALNIZ seçilen sunucuyla başlatılır', () {
    // Sabitleri doğrudan kullanan ikinci bir `Supabase.initialize` ya da
    // adres kuran bir servis, geçişte veriyi yanlış projeye yazardı.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('url: sunucu.url'), isTrue);
    expect(main.contains('anonKey: sunucu.anonKey'), isTrue);
    expect(main.contains('SecureSessionStorage.defaultKeyFor(sunucu.url)'), isTrue);
    expect('Supabase.initialize('.allMatches(main).length, 1);
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('supabase_config.dart')) continue;
      final s = f.readAsStringSync();
      if (f.path.endsWith('main.dart')) continue; // yapılandırma-hatası ekranı boşluğu okur
      if (f.path.endsWith('sunucu_secimi.dart')) continue; // karar burada
      expect(RegExp(r'\bsupabase(Url|AnonKey)(Eu)?\b').hasMatch(s), isFalse,
          reason: '${f.path} derleme sabitini doğrudan kullanıyor');
    }
  });
}
