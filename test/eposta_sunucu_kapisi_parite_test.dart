import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/eposta_onerisi.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sunucu kapısı (0185) ile istemci önerisi aynı dili konuşur: sunucunun
/// reddettiği her alan adına istemci de AYNI düzeltmeyi önerir. Aksi hâlde
/// yeni sürümde kullanıcı öneri görmeden sunucudan ret alırdı, ya da öneri
/// başka, ret mesajı başka adres söylerdi.
void main() {
  final sql = File('supabase/migrations/0185_kayit_eposta_yazim_kapisi.sql')
      .readAsStringSync();

  test('sağlayıcı yazım hatası haritası istemciyle aynı düzeltmeyi verir', () {
    final ciftler = RegExp(r"^\s*'([a-z0-9.\-]+)', '([a-z0-9.\-]+)',?\s*$",
            multiLine: true)
        .allMatches(sql)
        .map((m) => (m.group(1)!, m.group(2)!))
        .toList();
    expect(ciftler.length, greaterThanOrEqualTo(25),
        reason: 'harita satırları okunamadı; biçim değiştiyse testi güncelle');
    for (final (yanlis, dogru) in ciftler) {
      expect(ePostaYazimOnerisi('a@$yanlis'), 'a@$dogru', reason: yanlis);
    }
  });

  test('son ek hataları istemcide de düzeltilir', () {
    final ekler = RegExp(r'\\\.\(([a-z|]+)\)\$').firstMatch(sql)!.group(1)!;
    for (final ek in ekler.split('|')) {
      expect(ePostaYazimOnerisi('a@sirket.$ek'), 'a@sirket.com', reason: ek);
    }
    expect(ePostaYazimOnerisi('a@sirket.comtr'), 'a@sirket.com.tr');
  });

  // Mağazadaki eski sürüm ret mesajını kendi friendlyError'uyla gösterir;
  // genel "işlem tamamlanamadı"ya düşmemeli.
  test('ret mesajı kullanıcıya "E-posta adresi geçersiz" olarak görünür', () {
    final e = AuthApiException(
        'Email address domain looks invalid (typo): gmail.con. '
        'Did you mean gmail.com?',
        statusCode: '400');
    expect(friendlyError(e), contains('E-posta adresi geçersiz'));
    expect(sql, contains('Email address domain looks invalid'));
  });

  // Kayıt ekranı kesin hataları sunucuya gitmeden kırmızı gösterir; liste
  // sunucuyla BİREBİR olmalı — fazlası gerçek adresi engeller, eksiği
  // kullanıcıyı yine sunucunun genel retine düşürür.
  test('kesin hata listesi sunucu kapısıyla birebir', () {
    final sunucu = Map.fromEntries(RegExp(
            r"^\s*'([a-z0-9.\-]+)', '([a-z0-9.\-]+)',?\s*$",
            multiLine: true)
        .allMatches(sql)
        .map((m) => MapEntry(m.group(1)!, m.group(2)!)));
    expect(kesinYazimHatalari, sunucu);
    final ekler = RegExp(r'\\\.\(([a-z|]+)\)\$').firstMatch(sql)!.group(1)!;
    expect(kesinHataliSonEkler, ekler.split('|').toSet());
  });

  test('ePostaKesinYazimHatasi sunucu karar sırasını izler', () {
    expect(ePostaKesinYazimHatasi('A@GMIAL.CON'), 'A@gmail.com');
    expect(ePostaKesinYazimHatasi('x@hotmail.com.t'), 'x@hotmail.com.tr');
    expect(ePostaKesinYazimHatasi('x@sirket.comtr'), 'x@sirket.com.tr');
    expect(ePostaKesinYazimHatasi('x@sirket.con'), 'x@sirket.com');
    for (final e in ['x@gmail.com', 'x@boun.edu.tr', 'x@ymail.com',
        'x@yahoo.com.tr', 'x@sirket.co', 'x@gmali.co']) {
      // gmali.co: istemci önerir (benzerlik) ama sunucu reddetmez → kırmızı yok.
      expect(ePostaKesinYazimHatasi(e), isNull, reason: e);
    }
  });
}
