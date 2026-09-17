import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';

/// **"Tüm varlıklar her yerde tek kaynaktan ve tutarlı şekilde çekilmelidir."**
/// (kullanıcı kararı, 2026-09-17)
///
/// Bu test sözleşmenin üç maddesini de kilitler:
///
///   1. Sembol/kaynak kararı TEK yerde (`fiyat_kaynagi.dart`).
///   2. Ekrandaki fiyat ile serinin ÖLÇEĞİ aynı (kalibrasyon/hizalama).
///   3. Uydurma sayı yasak (`35.0`/`40.0` gibi sabit kur yok).
///
/// Karar bir arızadan doğdu: altın serisi dört ayrı yolda dört ayrı
/// merdivenle kuruluyordu ve hangi yolun hangi kaynağı seçtiği isteğe göre
/// değişiyordu. Aynı sınıf ayrışma bu projede ağırlık çarpanında, Yahoo
/// `range` merdiveninde ve çözünürlük merdiveninde de yaşandı — hepsinin
/// imzası aynı: kod çalışıyor, sayı yanlış, arıza sessiz.
void main() {
  Asset varlik({
    required AssetType type,
    String ticker = 'THYAO.IS',
    String currency = 'TRY',
    bool manuel = false,
  }) =>
      Asset(
        id: 'x',
        userId: 'u',
        name: ticker,
        ticker: ticker,
        type: type,
        quantity: 1,
        purchasePrice: 1,
        currency: currency,
        notes: '',
        currentPrice: 1,
        addedDate: DateTime(2026, 1, 1),
        isManualPrice: manuel,
      );

  group('1) sembol kararı tek yerde', () {
    test('altın: üç sembol de ÖNDEN istenir (spot, vadeli, kur)', () {
      final s = FiyatKaynagi.seriSembolleri(
          varlik(type: AssetType.altin, ticker: 'ALTIN_CEYREK'));
      expect(s, [FiyatKaynagi.xauTry, FiyatKaynagi.xauUsd, FiyatKaynagi.usdTry],
          reason: 'Yedek kaynağı sonradan başlatmak altını tek başına iki '
              'isteği SIRALI yapan tür haline getiriyordu (en kötü 30 sn).');
    });

    test('TRY kote varlık yalnızca kendi sembolünü ister', () {
      expect(FiyatKaynagi.seriSembolleri(varlik(type: AssetType.hisse)),
          ['THYAO.IS']);
    });

    test('USD kote varlık KUR serisini de ister', () {
      final s = FiyatKaynagi.seriSembolleri(
          varlik(type: AssetType.hisse, ticker: 'AAPL', currency: 'USD'));
      expect(s, ['AAPL', FiyatKaynagi.usdTry]);
    });

    test('elle fiyatlanan varlık HİÇBİR seri istemez', () {
      expect(
          FiyatKaynagi.seriSembolleri(
              varlik(type: AssetType.hisse, manuel: true)),
          isEmpty,
          reason: '"Ev", "Araba" gibi kayıtların yayımlanmış serisi yok — '
              'ağa çıkmak boşuna trafik.');
    });

    test('para birimi TICKER\'DAN TAHMİN EDİLMEZ', () {
      // `.IS` ile bitmeyen her şeyi USD saymak, TL kote bir emtiayı kurla
      // çarpıp fiyatı ~42 katına çıkarırdı.
      expect(
          FiyatKaynagi.usdKote(varlik(type: AssetType.emtia, ticker: 'XYZ')),
          isFalse);
      expect(
          FiyatKaynagi.usdKote(
              varlik(type: AssetType.emtia, ticker: 'XYZ', currency: 'usd')),
          isTrue);
    });
  });

  group('2) ölçek birliği', () {
    test('kur serisi CANLI kura hizalanır — oranlar korunur', () {
      // Seri Yahoo `USDTRY=X` (mid), canlı kotasyon truncgil `USD` (Alış).
      // Hizalanmazsa USD kote bir hissede kâr/zarar çipi ile grafiğin son
      // noktası iki ayrı sayı verir — ikisi de "canlı" diyerek.
      final seri = {1: 41.0, 2: 41.5, 3: 42.0};
      final hizali = kurSerisiniHizala(seri, 41.8);

      expect(hizali[3], closeTo(41.8, 1e-9));
      // Oran korunur: 2/1 aynı kalmalı.
      expect(hizali[2]! / hizali[1]!, closeTo(41.5 / 41.0, 1e-12));
    });

    test('canlı kur bilinmiyorsa seri OLDUĞU GİBİ kalır', () {
      final seri = {1: 41.0, 2: 42.0};
      expect(kurSerisiniHizala(seri, null), same(seri));
      expect(kurSerisiniHizala(seri, 0), same(seri));
    });

    test('%10\'u aşan sapma hizalanmaz — o makas değil ARIZADIR', () {
      // Ters çevrilmiş parite (1/42) ya da yanlış sembol bu aralığa düşer;
      // kalibrasyon onu örterse hata sessizleşir.
      final seri = {1: 42.0};
      expect(kurSerisiniHizala(seri, 0.024), same(seri));
      expect(kurSerisiniHizala(seri, 420.0), same(seri));
    });

    test('ölçek çarpanı sınır dışındayken 1.0 döner', () {
      expect(olcekCarpani(seriSon: 100, canli: 700, alt: 0.75, ust: 1.33), 1.0);
      expect(olcekCarpani(seriSon: 100, canli: 110, alt: 0.75, ust: 1.33),
          closeTo(1.1, 1e-12));
      expect(olcekCarpani(seriSon: 0, canli: 110, alt: 0.75, ust: 1.33), 1.0);
    });
  });

  group('3) uydurma sayı yasak', () {
    final servisler = Directory('lib/services')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    test('hiçbir serviste sabit kur varsayılanı yok', () {
      // Ölçülen en kötü hâl: `usdRate = 35.0` ile gerçek kur ~42 iken
      // portföy %17 düşük görünüyordu — sessizce.
      final ihlaller = <String>[];
      final desenler = [
        RegExp(r'\?\?\s*40\.0'),
        RegExp(r'\?\?\s*35\.0'),
        RegExp(r'usdRate\s*=\s*3[05]\.0'),
        RegExp(r'\*\s*40\.0'),
      ];
      for (final f in servisler) {
        final src = f.readAsStringSync();
        for (final d in desenler) {
          for (final m in d.allMatches(src)) {
            // Yorum satırındaki tarihsel anlatım serbest — kural KOD için.
            final satirBasi = src.lastIndexOf('\n', m.start) + 1;
            final satir = src.substring(satirBasi, m.start).trimLeft();
            if (satir.startsWith('//') || satir.startsWith('///')) continue;
            ihlaller.add('${f.path}: ${m.group(0)}');
          }
        }
      }
      expect(ihlaller, isEmpty,
          reason: 'Uydurma kur sabiti geri gelmiş: ${ihlaller.join(", ")}');
    });

    test('canlı kur TEK yerden okunur', () {
      final src = File('lib/services/history_service.dart').readAsStringSync();
      expect(src.contains('static double? Function() canliKur'), isTrue,
          reason: 'Grafik yollarının kur gerçeği tek kapıdan geçmeli.');
      expect(src.contains('sonBilinenFiyat(FiyatKaynagi.usdTry)'), isTrue,
          reason: 'Canlı kur, ekrandaki TL karşılığıyla aynı kaynaktan '
              'gelmeli (`fetchQuotes` sonucu).');
    });
  });

  group('kaynak sözleşmesinin DIŞINDA kalan yüzey yok', () {
    final servisler = {
      for (final f in Directory('lib/services')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        f.path: f.readAsStringSync(),
    };

    test('ham altın sembolü yalnızca sözleşme dosyasında geçer', () {
      final ihlal = <String>[];
      servisler.forEach((yol, src) {
        if (yol.endsWith('fiyat_kaynagi.dart')) return;
        for (final sembol in ["'GC=F'", "'XAUTRY=X'", "'USDTRY=X'"]) {
          for (final m in sembol.allMatches(src)) {
            final satirBasi = src.lastIndexOf('\n', m.start) + 1;
            final satir = src.substring(satirBasi, m.start).trimLeft();
            if (satir.startsWith('//') || satir.startsWith('///')) continue;
            ihlal.add('$yol: $sembol');
          }
        }
      });
      // `price_service` canlı kotasyon tarafının kendi merdivenini taşıyor
      // (truncgil → Yahoo); sözleşme oraya HENÜZ taşınmadı, bkz.
      // TECHNICAL_DEBT. Geri kalan hiçbir servis ham sembol yazmamalı.
      final beklenmeyen =
          ihlal.where((e) => !e.startsWith('lib/services/price_service.dart'));
      expect(beklenmeyen, isEmpty,
          reason: 'Sembol kararı sözleşmenin dışına sızmış: '
              '${beklenmeyen.join(", ")}');
    });

    test('sparkline altını da gram22k TL serisinden çizer', () {
      final src = servisler['lib/services/sparkline_service.dart']!;
      expect(src.contains('altinGramSerisi('), isTrue,
          reason: 'Sparkline kendi altın kaynağına dönmüş (ons/USD eğrisi); '
              'kullanıcı TL tutuyor, kur hareketi grafiğe yansımaz.');
    });
  });
}
