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

import '../utils/islem_isaretleri.dart';
import '../utils/tr_format.dart' show dayKey;
import 'asset.dart';

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
    gunSonu[dayKey(t)] = v;
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

/// Bir takvim gününde kullanıcının bu varlıktaki alım/satımı — tablo
/// satırındaki "Alış · 12 lot" etiketi (Ar-Ge 15 Kas #1).
///
/// [ornek] o günün bir lotu: birim ("lot", "pay", "gr") ve miktar biçimi
/// `Asset.miktarMetni`'nden gelsin diye; ekran kendi birim kuralını kurmaz.
class GunIslemi {
  const GunIslemi({
    required this.alisMiktar,
    required this.satisMiktar,
    required this.ornek,
  });

  final double alisMiktar;
  final double satisMiktar;
  final Asset ornek;

  bool get alis => alisMiktar > 0;
  bool get satis => satisMiktar > 0;
}

/// [lotlar] → takvim günü (00:00) → o günün alım/satımı. Saf.
///
/// Hangi lotun işlem sayıldığı GRAFİĞİN işaretleriyle aynı kuraldan gelir
/// ([islemIsaretleri]: temettü, silinmiş lot, birim fiyatı olmayan lot
/// işaret üretmez) — grafikte noktası olmayan gün tabloda etiket almasın.
/// Eksen başı epoch: tablo tarihle eşleştirir, X ekseni kullanılmaz; gün
/// lotun KENDİ tarihidir (işaretin eksene yaslanmış x'i değil).
Map<DateTime, GunIslemi> islemGunleri(List<Asset> lotlar) {
  if (lotlar.isEmpty) return const {};
  final isaretler = islemIsaretleri(
    lotlar: lotlar,
    eksenBasi: DateTime.fromMillisecondsSinceEpoch(0),
    ilkX: 0,
    sonX: double.infinity,
  );
  final out = <DateTime, GunIslemi>{};
  for (final m in isaretler) {
    final gun = dayKey(m.lot.addedDate.toLocal());
    final eski = out[gun];
    final q = m.lot.quantity.abs();
    out[gun] = GunIslemi(
      alisMiktar: (eski?.alisMiktar ?? 0) + (m.satis ? 0 : q),
      satisMiktar: (eski?.satisMiktar ?? 0) + (m.satis ? q : 0),
      ornek: eski?.ornek ?? m.lot,
    );
  }
  return out;
}

/// Sayfa başındaki "Son alışın 3 Eki · o günden beri +%8,4" (Ar-Ge 15 Kas
/// #1). [satirlar] TAM liste, en yeni üstte ([gunlukKapanislar], kesilmemiş);
/// [islemler] [islemGunleri]. Saf.
///
/// Uydurma yok: son alış günü serinin bir kapanış satırı değilse (dönemden
/// önce, hafta sonu, tatil) yakın bir günün fiyatı ödünç alınmaz, `null`.
/// Daha eski bir alışa da düşülmez — "son alışın" gerçekten son alış.
/// Son alış bugünün (en yeni satırın) günüyse ölçülecek bir "o günden beri"
/// yok, `null`.
({DateTime gun, double pct})? sonAlistanBeri(
  List<GunlukKapanis> satirlar,
  Map<DateTime, GunIslemi> islemler,
) {
  if (satirlar.length < 2) return null;
  DateTime? son;
  islemler.forEach((gun, i) {
    if (i.alis && (son == null || gun.isAfter(son!))) son = gun;
  });
  final s = son;
  if (s == null || !s.isBefore(satirlar.first.gun)) return null;
  for (final r in satirlar) {
    if (r.gun == s) {
      return (gun: s, pct: (satirlar.first.kapanis / r.kapanis - 1) * 100);
    }
  }
  return null;
}

/// Ücretsiz kilit satırının yarım sonucu (Ar-Ge 15 Kas #3): dönemdeki
/// kapanış sayısı ve en yüksek kapanışın GÜNÜ — fiyatlar kilitli kalır.
/// [seri] grafiğin serisi; sayım 60 satırlık kesimden ÖNCE (dönemin hepsi).
/// En yüksek eşitse en yenisi. Kapanış yoksa `null` (eski metin). Saf.
({int sayi, DateTime enYuksekGun})? kilitOzeti(Map<int, double> seri) {
  final tum = gunlukKapanislar(seri, azami: 1 << 30);
  if (tum.isEmpty) return null;
  var enYuksek = tum.first; // en yeni üstte: eşitlikte yenisi kalır
  for (final r in tum) {
    if (r.kapanis > enYuksek.kapanis) enYuksek = r;
  }
  return (sayi: tum.length, enYuksekGun: enYuksek.gun);
}
