import '../utils/tr_format.dart';
import '../utils/tr_katla.dart';
import 'asset.dart';
import 'position.dart';

/// Varlık Ekle seçicilerinin (BIST, ABD, TEFAS) ortak süzgeci.
///
/// 2026-11-07 (Ar-Ge 0200 madde 1): üç seçici ayrı ayrı `toLowerCase()` ile
/// süzüyordu. Dart'ta `'ALTIN'.toLowerCase()` = `altin`; Türkçe klavyede
/// "altın" yazan altın fonlarını, "katılım" yazan katılım fonlarını, "is
/// portfoy" yazan "İŞ PORTFÖY"ü bulamıyordu. Genel arama bunu `trKatla` ile
/// çözmüştü; aynı uygulamada iki arama farklı sonuç vermesin diye seçiciler de
/// aynı katlamayı kullanır (sorguya da ada/koda da).
///
/// Sıra: kod tam eşit > kod ile başlar > ad ya da kod içerir. Aynı sıradaki
/// öğeler gelen sırasını korur (çağıran adla sıralı verir): "TTE" yazan TTE'yi
/// alfabenin ortasında aramaz, ilk satırda bulur.
///
/// [kodSorgusu] sorgunun kod alanına özgü biçimi (ABD: "brk.b" → `BRK-B`);
/// verilmezse sorgunun kendisi.
List<T> seciciSuz<T>(
  Iterable<T> hepsi,
  String sorgu, {
  required String Function(T) kod,
  required String Function(T) ad,
  String Function(String)? kodSorgusu,
}) {
  final ham = sorgu.trim();
  if (ham.isEmpty) return hepsi.toList();
  final q = trKatla(ham);
  final kq = trKatla(kodSorgusu?.call(ham) ?? ham);
  final derece = <(int, int, T)>[];
  var i = 0;
  for (final o in hepsi) {
    final k = trKatla(kod(o));
    final int? d = k == kq
        ? 0
        : k.startsWith(kq)
            ? 1
            : (trKatla(ad(o)).contains(q) || k.contains(kq))
                ? 2
                : null;
    if (d != null) derece.add((d, i, o));
    i++;
  }
  // `List.sort` kararlı değil; gelen sıra ikinci anahtar.
  derece.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  return [for (final d in derece) d.$3];
}

/// Portföyde BUGÜN tutulan, [kod]'un tanıdığı türdeki varlıkların kodları;
/// pozisyon değerine göre büyükten küçüğe, en çok [adet] tane.
///
/// Varlık Ekle seçicisinde boş aramada "Portföyündekiler" bölümü bunu okur
/// (Ar-Ge 0200 madde 2: kullanıcının çoğu aynı fona ek alım yapıyor). Bugünkü
/// mülkiyet sorusu: `aktifLotlar` (CLAUDE.md "Kapanmış pozisyon"); satılmış
/// fon listede kalmaz. Sahiplik sınırı `lotlarSahibeGore` ("Birlikte"
/// kapsamında ortağın lotu benimkiyle aynı pozisyon sayılmasın), kural
/// `altinKisayollari` ile aynı. [kod] türü tutmayan lotta `null` döner.
List<String> portfoydekiKodlar(
  Iterable<Asset> assets,
  String? Function(Asset) kod, {
  int adet = 5,
}) {
  final pozisyonlar = aggregatePositionsByOwner(
      [for (final l in lotlarSahibeGore(assets)) aktifLotlar(l)])
    ..sort((a, b) => b.totalValue.compareTo(a.totalValue));
  final sonuc = <String>[];
  for (final p in pozisyonlar) {
    final k = kod(p.representative);
    if (k != null && k.isNotEmpty && !sonuc.contains(k)) sonuc.add(k);
    if (sonuc.length >= adet) break;
  }
  return sonuc;
}

/// Boş aramada listenin başına çıkan "Portföyündekiler" öğeleri: [kodlar]
/// sırasıyla, listede bulunanlar. Yazmaya başlayınca bölüm kalkar (boş liste)
/// — arama sonucu tek liste olmalı, aynı fon iki yerde görünmesin.
List<T> portfoyBolumu<T>(
  Iterable<T> hepsi,
  List<String> kodlar,
  String sorgu, {
  required String Function(T) kod,
}) {
  if (sorgu.trim().isNotEmpty || kodlar.isEmpty) return const [];
  final harita = {for (final o in hepsi) kod(o): o};
  return [
    for (final k in kodlar)
      if (harita[k] case final o?) o,
  ];
}

/// Fon satırının alt metni: "İş Portföy · 1 yıl +%42,1".
///
/// Ar-Ge 0200 madde 3: TEFAS adları uzun ve birbirine benziyor; kurucu ve
/// 1 yıllık getiri doğru fonu seçtirir. Uydurma sayı yok: getiri bilinmiyorsa
/// yalnız kurucu; ikisi de yoksa `null` (çağıran eski alt metne, fiyata,
/// düşer). İşaret metinde (`fmtPctIsaretli`), renk tek başına anlam taşımaz.
/// [yilEtiketi] l10n kalıbı ("1 yıl {pct}").
String? fonAltBasligi({
  required String kurucu,
  required double? getiri1y,
  required String Function(String yuzde) yilEtiketi,
}) {
  final k = kurucu.trim();
  final g = getiri1y == null || !getiri1y.isFinite
      ? null
      : yilEtiketi(fmtPctIsaretli(getiri1y, digits: 1));
  if (k.isEmpty) return g;
  return g == null ? k : '$k · $g';
}
