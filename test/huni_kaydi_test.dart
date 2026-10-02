import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/huni_kaydi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Kayıt hunisinin istemci ayağı (0097). Kilitlenen kararlar:
///  - güncelleme ile gelen cihaz huniye GİRMEZ (yoksa her eski kullanıcı
///    "yeni kurulum" sayılırdı);
///  - adım kurulum başına bir kez gider, çevrimdışı olay kaybolmaz ve
///    sırası korunur;
///  - hata detayı yalnızca sınıf+kod taşır, mesaj (e-posta olabilir) asla;
///  - istemci adım listesi sunucunun CHECK listesiyle birebir.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> giden;
  late HuniKaydi h;

  setUp(() {
    giden = [];
    h = HuniKaydi.instance..sifirlaTestIcin();
    h.gonderici = (p) async => giden.add(p);
  });

  group('kurulum tanıma', () {
    test('yeni kurulum: kimlik üretilir, ilk_acilis gider', () async {
      SharedPreferences.setMockInitialValues({});
      await h.hazirla();
      await h.bosalt();

      expect(h.kurulumId, isNotNull);
      expect(giden.map((p) => p['p_adim']), ['ilk_acilis']);
      expect(giden.single['p_kurulum'], h.kurulumId);
      // İstemci user_id GÖNDERMEZ — sunucu auth.uid()'den alır.
      expect(giden.single.containsKey('p_user_id'), isFalse);
    });

    test('güncelleme ile gelen cihaz (RetentionTracker izi var): hiçbir şey gitmez',
        () async {
      SharedPreferences.setMockInitialValues({HuniKaydi.eskiKurulumIzi: 20000});
      await h.hazirla();
      await h.kaydet(HuniAdimi.kayitEkrani);
      await h.kaydet(HuniAdimi.ilkGiris);

      expect(giden, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(HuniKaydi.aktifAnahtari), isFalse);
    });

    test('ikinci açılış: kimlik aynı kalır, ilk_acilis tekrar gitmez', () async {
      SharedPreferences.setMockInitialValues({});
      await h.hazirla();
      await h.bosalt();
      final ilkKimlik = h.kurulumId;

      // Süreç yeniden başlar. Bu arada RetentionTracker kurulum gününü
      // yazmıştır — cihaz yine de AKTİF kalmalı (karar ilk açılışta verildi).
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(HuniKaydi.eskiKurulumIzi, 20000);
      h.sifirlaTestIcin();
      h.gonderici = (p) async => giden.add(p);
      await h.hazirla();
      await h.kaydet(HuniAdimi.kayitEkrani);

      expect(h.kurulumId, ilkKimlik);
      expect(giden.map((p) => p['p_adim']), ['ilk_acilis', 'kayit_ekrani']);
    });

    test('hazirla çağrılmadıysa (test, eski yol) kaydet no-op', () async {
      SharedPreferences.setMockInitialValues({});
      await h.kaydet(HuniAdimi.kayitEkrani);
      expect(giden, isEmpty);
    });
  });

  group('teslim', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('aynı adım iki kez: tek gönderim', () async {
      await h.hazirla();
      await h.kaydet(HuniAdimi.kayitEkrani);
      await h.kaydet(HuniAdimi.kayitEkrani);
      expect(giden.map((p) => p['p_adim']), ['ilk_acilis', 'kayit_ekrani']);
    });

    test('çevrimdışı: olay kuyrukta kalır, bağlantı gelince SIRAYLA gider',
        () async {
      var cevrimdisi = true;
      h.gonderici = (p) async {
        if (cevrimdisi) throw const SocketException('Network is unreachable');
        giden.add(p);
      };
      await h.hazirla();
      await h.kaydet(HuniAdimi.kayitEkrani);
      await h.kaydet(HuniAdimi.kayitFormu);
      expect(giden, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      final kuyruk = jsonDecode(prefs.getString(HuniKaydi.bekleyenAnahtari)!) as List;
      expect(kuyruk.map((o) => o['a']), ['ilk_acilis', 'kayit_ekrani', 'kayit_formu']);

      cevrimdisi = false;
      await h.bosalt();
      expect(giden.map((p) => p['p_adim']),
          ['ilk_acilis', 'kayit_ekrani', 'kayit_formu']);
      expect(jsonDecode(prefs.getString(HuniKaydi.bekleyenAnahtari)!), isEmpty);
    });

    test('olay zamanı istemcinin yaşadığı an — gönderim anı değil', () async {
      h.saat = () => DateTime.utc(2026, 10, 2, 9);
      h.gonderici = (p) async => throw TimeoutException('yavaş');
      await h.hazirla();

      h.saat = () => DateTime.utc(2026, 10, 2, 12);
      h.gonderici = (p) async => giden.add(p);
      await h.bosalt();

      expect(giden.single['p_ts'], '2026-10-02T09:00:00.000Z');
    });

    test('farklı hata kodları ayrı, aynı kod tek kez', () async {
      await h.hazirla();
      final zayif = AuthApiException('Password is too weak', code: 'weak_password');
      await h.hata('kayit', zayif);
      await h.hata('kayit', zayif);
      await h.hata('otp', AuthApiException('Token has expired', code: 'otp_expired'));

      final hatalar = giden.where((p) => p['p_adim'] == 'kayit_hatasi');
      expect(hatalar.map((p) => p['p_detay']),
          ['kayit:auth_weak_password', 'otp:auth_otp_expired']);
    });
  });

  group('hata detayı', () {
    test('mesaj taşınmaz, yalnızca sınıf + kod', () {
      final e = AuthApiException('ali@ornek.com already registered',
          code: 'user_already_exists');
      final d = HuniKaydi.hataDetayi('kayit', e);
      expect(d, 'kayit:auth_user_already_exists');
      expect(d.contains('@'), isFalse);
    });

    test('sınıflar', () {
      expect(HuniKaydi.hataKodu(TimeoutException('x')), 'zaman_asimi');
      expect(HuniKaydi.hataKodu(const SocketException('x')), 'ag');
      expect(HuniKaydi.hataKodu(const PostgrestException(message: 'm', code: '42501')),
          'pg_42501');
      expect(HuniKaydi.hataKodu(AuthApiException('m', statusCode: '429')), 'auth_429');
      expect(HuniKaydi.hataKodu(StateError('x')), 'diger');
    });

    test('sunucu biçimi: asama(≤24):kod(≤40), nokta/@ yok', () {
      // Biçim migration 0097 `huni_kaydet` ile aynı; uymayan detay
      // sunucuda 'gecersiz' olur ve hata kodu kaybolur.
      final bicim = RegExp(r'^[a-z0-9_]{1,24}:[a-z0-9_]{1,40}$');
      for (final d in [
        HuniKaydi.hataDetayi(
            'Sosyal_Google', AuthApiException('m', code: 'Çok Uzun ${'x' * 80}')),
        HuniKaydi.hataDetayi('kayit', AuthApiException('m', code: 'a.b@c.com')),
        HuniKaydi.hataDetayi('', StateError('x')),
        HuniKaydi.hataDetayi(
            'otp', AuthApiException('m', code: 'over_email_send_rate_limit')),
      ]) {
        expect(bicim.hasMatch(d), isTrue, reason: d);
      }
    });
  });

  group('sözleşme', () {
    test('signup_step → huni eşlemesi: bilinen yedi adımın hepsi', () {
      const adlar = [
        'form_opened',
        'otp_sent',
        'otp_verified',
        'disclaimer_accepted',
        'username_set',
        'tour_done',
        'home_first_seen',
      ];
      for (final a in adlar) {
        expect(HuniKaydi.signupStepten(a), isNotNull, reason: a);
      }
      expect(HuniKaydi.signupStepten('bilinmeyen'), isNull);
    });

    test('istemci adım listesi == migration 0097 CHECK listesi', () {
      final sql =
          File('supabase/migrations/0097_kayit_hunisi.sql').readAsStringSync();
      final blok = RegExp(r"huni_olaylari_adim_chk check \(adim in \(([^)]*)\)\)")
          .firstMatch(sql)!
          .group(1)!;
      final sunucu = RegExp(r"'([a-z_]+)'").allMatches(blok).map((m) => m[1]).toSet();
      final istemci = HuniAdimi.values.map((a) => a.kod).toSet();
      expect(istemci, sunucu);
    });
  });
}
