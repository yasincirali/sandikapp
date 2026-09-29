import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/kullanici_adi.dart';
import 'package:portfoy_takip/services/kullanici_adi_denetimi.dart';

/// Kullanıcı adı anlık denetimi — kayıt formu ve ad ekranının ortak
/// mantığı (2026-09-28). Sözleşme:
///   · biçim anında, sunucuya gidilmez;
///   · biçim uygunsa `bekleme` sonra TEK soru; her tuş sayacı sıfırlar;
///   · eski yanıt yeni metnin üstüne yazılmaz;
///   · mevcut ad sorulmaz ve kaydedilemez;
///   · yanıt gelmeden de kaydedilebilir (sunucu son sözü kayıtta söyler).
void main() {
  test('biçim hatası anında; sunucuya sorulmaz', () {
    var sorulan = 0;
    final d = KullaniciAdiDenetimi(sor: (_) async {
      sorulan++;
      return KullaniciAdiSonuc.uygun;
    });
    fakeAsync((f) {
      d.metinDegisti('ali veli');
      f.elapse(const Duration(seconds: 2));
      expect(d.durum, KullaniciAdiSonuc.bicim);
      expect(d.kaydedilebilir, isFalse);
      expect(sorulan, 0);
    });
  });

  test('gecikmeli tek soru; her tuş sayacı sıfırlar', () {
    final sorulanlar = <String>[];
    final d = KullaniciAdiDenetimi(
      bekleme: const Duration(milliseconds: 100),
      sor: (m) async {
        sorulanlar.add(m);
        return KullaniciAdiSonuc.uygun;
      },
    );
    fakeAsync((f) {
      d.metinDegisti('ays');
      f.elapse(const Duration(milliseconds: 60));
      d.metinDegisti('ayse');
      f.elapse(const Duration(milliseconds: 60));
      expect(sorulanlar, isEmpty, reason: 'sayaç sıfırlandı, henüz sorulmadı');
      // Yanıt gelmeden düğme kilitlenmez.
      expect(d.kaydedilebilir, isTrue);
      expect(d.durum, isNull);
      f.elapse(const Duration(milliseconds: 60));
      expect(sorulanlar, ['ayse']);
      expect(d.durum, KullaniciAdiSonuc.uygun);
      expect(d.kaydedilebilir, isTrue);
      expect(d.soruluyor, isFalse);
    });
  });

  test('eski yanıt yeni metnin üstüne yazılmaz', () {
    final bekleyen = <String, Completer<KullaniciAdiSonuc>>{};
    final d = KullaniciAdiDenetimi(
      bekleme: const Duration(milliseconds: 10),
      sor: (m) => (bekleyen[m] = Completer<KullaniciAdiSonuc>()).future,
    );
    fakeAsync((f) {
      d.metinDegisti('ayse');
      f.elapse(const Duration(milliseconds: 20));
      d.metinDegisti('ayse.k');
      f.elapse(const Duration(milliseconds: 20));
      // İlk soru "alınmış" döner ama metin artık başka.
      bekleyen['ayse']!.complete(KullaniciAdiSonuc.alinmis);
      f.flushMicrotasks();
      expect(d.durum, isNull);
      expect(d.kaydedilebilir, isTrue);
      bekleyen['ayse.k']!.complete(KullaniciAdiSonuc.uygun);
      f.flushMicrotasks();
      expect(d.durum, KullaniciAdiSonuc.uygun);
    });
  });

  test('sunucu reddi düğmeyi kilitler; metin değişince açılır', () {
    final d = KullaniciAdiDenetimi(
      bekleme: const Duration(milliseconds: 10),
      sor: (_) async => KullaniciAdiSonuc.alinmis,
    );
    fakeAsync((f) {
      d.metinDegisti('ayse');
      f.elapse(const Duration(milliseconds: 20));
      expect(d.durum, KullaniciAdiSonuc.alinmis);
      expect(d.kaydedilebilir, isFalse);
      d.metinDegisti('ayse2');
      expect(d.durum, isNull);
      expect(d.kaydedilebilir, isTrue);
    });
  });

  test('mevcut ad: sorulmaz, kaydedilemez, durum yok', () {
    var sorulan = 0;
    final d = KullaniciAdiDenetimi(
      mevcutAd: 'ayse',
      bekleme: const Duration(milliseconds: 10),
      sor: (_) async {
        sorulan++;
        return KullaniciAdiSonuc.uygun;
      },
    );
    fakeAsync((f) {
      d.metinDegisti('ayse');
      f.elapse(const Duration(seconds: 1));
      expect(sorulan, 0);
      expect(d.durum, isNull);
      expect(d.kaydedilebilir, isFalse);
    });
  });

  test('kayıt denemesinden dönen ret alana yazılır', () {
    final d = KullaniciAdiDenetimi(sor: (_) async => KullaniciAdiSonuc.uygun);
    d.metinDegisti('ayse');
    d.sonucYaz('ayse', KullaniciAdiSonuc.uygunsuz);
    expect(d.durum, KullaniciAdiSonuc.uygunsuz);
    expect(d.kaydedilebilir, isFalse);
  });

  test('hemen sor: gecikmesiz (açılıştaki öneri)', () {
    var sorulan = 0;
    final d = KullaniciAdiDenetimi(sor: (_) async {
      sorulan++;
      return KullaniciAdiSonuc.uygun;
    });
    fakeAsync((f) {
      d.metinDegisti('Yasin.Dirali', hemen: true);
      f.flushMicrotasks();
      expect(sorulan, 1);
      expect(d.durum, KullaniciAdiSonuc.uygun);
      // Gecikmeli sayaç kurulmadı: sonra ikinci soru gelmez.
      f.elapse(const Duration(seconds: 2));
      expect(sorulan, 1);
    });
  });
}
