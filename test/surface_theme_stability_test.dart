import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/surface_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Kilit ekranı / widget teması müşterinin SEÇİMİNİ izler ve kendiliğinden
/// DEĞİŞMEZ.**
///
/// ## Kullanıcı bulgusu
/// "Canlı etkinlikler tema rengi sürekli değişiyor. Müşteri tema seçimi
/// neyse o şekilde görünmeli ve değişmemeli; müşteri değiştirirse değişmeli."
///
/// ## Neden oluyordu
/// Karar TABLOSU doğruydu (`resolveThemeIsLightWith`, ayrı testi var). Bozuk
/// olan kararın NE ZAMAN verildiğiydi: `main.dart`'taki portföy dinleyicisi
/// her state yayınında — fiyat tazeleme, sekme değişimi, varlık ekleme:
/// dakikada birkaç kez — cihaz görünümünü yeniden örnekliyordu. Üç etki
/// üst üste biniyordu:
///   1. varsayılan tercih `ThemeMode.system`, yani örneklenen şey CİHAZIN
///      görünümü; "Otomatik" görünümde gün içinde kendiliğinden döner,
///   2. iOS arkaya alınan uygulamanın karesini TERS görünümde de yakalar ve
///      `platformBrightness` o an ters raporlanır,
///   3. yanlış örneklenen bool `live_activity_sessions.summary`'ye yazılıyor
///      ve sunucu onu 5 dakikada bir push'luyordu — yani bir kerelik hata
///      bir sonraki öne dönüşe kadar kilit ekranında kalıyor, öne dönüşte
///      düzeliyor, sonra yine bozuluyordu.
///
/// Bu testin doğruladığı: karar artık kalıcı, tek noktada ve yalnızca meşru
/// tetikleyicilerle değişiyor. Görsel doğrulama gerçek cihazda yapılır
/// (emülatörler Flutter'ı render edemiyor — bkz. CLAUDE.md).
String _yorumsuz(String src) => src.split('\n').where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///');
    }).join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Bekleyen disk yazımları ÖNCE boşalsın: `_persist` bilinçli olarak
    // beklenmiyor ve bir önceki testin yazımı bu testin temiz deposuna
    // sızabilir.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    SharedPreferences.setMockInitialValues({});
    SurfaceTheme.instance.resetForTest();
  });

  group('karar tablosu', () {
    test('açık/koyu tercih cihaz görünümünü EZER', () {
      expect(
        SurfaceTheme.decide(ThemeMode.light,
            current: false,
            trustDeviceBrightness: true,
            brightness: Brightness.dark),
        isTrue,
      );
      expect(
        SurfaceTheme.decide(ThemeMode.dark,
            current: true,
            trustDeviceBrightness: true,
            brightness: Brightness.light),
        isFalse,
      );
    });

    test('açık/koyu tercih GÜVENİLMEYEN parlaklıkta da nettir', () {
      // Cihaz görünümü hiç okunmuyor: karar zaten kullanıcının.
      expect(
        SurfaceTheme.decide(ThemeMode.light,
            current: false,
            trustDeviceBrightness: false,
            brightness: Brightness.dark),
        isTrue,
      );
      expect(
        SurfaceTheme.decide(ThemeMode.dark,
            current: true,
            trustDeviceBrightness: false,
            brightness: Brightness.light),
        isFalse,
      );
    });

    test('Sistem + önplan → cihaz görünümüne düşer', () {
      expect(
        SurfaceTheme.decide(ThemeMode.system,
            current: false,
            trustDeviceBrightness: true,
            brightness: Brightness.light),
        isTrue,
      );
      expect(
        SurfaceTheme.decide(ThemeMode.system,
            current: true,
            trustDeviceBrightness: true,
            brightness: Brightness.dark),
        isFalse,
      );
    });

    test('Sistem + arka plan → SON KARAR korunur', () {
      // iOS arka plan anlık görüntüsünün ters parlaklığı burada yutulur.
      // Bu satır düşerse hata aynen geri gelir.
      expect(
        SurfaceTheme.decide(ThemeMode.system,
            current: true,
            trustDeviceBrightness: false,
            brightness: Brightness.dark),
        isTrue,
        reason: 'güvenilmeyen parlaklık son kararı EZMEMELİ',
      );
      expect(
        SurfaceTheme.decide(ThemeMode.system,
            current: false,
            trustDeviceBrightness: false,
            brightness: Brightness.light),
        isFalse,
      );
    });
  });

  group('durum yalnızca meşru tetikleyiciyle değişir', () {
    test('update yalnızca gerçekten değiştiğinde true döner', () {
      final s = SurfaceTheme.instance;
      expect(s.isLight, isFalse, reason: 'varsayılan koyu');

      expect(
        s.update(ThemeMode.light, trustDeviceBrightness: true),
        isTrue,
        reason: 'ilk geçiş bir değişim',
      );
      expect(s.isLight, isTrue);

      expect(
        s.update(ThemeMode.light, trustDeviceBrightness: true),
        isFalse,
        reason: 'aynı tercih tekrar itildiğinde yüzeyler tazelenmemeli',
      );
      expect(s.isLight, isTrue);
    });

    test('Sistem modunda arka plan raporu kararı bozmaz', () {
      final s = SurfaceTheme.instance;
      s.update(ThemeMode.light, trustDeviceBrightness: true);
      expect(s.isLight, isTrue);

      // Uygulama arkaya alınıyor; iOS kareyi koyu görünümde yakalıyor ve
      // tercih bu arada "Sistem"e çekilmiş olsa bile karar KORUNUR.
      expect(
        s.update(
          ThemeMode.system,
          trustDeviceBrightness: false,
          brightness: Brightness.dark,
        ),
        isFalse,
      );
      expect(s.isLight, isTrue, reason: 'palet salınmamalı');
    });

    test('karar diske yazılır ve süreç yeniden başlarken geri okunur',
        () async {
      final s = SurfaceTheme.instance;
      s.update(ThemeMode.light, trustDeviceBrightness: true);
      // `_persist` beklenmez (yüzey güncellemesi diski beklemesin);
      // kuyruğun boşalmasını bekle.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SurfaceTheme.prefKey), isTrue);

      // Yeni süreç: singleton `false` doğar, diskten gerçek karar gelir.
      s.resetForTest();
      expect(s.isLight, isFalse);
      await s.restore();
      expect(s.isLight, isTrue,
          reason: 'açık temalı kullanıcı ilk portföy yayınına kadar koyu '
              'palet görmemeli');
    });

    test('kayıt yoksa varsayılan koyu kalır', () async {
      final s = SurfaceTheme.instance;
      await s.restore();
      expect(s.isLight, isFalse);
    });
  });

  group('main.dart kararı YENİDEN ÇÖZMÜYOR', () {
    late String kaynak;

    setUpAll(() async {
      kaynak = _yorumsuz(await File('lib/main.dart').readAsString());
    });

    test('portföy dinleyicisi yalnızca OKUR', () {
      expect(kaynak.contains('SurfaceTheme.instance.isLight'), isTrue,
          reason: 'karar okunmalı');
      expect(kaynak.contains('resolveThemeIsLightNow('), isFalse,
          reason: 'her portföy yayınında yeniden örnekleme hatanın kaynağıydı');
    });

    test('tercih değişimi TEK dinleyiciden itiliyor', () {
      // İtişi ekranlara dağıtmak birini atlamak demekti: Profil
      // başlığındaki hızlı geçiş (`_ThemeToggleButton`) hiç itmiyordu.
      expect(kaynak.contains('ref.listen<ThemeMode>(themeModeProvider'), isTrue,
          reason: 'merkezî dinleyici iki giriş noktasını da kapsar');
    });

    test('parlaklık değişimi yalnızca ÖNPLANDA kabul ediliyor', () {
      final i = kaynak.indexOf('void didChangePlatformBrightness()');
      expect(i, greaterThan(0), reason: 'geri çağrı tanımlı olmalı');
      // Kapı geri çağrının ilk satırlarında olmalı; kaybolursa iOS arka
      // plan anlık görüntüsünün ters parlaklığı yeniden kabul edilir.
      final govde =
          kaynak.substring(i, (i + 320).clamp(i, kaynak.length).toInt());
      expect(govde.contains('AppLifecycleState.resumed'), isTrue,
          reason: 'arka plan anlık görüntüsü kapısı kaldırılmış');
    });
  });

  group('ekranlar kendi başına itmiyor', () {
    test('Ayarlar tema seçicisi yalnızca tercihi yazıyor', () async {
      final src = _yorumsuz(
          await File('lib/screens/settings_screen.dart').readAsString());
      expect(src.contains('resolveThemeIsLightNow'), isFalse,
          reason: 'çözüm tek noktada — SurfaceTheme');
      expect(src.contains('LiveActivityService.instance.themeIsLight ='), isFalse,
          reason: 'itiş merkezî dinleyicinin işi');
    });

    test('Profil hızlı geçişi de yalnızca tercihi yazıyor', () async {
      final src = _yorumsuz(
          await File('lib/screens/profile_screen.dart').readAsString());
      expect(src.contains('themeIsLight ='), isFalse);
      expect(src.contains('themeModeProvider.notifier).set('), isTrue,
          reason: 'hızlı geçiş aynı provider üzerinden gitmeli');
    });
  });
}
