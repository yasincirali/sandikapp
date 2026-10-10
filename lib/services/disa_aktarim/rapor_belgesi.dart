import 'package:flutter/foundation.dart';

/// Dışa aktarılan belgenin biçimden bağımsız hâli (Premium, 2026-10-10).
///
/// Aynı içerik iki biçime yazılır: Excel (`xlsx_yazici.dart`) ve PDF
/// (`pdf_yazici.dart`). İçerik bir kez kurulur (`rapor_belgeleri.dart`),
/// yazıcılar yalnız biçimler; iki dosyanın sayıları bu yüzden ayrışamaz.
///
/// Hücre değeri `String`, `num`, `DateTime` ya da `null`. Para tutarı
/// [TlTutar] ile sarılır ki Excel'de sayı (toplanabilir), PDF'te `fmtTRY`
/// biçimli metin olsun; yüzde ve miktar düz `num`.
@immutable
class RaporBelgesi {
  const RaporBelgesi({
    required this.baslik,
    required this.altBaslik,
    required this.ozet,
    required this.tablolar,
    required this.dipnotlar,
    required this.dosyaAdi,
  });

  /// Belge başlığı ("sandık · 2025 yıllık rapor").
  final String baslik;

  /// Kimin, ne zaman (kullanıcı adı, oluşturma tarihi).
  final String altBaslik;

  /// Üstteki özet: etiket → değer (değer [TlTutar], `String` ya da `null`).
  final List<(String, Object?)> ozet;

  final List<RaporTablosu> tablolar;

  /// Altta: kaynak ve sınırlar ("vergi beyannamesi değildir" vb.).
  final List<String> dipnotlar;

  /// Uzantısız dosya adı (ASCII, boşluksuz).
  final String dosyaAdi;
}

@immutable
class RaporTablosu {
  const RaporTablosu({
    required this.baslik,
    required this.sutunlar,
    required this.satirlar,
    this.toplam,
  });

  /// Excel'de sayfa adı da budur (31 karaktere kısaltılır).
  final String baslik;
  final List<String> sutunlar;
  final List<List<Object?>> satirlar;

  /// İsteğe bağlı toplam satırı (sütun sayısıyla aynı uzunlukta).
  final List<Object?>? toplam;
}

/// TL tutarı: Excel'de sayı, PDF'te `fmtTRY`.
@immutable
class TlTutar {
  const TlTutar(this.deger);
  final double deger;

  @override
  bool operator ==(Object other) => other is TlTutar && other.deger == deger;

  @override
  int get hashCode => deger.hashCode;
}
