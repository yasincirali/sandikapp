import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/halka_arz.dart';

/// Halka arz takvimi verisinin şema ve tutarlılık kapısı (F6, ADR-3).
///
/// Veri elle derlenir; bu test derleyenin yapabileceği hataları CI'da
/// yakalar: iki kopyanın ayrışması (Pages'teki ile uygulamaya gömülü),
/// kaynaksız kayıt, bozuk tarih, ters sıralı tarih, sıfır/negatif fiyat.
/// **Uydurma yasak:** bilinmeyen alan `null` durur — test `null`'a izin
/// verir, "tahmini" değere değil (fiyat > 0 ya da null).
void main() {
  const pagesYolu = 'docs/data/halka_arz.json';
  const assetYolu = 'assets/data/halka_arz.json';

  // Satır sonu farkı (Windows checkout'unda CRLF) içerik farkı değildir.
  String oku(String yol) =>
      File(yol).readAsStringSync().replaceAll('\r\n', '\n');

  final ham = oku(pagesYolu);
  final kok = jsonDecode(ham) as Map<String, dynamic>;
  final kayitlar =
      (kok['kayitlar'] as List).cast<Map<String, dynamic>>();

  const alanlar = {
    'kod',
    'sirket',
    'talep_baslangic',
    'talep_bitis',
    'fiyat',
    'dagitim',
    'islem_baslangic',
    'pazar',
    'kaynak',
    'guncelleme',
  };
  const tarihAlanlari = [
    'talep_baslangic',
    'talep_bitis',
    'islem_baslangic',
    'guncelleme',
  ];

  test('Pages kopyası ile gömülü asset BİREBİR aynı', () {
    expect(oku(assetYolu), ham,
        reason: '$pagesYolu değişti ama $assetYolu güncellenmedi (ya da '
            'tersi). İkisini aynı içerikle kaydet.');
  });

  test('pubspec gömülü kopyayı asset olarak tanıyor', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains(assetYolu));
  });

  test('dosya başlığı: desteklenen sürüm + geçerli derleme tarihi', () {
    expect(kok['surum'], HalkaArzListesi.desteklenenSurum);
    expect(HalkaArz.isoGun(kok['guncelleme'] as String), isNotNull);
    expect(kayitlar, isNotEmpty);
  });

  test('her kayıt tam şemayı taşır; kod, şirket, kaynak dolu', () {
    for (final k in kayitlar) {
      final ad = k['kod'];
      expect(k.keys.toSet(), alanlar, reason: '$ad: alan kümesi şemadan farklı');
      for (final zorunlu in ['kod', 'sirket', 'kaynak']) {
        final v = k[zorunlu];
        expect(v is String && v.trim().isNotEmpty, isTrue,
            reason: '$ad: "$zorunlu" boş');
      }
      expect(RegExp(r'^[A-Z0-9]{3,6}$').hasMatch(ad as String), isTrue,
          reason: '$ad: BIST kodu biçiminde değil (".IS" eki YAZILMAZ)');
      final kaynak = Uri.tryParse(k['kaynak'] as String);
      expect(kaynak != null && kaynak.scheme == 'https' && kaynak.host.isNotEmpty,
          isTrue,
          reason: '$ad: kaynak https bağlantısı değil');
    }
  });

  test('kodlar tekil', () {
    final kodlar = kayitlar.map((k) => k['kod']).toList();
    expect(kodlar.toSet().length, kodlar.length);
  });

  test('tarihler geçerli ISO gün (YYYY-MM-DD) ya da null', () {
    for (final k in kayitlar) {
      for (final a in tarihAlanlari) {
        final v = k[a];
        if (v == null) continue;
        expect(v is String && HalkaArz.isoGun(v) != null, isTrue,
            reason: '${k['kod']}: $a = "$v" geçerli bir gün değil');
      }
    }
  });

  test('dolu tarihler sıralı: talep başı ≤ talep sonu ≤ işlem başı', () {
    DateTime? t(Map<String, dynamic> k, String a) =>
        k[a] == null ? null : HalkaArz.isoGun(k[a] as String);
    for (final k in kayitlar) {
      final bas = t(k, 'talep_baslangic');
      final bit = t(k, 'talep_bitis');
      final islem = t(k, 'islem_baslangic');
      if (bas != null && bit != null) {
        expect(bas.isAfter(bit), isFalse, reason: '${k['kod']}: talep ters');
      }
      if (bit != null && islem != null) {
        expect(bit.isAfter(islem), isFalse,
            reason: '${k['kod']}: işlem talep bitmeden başlıyor');
      }
      if (bas != null && islem != null) {
        expect(bas.isAfter(islem), isFalse, reason: '${k['kod']}');
      }
    }
  });

  test('fiyat > 0 ya da null — 0/negatif "bilinmiyor" yerine yazılmaz', () {
    for (final k in kayitlar) {
      final f = k['fiyat'];
      if (f == null) continue;
      expect(f is num && f > 0, isTrue, reason: '${k['kod']}: fiyat $f');
    }
  });

  test('her kayıt uygulamanın okuyucusundan geçer (sessizce düşmez)', () {
    final liste = HalkaArzListesi.fromJson(kok, HalkaArzKaynagi.gomulu);
    expect(liste, isNotNull);
    expect(liste!.kayitlar.length, kayitlar.length);
  });

  test('işlem görmeye başlamış her kod hisse seçicisinde adıyla var', () {
    // "Katıldım" formu `KOD.IS` ile açar; sembol listede yoksa kayıt
    // şirket adını kaybeder (`resolveIdentity`). Derleme tarihine kadar
    // işlem görmeye başlayan her kayıt `bist100StocksMap`'e de eklenmeli.
    final derleme = HalkaArz.isoGun(kok['guncelleme'] as String)!;
    for (final k in kayitlar) {
      final islem = k['islem_baslangic'];
      if (islem == null) continue;
      if (HalkaArz.isoGun(islem as String)!.isAfter(derleme)) continue;
      final sembol = '${k['kod']}.IS';
      expect(bist100StocksMap[sembol], isNotNull,
          reason: '$sembol bist100StocksMap\'te yok — asset_categories.dart');
    }
  });
}
