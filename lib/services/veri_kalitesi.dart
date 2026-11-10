import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import 'bist_calendar.dart';
import '../utils/tr_format.dart' show dayKey;

/// Pozisyonun hesabını sessizce yanlış gösteren eksik bilgi.
///
/// ## Neden (yasin onayı 2026-10-20; Ar-Ge raporları 13:15 #1, 17:15 #3)
/// İki ayrı boşluk aynı sonucu doğuruyordu — kullanıcının toplamı ya da
/// kâr/zararı yanlış ve haberi yok:
/// · [alisFiyati]: ekran görüntüsünden/toplu eklemede maliyeti okunamayan
///   lot o günün fiyatıyla kaydedilir (`Asset.maliyetBilinmiyor`, 0162);
///   kâr/zarar sıfır görünür.
/// · [eskiFiyat]: elle fiyatlanan varlığın (listede olmayan fon, arsa,
///   koleksiyon) değeri kullanıcı güncellemedikçe hiç değişmez; 30 günden
///   eskiyse toplam bayat bir sayıyla toplanır.
/// Rapor "iki ayrı uyarı olmasın" dedi: ikisi tek satırda sayılır
/// ("N varlıkta bilgi eksik"), Portföy satırı hangisi olduğunu söyler.
/// · [fiyatGelmiyor] (müşteri 2026-11-10): TEFAS'tan fiyatı gelen fonun son
///   fiyatı [fiyatGelmiyorEsikIsGunu] BIST iş gününden eski. Fon kapanmış
///   ya da başka fonla birleşmişse TEFAS fiyat yayımlamayı keser; değer son
///   fiyatta donar ve kullanıcı bunu fark etmez. Elle fiyat ([eskiFiyat])
///   değil: kullanıcı bir şey girmedi, kaynak sustu.
enum VeriEksigiTuru { alisFiyati, eskiFiyat, fiyatGelmiyor }

/// Fon fiyatı kaç BIST iş gününden eskiyse "fiyatı gelmiyor" sayılır.
///
/// Fon günde bir fiyat yayımlar, bugünün fiyatı akşam ya da ertesi sabah
/// gelir: olağan gecikme 1 iş günü, uzun bayramda da tatil günleri
/// sayılmadığı için büyümez. 7 iş günü (takvimde 9-10 gün) TEFAS'ın geçici
/// aksamasını uyarıya çevirmeyecek kadar uzun, kapanan fonu haftalarca
/// sessiz bırakmayacak kadar kısa.
const fiyatGelmiyorEsikIsGunu = 7;

/// [tarih] ile [simdi] arasındaki BIST iş günü sayısı: [tarih]'ten SONRA,
/// bugün DAHİL. Hafta sonu ve [BistTakvimi.tatilMi] sayılmaz; yarım gün
/// (arife) iş günüdür, fon o gün de fiyat yayımlar. Cuma fiyatı Pazartesi
/// 1 iş günü eskidir.
int bistIsGunuFarki(DateTime tarih, DateTime simdi) {
  final bugun = dayKey(simdi);
  final t0 = dayKey(tarih.toLocal());
  var g = DateTime(t0.year, t0.month, t0.day + 1);
  var sayi = 0;
  while (!g.isAfter(bugun)) {
    if (g.weekday < DateTime.saturday && !BistTakvimi.tatilMi(g)) sayi++;
    // Takvim günü ekleyerek (Duration değil): yaz saati geçişinde gün
    // kaymasın.
    g = DateTime(g.year, g.month, g.day + 1);
  }
  return sayi;
}

/// Elle girilen fiyat kaç günden eskiyse "bilgi eksik" sayılır. Aylık
/// güncelleme makul bir alışkanlık; daha kısa eşik her hafta aynı uyarıyı
/// gösterip satırı gürültüye çevirirdi.
const eskiFiyatEsikGun = 30;

/// Eski fiyat etiketinin ay sayısı; `null` → bir yıldan eski.
///
/// ## Neden (Ar-Ge 5 Kas 20:45 #3, müşteri YAP)
/// Etiket gün sayıyordu: "Fiyat 601 gün önce girildi" 390 pt'de iki satıra
/// taşıyor, satırı büyütüyordu; 601 gün okunması zor bir sayı. iOS ve
/// Kubera göreli zamanı kaba birimle yazar ("3 ay önce", "1 yıldan eski").
/// Ay 30 gün sayılır (kesin takvim ayı gerekmez, etiket bir hatırlatma);
/// eşiğin ([eskiFiyatEsikGun]) altında etiket zaten çıkmaz, çıkarsa en az
/// 1 ay yazılır. 365 gün ve üstü tek cümle: yılı saymak bir şey katmaz.
int? eskiFiyatAySayisi(int gun) {
  if (gun >= 365) return null;
  final ay = gun ~/ 30;
  return ay < 1 ? 1 : ay;
}

class VeriEksigi {
  const VeriEksigi({
    required this.pozisyon,
    required this.tur,
    this.gun,
    this.lotlar = const [],
  });

  final Position pozisyon;
  final VeriEksigiTuru tur;

  /// [VeriEksigiTuru.eskiFiyat]: fiyatın girildiği günden bu yana gün.
  /// [VeriEksigiTuru.fiyatGelmiyor]: son fon fiyatının gününden bu yana
  /// TAKVİM günü (kullanıcıya "N gündür" diye okunur; iş günü eşikte).
  final int? gun;

  /// [VeriEksigiTuru.alisFiyati]: maliyeti bilinmeyen lotlar (düzenleme
  /// formu lot başına açılır).
  final List<Asset> lotlar;

  /// Kapatma kaydının anahtarı: tür + pozisyon. Gün sayısı girmez — aynı
  /// bayat fiyat her gün "yeni" sayılıp kapatılan satırı geri getirmesin.
  String get anahtar => '${tur.name}|${pozisyon.key}';
}

/// Elle fiyatın girildiği an: son güncelleme, yoksa satırın sunucuya
/// girildiği an, o da yoksa alış tarihi. Geriye tarihli alımda alış
/// tarihi fiyatın girildiği gün değildir; `createdAt` bu yüzden önce gelir.
DateTime elleFiyatTarihi(Asset a) => a.lastUpdated ?? a.createdAt ?? a.addedDate;

/// Kendi bugünkü pozisyonlarındaki eksikler — SAF (test: `veri_kalitesi_test`).
///
/// Sözleşmeli türler (mevduat, BES) dışarıda: birim değerleri sözleşmeden
/// hesaplanır, "elle fiyat" ya da "maliyet" kavramı kullanıcının girdiği
/// bir sayı değildir. Bir pozisyon iki eksiği birden taşıyabilir; sayı
/// pozisyon başına bir kez sayılır ([eksikPozisyonSayisi]).
///
/// [fonFiyatTarihi]: TEFAS fonunun son fiyatının günü (fon kodu → gün;
/// `TefasService.fiyatTarihi`). Verilmezse ya da gün bilinmiyorsa
/// [VeriEksigiTuru.fiyatGelmiyor] hiç sayılmaz: gününü bilmediğimiz fiyatı
/// "gelmiyor" diye işaretlemek uydurma olurdu. [pozisyonlar] bugünkü
/// mülkiyettir (çağıran `aktifLotlar` ile süzer); kapanmış fon sorulmaz.
List<VeriEksigi> veriEksikleri(
  List<Position> pozisyonlar, {
  required DateTime simdi,
  DateTime? Function(String fonKodu)? fonFiyatTarihi,
}) {
  final bugun = dayKey(simdi);
  final sonuc = <VeriEksigi>[];
  for (final p in pozisyonlar) {
    final r = p.representative;
    if (r.type.sozlesmeli || p.lots.any((l) => l.sozlesmeId != null)) {
      continue;
    }
    final maliyetsiz = [
      for (final l in p.lots)
        if (l.isBuy && l.isActive && l.maliyetBilinmiyor == true) l,
    ];
    if (maliyetsiz.isNotEmpty) {
      sonuc.add(VeriEksigi(
          pozisyon: p, tur: VeriEksigiTuru.alisFiyati, lotlar: maliyetsiz));
    }
    if (r.isManualPrice) {
      final t = elleFiyatTarihi(r);
      final gun = bugun.difference(dayKey(t)).inDays;
      if (gun > eskiFiyatEsikGun) {
        sonuc.add(VeriEksigi(
            pozisyon: p, tur: VeriEksigiTuru.eskiFiyat, gun: gun));
      }
    } else if (r.type == AssetType.fon && fonFiyatTarihi != null) {
      final t = r.ticker.trim().isEmpty ? null : fonFiyatTarihi(r.ticker);
      if (t != null &&
          bistIsGunuFarki(t, simdi) > fiyatGelmiyorEsikIsGunu) {
        sonuc.add(VeriEksigi(
          pozisyon: p,
          tur: VeriEksigiTuru.fiyatGelmiyor,
          gun: _takvimGunu(t, simdi),
        ));
      }
    }
  }
  return sonuc;
}

/// [t]'den [simdi]'ye takvim günü; UTC gün başlarıyla, yaz saati geçişi
/// 23 saatlik günü 0'a yuvarlamasın (`fonFiyatGunFarki` ile aynı yol).
int _takvimGunu(DateTime t, DateTime simdi) {
  final a = t.toLocal();
  final b = simdi.toLocal();
  return DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
}

/// Satırdaki sayı: eksiği olan POZİSYON sayısı ("2 varlıkta").
int eksikPozisyonSayisi(Iterable<VeriEksigi> eksikler) =>
    {for (final e in eksikler) e.pozisyon.key}.length;

/// Satır görünür mü: kapatıldığı andan sonra yeni bir eksik çıktıysa evet.
/// Hepsi düzelince liste boştur, satır kendiliğinden kalkar.
bool veriSeridiGorunur(
        Iterable<VeriEksigi> eksikler, Set<String> kapatilanlar) =>
    eksikler.any((e) => !kapatilanlar.contains(e.anahtar));
