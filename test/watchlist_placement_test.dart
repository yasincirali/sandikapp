import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Takip listesinin yeri: Portföy ekranının gövde ÜSTÜNDE bir segment.**
///
/// ## Yerleşimin geçmişi — üç deneme
/// 1. **Ana ekranın üst barı (ikon).** Orası zaten DÖRT düğme taşıyordu
///    (yenile · bakiye gizle · sinyal çanı · çıkış) ve satır o hâliyle bile
///    taşıyordu: `home_screen.dart`'taki marka rozetinin `Flexible`+`FittedBox`
///    sarmalayıcısı 17px'lik bir taşmayı kapatmak için eklenmişti. Beşinci
///    düğme HIG'in navigation bar kuralını çiğniyordu ("Don't overcrowd with
///    too many buttons" — Severity: High).
/// 2. **Portföy listesinin EN DİBİ.** Taşma çözüldü ama liste uzun; giriş
///    satırı 32pt boşluktan sonra, kaydırmanın sonunda kalıyordu. Kullanıcı
///    testinde bulgu buydu: "takip listesi daha görünür bir yerde olmalı".
/// 3. **Gövdenin EN ÜSTÜNDE segment** — bugünkü hâli. Bir dokunuşla görünür,
///    hiçbir bar kalabalıklaşmaz.
///
/// ## Neden alt gezinme çubuğuna sekme DEĞİL
/// Bar zaten Ana·Portföy·[+]·Performans·Profil ile dolu. Beşinci sekme aynı
/// HIG kuralına girerdi — sorunu bir ekran öteye taşımak çözüm olmaz.
///
/// ## Neden iki seçici yan yana gelmiyor
/// Portföy ekranında ortak seçici (`ModernTabSelector`) de bir yatay segment.
/// İkisi üst üste dizilseydi "hangi seçici neyi filtreliyor?" sorusu doğardı.
/// Gövde sekmesi EN ÜSTTE; ortak seçici "Varlıklarım" dalının İÇİNDE kalır,
/// yani Takip sekmesindeyken hiç çizilmez.
///
/// ## Neden `home_screen_overflow_test` bunu YAKALAMADI
/// O test `takeException()` null mu diye bakar. Flutter'ın taşma hatası paint
/// zamanında atılır — ama `FittedBox` taşmayı YUTAR: hata atmak yerine içeriği
/// küçültür. Yani beşinci düğme bir istisna üretmedi, sessizce marka logosunu
/// daralttı. O test yapısı gereği bu regresyona kördü.
///
/// Bu yüzden koruma metin düzeyinde: düğmenin nereye konduğunu doğrudan
/// denetliyoruz. Yerleşim kararı bir GÖRÜNÜM tercihi değil, ölçülmüş bir
/// kısıt — kod okunarak korunmalı.
///
/// ## Bu testin sınırı
/// Kaynak metnine bakar, piksel ölçmez. Amacı "beşinci düğme geri gelmesin" ve
/// "giriş noktası yine listenin dibine düşmesin" kurallarını kilitlemek;
/// görsel doğrulama widget testlerinin işi.

/// Yorum satırlarını atar — aksi halde bir açıklama içindeki kelime gerçek
/// kodmuş gibi sayılır. (Bu tuzağa `signal_provider` tarafındaki wiring
/// testinde bir kez düşüldü: sabotaj yorum satırına alındığında test hâlâ
/// geçiyordu.)
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
  late String nav;

  setUpAll(() async {
    home = _yorumsuz(await File('lib/screens/home_screen.dart').readAsString());
    charts =
        _yorumsuz(await File('lib/screens/charts_screen.dart').readAsString());
    nav = _yorumsuz(
        await File('lib/screens/main_navigation_screen.dart').readAsString());
  });

  group('hiçbir bar kalabalıklaşmaz', () {
    test('Ana ekranın üst barında takip listesi düğmesi YOK', () {
      expect(home.contains('_WatchlistBadgeButton'), isFalse,
          reason: 'Ana ekranın üst barı zaten dört düğmeyle taşıyordu; '
              'beşincisi marka logosunu sessizce daraltır');
      expect(home.contains('WatchlistBody'), isFalse,
          reason: 'Ana ekran takip listesine giriş noktası SUNMAZ — '
              'giriş Portföy sekmesindedir');
    });

    test('Portföy ekranının ÜST BARINA da eklenmemiş', () {
      // Aynı hatayı bir ekran ötesine taşımak çözüm olmazdı: Portföy'ün üst
      // barı da üç kontrol taşıyor (sırala · karşılaştır · çıkış). Giriş
      // noktası GÖVDEDE olmalı.
      //
      // Header, gövde sekmesine kadar olan bölüm.
      final bodyStart = charts.indexOf('_BodyTabs(');
      expect(bodyStart, greaterThan(0),
          reason: 'charts_screen yapısı değişmiş — bu testi güncelle');
      final header = charts.substring(0, bodyStart);
      expect(header.contains('WatchlistBody'), isFalse,
          reason: 'takip listesi üst bara değil gövdeye konur');
    });

    test('alt gezinme çubuğuna BEŞİNCİ sekme eklenmemiş', () {
      // Bar zaten Ana·Portföy·[+]·Performans·Profil ile dolu.
      expect(nav.contains('WatchlistBody'), isFalse,
          reason: 'beşinci sekme aynı HIG kuralına girer');

      // Sekme sayısı sabit: dört `_navItem(<indeks>` çağrısı + bir FAB.
      // (Tanımın kendisi `_navItem(int index` olduğu için rakam eşleşmez.)
      final sekmeSayisi = RegExp(r'_navItem\(\d').allMatches(nav).length;
      expect(sekmeSayisi, 4,
          reason: 'alt barda dört sekme + FAB olmalı, bulunan: $sekmeSayisi');
    });
  });

  group('giriş noktası gövdenin ÜSTÜNDE', () {
    test('Portföy ekranında gövde sekmesi VAR', () {
      expect(charts.contains('class _BodyTabs'), isTrue,
          reason: 'takip listesi bir dokunuşla erişilebilir olmalı');
      expect(charts.contains("'Takip Listesi'"), isTrue);
      expect(charts.contains("'Varlıklarım'"), isTrue);
    });

    test('sekme, varlık listesinden ÖNCE gelir', () {
      // Bulgu tam da buydu: giriş noktası listenin dibindeyken bulunamıyordu.
      final sekme = charts.indexOf('_BodyTabs(');
      final liste = charts.indexOf('_AssetList(');
      expect(sekme, greaterThan(0));
      expect(liste, greaterThan(0));
      expect(sekme, lessThan(liste),
          reason: 'sekme kaydırmanın sonunda değil, en üstte olmalı');
    });

    test('listenin dibindeki eski giriş satırı KALDIRILDI', () {
      expect(charts.contains('_WatchlistEntry'), isFalse,
          reason: 'iki giriş noktası tutmak, hangisinin doğru olduğu '
              'sorusunu doğururdu');
    });

    test('sekme, takip edilen varlık SAYISINI gösterir', () {
      // Sekme altındaki içerik görünmezken ne olduğunu söylemeli: boş bir
      // listeyle dolu bir liste arasındaki fark, dokunmaya değip
      // değmeyeceğini söyler.
      expect(charts.contains('watchlistCountProvider'), isTrue);
    });

    test('sekme 36pt+ dokunma hedefi sağlar', () {
      final i = charts.indexOf('class _BodyTabs');
      expect(i, greaterThan(0));
      final govde = charts.substring(i, i + 4000);
      expect(govde.contains('minHeight: 36'), isTrue,
          reason: 'dikey padding ile birlikte HIG minimumunu aşar');
    });
  });

  group('gövde tek yerde', () {
    test('takip yüzeyi tek bir gövde widget ında', () async {
      // İki kopya olsaydı biri düzelirken öteki bozuk kalırdı — bu projede
      // tekrar eden bir hata sınıfı (bkz. eksen düzeltmesi).
      final watchlist = _yorumsuz(
          await File('lib/screens/watchlist_screen.dart').readAsString());
      expect(watchlist.contains('class WatchlistBody'), isTrue);
      expect(charts.contains('const Expanded(child: WatchlistBody())'), isTrue,
          reason: 'sekme bu gövdeyi kullanmalı');
    });

    test('ULAŞILAMAYAN tam sayfa route u kalmadı', () async {
      // Segment geldikten sonra `WatchlistScreen`'e giden hiçbir yol
      // kalmamıştı. Ulaşılamayan bir route bakım yükünden başka bir şey
      // değildir; kaldırıldı.
      final watchlist = _yorumsuz(
          await File('lib/screens/watchlist_screen.dart').readAsString());
      expect(watchlist.contains('class WatchlistScreen'), isFalse);
    });

    test('sekmeden de varlık EKLENEBİLİR', () async {
      // Sekmede tam sayfanın üst barı (dolayısıyla oradaki "+") yok. Ekleme
      // yolu gövdenin kendisinde olmalı, yoksa dolu bir takip listesine
      // ikinci bir varlık eklemenin hiçbir yolu kalmıyor.
      final watchlist = _yorumsuz(
          await File('lib/screens/watchlist_screen.dart').readAsString());
      expect(watchlist.contains('class _AddRow'), isTrue,
          reason: 'liste içinde bir ekleme yolu olmalı');
      final i = watchlist.indexOf('class _AddRow');
      expect(watchlist.substring(i).contains('AddWatchlistScreen'), isTrue,
          reason: 'ekleme satırı ekleme ekranını açmalı');
    });
  });

  group('portföy toplamları etkilenmez', () {
    test('takip sekmesi portföy gövdesinin YERİNE geçer', () {
      // Değişmez: bu ekranın toplamları yalnızca `assets`'ten gelir. Takip
      // listesi ayrı bir dal olduğu için özet widget'ı onunla hiç
      // karşılaşmaz.
      expect(charts.contains('if (_bodyTab == 1)'), isTrue,
          reason: 'iki veri kümesi aynı kaydırma alanında birleşmemeli');
    });
  });
}
