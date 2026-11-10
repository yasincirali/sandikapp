/// Varlık grafiğinin "Tablo olarak gör" sayfası için gün sonu kapanışları
/// (Premium, 2026-11-10).
///
/// ## Kaynak: grafiğin elindeki seri, yeni istek yok
/// Tablo, grafikte ZATEN çizilen seçili dönemin serisinden kurulur
/// (`HistoryService` → ekran). Ayrı bir "günlük kapanış" çağrısı yapılsaydı
/// tablo ile grafik aynı gün için iki sayı yazabilirdi (fiyat kaynağı
/// sözleşmesi madde 1: seriye yalnız `fiyat_kaynagi.dart` karar verir) ve
/// her açılış bir ağ isteği olurdu.
///
/// ## Uydurma satır yok
/// Bir takvim gününün kapanışı o günün serideki SON noktasıdır. Seride
/// nokta olmayan gün (hafta sonu, tatil, haftalık çözünürlükteki 5Y'nin ara
/// günleri) satıra girmez; ara değer üretilmez, önceki gün tekrarlanmaz.
/// Bu yüzden "değişim" takvimde bir önceki güne değil, bir önceki SATIRA
/// (bir önceki kapanışa) göredir; sayfanın dipnotu bunu söyler.
library;

/// Tablonun bir satırı. [degisimPct] önceki kapanışa göre yüzde; önceki
/// kapanış yoksa (dönemin ilk günü) ya da sıfır/negatifse `null`.
class GunlukKapanis {
  const GunlukKapanis({
    required this.gun,
    required this.kapanis,
    required this.degisimPct,
  });

  /// Yerel takvim günü (saat 00:00).
  final DateTime gun;
  final double kapanis;
  final double? degisimPct;
}

/// Tablonun en fazla satır sayısı. 60 gün ≈ üç ay işlem günü: kısa
/// dönemlerin tamamı, 1Y/5Y'nin en yeni kısmı sığar. Daha uzun liste
/// telefonda okunmaz; uzun geçmiş için grafiğin kendisi var.
const gecmisFiyatlarAzamiSatir = 60;

/// [seri] (epoch ms → fiyat) → gün sonu kapanışları, EN YENİ ÜSTTE, en fazla
/// [azami] satır. Saf.
///
/// Değişim tam listede hesaplanır, sonra kesilir: 60. satırın da (seride
/// varsa) bir önceki kapanışı vardır, "—" yalnız dönemin gerçek ilk
/// gününde çıkar. Sonlu olmayan ya da sıfır/negatif fiyat atlanır.
List<GunlukKapanis> gunlukKapanislar(
  Map<int, double> seri, {
  int azami = gecmisFiyatlarAzamiSatir,
}) {
  if (seri.isEmpty || azami <= 0) return const [];
  final anahtarlar = seri.keys.toList()..sort();
  // Gün → (en geç zaman damgası, fiyat). Sıralı gezildiği için son yazan
  // o günün son noktasıdır.
  final gunSonu = <DateTime, double>{};
  for (final ms in anahtarlar) {
    final v = seri[ms]!;
    if (!v.isFinite || v <= 0) continue;
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    gunSonu[DateTime(t.year, t.month, t.day)] = v;
  }
  final gunler = gunSonu.keys.toList()..sort();
  final satirlar = <GunlukKapanis>[];
  double? onceki;
  for (final g in gunler) {
    final k = gunSonu[g]!;
    satirlar.add(GunlukKapanis(
      gun: g,
      kapanis: k,
      degisimPct: onceki == null ? null : (k / onceki - 1) * 100,
    ));
    onceki = k;
  }
  final yeniUstte = satirlar.reversed.toList();
  return yeniUstte.length > azami ? yeniUstte.sublist(0, azami) : yeniUstte;
}
