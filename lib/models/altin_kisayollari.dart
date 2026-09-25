import 'asset.dart';
import 'asset_categories.dart';
import 'asset_type.dart';
import 'position.dart';

/// Altın türü seçicisinin (Varlık Ekle → Altın) veri kuralları.
///
/// ## Neden (kullanıcı kararı 2026-09-25)
/// 16 altın türü tek çip ızgarasında ekranı dolduruyordu ("çok fazla çip
/// doldu"). Üç alternatif arasından seçilen düzen: hisse/fon seçicisiyle
/// aynı **seçim alanı** (tümü aramalı, gruplu alt sayfada) + altında
/// **5 kısayol çipi**. Kısayolların kuralı kullanıcının sözüyle:
/// "Eğer portföyünde varsa o tipler gösterilmeli, 5'e tamamlamak için de en
/// popülerlerden alınmalı." Hiç altını yoksa popüler beşli görünür.

/// Hiç altını olmayan kullanıcının göreceği kısayollar, kullanıcının verdiği
/// sırayla: "Çeyrek, gram, 22 ayar gram, yarım, tam". "Gram" = 24 ayar
/// (Türkiye'de "gram altın" denince kastedilen, bkz. [GoldSubCategory]).
const populerAltinTurleri = <GoldSubCategory>[
  GoldSubCategory.ceyrek,
  GoldSubCategory.gr24,
  GoldSubCategory.gr22,
  GoldSubCategory.yarim,
  GoldSubCategory.tam,
];

/// Alt sayfadaki gruplar. Kuyumcu dilindeki ayrım: gramla alınan ayarlar,
/// ziynet (düğün/takı) altınları, tarihî sikkeler ve uluslararası ons.
enum AltinGrubu { gram, ziynet, sikke, ons }

extension GoldSubCategoryGrup on GoldSubCategory {
  AltinGrubu get grup => switch (this) {
        GoldSubCategory.gr24 ||
        GoldSubCategory.gr22 ||
        GoldSubCategory.gr18 ||
        GoldSubCategory.gr14 ||
        GoldSubCategory.has =>
          AltinGrubu.gram,
        GoldSubCategory.ceyrek ||
        GoldSubCategory.yarim ||
        GoldSubCategory.tam ||
        GoldSubCategory.ikibucuk ||
        GoldSubCategory.gremse ||
        GoldSubCategory.besli =>
          AltinGrubu.ziynet,
        GoldSubCategory.cumhuriyet ||
        GoldSubCategory.ata ||
        GoldSubCategory.resat ||
        GoldSubCategory.hamit =>
          AltinGrubu.sikke,
        GoldSubCategory.ons => AltinGrubu.ons,
      };
}

/// Bir lot'un hangi altın türü olduğu. `null` → altın değil / tanınmıyor.
///
/// Önce **ticker**'a bakılır: `subCategory` alanı kaynağa göre farklı
/// yazılıyor — ekleme formu `label` ('Çeyrek Altın'), CSV içe aktarma enum
/// adı ('ceyrek') yazar. Ticker ise her iki yolda da [goldTickerMap]'ten
/// gelir ve tektir. Ticker tanınmazsa (eski/elle girilmiş kayıt) iki
/// `subCategory` biçimi de denenir.
GoldSubCategory? altinTuru(Asset a) {
  if (a.type != AssetType.altin) return null;
  final t = a.ticker.trim().toUpperCase();
  for (final g in GoldSubCategory.values) {
    if (goldTickerMap[g.label]?.toUpperCase() == t) return g;
  }
  final s = a.subCategory?.trim();
  if (s == null || s.isEmpty) return null;
  for (final g in GoldSubCategory.values) {
    if (g.label == s || g.name == s) return g;
  }
  return null;
}

/// Seçim alanının altındaki kısayol çipleri.
///
/// 1. Kullanıcının BUGÜN tuttuğu altın türleri (`aktifLotlar`: tamamen
///    satılmış tür kısayolda kalmaz), pozisyon değerine göre büyükten
///    küçüğe — en çok tutulan en başta.
/// 2. [adet]'e tamamlamak için [populerAltinTurleri] sırasıyla, tekrar
///    etmeden.
///
/// Sahiplik sınırı `lotlarSahibeGore` ile korunur ("Birlikte" kapsamında
/// ortağın lot'u benimkiyle toplanıp yanlış pozisyon kurmasın).
List<GoldSubCategory> altinKisayollari(
  Iterable<Asset> assets, {
  int adet = 5,
}) {
  final pozisyonlar = aggregatePositionsByOwner(
      [for (final l in lotlarSahibeGore(assets)) aktifLotlar(l)])
    ..sort((a, b) => b.totalValue.compareTo(a.totalValue));

  final sonuc = <GoldSubCategory>[];
  for (final p in pozisyonlar) {
    final g = altinTuru(p.representative);
    if (g != null && !sonuc.contains(g)) sonuc.add(g);
  }
  for (final g in populerAltinTurleri) {
    if (sonuc.length >= adet) break;
    if (!sonuc.contains(g)) sonuc.add(g);
  }
  return sonuc.take(adet).toList(growable: false);
}

/// Alt sayfadaki arama: ad ve açıklamada, aksan ve büyük/küçük harf
/// duyarsız ("resat" → Reşat, "IKIBUCUK" → İkibuçuk). Türk klavyesi olmadan
/// arayan da bulsun. Boş sorgu tüm türleri enum (ekran) sırasıyla döner.
List<GoldSubCategory> altinTurleriniAra(String sorgu) {
  final q = _sade(sorgu.trim());
  return [
    for (final g in GoldSubCategory.values)
      if (q.isEmpty || _sade('${g.label} ${g.description}').contains(q)) g,
  ];
}

String _sade(String s) {
  const esle = {
    'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
    'Ç': 'c', 'Ğ': 'g', 'I': 'i', 'İ': 'i', 'Ö': 'o', 'Ş': 's', 'Ü': 'u',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(esle[ch] ?? ch.toLowerCase());
  }
  return b.toString();
}
