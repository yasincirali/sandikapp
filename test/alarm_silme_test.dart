import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/widgets/delete_asset_dialog.dart';

/// Varlık silinince ÖKSÜZ kalan alarmlar bulunmalı.
///
/// ## Kullanıcı bildirimi (2026-09-16)
///
/// "Varlık eklenip alarm eklendiğinde, sonra varlığı silip geri eklediğimde
/// hâlâ alarm var gibi görünüyor — alarmı da silmeli."
///
/// ## Kök neden
///
/// Alarm varlığa DEĞİL sembole bağlı: `price_alerts` tablosunda `asset_id`
/// kolonu yok, yalnızca `symbol` (bkz. 0046_price_alerts.sql). Bu kasıtlı
/// bir tasarım — "gram altın 5.400 olunca haber ver" portföyde altın
/// olmasa da anlamlı bir istek.
///
/// Ama silme akışı (`confirmAndDeletePosition`) alarmlara HİÇ dokunmuyordu.
/// Alarm sunucuda kalıyor, aynı sembol yeniden eklenince zil rozetinde
/// beliriyor ve kullanıcı hiç kurmadığı bir alarmı görüyordu.
///
/// ## Çözüm ve neden "sor"
///
/// Sessizce silmek yerine kullanıcıya soruluyor (kullanıcı kararı): alarm
/// bağımsız bir kayıt olduğu için "portföyden çıktım ama fiyatı izlemeye
/// devam edeyim" meşru bir istek. Bu test sorunun KİME sorulacağını, yani
/// hangi alarmların öksüz kaldığını kilitliyor.
void main() {
  Asset lot({
    required String id,
    String ticker = 'THYAO.IS',
    String? subCategory,
    AssetKind kind = AssetKind.buy,
    double qty = 10,
    AssetType type = AssetType.hisse,
  }) =>
      Asset(
        id: id,
        userId: 'u1',
        name: 'Test',
        ticker: ticker,
        type: type,
        quantity: qty,
        purchasePrice: 100,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        subCategory: subCategory,
        kind: kind,
        addedDate: DateTime(2026, 1, 1),
      );

  PriceAlert alarm(String symbol, {String id = 'al1'}) => PriceAlert(
        id: id,
        userId: 'u1',
        symbol: symbol,
        label: symbol,
        targetPrice: 300,
        direction: 'above',
        enabled: true,
        createdAt: DateTime(2026, 1, 1),
      );

  test('silinen varlığın alarmı ÖKSÜZ kalır — bildirilen arıza', () {
    final sonuc = oksuzKalanAlarmlar(
      silinen: [lot(id: 'a1')],
      kalanVarliklar: const [],
      alarmlar: [alarm('THYAO.IS')],
    );
    expect(sonuc, hasLength(1),
        reason: 'Sembolün başka sahibi yok; alarm sorulmalı.');
  });

  test('AYNI sembolden başka pozisyon varsa alarm öksüz DEĞİL', () {
    // Asıl risk: fazla silme. Kullanıcı aynı sembolden iki ayrı pozisyon
    // tutuyor olabilir; birini silince öteki hâlâ duruyor ve alarm geçerli.
    // Bu kontrol olmadan kullanıcı sahip olduğu varlığın alarmını kaybeder.
    final sonuc = oksuzKalanAlarmlar(
      silinen: [lot(id: 'a1')],
      kalanVarliklar: [lot(id: 'a2')],
      alarmlar: [alarm('THYAO.IS')],
    );
    expect(sonuc, isEmpty);
  });

  test('BAŞKA sembolün alarmına dokunulmaz', () {
    final sonuc = oksuzKalanAlarmlar(
      silinen: [lot(id: 'a1', ticker: 'THYAO.IS')],
      kalanVarliklar: const [],
      alarmlar: [alarm('ASELS.IS'), alarm('THYAO.IS', id: 'al2')],
    );
    expect(sonuc.map((a) => a.symbol), ['THYAO.IS']);
  });

  test('altın alt kategorisi doğru eşlenir — ticker DEĞİL', () {
    // Altında alarm sembolü alt kategoridir (ALTIN_GRAM), ticker değil.
    // `alarmSembolu` ile aynı eşleme kullanılmazsa bu durum sessizce
    // ıskalanır ve altın alarmları hiç temizlenmez.
    final sonuc = oksuzKalanAlarmlar(
      silinen: [
        lot(
          id: 'g1',
          ticker: 'GRAMALTIN',
          subCategory: 'ALTIN_GRAM',
          type: AssetType.altin,
        ),
      ],
      kalanVarliklar: const [],
      alarmlar: [alarm('ALTIN_GRAM')],
    );
    expect(sonuc, hasLength(1));
  });

  test('tamamı SATILMIŞ pozisyon sahip sayılmaz', () {
    // `aktifLotlar` net miktarı 0'a düşen pozisyonu elemeli. Ham defteri
    // saymak "hâlâ sahibim" yanılgısı üretir ve alarm hiç temizlenmezdi.
    final sonuc = oksuzKalanAlarmlar(
      silinen: [lot(id: 'a1')],
      kalanVarliklar: [
        lot(id: 'b1', ticker: 'ASELS.IS'),
        lot(id: 'b2', ticker: 'ASELS.IS', kind: AssetKind.sell),
      ],
      alarmlar: [alarm('ASELS.IS')],
    );
    // ASELS satılıp bitmiş; silinen THYAO. ASELS'in alarmı BU silmenin
    // konusu değil — yalnızca silinen sembole bakılır.
    expect(sonuc, isEmpty);
  });

  test('alarm yoksa soru sorulmaz — akış değişmez', () {
    expect(
      oksuzKalanAlarmlar(
        silinen: [lot(id: 'a1')],
        kalanVarliklar: const [],
        alarmlar: const [],
      ),
      isEmpty,
    );
  });

  test('sembolsüz varlık (manuel fiyat) alarm aramaz', () {
    // Ticker'ı olmayan varlığa zaten alarm kurulamıyor (`alarmSembolu`
    // null döner). Boş sembolle arama yapmak TÜM alarmları eşleştirebilirdi.
    final sonuc = oksuzKalanAlarmlar(
      silinen: [lot(id: 'a1', ticker: '')],
      kalanVarliklar: const [],
      alarmlar: [alarm('THYAO.IS'), alarm('', id: 'bos')],
    );
    expect(sonuc, isEmpty);
  });

  test('çok lotlu pozisyonun TEK alarmı bir kez döner', () {
    final sonuc = oksuzKalanAlarmlar(
      silinen: [lot(id: 'a1'), lot(id: 'a2'), lot(id: 'a3')],
      kalanVarliklar: const [],
      alarmlar: [alarm('THYAO.IS')],
    );
    expect(sonuc, hasLength(1), reason: 'Lot başına tekrar etmemeli.');
  });
}
