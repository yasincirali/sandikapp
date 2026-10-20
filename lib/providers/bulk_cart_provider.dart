import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset_type.dart';

/// Sepetteki vadeli mevduatın sözleşmesi (ekstreden, 2026-10-03).
///
/// Mevduat sözleşmeli türdür: lot tek başına anlamsız, birim değer faiz ve
/// vadeden hesaplanır. Kalem bu bilgiyi taşırsa toplu kayıt onu
/// `SozlesmeNotifier.mevduatAc` ile yazar (sözleşme + dönem + anapara lotu);
/// miktar = anapara, tarih = dönem başı.
typedef SepetMevduati = ({
  String kurum,
  double yillikFaiz,
  double stopaj,
  int vadeGun,
});

class BulkCartItem {
  BulkCartItem({
    required this.id,
    required this.type,
    required this.name,
    required this.ticker,
    required this.quantity,
    required this.price,
    required this.currency,
    required this.addedDate,
    this.subCategory,
    this.unitType = 'piece',
    this.isManualPrice = false,
    this.satis = false,
    this.mevduat,
    this.maliyetSonra = false,
    this.yol = 'toplu',
  });

  final String id;
  final AssetType type;
  final String name;
  final String ticker;
  final double quantity;
  final double price;
  final String currency;
  final String? subCategory;
  final String unitType;
  final bool isManualPrice;
  /// Kullanıcının bu varlığı hangi tarihte satın aldığını belirtir. Save
  /// aşamasında hem asset.addedDate olarak yazılır hem de fiyat boşsa bu
  /// tarihin kapanış fiyatı fetch edilir.
  final DateTime addedDate;

  /// Satış satırı mı (karar 5.4, 2026-09-30 — aracı kurum işlem ekstresi
  /// alım ve satımı birlikte verir). Satış kalemi toplu kayıtta alımlardan
  /// SONRA, tarih sırasıyla `addSellTransaction` ile yazılır; miktar o
  /// tarihte elde olandan fazlaysa yazılmaz (bkz. `IceAktarmaSatislari`).
  /// [price] satışta SATIŞ fiyatıdır.
  final bool satis;

  /// Doluysa kalem vadeli mevduattır ([type] `AssetType.mevduat`); formda
  /// düzenlenmez (ekleme formu sözleşme alanlarını taşımıyor).
  final SepetMevduati? mevduat;

  /// Maliyet okunamadı, kullanıcı sonra girecek (ekran görüntüsünden
  /// ekleme, 2026-10-19; `ekran_goruntusu_sepeti.dart`). Fiyat boştur;
  /// toplu kayıt o günün kapanışını yazar, sepet satırı bunu söyler.
  /// Kullanıcı fiyat girince düşer ([copyWith]).
  final bool maliyetSonra;

  /// Kalemin sepete hangi yoldan girdiği — `asset_added` olayının `yol`
  /// parametresi (ekleme yollarını sayma, 2026-10-20; 19 Kasım "hangi yolu
  /// sadeleştirelim" kararını besler). `toplu`: Toplu Ekle'de elle eklenen
  /// kalem; `ekstre`: metin/dosya içe aktarma; `ekran_goruntusu`.
  final String yol;

  BulkCartItem copyWith({
    AssetType? type,
    String? name,
    String? ticker,
    double? quantity,
    double? price,
    String? currency,
    String? subCategory,
    String? unitType,
    bool? isManualPrice,
    DateTime? addedDate,
    bool? satis,
    bool? maliyetSonra,
    String? yol,
  }) =>
      BulkCartItem(
        id: id,
        type: type ?? this.type,
        name: name ?? this.name,
        ticker: ticker ?? this.ticker,
        quantity: quantity ?? this.quantity,
        price: price ?? this.price,
        currency: currency ?? this.currency,
        subCategory: subCategory ?? this.subCategory,
        unitType: unitType ?? this.unitType,
        isManualPrice: isManualPrice ?? this.isManualPrice,
        addedDate: addedDate ?? this.addedDate,
        satis: satis ?? this.satis,
        mevduat: mevduat,
        // Fiyat girildiyse maliyet artık biliniyor.
        maliyetSonra:
            maliyetSonra ?? (price != null && price > 0 ? false : this.maliyetSonra),
        yol: yol ?? this.yol,
      );
}

class BulkCartNotifier extends Notifier<List<BulkCartItem>> {
  @override
  List<BulkCartItem> build() => const [];

  void add(BulkCartItem item) => state = [...state, item];

  void update(BulkCartItem item) => state = [
        for (final it in state) it.id == item.id ? item : it,
      ];

  void remove(String id) =>
      state = [for (final it in state) if (it.id != id) it];

  void clear() => state = const [];
}

final bulkCartProvider =
    NotifierProvider<BulkCartNotifier, List<BulkCartItem>>(BulkCartNotifier.new);
