import 'asset_type.dart';

/// Boş ana ekrandaki "Ne biriktiriyorsun?" seçenekleri (sadeleştirme 2,
/// liste madde 4; bayrak `ilk_varlik_kolay`).
///
/// ## Neden bu beş
/// Türkiye'de ilk birikimin en sık biçimleri: gram altın, dolar, euro; fon ve
/// hisse ise "bir tane" seçilecek türler. Kripto, emtia, mevduat, BES
/// eksik değil, bilerek dışarıda: beşten fazla çip ilk ekranı yeniden ağır
/// form hâline getirir; onlar Varlık Ekle'nin tür çipinde duruyor.
///
/// ## Neden ayrı bir ekran değil
/// Seçim yalnızca Varlık Ekle'yi ÖN SEÇİMLİ açar. Kayıt, doğrulama, fiyat
/// önizlemesi ve tarih varsayılanı olduğu gibi formun; ikinci bir kayıt yolu
/// yazılsaydı her kural (kimlik eksiği, kapanmış pozisyon, sepet) iki yerde
/// tutulmak zorunda kalırdı.
enum IlkVarlikSecimi {
  gramAltin(AssetType.altin),
  dolar(AssetType.doviz),
  euro(AssetType.doviz),
  fon(AssetType.fon),
  hisse(AssetType.hisse);

  const IlkVarlikSecimi(this.tur);

  /// Formun açılacağı tür.
  final AssetType tur;

  /// Varlığın kendisi de seçili mi (yalnız miktar kalır), yoksa tür seçilip
  /// kullanıcı listeden mi seçecek? Fon ve hisse binlerce seçenek: tek
  /// "önerilen" fon/hisse yazmak yatırım tavsiyesi gibi okunur.
  bool get varlikHazir => switch (this) {
        gramAltin || dolar || euro => true,
        fon || hisse => false,
      };

  /// Döviz seçeneğinin `dovizOptions` etiketi; döviz değilse `null`.
  String? get dovizEtiketi => switch (this) {
        dolar => 'USD',
        euro => 'EUR',
        _ => null,
      };
}
