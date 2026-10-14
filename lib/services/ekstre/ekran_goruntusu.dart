import 'dart:math' as math;

import '../../utils/tr_katla.dart';
import '../bist_hisse_katalogu.dart';
import '../csv_import_service.dart';
import 'fon_adi.dart';
import 'tablo_anlama.dart' show sayiCoz;
import 'tablo_okuyucular.dart' show sayiMetni;

/// Ekran görüntüsünden adet ve ortalama maliyet — SAF, eklentisiz.
///
/// ## Neden (yasin, 2026-10-13)
/// "Bankalarda ekstrelerde varlıkların ortalama maliyetleri, alım zamanları
/// yazmıyor." Banka varlık ekstresi o günün fotoğrafıdır: adet var, maliyet
/// yok; içe aktarılan satır ekstre gününün fiyatını alır ve K/Z o günden
/// başlar. Oysa her banka ve aracı kurum uygulamasının portföy ekranı adedi
/// ve ortalama maliyeti zaten gösterir (Midas "Ort. Maliyet", banka fon
/// ekranı "Maliyet"). Kullanıcı o ekranın görüntüsünü seçer; metin cihazda
/// okunur (`ekran_okuyucu.dart`), burada anlaşılır. Muadil araştırması:
/// Greenline/Sharesight görüntüden içe aktarır, Türkiye'de hesap bağlama
/// (açık bankacılık, MKK) yatırım hesabına açık değil.
///
/// ## Düzenler
/// Kurum başına kod YOK. Üç düzen aynı kuralla çözülür:
/// 1. **Liste satırı:** `THYAO` altında `100 Adet · Ort. 250,00` — etiket ve
///    sayı aynı hücrede ([_hucreyiCoz]).
/// 2. **Kart:** fon adı, altında `Pay Adedi | Maliyet` etiketleri ve
///    hemen altlarında değerler — etiketin değeri sağında ya da altında.
/// 3. **Tablo:** üstte `Sembol  Adet  Ort. Maliyet` başlık satırı, her
///    satırda değerler — değer, başlığın sütununda.
///
/// Varlık "çapası" bilinen bir koddur (BIST kataloğu, TEFAS fon kodu) ya da
/// TEFAS unvanına TEK eşleşen fon adıdır (`fonKoduBul`, tahmin yok). Çapa
/// bulunamayan değer hiçbir varlığa yazılmaz.
///
/// ## Uydurma yok
/// Etiketsiz sayı (güncel fiyat, değer) maliyet sayılmaz. Yalnız "Maliyet"
/// yazan etiket birim mi toplam mı belirsizdir: güncel değer de okunduysa
/// birim fiyata yakın olan seçilir, yoksa birim sayılır (portföy ekranları
/// çoğunlukla birim gösterir) ve önizleme kullanıcıya gösterir.
class OcrHucre {
  const OcrHucre(this.metin, this.sol, this.ust, this.sag, this.alt);

  final String metin;
  final double sol, ust, sag, alt;

  double get yukseklik => math.max(1, alt - ust);
  double get merkezX => (sol + sag) / 2;
  double get merkezY => (ust + alt) / 2;

  @override
  String toString() => 'OcrHucre($metin)';
}

/// Yerel OCR'ın bir satırı: kutusu ve kelimeleri (kelime kutuları sütunları
/// ayırır — OCR tablo satırını tek satır verebilir).
class OcrSatiri {
  const OcrSatiri(this.kutu, this.kelimeler);

  factory OcrSatiri.haritadan(Map<Object?, Object?> m) {
    OcrHucre kutu(Map<Object?, Object?> x) => OcrHucre(
          (x['t'] as String?) ?? '',
          (x['l'] as num?)?.toDouble() ?? 0,
          (x['u'] as num?)?.toDouble() ?? 0,
          (x['r'] as num?)?.toDouble() ?? 0,
          (x['b'] as num?)?.toDouble() ?? 0,
        );
    return OcrSatiri(kutu(m), [
      for (final k in (m['k'] as List?) ?? const [])
        if (k is Map) kutu(k),
    ]);
  }

  final OcrHucre kutu;
  final List<OcrHucre> kelimeler;
}

/// Satırları hücrelere böler: kelime arası boşluk satır yüksekliğinin
/// 0,8 katını aşarsa yeni hücre (PDF okuyucusunun eşiğiyle aynı fikir).
/// Kelime kutusu yoksa satır tek hücredir.
List<OcrHucre> ocrSatirlarindanHucreler(List<OcrSatiri> satirlar) {
  final out = <OcrHucre>[];
  for (final s in satirlar) {
    final k = [
      for (final w in s.kelimeler)
        if (w.metin.trim().isNotEmpty) w,
    ]..sort((a, b) => a.sol.compareTo(b.sol));
    if (k.isEmpty) {
      if (s.kutu.metin.trim().isNotEmpty) out.add(s.kutu);
      continue;
    }
    final h = s.kutu.yukseklik;
    var grup = <OcrHucre>[k.first];
    void kapat() {
      out.add(OcrHucre(
        grup.map((w) => w.metin.trim()).join(' '),
        grup.map((w) => w.sol).reduce(math.min),
        grup.map((w) => w.ust).reduce(math.min),
        grup.map((w) => w.sag).reduce(math.max),
        grup.map((w) => w.alt).reduce(math.max),
      ));
    }

    for (final w in k.skip(1)) {
      if (w.sol - grup.last.sag > h * 0.8) {
        kapat();
        grup = [w];
      } else {
        grup.add(w);
      }
    }
    kapat();
  }
  return out;
}

/// Görüntüden okunan bir varlık. [kod] yoksa [ad] TEFAS'ta tek fona
/// eşleşmeyen bir fon adıdır (içe aktarılmaz, önizleme "tanınmadı" der).
class EkranVarligi {
  const EkranVarligi({
    this.kod,
    this.ad,
    required this.tur,
    this.adet,
    this.maliyet,
  });

  final String? kod;
  final String? ad;

  /// `Hisse` ya da `Fon` (kanonik metnin `tur` hücresi).
  final String tur;
  final double? adet;

  /// Birim ortalama maliyet.
  final double? maliyet;

  EkranVarligi _doldur(EkranVarligi o) => EkranVarligi(
        kod: kod,
        ad: ad,
        tur: tur,
        adet: adet ?? o.adet,
        maliyet: maliyet ?? o.maliyet,
      );

  @override
  String toString() => 'EkranVarligi(${kod ?? ad}, $adet, $maliyet)';
}

enum _Rol { adet, maliyet, maliyetBelirsiz, toplamMaliyet, deger, fiyat, kz }

/// Etiket sözlüğü (katlanmış, noktalama boşluk). Uzun olan önce eşlenir:
/// "maliyet değeri" toplamdır, "maliyet" tek başına belirsiz, "alış fiyatı"
/// maliyettir ama "fiyat" güncel fiyattır.
const _sozluk = <_Rol, List<String>>{
  _Rol.toplamMaliyet: [
    'toplam maliyet', 'maliyet tutari', 'maliyet degeri', 'maliyet bedeli',
    'alis tutari', 'yatirilan tutar', 'yatirilan', 'total cost',
  ],
  _Rol.maliyet: [
    'ortalama alis fiyati', 'ort alis fiyati', 'ortalama maliyet',
    'ort maliyet', 'ort mlyt', 'ortalama alis', 'ort alis', 'alis fiyati',
    'maliyet fiyati', 'birim maliyet', 'ortalama fiyat', 'ort fiyat', 'ort',
    'mlyt', 'avg cost', 'average cost', 'avg price', 'average price',
  ],
  _Rol.maliyetBelirsiz: ['maliyet', 'cost'],
  _Rol.adet: [
    'pay adedi', 'pay sayisi', 'nominal miktar', 'nominal', 'adet', 'adedi',
    'miktar', 'lot', 'shares', 'quantity', 'qty', 'pay',
  ],
  _Rol.deger: [
    'guncel deger', 'piyasa degeri', 'toplam deger', 'portfoy degeri',
    'deger', 'tutar', 'market value', 'value',
  ],
  _Rol.fiyat: [
    'son fiyat', 'guncel fiyat', 'birim fiyat', 'anlik fiyat', 'fiyat',
    'price',
  ],
  _Rol.kz: ['kar zarar', 'k z', 'kar', 'zarar', 'getiri', 'p l', 'gain'],
};

final List<(_Rol, RegExp, int)> _desenler = () {
  final l = <(_Rol, RegExp, int)>[
    for (final e in _sozluk.entries)
      for (final d in e.value)
        (
          e.key,
          RegExp('(?<![a-z0-9])${d.split(' ').join(r'\s+')}(?![a-z0-9])'),
          d.length,
        ),
  ];
  l.sort((a, b) => b.$3.compareTo(a.$3));
  return l;
}();

/// Karakter karakter katlama (konumlar korunur): Türkçe harf → ASCII,
/// küçük harf, harf/rakam dışı → boşluk.
String _katla(String s) {
  final b = StringBuffer();
  for (final c in s.codeUnits) {
    final k = trKatla(String.fromCharCode(c));
    final h = k.isEmpty ? ' ' : k[0];
    b.write(RegExp('[a-z0-9]').hasMatch(h) ? h : ' ');
  }
  return b.toString();
}

final _sayiDeseni = RegExp(r'[-+−]?\d[\d.,]*');
final _harfRakam = RegExp(r'[0-9A-Za-zÇĞİÖŞÜçğıöşü]');

typedef _Etiket = ({_Rol rol, int bas, int son});
typedef _Sayi = ({double deger, int bas, int son});

({List<_Etiket> etiketler, List<_Sayi> sayilar}) _hucreyiCoz(String metin) {
  final k = _katla(metin);
  final etiketler = <_Etiket>[];
  final dolu = List.filled(k.length, false);
  for (final (rol, re, _) in _desenler) {
    for (final m in re.allMatches(k)) {
      if (dolu.sublist(m.start, m.end).any((x) => x)) continue;
      for (var i = m.start; i < m.end; i++) {
        dolu[i] = true;
      }
      etiketler.add((rol: rol, bas: m.start, son: m.end));
    }
  }
  etiketler.sort((a, b) => a.bas.compareTo(b.bas));
  final sayilar = <_Sayi>[];
  for (final m in _sayiDeseni.allMatches(metin)) {
    var son = m.end;
    while (son > m.start && ',.'.contains(metin[son - 1])) {
      son--;
    }
    final ham = metin.substring(m.start, son);
    // Kodun ya da kelimenin parçası (BIST100, TRMYK9…) sayı değil.
    if (m.start > 0 && _harfRakam.hasMatch(metin[m.start - 1])) continue;
    // Yüzde (getiri), tarih, saat: değer değil.
    final once = metin.substring(0, m.start).trimRight();
    final sonra = metin.substring(son).trimLeft();
    if (once.endsWith('%') || sonra.startsWith('%')) continue;
    if (sonra.startsWith(':') || RegExp(r'\d:$').hasMatch(once)) continue;
    if (RegExp(r'^\d{1,2}[./]\d{1,2}[./]\d{2,4}$').hasMatch(ham.replaceAll(RegExp(r'^[-+]'), ''))) {
      continue;
    }
    final v = sayiCoz(ham.replaceAll('−', '-'));
    if (v == null) continue;
    sayilar.add((deger: v, bas: m.start, son: son));
  }
  return (etiketler: etiketler, sayilar: sayilar);
}

class _Hucre {
  _Hucre(this.h)
      : cozum = _hucreyiCoz(h.metin);
  final OcrHucre h;
  final ({List<_Etiket> etiketler, List<_Sayi> sayilar}) cozum;
  int satir = 0;

  bool get etiketli => cozum.etiketler.isNotEmpty;
  bool get yalnizSayi => !etiketli && cozum.sayilar.isNotEmpty;
  bool get yalnizEtiket => etiketli && cozum.sayilar.isEmpty;
  bool kullanildi = false;
}

typedef _Capa = ({_Hucre hucre, String? kod, String? ad, String tur, int sonSatir});

/// Görüntünün hücrelerinden varlıklar. [fonlar]: TEFAS (kod, unvan) listesi;
/// boşsa fon kodları ve adları tanınmaz (yalnız BIST hisseleri).
List<EkranVarligi> ekranGoruntusunuAnla(
  List<OcrHucre> hucreler, {
  Iterable<({String kod, String unvan})> fonlar = const [],
}) {
  if (hucreler.isEmpty) return const [];
  final fonListesi = fonlar.toList();
  final fonKodlari = {for (final f in fonListesi) f.kod.trim().toUpperCase()};
  final hs = [for (final h in hucreler) _Hucre(h)]
    ..sort((a, b) => a.h.merkezY.compareTo(b.h.merkezY));
  final yukseklikler = [for (final h in hs) h.h.yukseklik]..sort();
  final medH = yukseklikler[yukseklikler.length ~/ 2];

  // Satırlar: dikey merkezi yarım satır yüksekliği içinde olanlar.
  final satirlar = <List<_Hucre>>[];
  for (final h in hs) {
    final son = satirlar.lastOrNull;
    if (son != null &&
        (h.h.merkezY - son.first.h.merkezY).abs() < medH * 0.5) {
      son.add(h);
    } else {
      satirlar.add([h]);
    }
  }
  for (var i = 0; i < satirlar.length; i++) {
    satirlar[i].sort((a, b) => a.h.sol.compareTo(b.h.sol));
    for (final h in satirlar[i]) {
      h.satir = i;
    }
  }

  // Çapalar: kod ya da fon adı. Ad alttaki rakamsız satırlara taşabilir
  // ("… YARI İLETKEN TEKNOLOJİLERİ" / "DEĞİŞKEN FON").
  final capalar = <_Capa>[];
  final adParcasi = <_Hucre>{};
  for (var i = 0; i < satirlar.length; i++) {
    for (final h in satirlar[i]) {
      if (h.etiketli || adParcasi.contains(h)) continue;
      final kod = _kodBul(h.h.metin, fonKodlari);
      if (kod != null) {
        capalar.add((hucre: h, kod: kod.kod, ad: null, tur: kod.tur, sonSatir: i));
        continue;
      }
      if (fonListesi.isEmpty || !_fonAdiGibi(h.h.metin)) continue;
      final parcalar = [h];
      var j = i;
      while (j + 1 < satirlar.length && parcalar.length < 4) {
        final alt = satirlar[j + 1].where((x) =>
            !x.etiketli &&
            !RegExp(r'\d').hasMatch(x.h.metin) &&
            (x.h.sol - h.h.sol).abs() < medH * 1.5 &&
            x.h.ust - parcalar.last.h.alt < medH * 0.9);
        if (alt.isEmpty) break;
        parcalar.add(alt.first);
        j++;
      }
      String? bulunan;
      var kullanilan = 1;
      for (var n = 1; n <= parcalar.length; n++) {
        final ad = _adTemizle(parcalar.take(n).map((x) => x.h.metin).join(' '));
        final adaylar = fonAdaylari(ad, fonListesi);
        if (adaylar.length == 1) {
          bulunan = adaylar.single;
          kullanilan = n;
        } else if (adaylar.isEmpty) {
          break;
        }
      }
      adParcasi.addAll(parcalar.take(bulunan == null ? parcalar.length : kullanilan));
      capalar.add((
        hucre: h,
        kod: bulunan,
        ad: bulunan == null
            ? _adTemizle(parcalar.map((x) => x.h.metin).join(' '))
            : null,
        tur: 'Fon',
        sonSatir: i + (bulunan == null ? parcalar.length : kullanilan) - 1,
      ));
    }
  }
  if (capalar.isEmpty) return const [];

  // Başlık satırları (tablo düzeni): yalnız etiket hücreli, en az iki
  // sütunlu satırlar. Sütun = etiketin yatay aralığı.
  final sutunlar = <({_Rol rol, double sol, double sag})>[];
  for (final s in satirlar) {
    final etiketler = s.where((h) => h.yalnizEtiket).toList();
    if (etiketler.length < 2 || s.any((h) => h.cozum.sayilar.isNotEmpty)) {
      continue;
    }
    for (final h in etiketler) {
      sutunlar.add((rol: h.cozum.etiketler.first.rol, sol: h.h.sol, sag: h.h.sag));
      h.kullanildi = true;
    }
  }

  // Bölümler: bir çapanın satırından bir sonrakinin satırına kadar. Aynı
  // satırda birden çok çapa (yan yana kartlar) → hücre solundaki en yakın
  // çapaya.
  final capaSatirlari = <int, List<_Capa>>{};
  for (final c in capalar) {
    (capaSatirlari[c.hucre.satir] ??= []).add(c);
  }
  final siraliSatirlar = capaSatirlari.keys.toList()..sort();
  final bolumler = <_Capa, List<_Hucre>>{for (final c in capalar) c: []};
  for (var k = 0; k < siraliSatirlar.length; k++) {
    final bas = siraliSatirlar[k];
    final son = k + 1 < siraliSatirlar.length ? siraliSatirlar[k + 1] : satirlar.length;
    final buSatir = capaSatirlari[bas]!..sort((a, b) => a.hucre.h.sol.compareTo(b.hucre.h.sol));
    for (var i = bas; i < son; i++) {
      for (final h in satirlar[i]) {
        if (adParcasi.contains(h) || capalar.any((c) => c.hucre == h)) continue;
        var hedef = buSatir.first;
        for (final c in buSatir) {
          if (c.hucre.h.sol <= h.h.merkezX) hedef = c;
        }
        bolumler[hedef]!.add(h);
      }
    }
  }

  final out = <EkranVarligi>[];
  for (final c in capalar) {
    final bolum = bolumler[c]!;
    final degerler = <_Rol, double>{};
    void yaz(_Rol r, double v) => degerler.putIfAbsent(r, () => v);

    for (final h in bolum) {
      if (!h.etiketli || h.kullanildi) continue;
      final e = h.cozum.etiketler, s = h.cozum.sayilar;
      final kullanilanSayi = <_Sayi>{};
      for (var i = 0; i < e.length; i++) {
        final sinirSag = i + 1 < e.length ? e[i + 1].bas : h.h.metin.length;
        final sinirSol = i > 0 ? e[i - 1].son : 0;
        final sonra = s.where((x) =>
            !kullanilanSayi.contains(x) && x.bas >= e[i].son && x.son <= sinirSag);
        final once = s.where((x) =>
            !kullanilanSayi.contains(x) && x.son <= e[i].bas && x.bas >= sinirSol);
        final secilen = sonra.isNotEmpty ? sonra.first : (once.isNotEmpty ? once.last : null);
        if (secilen != null) {
          kullanilanSayi.add(secilen);
          yaz(e[i].rol, secilen.deger);
        } else if (s.isEmpty && e.length == 1) {
          // Yalnız etiket: değer sağında ya da altında.
          final v = _etiketinDegeri(h, bolum, medH);
          if (v != null) {
            v.kullanildi = true;
            yaz(e[i].rol, v.cozum.sayilar.first.deger);
          }
        }
      }
    }
    // Tablo: başlık sütunundaki etiketsiz sayı.
    for (final col in sutunlar) {
      if (degerler.containsKey(col.rol)) continue;
      _Hucre? en;
      var enUzak = double.infinity;
      for (final h in bolum) {
        if (!h.yalnizSayi || h.kullanildi) continue;
        if (h.h.sag < col.sol - medH || h.h.sol > col.sag + medH) continue;
        final d = (h.h.merkezX - (col.sol + col.sag) / 2).abs() +
            (h.satir - c.hucre.satir).abs() * medH * 4;
        if (d < enUzak) {
          enUzak = d;
          en = h;
        }
      }
      if (en != null) {
        en.kullanildi = true;
        yaz(col.rol, en.cozum.sayilar.first.deger);
      }
    }

    final adet = degerler[_Rol.adet]?.abs();
    double? maliyet = degerler[_Rol.maliyet]?.abs();
    final toplam = degerler[_Rol.toplamMaliyet]?.abs();
    final belirsiz = degerler[_Rol.maliyetBelirsiz]?.abs();
    if (maliyet == null && toplam != null && adet != null && adet > 0) {
      maliyet = toplam / adet;
    }
    if (maliyet == null && belirsiz != null) {
      maliyet = belirsiz;
      final deger = degerler[_Rol.deger]?.abs();
      final fiyat = degerler[_Rol.fiyat]?.abs();
      final birim = fiyat ?? (deger != null && adet != null && adet > 0 ? deger / adet : null);
      if (birim != null && birim > 0 && adet != null && adet > 0) {
        double uzaklik(double x) => (math.log(x / birim)).abs();
        if (belirsiz > 0 && uzaklik(belirsiz / adet) < uzaklik(belirsiz)) {
          maliyet = belirsiz / adet;
        }
      }
    }
    if (maliyet != null && maliyet <= 0) maliyet = null;
    if (adet == null && maliyet == null && c.kod != null) continue;
    out.add(EkranVarligi(
      kod: c.kod,
      ad: c.ad,
      tur: c.tur,
      adet: adet == null || adet <= 0 ? null : adet,
      maliyet: maliyet,
    ));
  }
  return ekranVarliklariniBirlestir([out]);
}

_Hucre? _etiketinDegeri(_Hucre etiket, List<_Hucre> bolum, double medH) {
  // Aynı satırda sağdaki ilk etiketsiz sayı.
  _Hucre? sag;
  for (final h in bolum) {
    if (h.satir != etiket.satir || !h.yalnizSayi || h.kullanildi) continue;
    if (h.h.sol < etiket.h.sag - medH * 0.2) continue;
    if (sag == null || h.h.sol < sag.h.sol) sag = h;
  }
  if (sag != null) return sag;
  // Altta, yatayda örtüşen (ya da en yakın merkezli) ilk sayı.
  _Hucre? alt;
  var enIyi = double.infinity;
  for (final h in bolum) {
    if (h.satir <= etiket.satir || !h.yalnizSayi || h.kullanildi) continue;
    final dy = h.h.ust - etiket.h.alt;
    if (dy > medH * 2.5) continue;
    final ortusme = math.min(h.h.sag, etiket.h.sag) - math.max(h.h.sol, etiket.h.sol);
    final dx = (h.h.merkezX - etiket.h.merkezX).abs();
    if (ortusme <= 0 && dx > medH * 3) continue;
    final puan = (h.satir - etiket.satir) * 1000 + dx;
    if (puan < enIyi) {
      enIyi = puan;
      alt = h;
    }
  }
  return alt;
}

/// Hücrenin başındaki kod: BIST kataloğunda hisse ya da (hücrede tek başına
/// duran) TEFAS fon kodu. Büyük harf şart: "Pay" ya da "Son" kod sayılmaz.
({String kod, String tur})? _kodBul(String metin, Set<String> fonKodlari) {
  final t = metin.trim().replaceAll(RegExp(r'^[^\wÇĞİÖŞÜ]+|[^\wÇĞİÖŞÜ.]+$'), '');
  if (t.isEmpty) return null;
  final ayik = CsvImportService.sembolAyikla(t);
  final ilk = ayik.split(RegExp(r'\s+')).first.replaceAll(RegExp(r'\.(E|IS)$'), '');
  if (!RegExp(r'^[A-Z][A-Z0-9]{2,5}$').hasMatch(ilk)) return null;
  if (BistHisseKatalogu.instance.kodMu(ilk)) return (kod: ilk, tur: 'Hisse');
  final tekBasina = t.replaceAll(RegExp(r'\.(E|IS)$'), '') == ilk;
  if (tekBasina && ilk.length == 3 && fonKodlari.contains(ilk)) {
    return (kod: ilk, tur: 'Fon');
  }
  return null;
}

bool _fonAdiGibi(String metin) {
  if (RegExp(r'\d').hasMatch(metin)) return false;
  final k = trKatla(metin);
  return RegExp(r'\bportfoy\b').hasMatch(k) || RegExp(r'\bfon(u)?\b').hasMatch(k);
}

String _adTemizle(String ad) => ad
    .replaceAll('…', ' ')
    .replaceAll(RegExp(r'\.{2,}'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Birden çok görüntünün varlıkları: aynı kod tek satır, eksik alanı
/// sonraki görüntü tamamlar (liste kaydırılıp iki görüntü alınmış olabilir).
List<EkranVarligi> ekranVarliklariniBirlestir(List<List<EkranVarligi>> gruplar) {
  final out = <String, EkranVarligi>{};
  for (final g in gruplar) {
    for (final v in g) {
      final anahtar = v.kod ?? 'ad:${fonAdiAnahtari(v.ad ?? '')}';
      final eski = out[anahtar];
      out[anahtar] = eski == null ? v : eski._doldur(v);
    }
  }
  return out.values.toList();
}

/// Ekstre yokken görüntünün kendisi: kanonik sekmeli metin (aynı
/// `CsvImportService.parse` yolu). Adedi okunmayan ya da kodu çözülmeyen
/// varlık girmez; maliyeti okunmayanın fiyatı boş kalır (toplu kayıt o günün
/// kapanışını çeker).
String ekranKanonikMetni(List<EkranVarligi> varliklar) {
  final satirlar = [
    for (final v in varliklar)
      if (v.kod != null && v.adet != null)
        [
          v.kod!,
          sayiMetni(v.adet!),
          v.maliyet == null ? '' : sayiMetni(v.maliyet!),
          v.tur,
        ].join('\t'),
  ];
  if (satirlar.isEmpty) return '';
  return ['sembol\tadet\tfiyat\ttur', ...satirlar].join('\n');
}

/// Ekstrenin kanonik metnine görüntüdeki ortalama maliyeti yazar.
///
/// Adet ekstreden kalır (belge kaynaktır); yalnız fiyat değişir ve tutar
/// boşalır (yoksa `CsvImportService` fiyatı tutardan yeniden çıkarır).
/// Bir kod metinde TEK alış satırıysa yazılır; hareketlerle bölünmüş ya da
/// satışlı kod (`ekstre_hareketleri`) dokunulmaz: o satırların fiyatı
/// gerçek işlem fiyatıdır.
({String metin, int uygulanan, List<String> bolunmus, List<String> ekstredeYok})
    maliyetleriUygula(String metin, List<EkranVarligi> varliklar) {
  final maliyetler = {
    for (final v in varliklar)
      if (v.kod != null && v.maliyet != null) v.kod!.toUpperCase(): v.maliyet!,
  };
  final satirlar = metin.split('\n');
  if (maliyetler.isEmpty || satirlar.length < 2) {
    return (metin: metin, uygulanan: 0, bolunmus: const [], ekstredeYok: const []);
  }
  final baslik = satirlar.first.split('\t');
  final iSembol = baslik.indexOf('sembol');
  if (iSembol < 0) {
    return (metin: metin, uygulanan: 0, bolunmus: const [], ekstredeYok: maliyetler.keys.toList());
  }
  var iFiyat = baslik.indexOf('fiyat');
  if (iFiyat < 0) {
    baslik.add('fiyat');
    iFiyat = baslik.length - 1;
  }
  final iTutar = baslik.indexOf('tutar');
  final iYon = baslik.indexOf('islem turu');
  final hucreler = [
    for (final s in satirlar.skip(1))
      if (s.trim().isNotEmpty)
        [...s.split('\t'), for (var i = s.split('\t').length; i < baslik.length; i++) ''],
  ];
  final kodSatirlari = <String, List<int>>{};
  for (var i = 0; i < hucreler.length; i++) {
    (kodSatirlari[_kodNormal(hucreler[i][iSembol])] ??= []).add(i);
  }
  var uygulanan = 0;
  final bolunmus = <String>[], ekstredeYok = <String>[];
  for (final MapEntry(key: kod, value: m) in maliyetler.entries) {
    final idx = kodSatirlari[kod];
    if (idx == null) {
      ekstredeYok.add(kod);
      continue;
    }
    final satis = iYon >= 0 &&
        idx.any((i) => trKatla(hucreler[i][iYon]).startsWith('sat'));
    if (idx.length != 1 || satis) {
      bolunmus.add(kod);
      continue;
    }
    hucreler[idx.single][iFiyat] = sayiMetni(m);
    if (iTutar >= 0) hucreler[idx.single][iTutar] = '';
    uygulanan++;
  }
  return (
    metin: [baslik.join('\t'), for (final h in hucreler) h.join('\t')].join('\n'),
    uygulanan: uygulanan,
    bolunmus: bolunmus,
    ekstredeYok: ekstredeYok,
  );
}

String _kodNormal(String s) => CsvImportService.sembolAyikla(s)
    .trim()
    .toUpperCase()
    .replaceFirst(RegExp(r'^(TEFAS|KRIPTO):'), '')
    .replaceAll(RegExp(r'\.(IS|E)$'), '');
