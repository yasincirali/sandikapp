import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/analiz_provider.dart';
import 'package:portfoy_takip/services/aylik_rapor_kalemleri.dart';
import 'package:portfoy_takip/services/aylik_rapor_ozeti.dart';
import 'package:portfoy_takip/services/disa_aktarim/aylik_rapor_belgesi.dart';
import 'package:portfoy_takip/services/varlik_analizi.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Aylık rapor: tüm türler not alır, rapor önemli gelişmelerle başlar
/// (yasin 2026-11-07: "aylık raporda tüm varlıkları … yapay zekâyla
/// yorumlatmalıyız"; "not sayfası da rapor pdf'i de anlaşılır olmalı").
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('aylikNotAnahtari — sunucu lotSecimi ile aynı biçim', () {
    String? k(AssetType t, String s, {bool elle = false}) =>
        aylikNotAnahtari(tur: t, ticker: s, elleFiyat: elle);

    test('radar türleri eski anahtarla', () {
      expect(k(AssetType.hisse, 'thyao.is'), 'THYAO.IS');
      expect(k(AssetType.fon, 'TTE'), 'TEFAS:TTE');
      expect(k(AssetType.kripto, 'KRIPTO:BTC'), 'KRIPTO:BTC');
    });

    test('kök neden: ABD hissesi, altın, döviz, emtia, eurobond artık var', () {
      expect(k(AssetType.hisse, 'AAPL'), 'HISSE:AAPL');
      expect(k(AssetType.hisse, 'F'), 'HISSE:F');
      expect(k(AssetType.altin, 'ALTIN_CEYREK'), 'ALTIN:GRAM');
      expect(k(AssetType.altin, ''), 'ALTIN:GRAM');
      expect(k(AssetType.doviz, 'USDTRY=X'), 'USDTRY=X');
      expect(k(AssetType.emtia, 'GRAM:SI=F'), 'GRAM:SI=F');
      expect(k(AssetType.eurobond, 'EUROBOND:US900123CX66'),
          'EUROBOND:US900123CX66');
    });

    test('bilerek dışarıda: mevduat, diğer, USDT, elle fiyatlı', () {
      expect(k(AssetType.mevduat, 'MEVDUAT:x'), isNull);
      expect(k(AssetType.diger, 'EV'), isNull);
      expect(k(AssetType.kripto, 'KRIPTO:USDT'), isNull);
      expect(k(AssetType.hisse, 'AAPL', elle: true), isNull);
    });

    test('ekranda ham kod yok', () {
      expect(notKodu('HISSE:AAPL'), 'AAPL');
      expect(notKodu('USDTRY=X'), 'USD/TRY');
      expect(notKodu('KRIPTO:BTC'), 'BTC');
      expect(notKodu('EUROBOND:US900123CX66'), 'US900123CX66');
    });
  });

  final ay = DateTime.utc(2026, 10);
  AnalizOzeti not(String t, String rozet) => AnalizOzeti(
      ticker: t,
      donem: ay,
      baslik: '$t notu',
      rozet: rozet,
      maddeSayisi: 1,
      veriBaslangic: DateTime.utc(2026, 10, 1),
      veriBitis: DateTime.utc(2026, 10, 31));
  AyinVarligi varlik(String k, AssetType t, double pct) =>
      AyinVarligi(anahtar: k, tur: t, ad: k, pct: pct, piyasaTRY: pct * 100);

  test('raporKalemleri: önemli not önde ve bir kez; her pozisyon tek satır',
      () {
    final r = raporKalemleri(
      notlar: [
        not('THYAO.IS', 'sakin'),
        not('HISSE:AAPL', 'hareketli'),
        not('ALTIN:GRAM', 'hareketli'),
        not('TEFAS:TTE', 'buyuk_giris'),
      ],
      varliklar: [
        varlik('p-aapl', AssetType.hisse, 4),
        varlik('p-thy', AssetType.hisse, 8),
        varlik('p-ceyrek', AssetType.altin, -1),
        varlik('p-gram', AssetType.altin, -1.2),
      ],
      pozisyonlar: {
        'p-aapl': (notAnahtari: 'HISSE:AAPL', tur: AssetType.hisse, ad: 'AAPL'),
        'p-thy': (notAnahtari: 'THYAO.IS', tur: AssetType.hisse, ad: 'THYAO'),
        'p-ceyrek': (notAnahtari: 'ALTIN:GRAM', tur: AssetType.altin, ad: 'Altın'),
        'p-gram': (notAnahtari: 'ALTIN:GRAM', tur: AssetType.altin, ad: 'Altın'),
      },
      varlikAdi: (v) => v.anahtar,
      notAdi: notKodu,
    );
    // Rozet önemi: büyük giriş > hareketli; aynı kademede ada göre.
    expect(r.onemli.map((k) => k.not!.ticker),
        ['TEFAS:TTE', 'ALTIN:GRAM', 'HISSE:AAPL']);
    // Notu tek pozisyon taşıyorsa ayın sayısı karta eklenir; iki altın
    // lotunda eklenmez (yüzdeleri ayrı).
    expect(r.onemli[2].varlik?.anahtar, 'p-aapl');
    expect(r.onemli[1].varlik, isNull);
    expect(r.onemli[0].ad, 'TTE');
    // Her pozisyon satırda; sakin not ilk eşleşen satırın alt cümlesi.
    expect(r.diger.map((k) => k.ad), ['p-aapl', 'p-thy', 'p-ceyrek', 'p-gram']);
    expect(r.diger[1].not?.ticker, 'THYAO.IS');
    expect(r.diger[0].not, isNull, reason: 'önemli not satırda tekrar yok');
  });

  test('PDF kalem düzeni: önce önemli, sonra kısa bloklar; tablo yok', () {
    final b = aylikRaporBelgesi(
      donem: DateTime(2026, 10),
      notlar: const [
        AylikRaporNotu(
            kod: 'AAPL',
            tur: 'Hisse',
            baslik: 'AAPL yılın zirvesinde kapandı.',
            rozet: 'Hareketli',
            neOldu: 'Ayın değişimi +%4,0, piyasa etkisi +₺400',
            aralik: 'Not 1-31 Ekim 2026 verisinden'),
      ],
      satirlar: const [
        AylikRaporNotu(
            kod: 'THYAO',
            tur: 'Hisse',
            baslik: 'Sakin bir ay.',
            neOldu: '+%8,0 · +₺800'),
        AylikRaporNotu(kod: 'Vadeli', tur: 'Mevduat', baslik: ''),
      ],
      ozetCumlesi: 'x',
      eksikCumlesi: null,
      kim: 'demo',
      olusturma: DateTime(2026, 11, 1),
      varliklar: const [('THYAO', 8, 800)],
    );
    expect(b.tablolarOnce, isFalse);
    expect(b.tablolar.where((t) => t.baslik == 'Ayın varlıkları'), isEmpty);
    expect(b.bolumler.map((m) => m.baslik),
        ['AAPL · Hisse', 'THYAO · Hisse', 'Vadeli · Mevduat']);
    expect(b.bolumler[0].grup, 'Önemli gelişmeler');
    expect(b.bolumler[0].maddeler.first, startsWith('Ayın değişimi'));
    expect(b.bolumler[0].maddeler.last, startsWith('Not 1-31'));
    expect(b.bolumler[1].grup, 'Varlıklarının ayı');
    expect(b.bolumler[1].kisa, isTrue);
    expect(b.bolumler[2].grup, isNull);
  });
}
