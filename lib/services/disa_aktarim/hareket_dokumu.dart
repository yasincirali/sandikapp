import 'package:intl/intl.dart';

import '../../models/asset.dart';
import '../../utils/tr_format.dart';
import 'dosya_adi.dart';
import 'rapor_belgesi.dart';

/// "Verilerimi indir › Excel (tüm hareketler)" belgesi (Ar-Ge 7 Kas 20:30
/// #1, ücretsiz). Saf: dosya sistemi ve sağlayıcı yok, test edilir.
///
/// ## Neden
/// "Verilerimi indir" yalnız JSON veriyordu; sıradan kullanıcı ve mali
/// müşavir JSON açamaz. Premium portföy dökümünde de işlem tablosu var ama
/// o bir "an" belgesi (değerler, kâr/zarar) ve Premium. Veri taşınabilirliği
/// Premium'a konmaz: kullanıcının kendi girdisinin okunur kopyası herkese
/// açık. JSON yolu (KVKK m.11 tam döküm) aynen kalır.
///
/// ## Ne girer
/// HAM DEFTER, `aktifLotlar` değil: soru "bugün ne var" değil "ne yaptım"
/// (CLAUDE.md "Kapanmış pozisyon"). Kapanmış pozisyonun alış ve satışları
/// da girer. Girmeyen yalnız silinmiş kayıt (`isActive` = silinmemiş ve
/// mezar taşı değil): kullanıcı onu sildi, dökümde görmek istemez; JSON
/// dökümü silinmiş satırı da taşır.
///
/// ## Sütunlar
/// Varlık adı hareket listesindekiyle aynı (`TransactionRow`: kodu olan
/// hisse/fon/BES'te kod, diğerinde ad); ham sembol eki (`.IS`, `TEFAS:`)
/// yazılmaz. Fiyat, tutar ve komisyon varlığın PARA BİRİMİNDE: dökümde kur
/// çevrimi yok, müşavir gerekirse kendi kuruyla çevirir. Maliyeti
/// bilinmeyen alışta fiyat ve tutar boş (uydurma sayı yok). "Tutar" sütunu
/// görevde sayılmıyordu; temettünün ele geçen net tutarı başka hiçbir
/// sütuna sığmadığı için eklendi (alış/satışta miktar × birim fiyat).
const hareketSutunlari = [
  'Tarih',
  'Varlık',
  'Tür',
  'İşlem',
  'Miktar',
  'Birim fiyat',
  'Tutar',
  'Komisyon',
  'Para birimi',
  'Not',
];

/// Dökümün girdisi: silinmemiş, mezar taşı olmayan hareketler, eskiden
/// yeniye (müşavir defteri baştan okur). Eşit günde kayıt sırası.
List<Asset> dokumHareketleri(List<Asset> defter) => [
      for (final a in defter)
        if (a.isActive) a
    ]..sort((x, y) {
        final g = x.addedDate.compareTo(y.addedDate);
        if (g != 0) return g;
        final cx = x.createdAt, cy = y.createdAt;
        if (cx == null || cy == null) return 0;
        return cx.compareTo(cy);
      });

/// Kullanıcının hareket listesinde gördüğü ad.
String hareketVarlikAdi(Asset a) =>
    a.showTicker ? a.displayTicker! : a.name.trim();

String _islemAdi(Asset a) => switch (a.kind) {
      AssetKind.buy => 'Alış',
      AssetKind.sell => 'Satış',
      AssetKind.dividend => 'Temettü',
      // `dokumHareketleri` mezar taşını zaten ayıklar.
      AssetKind.deleteLog => 'Silme',
    };

/// Tek hareketin satırı ([hareketSutunlari] sırasıyla).
List<Object?> hareketSatiri(Asset a) {
  final temettu = a.isDividend;
  final double? fiyat = temettu
      ? null
      : a.isSell
          ? a.sellPrice
          : (a.maliyetBilinmiyor == true ? null : a.purchasePrice);
  final double? tutar =
      temettu ? a.dividendAmount : (fiyat == null ? null : fiyat * a.quantity);
  return [
    a.addedDate,
    hareketVarlikAdi(a),
    a.type.label,
    _islemAdi(a),
    temettu ? null : a.quantity,
    fiyat,
    tutar,
    a.commission == 0 ? null : a.commission,
    a.currency,
    a.notes.trim().isEmpty ? null : a.notes.trim(),
  ];
}

/// Tüm hareketlerin belgesi. Hiç hareket yoksa `null` (boş dosya
/// paylaşılmaz; ekran "henüz işlem yok" der).
///
/// Kapsam ilk hareketten belge gününe: döküm "bugüne kadar her şey" der,
/// son hareketten sonraki boşluk da bilgidir. Aralık hem ilk satırda
/// (başlık) hem dosya adında (yasin 2026-11-07 rapor tarih kuralı).
RaporBelgesi? hareketDokumuBelgesi({
  required List<Asset> defter,
  required String kim,
  required DateTime olusturma,
}) {
  final hareketler = dokumHareketleri(defter);
  if (hareketler.isEmpty) return null;
  final ilk = hareketler.first.addedDate;
  final son = hareketler.last.addedDate;
  // Gelecek tarihli kayıt varsa aralık onu da kapsar.
  final bit = son.isAfter(olusturma) ? son : olusturma;
  final aralik = fmtTarihAraligi(ilk, bit);
  return RaporBelgesi(
    belgeTuru: 'Tüm hareketler',
    kampanya: 'hareketler',
    baslik: 'sandık · tüm hareketler · $aralik',
    kapsam: 'Kapsam: $aralik',
    altBaslik:
        '$kim · ${DateFormat('dd.MM.yyyy HH:mm').format(olusturma)} itibarıyla',
    // PDF bandında tarih kapsam satırında bir kez; bantta yalnız kişi
    // (2026-11-10). Excel altBaslik'ı yazar.
    bantAlt: kim,
    dosyaAdi: belgeDosyaAdi(
        'Tüm Hareketler', '${gunDonemi(ilk)} - ${gunDonemi(bit)}'),
    ozet: [
      ('Hareket sayısı', '${hareketler.length}'),
      ('İlk hareket', fmtTarih(ilk)),
      ('Son hareket', fmtTarih(son)),
    ],
    tablolar: [
      RaporTablosu(
        baslik: 'Hareketler',
        sutunlar: hareketSutunlari,
        satirlar: [for (final a in hareketler) hareketSatiri(a)],
      ),
    ],
    dipnotlar: const [
      'Silinen kayıtlar dahil değil.',
      'Birim fiyat, tutar ve komisyon varlığın para biriminde. Maliyeti '
          'bilinmeyen alışta fiyat ve tutar boş.',
      'Temettü tutarı ele geçen net tutardır (stopaj sonrası).',
      'Tüm verilerinin makine okunur tam kopyası: Ayarlar › Verilerimi '
          'indir › JSON.',
    ],
  );
}
