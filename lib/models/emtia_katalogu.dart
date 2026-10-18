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
/// Listede olmayan emtia için form "Diğer"de eski serbest giriş yolunu
/// korur; eski kayıtlar (listede olmayan sembol) düzenlemede o yolda açılır.
library;

/// Miktar birimi — kullanıcı miktar alanına neyi yazacağını seçimden önce
/// görsün (altın listesindeki gram/adet/ons rozetiyle aynı gerekçe).
enum EmtiaBirimi { ons, libre, varil, mmbtu }

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
  EmtiaSecenegi('PL=F', 'Platin', EmtiaBirimi.ons),
  EmtiaSecenegi('PA=F', 'Paladyum', EmtiaBirimi.ons),
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
