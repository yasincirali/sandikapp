/// Takip listesinin sırası (Ar-Ge 2026-10-24 12:45 #1, kabul 13:15 #2).
///
/// ## Neden
/// Liste her zaman seçili dönemin değişimine göre diziliyordu: fiyatlar her
/// tazelendiğinde satırlar yer değiştiriyor, kullanıcı doları her seferinde
/// arıyordu; en çok baktığı varlığı en üste koyamıyordu. Artık üç seçenek
/// var: "Benim sıram" (varsayılan, uzun basıp sürükle), "En çok yükselen"
/// (eski davranış birebir), "En çok düşen".
///
/// ## Karar kuralları
/// - **İlk açılış kayıpsız.** Kayıtlı sıra yoksa "benim sıram" bugünkü
///   sıradan (değişime göre azalan) başlar ve o an kaydedilir; kullanıcı
///   alıştığı listeyi görür, ama liste artık zıplamaz.
/// - **Yeni eklenen sona** (gelen değişim sırasıyla), **silinen düşer.**
/// - **Boş liste kaydı silmez.** Sağlayıcı ağ hatasında da boş liste döner
///   (`WatchlistNotifier.build`); boş listeyle budamak kullanıcının sırasını
///   bir hata yüzünden sıfırlardı. Boşken kayıt olduğu gibi kalır.
/// - **Fiyatsız satır** yükselen/düşen sıralamada dipte; benim sıramda
///   kullanıcının koyduğu yerde.
///
/// Sıra yalnız telefonda (`shared_preferences`, kimlik listesi); sunucu ve
/// şema değişmez. Saf: Flutter, ağ, tercih yok.
library;

import '../models/watchlist_item.dart';

/// Takip listesi sıralama seçimi. Sıra (index) tercihte saklanır: yeni
/// değer SONA eklenir, araya girmez.
enum TakipSiralama { benim, yukselen, dusen }

/// Tercihteki tamsayı → seçim; tanınmayan değer varsayılana düşer.
TakipSiralama takipSiralamaOf(int i) =>
    i >= 0 && i < TakipSiralama.values.length
        ? TakipSiralama.values[i]
        : TakipSiralama.benim;

/// Seçili dönemin değişimine göre sıralı kopya. Fiyatsızlar her iki yönde de
/// dipte (eski kuralda `-999` ile azalan sıranın sonundaydılar). Eşitlikte
/// gelen sıra korunur (kararlı).
List<WatchlistItem> degisimeGoreSirala(
  List<WatchlistItem> items, {
  bool azalan = true,
}) {
  final sirali = [
    for (var i = 0; i < items.length; i++) (i, items[i]),
  ];
  sirali.sort((a, b) {
    final pa = a.$2.periodChangePct;
    final pb = b.$2.periodChangePct;
    if (pa == null || pb == null) {
      if (pa == null && pb == null) return a.$1.compareTo(b.$1);
      return pa == null ? 1 : -1;
    }
    final c = azalan ? pb.compareTo(pa) : pa.compareTo(pb);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in sirali) e.$2];
}

/// Ekranda gösterilecek liste ve kaydedilmesi gereken "benim sıram".
class TakipSiraSonucu {
  const TakipSiraSonucu({required this.liste, required this.sira});

  /// Seçili sıralamaya göre dizilmiş satırlar.
  final List<WatchlistItem> liste;

  /// Güncel "benim sıram" (kimlikler). Kayıtlıdan farklıysa kaydedilir;
  /// seçim yükselen/düşen olsa da hesaplanır ki geri dönüldüğünde yeni
  /// eklenen sonda dursun.
  final List<String> sira;
}

/// [items] (sağlayıcının listesi), [mod] ve [kayitliSira] (null = hiç
/// kaydedilmedi) → gösterilecek liste + güncel sıra.
TakipSiraSonucu takipSirala(
  List<WatchlistItem> items, {
  required TakipSiralama mod,
  required List<String>? kayitliSira,
}) {
  final degisime = degisimeGoreSirala(items);
  final List<String> sira;
  if (items.isEmpty) {
    sira = kayitliSira ?? const [];
  } else if (kayitliSira == null) {
    sira = [for (final w in degisime) w.id];
  } else {
    final mevcut = {for (final w in items) w.id};
    final bilinen = {...kayitliSira};
    sira = [
      for (final id in kayitliSira)
        if (mevcut.contains(id)) id,
      for (final w in degisime)
        if (!bilinen.contains(w.id)) w.id,
    ];
  }

  final liste = switch (mod) {
    TakipSiralama.yukselen => degisime,
    TakipSiralama.dusen => degisimeGoreSirala(items, azalan: false),
    TakipSiralama.benim => () {
        final kimlikle = {for (final w in items) w.id: w};
        return [
          for (final id in sira)
            if (kimlikle[id] != null) kimlikle[id]!,
        ];
      }(),
  };
  return TakipSiraSonucu(liste: liste, sira: sira);
}

/// [sira]da [eski] konumdaki kimliği [yeni] konuma taşır. [yeni], öğe
/// çıkarıldıktan SONRAKİ hedef konumdur (0..uzunluk-1); sınır dışı değer
/// kırpılır. Sürükleme (`onReorder`, kendi kuralıyla düzeltilerek) ve
/// erişilebilirlik eylemleri ("yukarı taşı" = eski-1, "aşağı taşı" = eski+1)
/// aynı fonksiyondan geçer.
List<String> siraTasi(List<String> sira, int eski, int yeni) {
  if (eski < 0 || eski >= sira.length) return sira;
  final hedef = yeni.clamp(0, sira.length - 1);
  if (hedef == eski) return sira;
  final l = [...sira];
  final id = l.removeAt(eski);
  l.insert(hedef, id);
  return l;
}
