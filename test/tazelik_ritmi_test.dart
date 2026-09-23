import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/tazelik_ritmi.dart';
import 'package:portfoy_takip/widgets/piyasa_seridi.dart';

import 'helpers/kaynak.dart';

/// Kullanıcı kararı (2026-09-23): *"fiyat yenileme sıklıklarımızı da senkron
/// hale getirmeliyiz, bu sayede bir ekranda altın fiyatıyla diğer ekranda
/// aynı olmalı."*
///
/// ## Ölçülen arıza
/// Beş ritim, beş ayrı yerde tanımlıydı. Kotasyon önbelleği 45 sn tutuyor,
/// yüzeyler 30 sn'de bir soruyordu — oran 1,5, yani tam sayı değil:
///
/// ```
///   t=  0 sn  AĞ (taze)
///   t= 30 sn  ÖNBELLEK (yaş 30)
///   t= 60 sn  ÖNBELLEK (yaş 15)
///   t= 90 sn  AĞ (taze)
/// ```
///
/// Önbellek paylaşımlı olduğu için AYNI ANDA soran iki yüzey aynı fiyatı
/// görür; ama TTL sınırının iki yanına düşen iki soru farklı yanıt alır.
/// `t=44` önbellekten eskiyi, `t=46` ağdan yeniyi alır — iki ekran iki
/// saniye arayla farklı altın fiyatı gösterir.
///
/// ## Bu dosya neyi kilitler
/// 1. Tüm ritimler `temel`in TAM KATI (faz kayması olamaz).
/// 2. Kotasyon ömrü yüzey ritminden UZUN DEĞİL (vuruş deseni geri gelemez).
/// 3. Yüzeyler kendi periyodunu ham literal olarak TANIMLAMAZ — tek kaynak.
void main() {
  group('hizalama', () {
    test('tüm ritimler temelin TAM KATI', () {
      for (final MapEntry(key: ad, value: d) in <String, Duration>{
        'kotasyonOmru': TazelikRitmi.kotasyonOmru,
        'yuzey': TazelikRitmi.yuzey,
        'gunIciSeriOmru': TazelikRitmi.gunIciSeriOmru,
        'canliUcAzamiGecikme': TazelikRitmi.canliUcAzamiGecikme,
      }.entries) {
        expect(TazelikRitmi.hizali(d), isTrue,
            reason: '$ad (${d.inSeconds} sn) temelin katı değil — '
                'faz kayması iki ekranda farklı fiyat demek');
      }
    });

    test('kotasyon ömrü yüzey ritminden UZUN DEĞİL', () {
      // Asıl arıza buydu: 45 sn TTL, 30 sn poll.
      expect(TazelikRitmi.kotasyonOmru.inSeconds,
          lessThanOrEqualTo(TazelikRitmi.yuzey.inSeconds),
          reason: 'TTL poll aralığından uzunsa, sınırın iki yanına düşen '
              'iki soru farklı fiyat alır (ölçüldü: 45/30 → vuruş deseni)');
    });

    test('vuruş deseni YOK — her tick aynı davranır', () {
      // Düzeltme öncesi simülasyon: TTL 45, poll 30 → desen tekrarlıyordu.
      List<bool> aga(int ttl, int poll, {int tur = 8}) {
        final out = <bool>[];
        var son = -1000;
        for (var t = 0; t < poll * tur; t += poll) {
          final cikti = t - son >= ttl;
          if (cikti) son = t;
          out.add(cikti);
        }
        return out;
      }

      // ESKİ: karışık desen
      final eski = aga(45, 30);
      expect(eski.toSet(), hasLength(2),
          reason: 'önkoşul: eski ayarda bazı tickler ağa çıkıyor bazıları çıkmıyor');

      // YENİ: her tick aynı
      final yeni = aga(TazelikRitmi.kotasyonOmru.inSeconds,
          TazelikRitmi.yuzey.inSeconds);
      expect(yeni.toSet(), hasLength(1),
          reason: 'her tick aynı davranmalı — yüzeye göre değişmemeli');
      expect(yeni.first, isTrue, reason: 'her tick tazeler');
    });

    test('gün içi seri ömrü yüzeyden UZUN (geçmiş veri tekrar çekilmez)', () {
      expect(TazelikRitmi.gunIciSeriOmru.inSeconds,
          greaterThan(TazelikRitmi.yuzey.inSeconds),
          reason: 'saatlik kovalar geçmiş veridir; 30 sn\'de bir yeniden '
              'indirmek aynı noktaları tekrar çekmek olurdu');
    });
  });

  group('yüzeyler tek kaynaktan okur', () {
    test('PiyasaSeridi', () {
      expect(PiyasaSeridi.yenilemeAraligi, TazelikRitmi.yuzey);
    });

    test('IntradaySeriesCache', () {
      expect(IntradaySeriesCache.minInterval, TazelikRitmi.gunIciSeriOmru);
    });

    test('kaynak taraması: ham periyot literali KALMADI', () {
      // `fiyat_kaynagi_sozlesmesi_test` ile aynı disiplin: sözleşmeyi
      // atlayan bir yüzey eklenirse burada görünür.
      //
      // Aranan desen: `Duration(seconds: 30)` / `Duration(seconds: 45)` —
      // yenileme ritmi olarak kullanılabilecek ham sabitler.
      final dosyalar = <String, String>{
        'piyasa_seridi.dart': ekranKaynagiSync('lib/widgets/piyasa_seridi.dart'),
        'bugun_karti.dart': ekranKaynagiSync('lib/widgets/bugun_karti.dart'),
        'price_service.dart': ekranKaynagiSync('lib/services/price_service.dart'),
      };

      dosyalar.forEach((ad, src) {
        for (final yasak in [
          'Duration(seconds: 30)',
          'Duration(seconds: 45)',
        ]) {
          expect(src.contains(yasak), isFalse,
              reason: '$ad içinde ham `$yasak` var — ritim '
                  'TazelikRitmi\'nden okunmalı, yoksa bir sonraki '
                  'değişiklikte yeniden ayrışır');
        }
      });
    });
  });
}
