import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/tazelik_ritmi.dart';

import 'helpers/kaynak.dart';

/// Kullanıcı isteği (2026-09-23): *"Günlük grafik, özet, ana sayfa kartları
/// tutarlı ve senkron şekilde yenilenmeli, veri tutarsızlığı olmamalı."*
///
/// ## Ritimleri eşitlemek YETMEDİ
/// `TazelikRitmi` ile tüm periyotlar 30 sn'ye hizalandı. Ama her yüzey kendi
/// `Timer`'ını MOUNT ANINDA kuruyordu — yani aynı sıklıkta, FARKLI FAZDA:
///
/// ```
///   Ana sayfa açıldı  t=0   → Bugün kartı tick: 0, 30, 60, 90…
///   Performans'a geçti t=12  → Performans tick: 12, 42, 72, 102…
/// ```
///
/// İki yüzey 12 saniye farklı anın verisini gösteriyordu. Gün başı serinin
/// ilk noktasından, canlı uç o andaki fiyattan geldiği için aradaki fark
/// ekrana yansıyordu.
///
/// ## Çözüm: tek nabız
/// Sayaç uygulamada, yüzeyler yalnızca DİNLER. Hangi ekrandan girildiğinden
/// bağımsız olarak herkes AYNI tick'te tazelenir.
void main() {
  // `TazelikNabzi` yaşam döngüsünü `WidgetsBinding` üzerinden izliyor
  // (arka planda durur, öne gelince tur atar) — binding ŞART.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nabız davranışı', () {
    test('dinleyiciler AYNI tick\'te çağrılır', () {
      final sira = <String>[];
      final birak1 = TazelikRitmi.nabiz.dinle(() => sira.add('bugun'));
      final birak2 = TazelikRitmi.nabiz.dinle(() => sira.add('performans'));

      TazelikRitmi.nabiz.atForTest();

      expect(sira, containsAll(['bugun', 'performans']),
          reason: 'iki yüzey aynı anda tazelenmeli — faz kayması olamaz');
      expect(sira, hasLength(2));

      birak1();
      birak2();
    });

    test('bırakılan dinleyici bir daha çağrılmaz', () {
      var sayac = 0;
      final birak = TazelikRitmi.nabiz.dinle(() => sayac++);
      TazelikRitmi.nabiz.atForTest();
      expect(sayac, 1);

      birak();
      TazelikRitmi.nabiz.atForTest();
      expect(sayac, 1, reason: 'ekranda olmayan yüzey için iş yapılmamalı');
    });

    test('dinleyici sayısı doğru izlenir', () {
      expect(TazelikRitmi.nabiz.dinleyiciSayisi, 0,
          reason: 'önkoşul: temiz başlangıç');

      final b1 = TazelikRitmi.nabiz.dinle(() {});
      expect(TazelikRitmi.nabiz.dinleyiciSayisi, 1);
      final b2 = TazelikRitmi.nabiz.dinle(() {});
      expect(TazelikRitmi.nabiz.dinleyiciSayisi, 2);

      b1();
      expect(TazelikRitmi.nabiz.dinleyiciSayisi, 1);
      b2();
      expect(TazelikRitmi.nabiz.dinleyiciSayisi, 0,
          reason: 'sıfıra inince sayaç da durmalı (pil)');
    });

    test('tick sırasında kendini bırakan dinleyici çökertmez', () {
      // Gerçek senaryo: kullanıcı ekrandan çıkarken `dispose` tam o anda.
      // Koleksiyon döngü sırasında değişirse `ConcurrentModificationError`.
      VoidCallback? birak;
      var sayac = 0;
      birak = TazelikRitmi.nabiz.dinle(() {
        sayac++;
        birak?.call(); // döngü İÇİNDE kendini kaldır
      });
      final digerBirak = TazelikRitmi.nabiz.dinle(() => sayac++);

      expect(() => TazelikRitmi.nabiz.atForTest(), returnsNormally,
          reason: 'kopya üzerinde gezilmeli');
      expect(sayac, 2);

      digerBirak();
      expect(TazelikRitmi.nabiz.dinleyiciSayisi, 0);
    });

    test('nabız aralığı yüzey ritmidir', () {
      expect(TazelikRitmi.nabiz.aralik, TazelikRitmi.yuzey);
      expect(TazelikRitmi.nabiz.aralik, TazelikRitmi.temel);
    });
  });

  group('yüzeyler kendi Timer\'ını KURMAZ', () {
    test('BugunKarti nabzı dinler', () {
      final src = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('TazelikRitmi.nabiz.dinle('), isTrue,
          reason: 'kendi sayacını kuran yüzey faz kaydırır');
      // YORUMLARI ele: açıklama metinlerinde `Timer.periodic` geçiyor
      // (eski davranışın kaydı). Aranan şey ÇALIŞAN kod.
      final kodsuz = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(kodsuz.contains('Timer.periodic'), isFalse,
          reason: 'bağımsız sayaç KALMAMALI');
      expect(tek.contains('_nabziBirak?.call();'), isTrue,
          reason: 'dispose\'da bırakılmalı (sızıntı)');
    });

    test('Performans nabzı dinler', () {
      final src =
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('TazelikRitmi.nabiz.dinle('), isTrue);
      expect(tek.contains('Timer.periodic(TazelikRitmi.yuzey'), isFalse,
          reason: 'bağımsız sayaç KALMAMALI');
      expect(tek.contains('_nabziBirak?.call();'), isTrue);
    });

    test('PiyasaSeridi nabzı dinler', () {
      // Bant da kendi `ForegroundPoller`'ını kuruyordu: "USD 48,79" derken
      // portföy toplamı henüz bir önceki kotasyondan hesaplanmış
      // olabiliyordu — aynı ekranda iki farklı an.
      final src = ekranKaynagiSync('lib/widgets/piyasa_seridi.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('TazelikRitmi.nabiz.dinle(_yukle)'), isTrue,
          reason: 'bant da ortak nabza bağlı olmalı');
      // Yorumları ele — açıklamada `ForegroundPoller` geçiyor (eski
      // davranışın kaydı). Aranan şey ÇALIŞAN kod.
      final kodsuz = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//') &&
              !l.trimLeft().startsWith('///'))
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(kodsuz.contains('ForegroundPoller'), isFalse,
          reason: 'bağımsız poller KALMAMALI');
      expect(tek.contains('_nabziBirak?.call();'), isTrue);
    });

    test('bant ilk turu HEMEN atar (nabız beklenmez)', () {
      // Nabız ilk tick'ini bir aralık SONRA atar; bant o süre boyunca
      // boş kalırdı.
      final src = ekranKaynagiSync('lib/widgets/piyasa_seridi.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('_yukle(); _nabziBirak = TazelikRitmi.nabiz.dinle'),
          isTrue,
          reason: 'açılışta 30 sn boş bant gösterilmemeli');
    });

    test('fiyat turunu Performans başlatır (tekilleştirme var)', () {
      // İki yüzey aynı nabızda `refreshPrices` çağırsa bile
      // `PortfolioNotifier` in-flight tekilleştirme yapıyor → tek ağ turu.
      final src =
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('ref.read(portfolioProvider.notifier).refreshPrices();'),
          isTrue);
    });
  });
}
