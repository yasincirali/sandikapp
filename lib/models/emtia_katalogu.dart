/// Seçilebilir emtialar — Varlık Ekle'nin emtia listesi ve sembol aramasının
/// TEK kaynağı (2026-10-18).
///
/// yasin (18 Eki): "emtia seçenekleri listelense, free text yerine". Eskiden
/// emtia formu serbest ad + Yahoo sembolü (`CL=F`) istiyordu; kullanıcı
/// sembolü bilmiyor, "petrol" yazıp sembolsüz (fiyatsız) lot kaydediyordu.
///
/// Liste bilerek kısa ve yalnız USD/birim kote vadeliler: tahıl ve yumuşak
/// emtialar (`ZW=F`, `KC=F`, `SB=F`) Yahoo'da **sent** kote — USD sanılıp
/// 100 kat büyük değer yazılırdı (fiyat kaynağı kuralı 2: ölçek aynı olmalı).
/// Ons altın burada yok: altın türünün kendi ons seçeneği var, iki yoldan
/// eklenen aynı varlık portföyde iki ayrı satır olurdu.
///
/// Ons kote metaller (gümüş, platin, paladyum) gram olarak da eklenir
/// (yasin 18 Eki: "ons olarak eklenmiş tüm ... emtialar gram ons
/// seçenekleriyle eklenebilmeli"). Gram varlık AYRI semboldür
/// (`GRAM:SI=F`): altındaki gram/ons ayrımıyla aynı gerekçe, ons ve gram
/// lotları aynı pozisyonda toplanırsa miktarlar karışırdı. Fiyatı ons
/// kotasyonunun 31,1035'e bölümüdür; bölmeyi fiyat katmanı yapar
/// (`PriceService`, sunucuda `_shared/emtia_gram.ts`), ekran yapmaz.
///
/// Listede olmayan emtia için form "Diğer"de eski serbest giriş yolunu
/// korur; eski kayıtlar (listede olmayan sembol) düzenlemede o yolda açılır.
library;

/// Miktar birimi — kullanıcı miktar alanına neyi yazacağını seçimden önce
/// görsün (altın listesindeki gram/adet/ons rozetiyle aynı gerekçe).
enum EmtiaBirimi { ons, gram, libre, varil, mmbtu }

class EmtiaSecenegi {
  const EmtiaSecenegi(this.ticker, this.ad, this.birim);

  /// Yahoo vadeli sembolü; fiyat ve seri `fiyat_kaynagi.dart`'ın emtia
  /// dalından (USD, Yahoo) gelir.
  final String ticker;

  /// Kayda yazılan ad; sembol aramasında da bu ad görünür (tek kaynak).
  /// Birim adda değil [birim]'de: çip "Gümüş · ons" der, ad sade kalır.
  final String ad;
  final EmtiaBirimi birim;
}

const emtiaKatalogu = <EmtiaSecenegi>[
  EmtiaSecenegi('SI=F', 'Gümüş', EmtiaBirimi.ons),
  EmtiaSecenegi('GRAM:SI=F', 'Gram Gümüş', EmtiaBirimi.gram),
  EmtiaSecenegi('PL=F', 'Platin', EmtiaBirimi.ons),
  EmtiaSecenegi('GRAM:PL=F', 'Gram Platin', EmtiaBirimi.gram),
  EmtiaSecenegi('PA=F', 'Paladyum', EmtiaBirimi.ons),
  EmtiaSecenegi('GRAM:PA=F', 'Gram Paladyum', EmtiaBirimi.gram),
  EmtiaSecenegi('HG=F', 'Bakır', EmtiaBirimi.libre),
  EmtiaSecenegi('BZ=F', 'Petrol (Brent)', EmtiaBirimi.varil),
  EmtiaSecenegi('CL=F', 'Petrol (WTI)', EmtiaBirimi.varil),
  EmtiaSecenegi('NG=F', 'Doğalgaz', EmtiaBirimi.mmbtu),
];

/// Sembolün katalogdaki karşılığı (büyük/küçük harf duyarsız), yoksa null.
EmtiaSecenegi? emtiaSecenegi(String ticker) {
  final t = ticker.trim().toUpperCase();
  for (final e in emtiaKatalogu) {
    if (e.ticker == t) return e;
  }
  return null;
}

/// Gram emtia sembolünün öneki (`GRAM:SI=F`).
const emtiaGramOneki = 'GRAM:';

/// Gram emtia sembolünün ons kote taban sembolü (`GRAM:SI=F` → `SI=F`);
/// gram sembolü değilse null. Sunucu eşi `_shared/emtia_gram.ts`.
String? emtiaGramTabani(String sembol) {
  final s = sembol.trim().toUpperCase();
  if (!s.startsWith(emtiaGramOneki)) return null;
  final t = s.substring(emtiaGramOneki.length);
  return t.isEmpty ? null : t;
}

/// Kayıttaki `unit_type`: portföydeki miktar etiketi ("10 gr", "2 oz") ve
/// formdaki hazır miktarlar bundan okunur (`birimEtiketi`,
/// `quantityPresets`). Libre/varil/MMBtu 'piece' kalır: #207 öncesi kayıtlar
/// da öyle, etiket değişikliği bu turun konusu değil.
String emtiaUnitType(EmtiaBirimi b) => switch (b) {
      EmtiaBirimi.ons => 'ounce',
      EmtiaBirimi.gram => 'gram',
      _ => 'piece',
    };
