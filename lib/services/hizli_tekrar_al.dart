import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import 'islem_notu.dart';

/// "Bunu tekrar al" ve Hızlı Al'ın "Son alımın" çipi — karar noktası.
///
/// ## Neden (Ar-Ge 8 Kas #1, müşteri YAP, ücretsiz)
/// Her ay aynı fona ya da altına aynı miktarı koyan kullanıcı her seferinde
/// varlığı bulup miktarı yeniden yazıyordu. İki kısa yol aynı bilgiden
/// beslenir: hareket notu sayfasındaki "Bunu tekrar al" o hareketin
/// miktarını, Hızlı Al'daki çip o varlığın SON alımının miktarını getirir.
/// Kayıt mevcut Hızlı Al yolundan gider (`addAsset`); sunucu değişmez.
/// Düzenli alım planı gelince aynı yolu kullanır.
///
/// Varlık Ekle'nin "Tekrar al" çipleriyle (`models/tekrar_al.dart`, 31 Eki)
/// akrabadır ama ayrı yüzeydir: orada çip VARLIĞI seçer ve miktar forma
/// yazılmaz; burada varlık zaten seçili (pozisyon), çip ve satır yalnız
/// MİKTARI doldurur. Son alım kuralı aynı: kendi, silinmemiş alış, en yeni.
///
/// Saf fonksiyonlar: ekran ve diyalog karar vermez, buraya sorar
/// (`hizli_tekrar_al_test`).

/// Bu hareket "Bunu tekrar al" satırını gösterir mi?
///
/// Sahiplik testi not düzenlemeyle AYNI ([islemNotuDuzenlenebilir]):
/// kaydın sahibi, silinmemiş, mezar taşı değil. Ortağın hareketine alım
/// yazılamaz (RLS) ve "onun alımını ben tekrar edeyim" ayrı bir sorudur.
/// Üstüne yalnız ALIŞ: satışı ya da temettüyü "tekrar al" anlamsız.
bool tekrarAlinabilir(Asset islem, {required String? benimId}) =>
    islem.isBuy && islemNotuDuzenlenebilir(islem, benimId: benimId);

/// Bir alışın Hızlı Al miktar alanına yazılacak değeri.
///
/// Alan çoğu türde miktardır (pay/lot/gr/adet). Mevduatta alan TL
/// TUTARIDIR (`mevduatTutarIslemi`): lot'un payı değil, o gün yatırılan
/// tutar (pay × birim değer, kuruşa yuvarlı) yazılır. Sıfır/negatif ya da
/// sayı olmayan miktar `null` — çip ya da önden doldurma uydurulmaz.
double? alimAlanDegeri(Asset alim) {
  if (!alim.isBuy) return null;
  final v = alim.type == AssetType.mevduat
      ? (alim.quantity * alim.purchasePrice * 100).round() / 100
      : alim.quantity;
  if (!v.isFinite || v <= 0) return null;
  return v;
}

/// [pozisyon]'un ham defterdeki SON alışı (işlem tarihine göre).
///
/// Ham defter kullanılır, `aktifLotlar` değil: soru geçmişi soruyor
/// ("en son ne kadar aldım"). Silinen alış ve mezar taşı sayılmaz
/// (`isActive`). Satış ve temettü alış değildir. Eşleşme pozisyon
/// anahtarıyla ([positionKey]) — Portföy'ün aynı varlığı birleştirdiği
/// kural; isim ya da sembol yazımı farklı eski lot'lar da aynı pozisyona
/// düşer. Alış yoksa `null` → çip yok, standart çipler aynen.
Asset? sonAlim(Iterable<Asset> defter, Asset pozisyon) {
  final anahtar = positionKey(pozisyon);
  Asset? son;
  for (final a in defter) {
    if (!a.isActive || !a.isBuy) continue;
    if (alimAlanDegeri(a) == null) continue;
    if (positionKey(a) != anahtar) continue;
    if (son == null || a.addedDate.isAfter(son.addedDate)) son = a;
  }
  return son;
}

/// "Bunu tekrar al" hedefi: Hızlı Al'ın açılacağı pozisyon ve önden
/// doldurulacak miktar. `null` → satır çizilmez.
///
/// Pozisyon kullanıcının kendi defterinden ve AÇIK olmalı
/// ([pozisyonGorunumu], `aktifLotlar` ile aynı süzgeç): Hızlı Al başka hiçbir
/// yüzeyde kapanmış pozisyona açılmaz ve kapanmış pozisyonun "bugünkü
/// fiyatı" fiyat turunda tazelenmez — eski fiyatla önden doldurmak uydurma
/// fiyat olurdu. Kapanmış varlığı yeniden almak Varlık Ekle'nin işi.
({Asset pozisyon, double miktar})? tekrarAlHedefi(
  Iterable<Asset> benimDefterim,
  Asset islem, {
  required String? benimId,
}) {
  if (!tekrarAlinabilir(islem, benimId: benimId)) return null;
  final miktar = alimAlanDegeri(islem);
  if (miktar == null) return null;
  final g = pozisyonGorunumu(benimDefterim, islem);
  if (g == null) return null;
  return (pozisyon: g.asset, miktar: miktar);
}
