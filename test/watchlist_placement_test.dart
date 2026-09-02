import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Takip listesinin yeri: Portföy ekranının GÖVDESİ — üst bar DEĞİL.**
///
/// ## Neden bu test var
/// Takip listesi ilk olarak Ana ekranın üst barına ikon olarak kondu. Orası
/// zaten DÖRT düğme taşıyordu (yenile · bakiye gizle · sinyal çanı · çıkış) ve
/// satır o hâliyle bile taşıyordu: `home_screen.dart`'taki marka rozetinin
/// `Flexible`+`FittedBox` sarmalayıcısı, 17px'lik bir taşmayı kapatmak için
/// eklenmişti. Beşinci düğme HIG'in navigation bar kuralını çiğniyordu
/// ("Don't overcrowd with too many buttons" — Severity: High).
///
/// ## Neden `home_screen_overflow_test` bunu YAKALAMADI
/// O test `takeException()` null mu diye bakar. Flutter'ın taşma hatası
/// paint zamanında atılır — ama `FittedBox` taşmayı YUTAR: hata atmak yerine
/// içeriği küçültür. Yani beşinci düğme bir istisna üretmedi, sessizce marka
/// logosunu daralttı. O test yapısı gereği bu regresyona kördü.
///
/// Bu yüzden koruma metin düzeyinde: düğmenin nereye konduğunu doğrudan
/// denetliyoruz. Yerleşim kararı bir GÖRÜNÜM tercihi değil, ölçülmüş bir
/// kısıt — kod okunarak korunmalı.
///
/// ## Bu testin sınırı
/// Kaynak metnine bakar, piksel ölçmez. Amacı "beşinci düğme geri gelmesin"
/// kuralını kilitlemek; görsel doğrulama widget testlerinin işi.

/// Yorum satırlarını atar — aksi halde bir açıklama içindeki kelime
/// gerçek kodmuş gibi sayılır. (Bu tuzağa `signal_provider` tarafındaki
/// wiring testinde bir kez düşüldü: sabotaj yorum satırına alındığında test
/// hâlâ geçiyordu.)
String _yorumsuz(String src) => src
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    })
    .join('\n');

void main() {
  late String home;
  late String charts;

  setUpAll(() async {
    home = _yorumsuz(await File('lib/screens/home_screen.dart').readAsString());
    charts =
        _yorumsuz(await File('lib/screens/charts_screen.dart').readAsString());
  });

  group('üst bar kalabalıklaşmaz', () {
    test('Ana ekranın üst barında takip listesi düğmesi YOK', () {
      expect(home.contains('_WatchlistBadgeButton'), isFalse,
          reason: 'Ana ekranın üst barı zaten dört düğmeyle taşıyordu; '
              'beşincisi marka logosunu sessizce daraltır');
      expect(home.contains('WatchlistScreen'), isFalse,
          reason: 'Ana ekran takip listesine giriş noktası SUNMAZ — '
              'giriş Portföy sekmesindedir');
    });

    test('Portföy ekranının ÜST BARINA da eklenmemiş', () {
      // Aynı hatayı bir ekran ötesine taşımak çözüm olmazdı: Portföy'ün üst
      // barı da dört kontrol taşıyor (sırala · performans · karşılaştır ·
      // çıkış). Giriş noktası GÖVDEDE olmalı.
      //
      // Header, `Body` yorumuna kadar olan bölüm. Yorumlar ayıklandığı için
      // sınırı `Expanded(` ile buluyoruz — gövde orada başlıyor.
      final bodyStart = charts.indexOf('Expanded(');
      expect(bodyStart, greaterThan(0),
          reason: 'charts_screen yapısı değişmiş — bu testi güncelle');
      final header = charts.substring(0, bodyStart);
      expect(header.contains('WatchlistScreen'), isFalse,
          reason: 'takip listesi girişi üst bara değil gövdeye konur');
    });
  });

  group('doğru yerde duruyor', () {
    test('Portföy ekranının gövdesinde giriş satırı VAR', () {
      expect(charts.contains('_WatchlistEntry'), isTrue,
          reason: 'takip listesi bir varlık listesidir; yeri sahip olunan '
              'varlıkların bittiği yerdir');
      expect(charts.contains('WatchlistScreen'), isTrue,
          reason: 'satır tam sayfayı açmalı');
    });

    test('giriş satırı varlık listesinden SONRA gelir', () {
      // Sıra anlam taşır: izlenen varlıklar sahip olunanların ALTINDA durur.
      // Üstte olsalardı ekranın tepesindeki toplamın parçasıymış gibi
      // okunurlardı.
      final liste = charts.indexOf('_AssetList(');
      final giris = charts.indexOf('const _WatchlistEntry()');
      expect(liste, greaterThan(0));
      expect(giris, greaterThan(liste),
          reason: 'takip girişi varlık listesinin ALTINDA olmalı');
    });

    test('satır 44pt dokunma hedefi sağlar', () {
      final i = charts.indexOf('class _WatchlistEntry');
      expect(i, greaterThan(0));
      final govde = charts.substring(i, i + 2000);
      expect(govde.contains('minHeight: 44'), isTrue,
          reason: 'HIG minimum dokunma hedefi');
    });

    test('satır "portföye dahil değil" ayrımını YAZIYLA söyler', () {
      // Ayrımı yalnızca kenarlık stiliyle anlatmak renk/biçim algısına
      // bağımlı olurdu (bkz. UX kuralı: "Don't convey information by color
      // alone", Severity: High).
      final i = charts.indexOf('class _WatchlistEntry');
      final govde = charts.substring(i, i + 2000);
      expect(govde.contains('portföye dahil değil'), isTrue,
          reason: 'en kritik ayrım metinde geçmeli, yalnızca stilde değil');
    });
  });
}
