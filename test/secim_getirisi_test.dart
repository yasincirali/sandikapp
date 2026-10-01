// Seçimlerinin getirisi (TWR) — istemci çekirdeği, SUNUCUYLA EŞLİK testi.
//
// Senaryo "Yarış Ölçüsü Kıyası" sayfasının (2026-10-01) sekiz oyuncusu:
// X dalgalı (100 → dip 80 → 120), Y sakin (100 → 110 → 105); ay = 30 gün,
// Ay 0 bugünden 360 gün önce. Beklenen sayılar o sayfanın TWR sütunu.
// Sunucu eşi aynı senaryoyu `supabase/tests/leaderboard_snapshot_test.ts`
// içinde `donemTwr` ile koşar — iki motor ayrışırsa biri kırılır.
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/secim_getirisi.dart';

const _gunMs = 24 * 60 * 60 * 1000;
final _now = DateTime.utc(2026, 9, 28, 15, 40).millisecondsSinceEpoch;

const _ay = 30;
const _xAy = [100, 104, 107, 110, 100, 90, 80, 88, 96, 104, 110, 118, 120];
const _yAy = [100, 101, 102, 103, 104, 106, 110, 109, 107, 106, 105, 105, 105];
int _ayAni(int ay) => _now - (360 - ay * _ay) * _gunMs;

List<(int, double)> _seri(List<int> f) =>
    [for (var ay = 0; ay < f.length; ay++) (_ayAni(ay), f[ay].toDouble())];
final _piyasa = {'X.IS': _seri(_xAy), 'Y.IS': _seri(_yAy)};

var _no = 0;
Asset _hareket(
  String ticker,
  int ay,
  double tutar, {
  bool satis = false,
  int? girisAyi,
  double? miktar,
}) {
  final fiyat = (ticker == 'X.IS' ? _xAy : _yAy)[ay].toDouble();
  return Asset(
    id: 'r${++_no}',
    userId: 'u1',
    name: ticker,
    ticker: ticker,
    type: AssetType.hisse,
    quantity: miktar ?? tutar / fiyat,
    purchasePrice: fiyat,
    currency: 'TRY',
    notes: '',
    addedDate: DateTime.fromMillisecondsSinceEpoch(_ayAni(ay)),
    createdAt: DateTime.fromMillisecondsSinceEpoch(_ayAni(girisAyi ?? ay)),
    kind: satis ? AssetKind.sell : AssetKind.buy,
  );
}

double? _twr(List<Asset> defter,
        {int gun = 365, SiralamaKapsami kapsam = SiralamaKapsami.anonim}) =>
    secimGetirisiPct(
      gecmis: pozisyonGecmisleri(defter, kapsam),
      birimFiyat: (p, t) {
        final s = _piyasa[p.sablon.ticker];
        return s == null ? null : seriDegeriAninda(s, t);
      },
      yedekBirimFiyat: (p) => p.sablon.currentPrice,
      nowMs: _now,
      gun: gun,
    );

void main() {
  group('senaryo (sunucuyla aynı sayılar)', () {
    test('Ayşe, Burak, Cem: para zamanlaması sonucu değiştirmez (%20)', () {
      expect(_twr([_hareket('X.IS', 0, 100000)]), closeTo(20, 1e-9));
      expect(
          _twr([_hareket('X.IS', 0, 100000), _hareket('X.IS', 6, 100000)]),
          closeTo(20, 1e-9));
      expect(
          _twr([_hareket('X.IS', 0, 100000), _hareket('X.IS', 3, 100000)]),
          closeTo(20, 1e-9));
    });

    test('Deniz: Y\'yi satıp X alan kararıyla ölçülür (%65)', () {
      final y = _hareket('Y.IS', 0, 100000);
      final satis = _hareket('Y.IS', 6, 0, satis: true, miktar: y.quantity);
      final x = _hareket('X.IS', 6, 110000);
      expect(_twr([y, satis, x]), closeTo(65, 1e-9));
    });

    test('Hakan: girilen fiyat (1 TL) kullanılmaz, piyasa fiyatı (%50)', () {
      final h = _hareket('X.IS', 6, 0, miktar: 1250)..purchasePrice = 1;
      expect(_twr([h]), closeTo(50, 1e-9));
    });

    test('Ege: yalnız tuttuğu ay ölçülür (%1,69)', () {
      expect(_twr([_hareket('X.IS', 11, 1000)]),
          closeTo((120 / 118 - 1) * 100, 1e-9));
    });

    test('Fikret: küçük taban + büyük geç para şişirmez (%6,69)', () {
      final v = _twr([
        _hareket('Y.IS', 0, 10000),
        _hareket('X.IS', 11, 200000),
      ])!;
      final bekl = (1.05 *
                  ((100 * 105 + (200000 / 118) * 120) / (100 * 105 + 200000)) -
              1) *
          100;
      expect(v, closeTo(bekl, 1e-9));
      expect(v, closeTo(6.69, 0.01));
    });

    test('Gül: Ay 12\'de girilen "Ay 6" alımı girildiği an sayılır', () {
      // Giriş bugün → ilk alım bugün → 30 günlük asgari ölçüm yok.
      expect(_twr([_hareket('X.IS', 6, 100000, girisAyi: 12)]), isNull);
      // Eski bir hesaba eklenen geriye tarihli dip alımı sonucu değiştirmez.
      expect(
          _twr([
            _hareket('X.IS', 0, 100000),
            _hareket('X.IS', 6, 100000, girisAyi: 12),
          ]),
          closeTo(20, 1e-9));
    });
  });

  group('kurallar', () {
    test('ortaklar kapsamı beyan edilen tarihe güvenir (kullanıcı kararı)', () {
      // İçe aktarılan geçmiş: Ay 12'de girilen Ay 6 alımı. Ortaklar arası
      // Yarış'ta beyan geçerli (%50, dipten beri); anonimde girildiği an
      // sayılır ve 30 günlük ölçüm olmadığı için sıralamada yok.
      final ice = [_hareket('X.IS', 6, 100000, girisAyi: 12)];
      expect(_twr(ice, kapsam: SiralamaKapsami.ortaklar), closeTo(50, 1e-9));
      expect(_twr(ice, kapsam: SiralamaKapsami.anonim), isNull);
      // Tarihi dürüst kayıtta iki kapsam aynı sayıyı verir.
      final durust = [_hareket('X.IS', 0, 100000)];
      expect(_twr(durust, kapsam: SiralamaKapsami.ortaklar),
          _twr(durust, kapsam: SiralamaKapsami.anonim));
    });

    test('yarisAni: 3 gün pay, fazlası giriş anı, giriş anı yoksa tarih', () {
      Asset r(int eklenmeGun, int? girisGun) => Asset(
            id: 'a',
            userId: 'u1',
            name: 'A',
            ticker: 'A.IS',
            type: AssetType.hisse,
            quantity: 1,
            purchasePrice: 1,
            currency: 'TRY',
            notes: '',
            addedDate: DateTime.fromMillisecondsSinceEpoch(
                _now - eklenmeGun * _gunMs),
            createdAt: girisGun == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    _now - girisGun * _gunMs),
          );
      expect(yarisAni(r(2, 0), SiralamaKapsami.anonim), _now - 2 * _gunMs);
      expect(yarisAni(r(3, 0), SiralamaKapsami.anonim), _now - 3 * _gunMs);
      expect(yarisAni(r(4, 0), SiralamaKapsami.anonim), _now);
      expect(yarisAni(r(40, null), SiralamaKapsami.anonim), _now - 40 * _gunMs);
    });

    test('asgari 30 gün ölçüm; 7 günlük dönemde yalnız son 7 gün', () {
      Asset alim(int gunOnce) => Asset(
            id: 'g$gunOnce',
            userId: 'u1',
            name: 'X',
            ticker: 'X.IS',
            type: AssetType.hisse,
            quantity: 10,
            purchasePrice: 1,
            currency: 'TRY',
            notes: '',
            addedDate:
                DateTime.fromMillisecondsSinceEpoch(_now - gunOnce * _gunMs),
            createdAt:
                DateTime.fromMillisecondsSinceEpoch(_now - gunOnce * _gunMs),
          );
      expect(_twr([alim(20)], gun: 7), isNull);
      expect(_twr([alim(31)], gun: 7), closeTo((120 / 118 - 1) * 100, 1e-9));
    });

    test('kapsama: serisi olmayan lot bugünkü değerin %20\'sini aşarsa null',
        () {
      Asset yok(double fiyat) => Asset(
            id: 'z',
            userId: 'u1',
            name: 'YOK',
            ticker: 'YOK.IS',
            type: AssetType.hisse,
            quantity: 100,
            purchasePrice: fiyat,
            currentPrice: fiyat,
            currency: 'TRY',
            notes: '',
            addedDate: DateTime.fromMillisecondsSinceEpoch(_ayAni(0)),
            createdAt: DateTime.fromMillisecondsSinceEpoch(_ayAni(0)),
          );
      final x = _hareket('X.IS', 0, 100000); // bugün 120.000
      expect(_twr([x, yok(500)]), isNull);
      expect(_twr([x, yok(50)]), closeTo(20, 1e-9));
    });

    test('silinmiş lot ve mezar taşı miktara girmez', () {
      final silinen = _hareket('X.IS', 0, 100000)
          .copyWithDeletedAt(DateTime.fromMillisecondsSinceEpoch(_now));
      expect(pozisyonGecmisleri([silinen], SiralamaKapsami.anonim), isEmpty);
    });

    test('giriş anı sunucudan OKUNUR, istemci YAZMAZ (0095)', () {
      final m = {
        'id': 'a',
        'user_id': 'u1',
        'name': 'X',
        'ticker': 'X.IS',
        'type': 'hisse',
        'quantity': 1,
        'purchase_price': 1,
        'currency': 'TRY',
        'current_price': 1,
        'added_date': '2026-06-01T00:00:00+00:00',
        'created_at': '2026-09-28T10:00:00+00:00',
      };
      final a = Asset.fromSupabase(m);
      expect(a.createdAt?.toUtc(), DateTime.utc(2026, 9, 28, 10));
      // Tetikleyici her girişte `now()` basar; istemci gövdesi taşımamalı.
      expect(a.toSupabase().containsKey('created_at'), isFalse);
      // Silme kopyası giriş anını kaybetmez.
      expect(a.copyWithDeletedAt(null).createdAt, a.createdAt);
      // Sütun öncesi satır: null → tarih olduğu gibi.
      final eski = Asset.fromSupabase({...m}..remove('created_at'));
      expect(eski.createdAt, isNull);
      expect(yarisAni(eski, SiralamaKapsami.anonim),
          eski.addedDate.millisecondsSinceEpoch);
    });

    test('olcumAnlari: başlangıç, bugüne hizalı tam günler, bugün', () {
      final a = olcumAnlari(_now - 2 * _gunMs - 1000, _now);
      expect(a, [
        _now - 2 * _gunMs - 1000,
        _now - 2 * _gunMs,
        _now - _gunMs,
        _now,
      ]);
      expect(olcumAnlari(_now, _now), isEmpty);
    });
  });
}
