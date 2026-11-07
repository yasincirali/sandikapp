import 'package:flutter/foundation.dart';

import '../../models/asset_type.dart';

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
    this.belgeTuru = 'Rapor',
    this.oneCikanlar = const [],
    this.grafikler = const [],
    this.bolumler = const [],
    this.kampanya = 'rapor',
    this.kapsam,
    this.tablolarOnce = false,
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

  /// PDF bandındaki küçük tür etiketi ("Yıllık rapor", "Portföy dökümü").
  final String belgeTuru;

  /// "Öne çıkanlar" — kayıtlardan HESAPLANAN düz cümleler (yasin
  /// 2026-10-30: "yorumları da eklenmeli"). Tavsiye değil, ölçüm: "en büyük
  /// pay X", "en çok kazandıran Y". PDF'te özetin altında kutu; Excel'de
  /// Özet sayfasının sonunda. Sayı belgedeki tablolarla aynı kaynaktan.
  final List<String> oneCikanlar;

  /// PDF'te tabloların üstünde çizilen grafikler. Excel'e yazılmaz: aynı
  /// sayılar zaten tablolarda (grafik onların görsel özeti).
  final List<RaporGrafigi> grafikler;

  /// Metin bölümleri (aylık rapor, 2026-10-31): varlık başına başlık, durum
  /// etiketi ve maddeler. PDF'te öne çıkanların altında; Excel'de "Notlar"
  /// sayfasında satır satır. Tablolu raporlar kullanmaz.
  final List<RaporMetinBolumu> bolumler;

  /// PDF dipnotundaki "sandık ile hazırlandı" bağlantısının `utm_campaign`'i
  /// (belge türü; ör. `yillik_rapor`). Kaç kurulumu hangi belgenin
  /// getirdiği ölçülür; kişi ya da gönderen izlenmez.
  final String kampanya;

  /// Belgenin KAPSADIĞI dönem, tam cümle ("Kapsam: 1–31 Ekim 2026"). Başlık
  /// bloğunun alt satırının başına yazılır. yasin 2026-11-07: "tüm
  /// raporlarda kapsadığı dataların zaman aralığı belirtilmeli". Her rapor
  /// belgesi verir (`rapor_kapsam_satiri_test`); `null` yalnız eski çağrı
  /// uyumu için.
  final String? kapsam;

  /// Tablolar metin bölümlerinden ÖNCE mi? Aylık raporda sayılar (ayın
  /// varlıkları, para akışı) notlardan önce okunur; diğer belgeler eski
  /// sırada kalır.
  final bool tablolarOnce;
}

/// Bir metin bölümü: başlık ("THYAO"), isteğe bağlı durum etiketi
/// ("Alıcı istekli"), öz cümle ve maddeler.
@immutable
class RaporMetinBolumu {
  const RaporMetinBolumu({
    required this.baslik,
    required this.oz,
    this.etiket,
    this.maddeler = const [],
    this.grup,
    this.kisa = false,
  });

  final String baslik;
  final String? etiket;
  final String oz;
  final List<String> maddeler;

  /// Bu bölümden ÖNCE basılan grup başlığı ("Önemli gelişmeler"); aynı
  /// grubun yalnız ilk bölümünde dolu (aylık rapor, 2026-11-07).
  final String? grup;

  /// Kısa blok: öz cümle kalın değil, maddeler madde imsiz küçük satır —
  /// "her varlık tek satır" listesi tablo yerine (yasin 2026-11-07).
  final bool kisa;
}

/// Grafik türü: [dagilim] tek yığılmış çubuk + lejant (pay %), [cubuk]
/// yatay çubuklar (işaretli tutar; eksi sola, artı sağa değil — sıfırdan
/// sağa uzunluk, renk + işaret).
enum RaporGrafikTuru { dagilim, cubuk }

@immutable
class RaporGrafigi {
  const RaporGrafigi({
    required this.baslik,
    required this.tur,
    required this.kalemler,
    this.not,
    this.turler = const {},
  });

  final String baslik;
  final RaporGrafikTuru tur;

  /// (etiket, TL değeri). Dağılımda pay buradan hesaplanır.
  final List<(String, double)> kalemler;

  /// Dağılım satırının varlık türü (etiket → tür). PDF rengi buradan gelir,
  /// satır SIRASINDAN değil (müşteri raporu 6 Kas 15:15 #1): önceki sıralı
  /// palette en büyük kalem değişince renkler yer değiştiriyor, fon kâr
  /// yeşili gibi okunuyordu. Etikete bağlı harita, çünkü yazıcı sıfır/eksi
  /// kalemleri ayıklayınca sıra kayar. Türü olmayan satır nötr gri çizilir.
  final Map<String, AssetType> turler;

  /// Başlığın sağındaki küçük açıklama ("açık pozisyonlar, TL").
  final String? not;
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
