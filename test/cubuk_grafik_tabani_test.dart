
import 'package:flutter_test/flutter_test.dart';
import 'helpers/kaynak.dart';

/// Çubuk grafiği: taban DÖNEM BAŞI, pencere dibi DEĞİL.
///
/// ## Neden bu test var
///
/// Kullanıcı bildirimi (2026-09-14, ekran görüntüsüyle): gün içi çubuk
/// grafiği "anlamlı şekilde izlenebilir değil". Portföy ₺2,49M–₺2,51M
/// arasında gezerken çubuklar görünür pencerenin ALT KENARINDAN başlıyordu;
/// her çubuk ~%99 oranında aynı yükseklikte çıkıp grafik taralı bir duvara
/// dönüyordu. O günkü −₺12.794'lük düşüş grafikte hiç görünmüyordu.
///
/// Taban dönem başı olunca çubuk yukarı (kazanç) ya da aşağı (kayıp) büyür
/// ve grafik değişimin YÖNÜNÜ ve BÜYÜKLÜĞÜNÜ anlatır.
///
/// ## Neden kaynak metnine bakıyor
///
/// `_cubukSegmentleri` private ve `LineChartData` kurulumu bir closure'ın
/// içinde; davranışı widget testiyle izole etmek ekranın tamamını (Supabase,
/// fiyat servisi, provider ağacı) ayağa kaldırmayı gerektirirdi.
///
/// Kaynak `\s+` → ' ' ile normalize ediliyor: bu repoda dört test daha önce
/// `dart format`'ın sarma noktasını kaydırması yüzünden, ilgili mantık hiç
/// değişmemişken sahte kırılmıştı. Kovalanan şey çağrının VARLIĞI.
void main() {
  final kaynak = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
      .replaceAll(RegExp(r'\s+'), ' ');

  group('çubuk tabanı', () {
    test('taban dönem başından alınır (viewMinY değil)', () {
      // Çağrı, ilk segmentin ilk noktasını taban olarak geçmeli.
      expect(
        kaynak.contains('segments.first.spots.first.y'),
        isTrue,
        reason: 'Çubuk tabanı dönem başı olmalı — grafiğin anlattığı şey '
            'değişim; pencere dibi taban alınırsa çubuklar eşitlenir.',
      );
    });

    test('Y ekseni tabanı içerir — çubuk alt ucu kırpılmaz', () {
      // Taban pencere dışında kalırsa çubukların altı kesilir ve yarım
      // çubuklar "veri yok" gibi okunur.
      expect(
        kaynak.contains('if (taban < minY) minY = taban;'),
        isTrue,
        reason: 'computeY çubuk tipinde tabanı Y aralığına katmalı.',
      );
    });
  });

  group('çubuk yoğunluğu', () {
    test('seyreltme sınırı TOPLAM nokta üzerinden', () {
      // Eski kod segment BAŞINA 60 çubuk çiziyordu; çok işlemli portföyde
      // segment sayısı arttıkça toplam yüzlere çıkıp çubuklar bitişiyordu.
      expect(
        kaynak.contains('segments.fold<int>(0, (t, s) => t + s.spots.length)'),
        isTrue,
        reason: 'Çubuk bütçesi grafiğin tamamı için hesaplanmalı.',
      );
      expect(
        kaynak.contains('const maksCubuk = 60'),
        isFalse,
        reason: 'Segment başına sabit çubuk sınırı geri gelmemeli.',
      );
    });

    test('kalınlık VERİNİN kapladığı genişlikten hesaplanır', () {
      // Gün içi eksen 00:00–24:00 gösterir ama seans 10:00–18:00 arasıdır:
      // çubuklar grafiğin ~üçte birine sıkışır. Grafiğin TAMAMINI varsayan
      // hesap aralarındaki mesafeyi olduğundan büyük sanıp çubukları üst
      // üste bindiriyordu (kullanıcı bildirimi, ekran görüntüsüyle).
      expect(
        kaynak.contains('final veriGenisligiPx = genislik * kaplamaOrani;'),
        isTrue,
        reason: 'Kalınlık, verinin gerçekte kapladığı piksel genişliğinden '
            'türetilmeli — grafiğin tamamından değil.',
      );
      expect(
        kaynak.contains('(veriAralik / gorunurAralik)'),
        isTrue,
        reason: 'Kaplama oranı veri aralığı / görünür aralık olmalı.',
      );
    });

    test('kalınlık sabit değil, yoğunluktan türetilir', () {
      expect(
        kaynak.contains('final cubukKalinligi ='),
        isTrue,
        reason: 'barWidth: 2.0 sabiti az veride cılız, çok veride bitişikti.',
      );
      // Çubuklar arasında boşluk kalmalı; bitişik çubuk bar grafiğini
      // alan grafiğine çevirir.
      expect(
        kaynak.contains('aralikPx * 0.65'),
        isTrue,
        reason: 'Çubuk genişliği aralığın tamamını doldurmamalı.',
      );
    });
  });
}
