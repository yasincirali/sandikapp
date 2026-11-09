import '../utils/tr_katla.dart';
import 'asset.dart';
import 'position.dart';

/// Genel aramadaki (bayrak `genel_arama`) "Eylemler" grubu.
///
/// ## Neden saf bir model dosyası
/// Ekran hangi eylemin hangi sözcükle bulunacağını bilmesin: kullanıcı
/// "ekstre", "csv", "aracı kurum dökümü" gibi farklı adlarla aynı yeri arıyor.
/// Eşleştirme burada, test edilebilir; ekran yalnızca eylemi hedef ekrana
/// bağlar (`genel_arama_screen.dart`). Etiketler `context.l10n`'de — burada
/// yalnızca ARAMA anahtarları durur (Türkçe + İngilizce, aksansız yazımlar
/// `trKatla` ile kendiliğinden eşleşir: "fiyat alarmi" = "fiyat alarmı").
///
/// Aylık rapor ve hafta özeti BİLEREK yok: ikisinin de açıcısı koşullu
/// (dönem verisi, bayrak, seviye) ve o koşulları tekrar kurmak iki ayrı
/// doğruluk kaynağı demekti. Güvenli bir ortak açıcı çıkınca eklenir.
enum AramaEylemi {
  fiyatAlarmlari,
  sinyalAyarlari,
  ekstreAktar,
  topluEkle,
  tumHareketler,
  karsilastir,
  takipListesi,
  bildirimler,
  ayarlar,
}

/// Eylemin arama anahtarları. Sıra = yazınca sonuç sırası; boş sorguda
/// "Tüm eylemler" altındaki sıra (önce [aramaSabitEylemler]).
const Map<AramaEylemi, List<String>> aramaEylemAnahtarlari = {
  AramaEylemi.fiyatAlarmlari: [
    'fiyat alarmı',
    'alarm',
    'alarmlarım',
    'hedef fiyat',
    'price alert',
    'alert',
  ],
  AramaEylemi.sinyalAyarlari: [
    'sinyal',
    'sinyal ayarları',
    'teknik sinyal',
    'rsi',
    'signal',
  ],
  AramaEylemi.ekstreAktar: [
    'ekstre',
    'ekstreden aktar',
    'csv',
    'içe aktar',
    'aracı kurum',
    'dosya',
    'import',
    'statement',
  ],
  AramaEylemi.topluEkle: [
    'toplu',
    'toplu ekle',
    'çoklu ekle',
    'sepet',
    'bulk',
  ],
  AramaEylemi.tumHareketler: [
    'hareketler',
    'tüm hareketler',
    'işlemler',
    'işlem geçmişi',
    'geçmiş',
    'temettü',
    'satış',
    'alış',
    'transactions',
    'history',
    'dividend',
  ],
  AramaEylemi.karsilastir: [
    'karşılaştır',
    'karşılaştırma',
    'kıyas',
    'kıyasla',
    'compare',
  ],
  AramaEylemi.takipListesi: [
    'takip',
    'takip listesi',
    'takibe al',
    'izleme',
    'watchlist',
  ],
  AramaEylemi.bildirimler: [
    'bildirim',
    'bildirimler',
    'zil',
    'notification',
  ],
  AramaEylemi.ayarlar: [
    'ayarlar',
    'ayar',
    'tema',
    'karanlık mod',
    'dil',
    'sessiz saat',
    'settings',
  ],
};

/// [sorgu]ya uyan eylemler, tanım sırasıyla. Boş sorgu → hepsi (öneri).
///
/// [mevcut] verilirse yalnızca onlar döner: ekran bugün açılamayan bir
/// hedefi (ör. çağıranın vermediği bildirim sayfası) listelemesin.
///
/// Eşleşme kuralı — iki yönlü, çünkü iki tür yazım var:
/// - Kısa/eksik yazım ("ala", "hareket"): sorgunun HER sözcüğü bir anahtar
///   sözcüğünün başı olmalı. "al" tek başına "alarm"ı da "alış"ı da bulur;
///   bu kabul — öneri listesi zaten kısa.
/// - Cümle ("fiyat alarmı kur", "csv yükle"): sorgu bir anahtarı
///   BÜTÜNÜYLE içeriyorsa eşleşir; fazladan sözcükler engel olmaz.
List<AramaEylemi> aramaEylemleriniSuz(String sorgu,
    {Set<AramaEylemi>? mevcut}) {
  final q = trKatla(sorgu.trim());
  final sonuc = <AramaEylemi>[];
  for (final e in AramaEylemi.values) {
    if (mevcut != null && !mevcut.contains(e)) continue;
    if (q.isEmpty || _eslesir(q, aramaEylemAnahtarlari[e] ?? const [])) {
      sonuc.add(e);
    }
  }
  return sonuc;
}

/// Boş sorguda her zaman görünen dört eylem — bu sırayla.
///
/// ## Neden sabit (2026-10-26)
/// Boş aramada dokuz satır, "Son baktıkların"ın altında ekranı dolduruyor
/// ve aranan kısayolu satır kalabalığında kaybettiriyordu. Dördü en sık
/// gidilen yerler (alarm, takip listesi, toplu ekle, ayarlar); kalanı tek
/// "Tüm eylemler" satırının arkasında, aynı listede açılır.
///
/// Kişiye göre sıralama / kullanım sayacı BİLEREK YOK: yeri değişen satır
/// alışkanlığı bozar — kullanıcı parmağını "üçüncü satır = toplu ekle"ye
/// alıştırır, sayaç bir gün sırayı değiştirince yanlış yere dokunur. Liste
/// hep aynı yerde durur; ayrıca cihazda kullanım kaydı tutmak gerekmez.
/// Yazınca (sorgu dolu) bu ayrım yok: eşleşen bütün eylemler gelir.
const List<AramaEylemi> aramaSabitEylemler = [
  AramaEylemi.fiyatAlarmlari,
  AramaEylemi.takipListesi,
  AramaEylemi.topluEkle,
  AramaEylemi.ayarlar,
];

/// Eylem listesinin ekrandaki düzeni: [gorunen] her zaman çizilir, [kalan]
/// "Tüm eylemler" açılınca altında.
///
/// - Boş sorgu: [gorunen] = [aramaSabitEylemler] (bu sırayla), [kalan] =
///   öteki eylemler tanım sırasıyla. "Tüm eylemler" yalnız [kalan] doluyken
///   çizilir.
/// - Dolu sorgu: [gorunen] = [aramaEylemleriniSuz] (eşleşen hepsi, bugünkü
///   davranış), [kalan] boş — açılır satır yok.
///
/// [mevcut] ikisini de süzer (açıcısı verilmeyen hedef hiçbir yerde
/// listelenmez). Açık/kapalı durumu burada değil: ekranın geçici durumu,
/// kalıcı değil (her açılışta kapalı başlar).
({List<AramaEylemi> gorunen, List<AramaEylemi> kalan}) aramaEylemDuzeni(
    String sorgu,
    {Set<AramaEylemi>? mevcut}) {
  final hepsi = aramaEylemleriniSuz(sorgu, mevcut: mevcut);
  if (sorgu.trim().isNotEmpty) return (gorunen: hepsi, kalan: const []);
  return (
    gorunen: [
      for (final e in aramaSabitEylemler)
        if (hepsi.contains(e)) e,
    ],
    kalan: [
      for (final e in hepsi)
        if (!aramaSabitEylemler.contains(e)) e,
    ],
  );
}

final _bosluk = RegExp(r'\s+');

bool _eslesir(String q, List<String> anahtarlar) {
  final katli = [for (final a in anahtarlar) trKatla(a)];
  // Cümle içinde bütün bir anahtar.
  for (final a in katli) {
    if (a.length >= 3 && q.contains(a)) return true;
  }
  // Her sorgu sözcüğü bir anahtar sözcüğünün öneki.
  final sozcukler = {for (final a in katli) ...a.split(_bosluk)};
  return q
      .split(_bosluk)
      .where((t) => t.isNotEmpty)
      .every((t) => sozcukler.any((s) => s.startsWith(t)));
}

/// "Varlıklarım" grubu: kullanıcının bugün AÇIK pozisyonlarından sembolü
/// ya da adı sorguya uyanlar.
///
/// `aggregatePositions` kapanmış (tamamı satılmış) ve silinmiş pozisyonu
/// zaten eler — CLAUDE.md "Kapanmış pozisyon": bugünkü mülkiyeti soran yer.
/// Sembol `pozisyonKodu` ile karşılaştırılır ("THYAO.IS" → "thyao",
/// "TEFAS:AFA" → "afa") ki kullanıcı ekranda gördüğü kodu yazsın.
/// Boş sorgu boş döner: öneri yerinde eylemler durur, portföy listesi
/// Portföy sekmesinin işi.
List<Position> aramaPozisyonlari(List<Asset> defter, String sorgu) {
  final q = trKatla(sorgu.trim());
  if (q.isEmpty) return const [];
  return [
    for (final p in aggregatePositions(defter))
      if (trKatla(pozisyonKodu(p.representative.ticker)).contains(q) ||
          trKatla(p.representative.ticker).contains(q) ||
          trKatla(p.representative.name).contains(q) ||
          trKatla(p.representative.subCategory ?? '').contains(q))
        p,
  ];
}
