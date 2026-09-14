
import 'package:flutter_test/flutter_test.dart';
import 'helpers/kaynak.dart';

/// Gün içi grafiğin X ekseni ÇİZİLEN GÜNÜN 00:00'ından başlamalı.
///
/// ## Yakaladığı hata (kullanıcı bildirimi 2026-09-12)
/// "Hâlâ grafiklerde 12 Eylül datalarını göremiyorum."
///
/// Veri katmanı doğruydu — ölçüldü, beş dönem de 12 Eylül'e ulaşıyordu.
/// Hata ÇİZİMDEYDİ: ekran X eksenini `effectiveStart` ile kuruyordu ve
/// gün içi dalda o değer BUGÜNÜN 00:00'ıydı.
///
/// Piyasa kapalıyken seri son seanstan (Cuma) bugüne uzanıyor. Eksen
/// bugünün 00:00'ına kurulunca Cuma noktaları NEGATİF X'e düşüyor ve
/// `fl_chart` onları çizim alanı dışında bırakıyordu: grafik boş ya da
/// yarım görünüyordu.
///
/// Tam ekran grafiği (`data?.seansGunu ?? startDate`) bunu zaten doğru
/// yapıyordu; ana grafik yapmıyordu — iki yüzey ayrışmıştı.
///
/// ## İkinci düzeltme: "şimdi" noktası
/// Canlı uç noktası `bugunMu` (gün eşitliği) koşuluna bağlıydı. Kuyruk
/// geldikten sonra bu ölçüt yanlış: seri bugüne uzanıyor, yani "şimdi"
/// eksende VAR. Ölçüt takvimden GEOMETRİYE çevrildi.
void main() {
  final kaynak = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
      .replaceAll('\r\n', '\n');

  /// Boşlukları tek boşluğa indirmiş kaynak.
  ///
  /// Kaynak-metin iddiaları BİÇİME değil, mantığın VARLIĞINA bakmalı.
  /// Dosya büyüdüğünde `dart format` sarma noktasını kaydırıyor ve
  /// satır başı girintisine dayanan iddialar, mantık hiç değişmemiş
  /// olmasına rağmen kırılıyor (2026-09-13'te tam olarak bu oldu:
  /// üçlü operatör üç satırdan ikiye düştü).
  final tek = kaynak.replaceAll(RegExp(r'\s+'), ' ');

  group('eksen başlangıcı', () {
    test('gün içi çizim `seansGunu`\'nu kullanır', () {
      expect(tek.contains('final cizimBaslangici = isIntraday'), isTrue,
          reason: 'Gün içi/dışı ayrımı yok.');
      expect(kaynak.contains('breakdown.seansGunu ?? effectiveStart'), isTrue,
          reason: 'Eksen hâlâ bugünün 00:00\'ına kuruluyor — kapalı '
              'günlerde noktalar negatif X\'e düşer.');
    });

    test('TÜM tüketiciler aynı başlangıcı alır', () {
      // Segment üretimi, değişim kartı, grafik kabı ve döküm paneli
      // aynı X eksenini yorumluyor. Biri `effectiveStart`ta kalırsa
      // yanlış günü anlatır — sessiz ve fark edilmesi zor.
      final sayi = 'cizimBaslangici'.allMatches(kaynak).length;
      expect(sayi, greaterThanOrEqualTo(5),
          reason: 'Tüketicilerden biri hizalanmamış ($sayi bulundu).');
    });

    test('non-intraday `effectiveStart` KORUNUR', () {
      // Düzeltme yalnızca gün içi dalı etkilemeli: diğer dönemlerde
      // başlangıç ilk alım tarihine kaydırılabiliyor.
      // Gün DIŞI dalın `effectiveStart`a düştüğünü doğrular. Girintiye
      // dayanan eski hâli (`'        : effectiveStart;'`) format
      // değişikliğinde kırılıyordu; kovalanan şey ternary'nin yanlış
      // dalının değişmemiş olması.
      expect(tek.contains(': effectiveStart;'), isTrue,
          reason: 'Gün dışı dal da değişmiş.');
      expect(tek.contains('if (!isIntraday && !_simulate)'), isTrue,
          reason: 'İlk alım kaydırması kaldırılmış.');
    });
  });

  group('"şimdi" noktası', () {
    test('ölçüt GEOMETRİ — takvim günü eşitliği DEĞİL', () {
      expect(kaynak.contains('simdiEksendeVar'), isTrue,
          reason: 'Yeni ölçüt yok.');
      expect(kaynak.contains('nowMinutesX >= 0'), isTrue,
          reason: '"Şimdi" eksende mi sorusu geometriyle sorulmuyor.');
    });

    test('eski `bugunMu` koşulu GERİ GELMEZ', () {
      // Bu koşul hafta sonunda canlı değeri engelliyordu.
      expect(kaynak.contains('final bugunMu ='), isFalse,
          reason: 'Gün eşitliği koşulu geri gelmiş — hafta sonunda son '
              'nokta canlı değere sabitlenmez.');
    });

    test('canlı toplam son noktaya YAZILIR', () {
      expect(
        kaynak.contains('FlSpot(nowMinutesX, currentTotalOverride)'),
        isTrue,
        reason: 'Kullanıcı isteği: "şu an noktasında izlenen anın değeri '
            'gösterilmeli."',
      );
    });
  });

  test('kuyruk bölmesi canlı noktadan SONRA yapılır', () {
    // Sıra önemli: bölme önce yapılsaydı canlı nokta hiçbir segmente
    // giremez ve grafiğin ucu eski değerde kalırdı.
    final canliIdx =
        kaynak.indexOf('FlSpot(nowMinutesX, currentTotalOverride)');
    final bolmeIdx = kaynak.indexOf('if (piyasaKapaliBaslangicTs != null)');
    expect(canliIdx, isNot(-1));
    expect(bolmeIdx, isNot(-1));
    expect(canliIdx < bolmeIdx, isTrue,
        reason: 'Bölme canlı noktadan ÖNCE yapılıyor — uç nokta kaybolur.');
  });
}
