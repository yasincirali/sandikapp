import '../utils/tr_katla.dart';

/// TEFAS emeklilik fonu (EMK) unvanlarından türetilen emeklilik şirketi.
///
/// ## Neden (yasin, 2026-10-29: "MetLife gibi BES varlıkları incelenmeli")
/// BES formunda şirket serbest metindi ("Örn. Anadolu Hayat") ve fon
/// seçici TÜM EMK fonlarını (yüzlercesi) tek listede veriyordu: MetLife
/// müşterisi kendi şirketinin fonunu yüzlerce satır arasında arıyordu.
///
/// ## Kaynak: fon unvanı, elle liste DEĞİL
/// TEFAS'ta her EMK fonunun unvanı şirketin ticaret unvanıyla başlar
/// ("ANADOLU HAYAT EMEKLİLİK A.Ş. ALTIN KATILIM EMEKLİLİK YATIRIM FONU").
/// Şirket listesi bu önekten kurulur; yeni şirket ya da unvan değişikliği
/// uygulama güncellemesi beklemez ve uydurma bir şirket listede görünmez.
/// "A.Ş." taşımayan unvan hiçbir şirkete bağlanmaz — o fon yalnız "Tüm
/// fonlar"da görünür (tahminle yanlış şirkete koymaktansa).
class EmeklilikSirketi {
  const EmeklilikSirketi({
    required this.anahtar,
    required this.ad,
    required this.fonSayisi,
  });

  /// Katlanmış ticaret unvanı öneki — eşleştirme anahtarı.
  final String anahtar;

  /// Kullanıcıya gösterilen ad ("Anadolu Hayat Emeklilik").
  final String ad;

  /// Listede bu şirkete bağlanan fon sayısı.
  final int fonSayisi;

  @override
  bool operator ==(Object other) =>
      other is EmeklilikSirketi && other.anahtar == anahtar;

  @override
  int get hashCode => anahtar.hashCode;
}

/// "A.Ş." / "A.S." / "AŞ" — unvanın şirket kısmını bitiren işaret.
final RegExp _anonimSirket =
    RegExp(r'\s+A\s?\.?\s?[ŞS]\s?\.?(?=\s|$)', caseSensitive: false);

/// Fon unvanının şirket öneki (ham, "A.Ş." hariç); bulunamazsa `null`.
String? emeklilikSirketOneki(String fonUnvani) {
  final u = fonUnvani.trim().replaceAll(RegExp(r'\s+'), ' ');
  final m = _anonimSirket.firstMatch(u);
  if (m == null || m.start == 0) return null;
  return u.substring(0, m.start).trim();
}

/// Fon unvanından şirket anahtarı; bağlanamazsa `null`.
String? emeklilikSirketAnahtari(String fonUnvani) {
  final o = emeklilikSirketOneki(fonUnvani);
  return o == null ? null : trKatla(o);
}

/// Markaların kendi yazımı — yalnız BÜYÜK/küçük harf düzeltmesi; listeye
/// şirket EKLEMEZ (şirket yalnız fon unvanından gelir).
///
/// Yabancı kelimeler de burada: TEFAS unvanında noktasız "I" Türkçe "ı"
/// sayılır ("KATILIM" → "Katılım"), ama "ALLIANZ" "Allıanz" olurdu.
const _markaYazimi = {
  'metlife': 'MetLife',
  'agesa': 'AgeSA',
  'avivasa': 'AvivaSA',
  'allianz': 'Allianz',
  'viennalife': 'Viennalife',
  'zurich': 'Zurich',
  'cigna': 'Cigna',
  'cardif': 'Cardif',
  'paribas': 'Paribas',
};

/// Harflerin hepsi büyük kalması gereken kısaltmalar.
const _kisaltmalar = {'hdi', 'axa', 'bnp', 'nn', 'bbva', 'qnb', 'ing', 'teb'};

/// Ham öneki gösterim adına çevirir: Türkçe büyük/küçük harf kuralıyla her
/// kelimenin ilk harfi büyük, bağlaç "ve" küçük, marka yazımları korunur.
/// "ALLIANZ YAŞAM VE EMEKLİLİK" → "Allianz Yaşam ve Emeklilik".
String emeklilikSirketAdi(String onek) {
  final kelimeler = onek.trim().split(RegExp(r'\s+'));
  final out = <String>[];
  for (var i = 0; i < kelimeler.length; i++) {
    final k = kelimeler[i];
    if (k.isEmpty) continue;
    final katli = trKatla(k);
    final marka = _markaYazimi[katli];
    if (marka != null) {
      out.add(marka);
    } else if (_kisaltmalar.contains(katli)) {
      out.add(_buyuk(k));
    } else if (i > 0 && katli == 've') {
      out.add('ve');
    } else {
      out.add(_buyuk(k.substring(0, 1)) + _kucuk(k.substring(1)));
    }
  }
  return out.join(' ');
}

String _kucuk(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

String _buyuk(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Fon unvanlarından şirket listesi — ada göre sıralı, tekrar yok.
List<EmeklilikSirketi> emeklilikSirketleri(Iterable<String> fonUnvanlari) {
  final sayac = <String, int>{};
  final adlar = <String, String>{};
  for (final u in fonUnvanlari) {
    final o = emeklilikSirketOneki(u);
    if (o == null) continue;
    final a = trKatla(o);
    sayac[a] = (sayac[a] ?? 0) + 1;
    adlar.putIfAbsent(a, () => emeklilikSirketAdi(o));
  }
  return [
    for (final e in sayac.entries)
      EmeklilikSirketi(anahtar: e.key, ad: adlar[e.key]!, fonSayisi: e.value),
  ]..sort((a, b) => trKatla(a.ad).compareTo(trKatla(b.ad)));
}

/// Fon [sirket]in fonu mu?
bool emeklilikFonuSirketin(String fonUnvani, EmeklilikSirketi sirket) =>
    emeklilikSirketAnahtari(fonUnvani) == sirket.anahtar;

/// Şirketi diğerlerinden AYIRMAYAN kelimeler — eşleştirmede sayılmaz.
const _genelKelimeler = {
  'emeklilik',
  'hayat',
  've',
  'yasam',
  'sigorta',
  'sirketi',
  'anonim',
  'a.s.',
  'as',
};

Set<String> _ayirtKelimeler(String s) => {
      for (final k in trKatla(s)
          .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
          .split(RegExp(r'\s+')))
        if (k.isNotEmpty && !_genelKelimeler.contains(k)) k,
    };

/// Sözleşmede yazılı serbest kurum adını ("Anadolu Hayat", "metlife")
/// listedeki şirkete bağlar; tek şirkete bağlanamazsa `null`.
///
/// Kural: büyük/küçük harf ve Türkçe karakter farkı yok sayılır
/// ([trKatla]); "emeklilik", "hayat", "ve" gibi her şirkette geçen
/// kelimeler ayırt etmez, sayılmaz. Yazılanın ayırt edici kelimelerinin
/// HEPSİ şirket adında geçmeli ve tek şirket kalmalı — iki şirkete uyan
/// ad (ör. yalnız "Garanti") tahmin edilmez.
EmeklilikSirketi? emeklilikSirketiBul(
    String? kurum, Iterable<EmeklilikSirketi> sirketler) {
  final yazilan = (kurum ?? '').trim();
  if (yazilan.isEmpty) return null;
  final katli = trKatla(yazilan);
  for (final s in sirketler) {
    if (trKatla(s.ad) == katli || s.anahtar == katli) return s;
  }
  final aranan = _ayirtKelimeler(yazilan);
  if (aranan.isEmpty) return null;
  EmeklilikSirketi? bulunan;
  for (final s in sirketler) {
    final kelimeler = _ayirtKelimeler(s.ad);
    if (aranan.every(kelimeler.contains)) {
      if (bulunan != null) return null; // iki aday: tahmin yok
      bulunan = s;
    }
  }
  return bulunan;
}

/// Fon unvanının kısa adı: şirket öneki ve her fonda tekrar eden
/// "EMEKLİLİK YATIRIM FONU" kuyruğu atılır.
/// "ANADOLU HAYAT EMEKLİLİK A.Ş. ALTIN KATILIM EMEKLİLİK YATIRIM FONU" →
/// "Altın Katılım". Sözleşme kartının fon satırı kodun yanına bunu yazar
/// (kod tek başına "AH5" kullanıcıya bir şey söylemez). Kısaltılacak bir
/// şey kalmazsa `null` — çağıran yalnız kodu gösterir.
String? emeklilikFonuKisaAdi(String fonUnvani) {
  final u = fonUnvani.trim().replaceAll(RegExp(r'\s+'), ' ');
  final m = _anonimSirket.firstMatch(u);
  var govde = m == null ? u : u.substring(m.end).trim();
  govde = govde
      .replaceFirst(
          RegExp(r'\s*(EMEKL[İI]L[İI]K\s+)?YATIRIM\s+FONU\s*$',
              caseSensitive: false),
          '')
      .trim();
  if (govde.isEmpty || govde == u) return null;
  return emeklilikSirketAdi(govde);
}
