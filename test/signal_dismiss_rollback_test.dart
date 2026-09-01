import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bildirim silme sözleşmesi: **iyimser güncelleme + başarısızlıkta geri alma**.
///
/// ## Kapsanan hata (2026-09-01)
/// Kullanıcı: "pushları bildirim çanı kısmından silmeye çalıştığımda silmiyor".
///
/// Üç ayrı kusur vardı ve üçü birlikte çalışınca silme hem olmuyor hem de
/// olmuş gibi görünüyordu:
///
/// 1. **Sessiz başarısızlık.** `SignalNotifier.dismiss` şöyleydi:
///        try { await ...dismissSignalNotification(id); } catch (_) {}
///        state = AsyncData([... dismissedAt: now ...]);
///    Sunucu isteği reddetse bile state "silindi" olarak yazılıyordu. Kullanıcı
///    sildiğini sanıyor, uygulama yeniden açılınca kayıt geri geliyordu.
///
/// 2. **Sheet provider'ı izlemiyordu.** `_SignalsBottomSheet` bir
///    `StatelessWidget`'tı ve listeyi `ref.read` ile PARAMETRE olarak alıyordu.
///    Sheet ayrı bir route olduğu için provider güncellemeleri ona hiç
///    ulaşmıyordu — silme sunucuda başarılı olsa bile liste ekranda
///    değişmiyordu. Artık `ConsumerWidget`.
///
/// 3. **GRANT eksikliği** (`0042`): RLS politikaları eksiksizdi ama tabloya
///    hiç `grant` yazılmamıştı. `signal_state`'te birebir yaşanmış hata
///    (0035 politika ekledi → sorun sürdü, 0036 GRANT'ı ekledi → çözüldü).
///
/// Buradaki testler 1. maddenin aritmetiğini kilitler: state geçişleri
/// private notifier'a bağlı olmadan yeniden üretilir.

/// `SignalNotifier.dismiss` / `delete` / `dismissAll` state geçişi.
///
/// Ekrandaki akışın birebir aynısı: önce iyimser yaz, sunucu reddederse
/// ÖNCEKİ listeye dön.
({List<String> son, bool hataFirlatildi}) silmeAkisi({
  required List<String> mevcut,
  required String silinecek,
  required bool sunucuKabulEtti,
}) {
  final oncesi = List<String>.from(mevcut);
  // İyimser: hemen düş.
  var state = mevcut.where((e) => e != silinecek).toList();
  if (!sunucuKabulEtti) {
    // Geri al — ekran yalan söylememeli.
    state = oncesi;
    return (son: state, hataFirlatildi: true);
  }
  return (son: state, hataFirlatildi: false);
}

void main() {
  group('tekil silme', () {
    test('sunucu kabul ederse satır gider', () {
      final r = silmeAkisi(
        mevcut: ['a', 'b', 'c'],
        silinecek: 'b',
        sunucuKabulEtti: true,
      );
      expect(r.son, ['a', 'c']);
      expect(r.hataFirlatildi, isFalse);
    });

    test('sunucu REDDEDERSE satır GERİ GELİR ve hata fırlatılır', () {
      // Asıl düzeltme. Eskiden satır gitmiş kalıyor, hata da yutuluyordu:
      // kullanıcı sildiğini sanıyor, yeniden açınca geri geliyordu.
      final r = silmeAkisi(
        mevcut: ['a', 'b', 'c'],
        silinecek: 'b',
        sunucuKabulEtti: false,
      );
      expect(r.son, ['a', 'b', 'c'],
          reason: 'başarısız silmede liste değişmemeli');
      expect(r.hataFirlatildi, isTrue,
          reason: 'çağıran kullanıcıya haber verebilmeli — sessiz kalınamaz');
    });

    test('iyimser güncelleme ANINDA olur — sunucu beklenmez', () {
      // Dokunma anında tepki (Apple: "respond on pointer-down"). Sunucu
      // yanıtı beklenirse satır saniyelerce ekranda kalır ve kullanıcı
      // tekrar tekrar dokunur.
      final r = silmeAkisi(
        mevcut: ['a', 'b'],
        silinecek: 'a',
        sunucuKabulEtti: true,
      );
      expect(r.son.contains('a'), isFalse);
    });
  });

  group('tümünü temizle', () {
    /// Toplu akış: ya hepsi ya hiçbiri.
    ({List<String> son, bool hataFirlatildi}) topluSilme({
      required List<String> mevcut,
      required bool sunucuKabulEtti,
    }) {
      final oncesi = List<String>.from(mevcut);
      if (!sunucuKabulEtti) return (son: oncesi, hataFirlatildi: true);
      return (son: <String>[], hataFirlatildi: false);
    }

    test('hepsi silinir', () {
      final r = topluSilme(mevcut: ['a', 'b', 'c'], sunucuKabulEtti: true);
      expect(r.son, isEmpty);
    });

    test('KISMİ başarı yok — biri düşerse hepsi geri gelir', () {
      // Eskiden her satır ayrı `try/catch` içindeydi ve hepsi yutuluyordu:
      // yarısı silinip yarısı kalabiliyor, ekran hepsini silinmiş
      // gösteriyordu. Artık tek toplu istek (`inFilter`), tek sonuç.
      final r = topluSilme(mevcut: ['a', 'b', 'c'], sunucuKabulEtti: false);
      expect(r.son, ['a', 'b', 'c']);
      expect(r.hataFirlatildi, isTrue);
    });

    test('boş listede istek atılmaz', () {
      // `dismissAll` erken döner; `dismissSignalNotifications` da boş listede
      // hiç sorgu kurmaz.
      final r = topluSilme(mevcut: [], sunucuKabulEtti: true);
      expect(r.son, isEmpty);
      expect(r.hataFirlatildi, isFalse);
    });
  });

  group('wiring koruması — kaynak metin', () {
    // Birim testleri aritmetiği doğrular, BAĞLANTIYI değil. Bu projede aynı
    // ayrım daha önce sabotajla ölçülmüştü (`lot_collapse_test.ts`): fonksiyon
    // doğruyken çağrı yeri bozulunca tüm birim testleri geçmişti.

    test('SİLME metotları hatayı YUTMAZ — rethrow var', () async {
      final src = await _oku('lib/providers/signal_provider.dart');

      // Kapsam yalnızca silme yolu. Dosyanın başka yerlerinde boş `catch`
      // MEŞRUDUR: `analyzePortfolio` okuma/analiz yapar ve orada hata
      // yutmak bilinçli bir karardır (fiyat çekilemezse ekran çökmemeli).
      // Silme farklıdır — kullanıcı bir eylem yaptı ve sonucunu bilmeli.
      for (final metot in ['dismiss', 'delete', 'dismissAll']) {
        final govde = _metotGovdesi(src, metot);
        expect(govde, isNotNull, reason: '$metot bulunamadı');
        expect(govde!.contains('rethrow'), isTrue,
            reason: '$metot başarısızlığı çağırana ulaşmalı — '
                '`catch (_) {}` sessiz başarısızlık üretir');
        expect(govde.contains('catch (_) {}'), isFalse,
            reason: '$metot içinde boş catch var — silme sessizce '
                'başarısız olur ve kullanıcı sildiğini sanır');
      }
    });

    test('sheet provider’ı İZLİYOR — ConsumerWidget', () async {
      final src = await _oku('lib/screens/home_screen.dart');
      expect(src.contains('class _SignalsBottomSheet extends ConsumerWidget'),
          isTrue,
          reason: 'StatelessWidget + parametre liste = sheet açıkken '
              'güncelleme görünmez');
      expect(src.contains('ref.watch(signalProvider)'), isTrue,
          reason: 'sheet listeyi provider’dan canlı okumalı');
    });

    test('toplu silme TEK istek — inFilter', () async {
      final src = await _oku('lib/services/supabase_service.dart');
      expect(src.contains('.inFilter(\'id\', ids)'), isTrue,
          reason: 'satır başına ayrı istek yavaş ve yarıda kesilmeye açık');
    });
  });
}

Future<String> _oku(String yol) async {
  // Test çalışma dizini proje kökü.
  return await File(yol).readAsString();
}

/// `Future<void> <ad>(` imzasından başlayıp süslü parantez dengesi kapanana
/// kadar olan gövdeyi döndürür — yoksa `null`.
///
/// Kaba ama yeterli: amaç metot GÖVDESİNİ izole etmek, böylece dosyanın başka
/// yerindeki (meşru) boş `catch`'ler silme sözleşmesini yanlışlıkla
/// düşürmesin.
String? _metotGovdesi(String src, String ad) {
  final imza = RegExp('Future<void>\\s+$ad\\s*\\(');
  final m = imza.firstMatch(src);
  if (m == null) return null;

  final acilis = src.indexOf('{', m.end);
  if (acilis < 0) return null;

  var derinlik = 0;
  for (var i = acilis; i < src.length; i++) {
    if (src[i] == '{') derinlik++;
    if (src[i] == '}') {
      derinlik--;
      if (derinlik == 0) return src.substring(acilis, i + 1);
    }
  }
  return null;
}
