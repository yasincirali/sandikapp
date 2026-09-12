import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hafta sonu kuyruğunun GÖRÜNÜMÜ — gri, kesikli, "piyasa kapalı" ibareli.
///
/// Kullanıcı isteği (2026-09-12): "cmt ve pazar günü için piyasa kapalı
/// ibaresi olup gri şekilde çizilecek."
///
/// Çizim `fl_chart` içinde gerçekleşiyor ve emülatör Flutter'ı render
/// edemiyor (bkz. CLAUDE.md) — çizginin gerçekten gri çıktığını gözle
/// doğrulamanın yolu yok. Bu yüzden sözleşme kaynakta denetleniyor:
/// segment ayrımı, kesikli desen, nötr renk ve rozet.
///
/// Kuyruk mantığının KENDİSİ ayrıca saf fonksiyon olarak test ediliyor
/// (`gun_ici_kapali_kuyruk_test.dart`).
void main() {
  final ekran = File('lib/screens/portfolio_performance_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final servis = File('lib/services/history_service.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  group('veri katmanı kuyruğu BİLDİRİR', () {
    test('breakdown `piyasaKapaliBaslangicTs` taşır', () {
      expect(servis.contains('final int? piyasaKapaliBaslangicTs'), isTrue,
          reason: 'Ekran kuyruğun nerede başladığını öğrenemez.');
    });

    test('seri kapanışta KESİLMEZ — bugüne uzar', () {
      // Eski davranış `nowTs = seansSonuTs ?? ...` idi: seri kapanışta
      // bitiyordu ve eksende yalnızca Cuma görünüyordu.
      expect(servis.contains('seansSonuTs ?? normalizeSlot'), isFalse,
          reason: 'Seri yine kapanışta kesiliyor; kuyruk çizilmez.');
      expect(servis.contains('gunIciSagUc('), isTrue,
          reason: 'Sağ uç hesabı ortak fonksiyondan gelmiyor.');
    });

    test('ızgara sabit 288 slotta SINIRLI değil', () {
      // Pazar günü seri ~3 günü kapsar (864 slot). Sabit sayı kuyruğu
      // Cuma gecesinde keserdi.
      expect(servis.contains('hedefSlot.clamp('), isTrue,
          reason: 'Izgara sağ uca göre genişlemiyor.');
    });
  });

  group('çizim — kuyruk AYIRT EDİLİR', () {
    test('segment `piyasaKapali` bayrağı taşır', () {
      expect(ekran.contains('final bool piyasaKapali'), isTrue);
    });

    test('kuyruk KESİKLİ çizilir', () {
      expect(ekran.contains('dashArray: seg.piyasaKapali'), isTrue,
          reason: 'Kesikli desen yok — renk körlüğünde ayırt edilemez.');
    });

    test('kuyruk NÖTR renkte, marka sarısında DEĞİL', () {
      // Sarı çizgi "bu senin birikimin" diyor; kuyruk bir hareket
      // anlatmıyor.
      expect(ekran.contains('lineColor: context.c.text36'), isTrue,
          reason: 'Kuyruk nötr renge çekilmemiş.');
    });

    test('kuyruk altında DOLGU yok', () {
      // Dolgu "bu bölge de birikim" derdi.
      expect(
        ekran.contains('areaGradientStart: Colors.transparent'),
        isTrue,
        reason: 'Kuyruk alanı doldurulmuş.',
      );
    });

    test('seans ve kuyruk AYRI segment', () {
      expect(ekran.contains('piyasaKapaliBaslangicTs != null'), isTrue,
          reason: 'Seri bölünmüyor; tek düz sarı çizgi çizilir.');
    });
  });

  group('ibare — kullanıcıya SÖZLE de söylenir', () {
    test('"PİYASA KAPALI" rozeti var', () {
      expect(ekran.contains("'PİYASA KAPALI'"), isTrue,
          reason: 'Kullanıcı düz çizgiyi "fiyat oynamadı" diye okur.');
    });

    test('rozet yalnızca kuyruk VARKEN gösterilir', () {
      expect(ekran.contains('if (kapaliKuyruk)'), isTrue,
          reason: 'Rozet koşulsuz — hafta içi de görünür.');
    });

    test('rozet segmentlerden TÜRETİLİR, ikinci kaynak yok', () {
      expect(ekran.contains('segments.any((s) => s.piyasaKapali)'), isTrue,
          reason: 'Rozet ayrı bir yoldan besleniyor; iki kaynak ayrışır.');
    });

    test('başlık aralık yazar — tek gün değil', () {
      expect(ekran.contains('→ bugün'), isTrue,
          reason: 'Eksen artık iki günü kapsıyor; başlık bunu söylemeli.');
    });
  });

  test('YASAL/DİL: kuyruk "veri yok" demez', () {
    // Ayrı bir kavram zaten var (`gunIciVerisiYokTurler`): o, fiyat
    // ÇEKİLEMEDİĞİNİ söyler. Kuyruk ise fiyatın var olduğu ama borsanın
    // kapalı olduğu durum. İkisini aynı sözle anlatmak yanlış teşhis olur.
    final bas = ekran.indexOf("'PİYASA KAPALI'");
    expect(bas, isNot(-1));
    final yakin = ekran.substring(bas - 400, bas);
    expect(yakin.contains('veri yok'), isFalse,
        reason: 'Kuyruk "veri yok" ile karıştırılmış.');
  });
}
