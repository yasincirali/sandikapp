/// Yatay tam ekran grafikte kullanıcının çizdiği çizgi ve kutular.
///
/// ## Neden (yasin, 2026-10-23)
/// *"Yan döndürünce grafiği izlenebilir hale getirebilir miyiz … trading
/// view'i birebir örnek alabilirsin … çizgi çektirme özelliğini de ondan
/// alabiliriz."* Ardından benchmark kararı ("önerini yap"): çizim araçları
/// ve telefonda saklama ÜCRETSİZ — TradingView, Investing ve Midas bunu
/// ücretsiz veriyor; kilitlemek kullanıcıyı onlara gönderirdi. Premium'a
/// ayrılanlar (çizgi alarmı, cihazlar arası eşitleme) sonraki adım.
///
/// ## Neden zaman + fiyat
/// Nokta mum İNDEKSİYLE değil, ZAMANLA ([CizimNoktasi.t], epoch ms)
/// saklanır. TradingView'deki gibi çizim aralık değişince (günlük → 4 saat)
/// aynı yerde kalır; indeks saklansaydı her aralıkta başka bir tarihe
/// kayardı. Fiyat ekrandaki ölçekle aynı birimdedir (TL ya da endeks puanı).
library;

/// Çizim araçları — TradingView mobilinin en çok kullanılan beşi.
enum CizimTuru {
  /// İki nokta arası doğru parçası.
  trend,

  /// İlk noktadan ikinciye doğru, grafiğin sağına uzayan ışın.
  isin,

  /// Tüm genişlikte yatay çizgi (destek/direnç).
  yatay,

  /// Noktadan sağa uzayan yatay ışın.
  yatayIsin,

  /// İki köşeyle dikdörtgen (bölge).
  kutu;

  /// Tek noktayla biten tür mü (yatay çizgi ve yatay ışın)?
  bool get tekNokta => this == yatay || this == yatayIsin;

  static CizimTuru? adla(String? ad) {
    for (final t in values) {
      if (t.name == ad) return t;
    }
    return null;
  }
}

/// Grafikte bir nokta: zaman (epoch ms) ve fiyat.
class CizimNoktasi {
  const CizimNoktasi(this.t, this.p);
  final int t;
  final double p;

  Map<String, Object> toJson() => {'t': t, 'p': p};

  static CizimNoktasi? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = j['t'], p = j['p'];
    if (t is! num || p is! num) return null;
    final pd = p.toDouble();
    if (!pd.isFinite) return null;
    return CizimNoktasi(t.toInt(), pd);
  }

  @override
  bool operator ==(Object other) =>
      other is CizimNoktasi && other.t == t && other.p == p;

  @override
  int get hashCode => Object.hash(t, p);
}

class GrafikCizimi {
  const GrafikCizimi({required this.tur, required this.a, this.b});

  final CizimTuru tur;
  final CizimNoktasi a;

  /// İkinci nokta; tek noktalı türlerde (yatay, yatay ışın) null.
  final CizimNoktasi? b;

  GrafikCizimi copyWith({CizimNoktasi? a, CizimNoktasi? b}) =>
      GrafikCizimi(tur: tur, a: a ?? this.a, b: b ?? this.b);

  Map<String, Object> toJson() => {
        'tur': tur.name,
        'a': a.toJson(),
        if (b != null) 'b': b!.toJson(),
      };

  /// Bozuk ya da tanınmayan kayıt null döner, listeden düşer: eski ya da
  /// elle bozulmuş bir tercih grafiği açılmaz hâle getirmez.
  static GrafikCizimi? fromJson(Object? j) {
    if (j is! Map) return null;
    final tur = CizimTuru.adla(j['tur'] as String?);
    final a = CizimNoktasi.fromJson(j['a']);
    if (tur == null || a == null) return null;
    final b = CizimNoktasi.fromJson(j['b']);
    if (!tur.tekNokta && b == null) return null;
    return GrafikCizimi(tur: tur, a: a, b: tur.tekNokta ? null : b);
  }

  @override
  bool operator ==(Object other) =>
      other is GrafikCizimi &&
      other.tur == tur &&
      other.a == a &&
      other.b == b;

  @override
  int get hashCode => Object.hash(tur, a, b);
}
