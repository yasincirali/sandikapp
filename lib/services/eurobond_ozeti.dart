import '../models/eurobond.dart';

/// Varlık ekranındaki "Tahvil bilgileri" kartının sayıları (2026-10-08).
///
/// Kart çizer, hesaplamaz (katmanlama kuralı): bütün türetilmiş değerler
/// burada, saf fonksiyonda üretilir ve testle bağlanır
/// (`eurobond_ozeti_test`). **Uydurma sayı yok:** kaynağı olmayan alan
/// `null` kalır ve kartta o satır hiç çizilmez — "0" ya da tahmin yazılmaz.
class EurobondOzeti {
  const EurobondOzeti({
    required this.sozlesme,
    required this.temizFiyat,
    required this.islemisFaiz,
    required this.kirliFiyat,
    required this.vadeyeGetiri,
    required this.sonrakiKupon,
    required this.sonrakiKuponTutari,
    required this.kalanGun,
    required this.bankaAlis,
    required this.bankaSatis,
    required this.bankaMakasi,
    required this.bankayaSatisTutari,
    required this.bankaGuncellendi,
  });

  final EurobondSozlesmesi sozlesme;

  /// Piyasa temiz fiyatı (100 nominal başına). Kaynak fiyat yoksa null.
  final double? temizFiyat;

  /// Bugünkü işlemiş faiz (100 nominal başına) — sözleşmeden, her zaman
  /// bilinir; vadeden sonra 0.
  final double islemisFaiz;

  /// Temiz + işlemiş. Temiz bilinmiyorsa null.
  final double? kirliFiyat;

  /// Yıllık vadeye getiri (oran, 0.065 = %6,5). Temiz yoksa ya da vade
  /// geçtiyse null.
  final double? vadeyeGetiri;

  /// Sonraki kupon tarihi; vade geçtiyse null.
  final DateTime? sonrakiKupon;

  /// Kullanıcının nominali için bir kuponun BRÜT tutarı (tahvil para
  /// biriminde). Nominal bilinmiyorsa (0) null.
  final double? sonrakiKuponTutari;

  /// Vadeye kalan gün; vade bugün ya da geçtiyse null.
  final int? kalanGun;

  /// Ziraat kotasyonu (KİRLİ, 100 nominal başına). Banka alışı = senin
  /// satışın.
  final double? bankaAlis;
  final double? bankaSatis;
  final double? bankaMakasi;

  /// Bugün bankaya satsan eline geçecek tutar (nominal × banka alış/100,
  /// tahvil para biriminde, vergi öncesi). Banka alışı yoksa null.
  final double? bankayaSatisTutari;

  /// Kotasyonun güncellendiği an — banka satırları varsa anlamlı.
  final DateTime? bankaGuncellendi;

  bool get bankaVar => bankaAlis != null || bankaSatis != null;
}

/// [nominal]: kullanıcının açık nominal tutarı (pozisyonun miktarı).
EurobondOzeti eurobondOzeti({
  required EurobondSozlesmesi sozlesme,
  required EurobondFiyati? fiyat,
  required double nominal,
  required DateTime simdi,
}) {
  final bugun = DateTime.utc(simdi.year, simdi.month, simdi.day);
  final temiz = fiyat?.temizFiyat;
  final islemis = sozlesme.islemisFaiz(bugun);
  final aralik = sozlesme.kuponAraligi(bugun);
  final kalan = sozlesme.vade.difference(bugun).inDays;
  final bankaAlis = fiyat?.bankaAlis;
  final bankaVar = bankaAlis != null || fiyat?.bankaSatis != null;
  return EurobondOzeti(
    sozlesme: sozlesme,
    temizFiyat: temiz,
    islemisFaiz: islemis,
    kirliFiyat: temiz == null ? null : temiz + islemis,
    vadeyeGetiri: temiz == null ? null : sozlesme.vadeyeGetiri(temiz, bugun),
    sonrakiKupon: aralik?.sonraki,
    sonrakiKuponTutari:
        aralik != null && nominal > 0 ? sozlesme.kuponTutari(nominal) : null,
    kalanGun: kalan > 0 ? kalan : null,
    bankaAlis: bankaAlis,
    bankaSatis: fiyat?.bankaSatis,
    bankaMakasi: fiyat?.bankaMakasi,
    bankayaSatisTutari:
        bankaAlis != null && nominal > 0 ? nominal * bankaAlis / 100 : null,
    bankaGuncellendi: bankaVar ? fiyat?.guncellendi : null,
  );
}
