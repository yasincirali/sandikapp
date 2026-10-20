import '../../providers/bulk_cart_provider.dart';
import '../csv_import_service.dart';
import 'ekran_goruntusu.dart';

/// Ekran görüntüsünden doğrudan Toplu Ekle sepetine (2026-10-19).
///
/// ## Neden
/// yasin (müşteri gözüyle rapor, 2026-10-19): "Ekran görüntüsünden portföy
/// ekleme: yap, ama dar kapsamla. İlk gün elle girişte vazgeçen kullanıcıyı
/// kurtarır. … İlk sürümde birden çok görüntü seçilebilmeli; maliyet
/// okunamazsa satır atılmamalı, sonra girilecek diye işaretlenmeli."
///
/// Okuma ve anlama zaten vardı (`ekran_goruntusu.dart`, 2026-10-13) ama
/// yalnız içe aktarma ekranında, bayrak (`ekran_goruntusu_maliyet`) ve
/// Premium ardındaydı; amacı ekstreye maliyet yazmaktı. Burası aynı okumayı
/// yeni kullanıcının ilk kapısına (Toplu Ekle) bağlar: bayraksız, ücretsiz.
/// Görüntü telefondan çıkmaz, sunucu/AI maliyeti yok.
///
/// Sepete giden yol içe aktarmayla AYNI: kanonik metin → `CsvImportService`
/// (sembol, tür, para birimi tek yerde çözülür; ikinci ayrıştırıcı yok).
///
/// ## Uydurma yok
/// Maliyeti okunmayan varlık DÜŞMEZ: fiyatı boş girer ve [BulkCartItem.
/// maliyetSonra] işaretlenir; sepet satırı "maliyet sonra girilecek" der.
/// Toplu kayıt boş fiyatı her zamanki gibi o günün kapanışıyla doldurur
/// (gerçek bir fiyat, ama kullanıcının maliyeti değil — satır bunu söyler).
/// Adedi okunmayan varlık eklenemez (miktarsız pozisyon olmaz); adıyla
/// listelenir ki kullanıcı onu elle eklesin.
class EkranSepetSonucu {
  const EkranSepetSonucu({
    required this.kalemler,
    required this.adediOkunamayan,
    required this.taninmayanFonlar,
  });

  final List<BulkCartItem> kalemler;

  /// Kodu tanınan ama adedi okunamayan varlıklar (eklenmedi).
  final List<String> adediOkunamayan;

  /// TEFAS'ta tek fona eşleşmeyen fon adları (eklenmedi).
  final List<String> taninmayanFonlar;

  int get maliyetiSonraGirilecek => kalemler.where((k) => k.maliyetSonra).length;
}

EkranSepetSonucu ekranVarliklarindanSepet(
  List<EkranVarligi> varliklar, {
  DateTime? bugun,
}) {
  final metin = ekranKanonikMetni(varliklar);
  final satirlar = metin.isEmpty
      ? const <BulkCartItem>[]
      : CsvImportService.parse(metin, today: bugun).rows;
  return EkranSepetSonucu(
    kalemler: [
      for (final k in satirlar)
        k.price > 0
            ? k.copyWith(yol: 'ekran_goruntusu')
            : k.copyWith(maliyetSonra: true, yol: 'ekran_goruntusu'),
    ],
    adediOkunamayan: [
      for (final v in varliklar)
        if (v.kod != null && v.adet == null) v.kod!,
    ],
    taninmayanFonlar: [
      for (final v in varliklar)
        if (v.kod == null && v.ad != null) v.ad!,
    ],
  );
}
