import '../utils/tr_format.dart' show dayKey;

/// Para piyasası fonunda "Son 30 günde günde ortalama ~₺X" (müşteri raporu
/// 7 Kas 22:30 #1, ücretsiz).
///
/// ## Neden
/// Parası para piyasası fonunda duran kullanıcı "bugün kaç lira işledi"
/// diye bakar; ekran ona yüzde söylüyordu. Banka uygulamaları vadesizde
/// günlük nemayı lira olarak gösterir. Ücretsiz: sayım, analiz değil (altın
/// gramıyla aynı karar).
///
/// ## Neden yalnız para piyasası
/// Hisse ya da altın fonunda "günde ortalama ₺X" sabit bir faiz gibi okunur
/// ve yanıltır; para piyasası fonunun getirisi güne yayılır, ortalama bir
/// anlam taşır.

/// TEFAS kategorisi (`TefasFund.kategori`, `fonTurAciklama`: "Para Piyasası
/// Şemsiye Fonu") para piyasası mı. `null` ya da boş → `false`: kategori
/// TAHMİN edilmez (fon adında "PARA" geçmesi yetmez).
///
/// Büyük/küçük harf ve Türkçe İ/ı farkı sonucu değiştirmez: TEFAS bir gün
/// "PARA PİYASASI" yazarsa satır sessizce kaybolmasın.
bool paraPiyasasiKategorisiMi(String? kategori) {
  if (kategori == null) return false;
  final k = kategori.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  return k.contains('para piyasas');
}

/// Pencerenin uzunluğu: "son 30 gün".
const gunlukGetiriPencereGun = 30;

/// Dönem başı noktası pencere başından en fazla bu kadar önce olabilir
/// (hafta sonu + bayram arifesi: fon fiyatı o günlerde yayımlanmaz). Daha
/// eski bir nokta seride delik demektir; o zaman satır yok.
const _toleransGun = 5;

/// Bugünkü pozisyonun son 30 günde günde ortalama ne kazandırdığı, TL.
/// Saf; ağ ve `BuildContext` yok.
///
/// ## Hesap
/// Pencere başı (`simdi − 30 gün`) ya da hemen öncesindeki birim fiyat
/// `eski`, bugünkü canlı birim fiyat [guncelBirim]. Bugünkü tutar
/// [guncelDegerTRY] = V ise 30 gün önce aynı paylar `V × eski / güncel`
/// ediyordu; kazanç `V × (1 − eski / güncel)`, gün sayısına bölünür. Gün
/// sayısı noktanın GERÇEK tarihinden (30–35): hafta sonuna denk gelen
/// pencerede kazanç fazladan bir güne bölünür, şişirilmez.
///
/// Görev "tutar × 30 günlük getiri / 30" diyordu; o biçim getiriyi bugünkü
/// (büyümüş) tutara uygular ve 30 gün önceki payların kazancını getiri
/// oranı kadar fazla yazar. Burada kazanç bugünkü payların 30 günde
/// gerçekten kazandığıdır.
///
/// [seriler]: birim fiyat serileri (epoch ms → TL), tercih sırasıyla; ilk
/// sonuç veren kullanılır (varlık ekranında 3A, 1A, 6A: dönem çipleri için
/// zaten yüklenmiş, yeni istek yok).
///
/// ## Satır yok (`null`) — uydurma sayı yok
///   · bugünkü değer ya da canlı fiyat bilinmiyor (≤ 0, sonsuz);
///   · hiçbir seri 30 gün geriye uzanmıyor (yeni fon, kısa seri);
///   · pencere başına en yakın nokta 5 günden eski (seride delik);
///   · dönem başı fiyatı ≤ 0.
double? gunlukOrtalamaGetiri({
  required Iterable<Map<int, double>?> seriler,
  required double guncelBirim,
  required double guncelDegerTRY,
  required DateTime simdi,
}) {
  if (!(guncelDegerTRY > 0) || !guncelDegerTRY.isFinite) return null;
  if (!(guncelBirim > 0) || !guncelBirim.isFinite) return null;
  // Pencere başı takvim gününün başı: gün içi saat sonucu oynatmasın.
  final hedef = dayKey(simdi)
      .subtract(const Duration(days: gunlukGetiriPencereGun))
      .millisecondsSinceEpoch;
  final altSinir = hedef - const Duration(days: _toleransGun).inMilliseconds;
  for (final seri in seriler) {
    if (seri == null || seri.isEmpty) continue;
    int? ts;
    double? eski;
    for (final e in seri.entries) {
      if (e.key > hedef || e.key < altSinir) continue;
      if (!(e.value > 0) || !e.value.isFinite) continue;
      if (ts == null || e.key > ts) {
        ts = e.key;
        eski = e.value;
      }
    }
    if (ts == null || eski == null) continue;
    final gun = simdi.millisecondsSinceEpoch - ts;
    final gunSayisi = gun / Duration.millisecondsPerDay;
    if (gunSayisi < gunlukGetiriPencereGun) continue;
    final kazanc = guncelDegerTRY * (1 - eski / guncelBirim);
    final gunluk = kazanc / gunSayisi;
    if (!gunluk.isFinite) continue;
    return gunluk;
  }
  return null;
}
