import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/eurobond.dart';
import 'package:portfoy_takip/models/tur_secici_duzeni.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';

/// Varlık Ekle "gruplu ızgara + arama" seçicisinin saf kuralları (bayrak
/// `tur_secici_izgara`, 2026-10-08). Süzme kuralları eski çip satırıyla
/// birebir olmalı: bayrağı kapalı tür sızmaz, sözleşmeli tür yalnız yeni
/// kayıtta.

bool _hepsi(AssetType _) => true;
bool _eurobondsuz(AssetType t) => t != AssetType.eurobond;

final _tr28 = EurobondSozlesmesi(
  isin: 'US900123DF45',
  ad: 'Türkiye %9,875 2028',
  paraBirimi: 'USD',
  kuponOrani: 0.09875,
  vade: DateTime.utc(2028, 1, 15),
  ihracTarihi: DateTime.utc(2018, 1, 15),
  ihracci: EurobondIhracci.hazine,
);

void main() {
  group('gruplar', () {
    test('her tür tam bir grupta (yeni tür unutulursa ızgarada görünmez)',
        () {
      final say = <AssetType, int>{};
      for (final kutular in turGruplariTam.values) {
        for (final k in kutular) {
          if (k.abd) continue; // ABD ayrı tür değil, hisse kutusunun eşi.
          say[k.tur] = (say[k.tur] ?? 0) + 1;
        }
      }
      expect(say.keys.toSet(), AssetType.values.toSet());
      expect(say.values.every((n) => n == 1), isTrue, reason: '$say');
    });

    test('her şey açık: üç grup, istenen sıra', () {
      final g = turSeciciGruplari(
          turAcik: _hepsi, abdAcik: true, sozlesmeliAcik: true);
      expect(g.map((e) => e.$1).toList(), TurGrubu.values);
      expect(g[0].$2, const [
        TurKutusu(AssetType.hisse),
        TurKutusu(AssetType.hisse, abd: true),
        TurKutusu(AssetType.fon),
        TurKutusu(AssetType.kripto),
      ]);
      expect(g[1].$2, const [
        TurKutusu(AssetType.doviz),
        TurKutusu(AssetType.altin),
        TurKutusu(AssetType.eurobond),
        TurKutusu(AssetType.emtia),
      ]);
      expect(g[2].$2, const [
        TurKutusu(AssetType.mevduat),
        TurKutusu(AssetType.bes),
        TurKutusu(AssetType.diger),
      ]);
    });

    test('bayraklar kapalı: ABD ve eurobond kutusu yok', () {
      final g = turSeciciGruplari(
          turAcik: _eurobondsuz, abdAcik: false, sozlesmeliAcik: true);
      final hepsi = [for (final e in g) ...e.$2];
      expect(hepsi.any((k) => k.abd), isFalse);
      expect(hepsi.any((k) => k.tur == AssetType.eurobond), isFalse);
      expect(hepsi.length, 9);
    });

    test('sepet/düzenleme: mevduat ve BES yok, Birikim yalnız Diğer', () {
      final g = turSeciciGruplari(
          turAcik: _hepsi, abdAcik: true, sozlesmeliAcik: false);
      expect(g.last.$1, TurGrubu.birikim);
      expect(g.last.$2, const [TurKutusu(AssetType.diger)]);
    });

    test('seçili kutu: ABD yalnız hissede', () {
      expect(seciliKutu(AssetType.hisse, isAbd: true),
          const TurKutusu(AssetType.hisse, abd: true));
      expect(seciliKutu(AssetType.hisse, isAbd: false),
          const TurKutusu(AssetType.hisse));
      expect(seciliKutu(AssetType.altin, isAbd: true),
          const TurKutusu(AssetType.altin));
    });
  });

  group('ipucu — yalnız var olan bilgiden', () {
    test('BIST seansı ve kripto 7/24; ABD ve eurobond için uydurma yok', () {
      expect(
          turKutusuIpucu(const TurKutusu(AssetType.hisse),
              bistSeansAcik: true),
          TurIpucu.bistAcik);
      expect(
          turKutusuIpucu(const TurKutusu(AssetType.hisse),
              bistSeansAcik: false),
          TurIpucu.bistKapali);
      expect(
          turKutusuIpucu(const TurKutusu(AssetType.kripto),
              bistSeansAcik: false),
          TurIpucu.yediYirmiDort);
      expect(
          turKutusuIpucu(const TurKutusu(AssetType.hisse, abd: true),
              bistSeansAcik: true),
          isNull);
      expect(
          turKutusuIpucu(const TurKutusu(AssetType.eurobond),
              bistSeansAcik: true),
          isNull);
    });
  });

  group('arama sonuçları', () {
    const hits = [
      SymbolHit(ticker: 'THYAO.IS', name: 'Türk Hava Yolları', source: 'BIST'),
      SymbolHit(ticker: 'XU100.IS', name: 'BIST 100 Endeksi', source: 'Endeks'),
      SymbolHit(ticker: 'BZ=F', name: 'Petrol (Brent)', source: 'Emtia'),
      SymbolHit(ticker: 'AAPL', name: 'Apple', source: 'ABD'),
      SymbolHit(ticker: 'TEFAS:AFA', name: 'AK Portföy Amerikan', source: 'Fon'),
      SymbolHit(ticker: 'KRIPTO:BTC', name: 'Bitcoin', source: 'Kripto'),
      SymbolHit(ticker: 'ALTIN_GRAM', name: '22 Ayar Gram Altın', source: 'Altın'),
      SymbolHit(ticker: 'USDTRY=X', name: 'Amerikan Doları', source: 'Döviz'),
    ];

    test('tür ve kimlik eşlemesi; endeks ve emtia vadelisi listelenmez', () {
      final s = turAramaSonuclari(hits,
          turAcik: _hepsi, abdAcik: true, limit: 10);
      expect(s.map((e) => e.etiket).toList(), [
        PazarEtiketi.bist,
        PazarEtiketi.abd,
        PazarEtiketi.tefas,
        PazarEtiketi.kripto,
        PazarEtiketi.altin,
        PazarEtiketi.doviz,
      ]);
      expect(s[0].kutu, const TurKutusu(AssetType.hisse));
      expect(s[0].ticker, 'THYAO.IS');
      expect(s[0].sembol, 'THYAO');
      expect(s[1].kutu, const TurKutusu(AssetType.hisse, abd: true));
      expect(s[1].ticker, 'AAPL');
      expect(s[2].kutu.tur, AssetType.fon);
      expect(s[2].sembol, 'AFA');
      expect(s[3].kutu.tur, AssetType.kripto);
      expect(s[3].sembol, 'BTC');
      expect(s[4].altin, GoldSubCategory.gr22);
      expect(s[5].dovizEtiketi, 'USD');
    });

    test('ABD bayrağı kapalıyken ABD sonucu yok', () {
      final s = turAramaSonuclari(hits,
          turAcik: _hepsi, abdAcik: false, limit: 10);
      expect(s.any((e) => e.kutu.abd), isFalse);
    });

    test('gizli tür aramada da yok', () {
      final s = turAramaSonuclari(hits,
          turAcik: (t) => t != AssetType.kripto, abdAcik: true, limit: 10);
      expect(s.any((e) => e.kutu.tur == AssetType.kripto), isFalse);
    });

    test('eurobond: bayrak açıkken katalogdan, en fazla 2 yer ayrılır', () {
      final eb = [(_tr28, null), (_tr28, null), (_tr28, null)];
      final acik = turAramaSonuclari(hits,
          eurobondlar: eb, turAcik: _hepsi, abdAcik: true);
      expect(acik.length, 6);
      expect(acik.where((e) => e.etiket == PazarEtiketi.eurobond).length, 2);
      expect(acik.last.eurobond!.$1.isin, 'US900123DF45');
      expect(acik.last.kutu, const TurKutusu(AssetType.eurobond));

      final kapali = turAramaSonuclari(hits,
          eurobondlar: eb, turAcik: _eurobondsuz, abdAcik: true);
      expect(kapali.any((e) => e.etiket == PazarEtiketi.eurobond), isFalse);
      expect(kapali.length, 6);
    });

    test('aynı sembol iki kez gelmez', () {
      final s = turAramaSonuclari(const [
        SymbolHit(ticker: 'THYAO.IS', name: 'Türk Hava Yolları', source: 'BIST'),
        SymbolHit(ticker: 'THYAO.IS', name: 'Türk Hava Yolları', source: 'BIST'),
      ], turAcik: _hepsi, abdAcik: true);
      expect(s.length, 1);
    });
  });
}
