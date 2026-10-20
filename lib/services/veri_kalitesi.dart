import '../models/asset.dart';
import '../models/position.dart';
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
enum VeriEksigiTuru { alisFiyati, eskiFiyat }

/// Elle girilen fiyat kaç günden eskiyse "bilgi eksik" sayılır. Aylık
/// güncelleme makul bir alışkanlık; daha kısa eşik her hafta aynı uyarıyı
/// gösterip satırı gürültüye çevirirdi.
const eskiFiyatEsikGun = 30;

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
List<VeriEksigi> veriEksikleri(
  List<Position> pozisyonlar, {
  required DateTime simdi,
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
    }
  }
  return sonuc;
}

/// Satırdaki sayı: eksiği olan POZİSYON sayısı ("2 varlıkta").
int eksikPozisyonSayisi(Iterable<VeriEksigi> eksikler) =>
    {for (final e in eksikler) e.pozisyon.key}.length;

/// Satır görünür mü: kapatıldığı andan sonra yeni bir eksik çıktıysa evet.
/// Hepsi düzelince liste boştur, satır kendiliğinden kalkar.
bool veriSeridiGorunur(
        Iterable<VeriEksigi> eksikler, Set<String> kapatilanlar) =>
    eksikler.any((e) => !kapatilanlar.contains(e.anahtar));
