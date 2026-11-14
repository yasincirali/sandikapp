import 'dart:convert';

import 'symbol_search_service.dart' show PortfolioSeries, SymbolHit;

/// Karşılaştır'ın hatırlanan kıyas seti (Ar-Ge 14 Kas 2026 22:03, YAP 2).
///
/// Premium'un bu ekrandaki değeri beş seridir; set her açılışta sıfırlandığı
/// için kullanıcı aynı beşliyi her seferinde yeniden kuruyordu. Son seçili
/// seriler ve SIRALARI (renk ataması sıraya bağlı) cihazda saklanır.
///
/// Saf fonksiyonlar: ekran yalnızca okur/yazar, karar burada ve testli
/// (`test/kiyas_seti_test.dart`).

/// Seçili serileri tercih listesine çevirir: her seri bir JSON nesnesi
/// `{"t": sembol, "n": ad, "s": köken}`.
///
/// Neden ad ve köken de saklanıyor: arama sonucunun eşzamanlı bir kataloğu
/// yok (`SymbolSearchService.search` ağa gider). Yalnız sembol saklansaydı
/// açılışta her seri için arama yapmak ya da satırı adsız göstermek
/// gerekirdi. Sembol kimliktir; ad/köken yalnız görüntü içindir ve satır
/// zaten seriyi sembolden çeker.
List<String> kiyasSetiKodla(Iterable<SymbolHit> seriler) => [
      for (final h in seriler)
        jsonEncode({'t': h.ticker, 'n': h.name, 's': h.source}),
    ];

/// Kayıtlı listeyi seriye geri çözer; çözülemeyeni SESSİZCE atar.
///
/// Atılanlar: bozuk kayıt, boş sembol, tekrar eden sembol, artık ortak
/// olmayan kişinin portföyü ([ortakIdleri] içinde yok) ve hiç ortak yokken
/// "Birlikte" (tek başına kullanan için kendi portföyüyle aynı şey; arama
/// sayfası da o zaman sunmuyor). Piyasa sembolü burada doğrulanmaz: verisi
/// gelmezse satır bugünkü gibi "veri yok" der, kayıt silinmez.
List<SymbolHit> kiyasSetiCoz(
  List<String>? kayit, {
  required Set<String> ortakIdleri,
}) {
  if (kayit == null) return const [];
  final out = <SymbolHit>[];
  for (final satir in kayit) {
    final Object? json;
    try {
      json = jsonDecode(satir);
    } on FormatException {
      continue;
    }
    if (json is! Map) continue;
    final t = json['t'];
    if (t is! String || t.isEmpty) continue;
    final pid = PortfolioSeries.partnerIdOf(t);
    if (pid != null && !ortakIdleri.contains(pid)) continue;
    if (t == PortfolioSeries.together && ortakIdleri.isEmpty) continue;
    final hit = SymbolHit(
      ticker: t,
      name: json['n'] is String ? json['n'] as String : t,
      source: json['s'] is String ? json['s'] as String : '',
    );
    if (out.contains(hit)) continue; // eşitlik sembolle
    out.add(hit);
  }
  return out;
}

/// Açılıştaki seri listesi: varlık sayfasından gelinmişse o varlık BAŞTA,
/// kayıtlı set sırasıyla arkasında; toplam [sinir]'e kırpılır (fazlası
/// sondan düşer — en eski eklenen öne yakın, kullanıcının çekirdek kıyası).
List<SymbolHit> kiyasSetiAcilisi({
  SymbolHit? baslangic,
  required List<SymbolHit> kayitli,
  required int sinir,
}) {
  final out = <SymbolHit>[
    if (baslangic != null) baslangic,
    for (final h in kayitli)
      if (h != baslangic) h,
  ];
  return out.length > sinir ? out.sublist(0, sinir) : out;
}
