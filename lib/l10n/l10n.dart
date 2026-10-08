import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';
import 'generated/app_localizations_tr.dart';

export 'generated/app_localizations.dart';

/// `context.l10n` — arayüz metinlerinin tek kapısı (3.20).
///
/// Delegate yoksa (delegate'siz `MaterialApp` kuran widget testleri, erken
/// bir overlay) TÜRKÇE sınıfa düşer: uygulamanın ana dili Türkçe, "metin
/// bulunamadı" diye çökmek yerine Türkçe göstermek doğru geri dönüş.
///
/// Türkçe şablon, İngilizce çeviri `app_en.arb`'da. İngilizce henüz BETA:
/// yalnızca giriş/kayıt, gezinme, kilit, yasal uyarı, Ayarlar hub'ı ve
/// Görünüm, ana ekran/portföy boş durumları ve varlık ekleme formu
/// çevrildi; kalan ekranlar Türkçe kalır (`docs/YOL_HARITASI_ILERLEME.md`
/// 3.20 satırı). Yeni metin: önce `app_tr.arb` + `app_en.arb`, sonra
/// `flutter gen-l10n`, sonra `context.l10n.anahtar`.
extension L10nX on BuildContext {
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? AppLocalizationsTr();

  /// `intl` tarih biçimleyicilerinin (`DateFormat('d MMM', …)`) dili —
  /// arayüz diliyle aynı.
  ///
  /// Önerilen ortak yardımcı (2026-09-29 emülatör testi #27): kod tabanında
  /// ~40 `DateFormat(..., 'tr_TR')` sabit locale'le yazılmış; İngilizce modda
  /// "29 Eyl" çıkıyor. Hepsini tek turda çevirmek geniş bir değişiklik
  /// (grafik eksenleri, widget/Live Activity sözleşmeleri Türkçe kalmalı).
  /// Arayüz metni üreten yerler bu getter'a geçer; `bugun_karti`'ndaki
  /// `_dil` aynı kuralın eski kopyası. Delegate yoksa (test) Türkçe.
  ///
  /// Dil [l10n]'dan okunur, `Localizations.maybeLocaleOf`'tan değil
  /// (2026-10-01): delegate'siz `MaterialApp` locale'i yine `en_US` verir,
  /// yani metin Türkçe'ye düşerken tarih "Aug 25" yazıyordu — yukarıdaki
  /// "delegate yoksa Türkçe" sözü tutmuyordu. Metin ile tarih aynı
  /// kaynaktan dil alınca ikisi ayrışamaz.
  String get tarihDili => l10n.localeName == 'en' ? 'en_US' : 'tr_TR';
}

/// Miktar biriminin arayüz dilindeki yazımı.
///
/// `birimEtiketi` (models/asset.dart) birimi VERİ olarak üretir ("adet",
/// "gr", "lot", coin kodu) — model katmanı `BuildContext` bilmez. Yalnız
/// Türkçe kelime olan "adet" çevrilir; "gr"/"kg"/"lot"/"BTC" iki dilde aynı.
/// İngilizce modda "15 adet" yazıyordu (emülatör testi #27).
String birimMetni(AppLocalizations l, String birim) =>
    birim == 'adet' ? l.unitPiece : birim;

/// Dönem kimliği → ekranda görünen etiket (3.20).
///
/// İki ekranın (`portfolio_performance`, `asset_detail`) dönem listeleri
/// `static const` ve öyle kalmalı: indeksleri durum makinesinin parçası.
/// Bu yüzden listedeki Türkçe etiket artık bir KİMLİKTİR, gösterim buradan
/// geçer. Tanınmayan kimlik olduğu gibi döner (yeni dönem eklenirse sessizce
/// kaybolmasın).
String donemEtiketi(AppLocalizations l, String kimlik) => switch (kimlik) {
      'GÜNLÜK' => l.periodDaily,
      '1H' => l.period1W,
      '1A' => l.period1M,
      '3A' => l.period3M,
      '6A' => l.period6M,
      '1Y' => l.period1Y,
      '5Y' => l.period5Y,
      _ => kimlik,
    };

/// Dile duyarlı BÜYÜK HARF.
///
/// Dart'ın `toUpperCase()`'i Türkçe bilmez: "En iyi" → "EN IYI" (noktasız).
/// Türkçe'de i→İ ve ı→I ayrı harflerdir; "EN İYİ" yazılmalı. İngilizce'de
/// ise i→I doğru olan ("Annualized" → "ANNUALIZED"), o yüzden dönüşüm
/// yalnızca `localeName` Türkçeyken uygulanır. Etiketleri .arb'da hazır
/// büyük harfle tutmak yerine burada çevirmek, aynı anahtarın düz metin
/// olarak da kullanılabilmesini korur.
String ustHarf(String s, AppLocalizations l) {
  if (l.localeName.startsWith('tr')) {
    s = s.replaceAll('i', 'İ').replaceAll('ı', 'I');
  }
  return s.toUpperCase();
}
