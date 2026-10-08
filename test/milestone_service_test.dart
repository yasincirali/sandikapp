import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/birikim_serisi.dart';
import 'package:portfoy_takip/services/milestone_service.dart';

/// Kilometre taşı hesabı.
///
/// **Bu testlerin ilkesel çapası:** kutlanan şey BİRİKİMDİR, işlem değil.
/// Robinhood her işlem sonrası konfeti atıyordu ve Massachusetts uzlaşması
/// (7,5M$, Ocak 2024) tam olarak bunu hedef aldı. Buradaki eşiklerin
/// hiçbiri bir işleme bağlı olmamalı — testler bunu da kontrol ediyor.
Asset _lot({
  required String id,
  AssetType type = AssetType.hisse,
  String? subCategory,
  double quantity = 1,
  DateTime? addedDate,
  AssetKind kind = AssetKind.buy,
  DateTime? deletedAt,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Test $id',
      ticker: 'TST',
      notes: '',
      type: type,
      subCategory: subCategory,
      quantity: quantity,
      purchasePrice: 100,
      currency: 'TRY',
      currentPrice: 100,
      kind: kind,
      addedDate: addedDate ?? DateTime(2026, 1, 1),
      deletedAt: deletedAt,
    );

void main() {
  final now = DateTime(2026, 9, 6);

  group('portföy değeri', () {
    test('geçilen tüm eşikler döner, geçilmeyenler dönmez', () {
      final m = MilestoneService.evaluate(
        assets: [_lot(id: 'a')],
        totalTRY: 120000,
        now: now,
      ).where((e) => e.kind == 'portfolio_value').toList();

      expect(m.map((e) => e.value),
          containsAll(['10000', '25000', '50000', '100000']));
      expect(m.map((e) => e.value), isNot(contains('250000')));
    });

    test('boş portföyde hiçbir eşik yok', () {
      expect(
        MilestoneService.evaluate(assets: const [], totalTRY: 999999, now: now),
        isEmpty,
      );
    });

    test('silinmiş lot eşiği tetiklemez', () {
      final m = MilestoneService.evaluate(
        assets: [_lot(id: 'a', deletedAt: DateTime(2026, 5, 1))],
        totalTRY: 500000,
        now: now,
      );
      expect(m, isEmpty, reason: 'silinen varlık portföyde sayılmaz');
    });
  });

  group('altın adedi', () {
    test('adet üzerinden sayılır, gram karşılığı üzerinden değil', () {
      final m = MilestoneService.evaluate(
        assets: [
          _lot(
              id: 'g1',
              type: AssetType.altin,
              subCategory: 'ALTIN_CEYREK',
              quantity: 12),
        ],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'gold_count').toList();

      expect(m.map((e) => e.value), containsAll(['ALTIN_CEYREK:1',
          'ALTIN_CEYREK:5', 'ALTIN_CEYREK:10']));
      expect(m.map((e) => e.value), isNot(contains('ALTIN_CEYREK:25')));
    });

    test('aynı türün lotları toplanır', () {
      final m = MilestoneService.evaluate(
        assets: [
          _lot(id: 'g1', type: AssetType.altin, subCategory: 'ALTIN_GRAM', quantity: 3),
          _lot(id: 'g2', type: AssetType.altin, subCategory: 'ALTIN_GRAM', quantity: 2),
        ],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'gold_count').toList();
      expect(m.map((e) => e.value), contains('ALTIN_GRAM:5'));
    });

    test('küsurat aşağı yuvarlanır — 4,9 çeyrek 5 sayılmaz', () {
      final m = MilestoneService.evaluate(
        assets: [
          _lot(id: 'g', type: AssetType.altin, subCategory: 'ALTIN_CEYREK', quantity: 4.9),
        ],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'gold_count').toList();
      expect(m.map((e) => e.value), contains('ALTIN_CEYREK:1'));
      expect(m.map((e) => e.value), isNot(contains('ALTIN_CEYREK:5')));
    });
  });

  group('portföy yaşı', () {
    test('en ESKİ alım portföyün yaşını belirler', () {
      final m = MilestoneService.evaluate(
        assets: [
          _lot(id: 'a', addedDate: DateTime(2024, 1, 1)),
          _lot(id: 'b', addedDate: DateTime(2026, 8, 1)),
        ],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'portfolio_age').toList();
      expect(m.map((e) => e.value), containsAll(['1y', '2y']));
      expect(m.map((e) => e.value), isNot(contains('3y')));
    });

    test('bir yıldan yeni portföyde yaş eşiği yok', () {
      final m = MilestoneService.evaluate(
        assets: [_lot(id: 'a', addedDate: DateTime(2026, 6, 1))],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'portfolio_age');
      expect(m, isEmpty);
    });
  });

  // REGRESYON (2026-09-27): çıkış → giriş yapınca "2 yıldır takiptesin"
  // kutlaması ve ardından puan istemi geldi. Kutlama bir ANDIR; giriş ve
  // geçmiş tarihli veri girişi an değildir.
  group('ayir — doğru zaman', () {
    Milestone yas(String v) =>
        Milestone(kind: 'portfolio_age', value: v, title: '', body: '', rank: 1);
    const deger = Milestone(
        kind: 'portfolio_value', value: '2500000', title: '', body: '', rank: 2500000);

    test('girişten sonraki ilk ölçüm HİÇBİRİNİ kutlamaz, hepsi sessiz kaydedilir', () {
      final a = MilestoneService.ayir(
        yeniler: [yas('2y'), deger],
        assets: [_lot(id: 'a', addedDate: DateTime(2024, 9, 20))],
        now: DateTime(2026, 9, 27),
        girisSonrasi: true,
        ilkKez: false,
      );
      expect(a.kutla, isEmpty);
      expect(a.sessiz, hasLength(2));
    });

    test('yaş: yıl dönümü son 14 gündeyse kutlanır', () {
      final a = MilestoneService.ayir(
        yeniler: [yas('2y')],
        // 2 × 365 gün sonrası 26 Eylül 2026 → dünkü yıl dönümü.
        assets: [_lot(id: 'a', addedDate: DateTime(2024, 9, 27))],
        now: DateTime(2026, 9, 27),
        girisSonrasi: false,
        ilkKez: false,
      );
      expect(a.kutla.map((m) => m.value), ['2y']);
    });

    test('yaş: geçmiş tarihli alım GİRİLİNCE (yıl dönümü uzak) sessiz', () {
      final a = MilestoneService.ayir(
        yeniler: [yas('2y')],
        assets: [_lot(id: 'a', addedDate: DateTime(2023, 1, 1))],
        now: DateTime(2026, 9, 27),
        girisSonrasi: false,
        ilkKez: false,
      );
      expect(a.kutla, isEmpty);
      expect(a.sessiz.map((m) => m.value), ['2y']);
    });

    test('oturum içinde geçilen değer eşiği kutlanır', () {
      final a = MilestoneService.ayir(
        yeniler: [deger],
        assets: [_lot(id: 'a')],
        now: DateTime(2026, 9, 27),
        girisSonrasi: false,
        ilkKez: false,
      );
      expect(a.kutla, [deger]);
    });

    test('İLK ölçüm (mevcut portföy giriliyor) kutlamaz — canlı veri 26-27 Eylül', () {
      final a = MilestoneService.ayir(
        yeniler: [deger],
        assets: [_lot(id: 'a')],
        now: DateTime(2026, 9, 27),
        girisSonrasi: false,
        ilkKez: true,
      );
      expect(a.kutla, isEmpty);
      expect(a.sessiz, [deger]);
    });

    test('yaş metni kullanıcıya uydurma süre söylemez', () {
      final m = MilestoneService.evaluate(
        assets: [_lot(id: 'a', addedDate: DateTime(2024, 1, 1))],
        totalTRY: 1000,
        now: DateTime(2026, 9, 27),
      ).firstWhere((e) => e.kind == 'portfolio_age' && e.value == '2y');
      // Tarih kullanıcının girdiği İŞLEM tarihi — uygulamayı ne zamandır
      // kullandığı değil.
      expect(m.body, isNot(contains('takiptesin')));
      expect(m.body, contains('İlk alımın 2 yıl önceydi'));
    });
  });

  group('çeşitlendirme', () {
    test('farklı TÜR sayılır, farklı varlık değil', () {
      final ucTur = MilestoneService.evaluate(
        assets: [
          _lot(id: 'a', type: AssetType.hisse),
          _lot(id: 'b', type: AssetType.altin, subCategory: 'ALTIN_GRAM'),
          _lot(id: 'c', type: AssetType.doviz),
        ],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'diversification').toList();
      expect(ucTur.map((e) => e.value), contains('3types'));

      final ayniTur = MilestoneService.evaluate(
        assets: [
          _lot(id: 'a', type: AssetType.hisse),
          _lot(id: 'b', type: AssetType.hisse),
          _lot(id: 'c', type: AssetType.hisse),
        ],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'diversification');
      expect(ayniTur, isEmpty, reason: 'üç hisse çeşitlendirme değildir');
    });
  });

  group('pickOne', () {
    test('metin değil SAYISAL büyüklüğe göre seçer', () {
      // Bu testin sebebi gerçek bir hata: `value` metindir ve '25000'
      // metin olarak '100000'den büyüktür. Metinle sıralayan bir seçim,
      // 100 bin eşiği yerine 25 bini kutlardı.
      final secilen = MilestoneService.pickOne(const [
        Milestone(
            kind: 'portfolio_value',
            value: '25000',
            title: '',
            body: '',
            rank: 25000),
        Milestone(
            kind: 'portfolio_value',
            value: '100000',
            title: '',
            body: '',
            rank: 100000),
      ]);
      expect(secilen?.value, '100000');
    });

    test('öncelik: yaş > değer > altın > çeşitlendirme', () {
      final secilen = MilestoneService.pickOne(const [
        Milestone(kind: 'diversification', value: '3types', title: '', body: '', rank: 3),
        Milestone(kind: 'gold_count', value: 'ALTIN_GRAM:5', title: '', body: '', rank: 5),
        Milestone(kind: 'portfolio_value', value: '100000', title: '', body: '', rank: 100000),
        Milestone(kind: 'portfolio_age', value: '1y', title: '', body: '', rank: 1),
      ]);
      expect(secilen?.kind, 'portfolio_age',
          reason: 'yaş en nadir ve en duygusal eşik');
    });

    test('boş listede null', () {
      expect(MilestoneService.pickOne(const []), isNull);
    });
  });

  group('ilke kontrolü', () {
    test('hiçbir eşik İŞLEME bağlı değil', () {
      // Eşik türleri sabit bir küme: işlem sayısı, alım-satım sıklığı ya da
      // "bugün işlem yaptın" gibi bir kalem EKLENMEMELİ. Yeni bir tür
      // eklenirse bu test kırılır ve karar bilinçli verilir.
      const izinli = {
        'portfolio_value',
        'gold_count',
        'portfolio_age',
        'diversification',
        // 2026-10-05 (yasin kararı): art arda birikim AYI — süreklilik,
        // tek bir işlem değil. Tek alım hiçbir eşiği açmaz (3 ay gerekir).
        'contribution_streak',
      };
      final uretilen = MilestoneService.evaluate(
        assets: [
          _lot(id: 'a', type: AssetType.hisse, addedDate: DateTime(2023, 1, 1)),
          _lot(id: 'b', type: AssetType.altin, subCategory: 'ALTIN_CEYREK', quantity: 10),
          _lot(id: 'c', type: AssetType.doviz),
        ],
        totalTRY: 2000000,
        now: now,
        seri: _seri(guncel: 12, enUzun: 12, buAy: true),
      ).map((e) => e.kind).toSet();
      expect(uretilen.difference(izinli), isEmpty);
    });
  });

  group('birikim serisi', () {
    test('seri verilmezse eşik üretilmez (bayrak kapalı)', () {
      final m = MilestoneService.evaluate(
        assets: [_lot(id: 'a')],
        totalTRY: 100,
        now: now,
      );
      expect(m.where((e) => e.kind == 'contribution_streak'), isEmpty);
    });

    test('ulaşılan eşikler EN UZUN seriye göre', () {
      final m = MilestoneService.evaluate(
        assets: [_lot(id: 'a')],
        totalTRY: 100,
        now: now,
        seri: _seri(guncel: 2, enUzun: 7, buAy: true),
      ).where((e) => e.kind == 'contribution_streak').map((e) => e.value);
      expect(m, ['3m', '6m']);
    });

    test('yalnız bu ayın katkısı eşiğe getirdiyse kutlanır', () {
      final yeniler = MilestoneService.evaluate(
        assets: [_lot(id: 'a')],
        totalTRY: 100,
        now: now,
        seri: _seri(guncel: 6, enUzun: 6, buAy: true),
      ).where((e) => e.kind == 'contribution_streak').toList();
      final ayrim = MilestoneService.ayir(
        yeniler: yeniler,
        assets: [_lot(id: 'a')],
        now: now,
        girisSonrasi: false,
        ilkKez: false,
        seri: _seri(guncel: 6, enUzun: 6, buAy: true),
      );
      expect(ayrim.kutla.map((e) => e.value), ['6m']);
      expect(ayrim.sessiz.map((e) => e.value), ['3m']);
    });

    test('bu ay katkı yoksa (geriye dönük uzama) sessiz', () {
      final seri = _seri(guncel: 6, enUzun: 6, buAy: false);
      final yeniler = MilestoneService.evaluate(
              assets: [_lot(id: 'a')], totalTRY: 100, now: now, seri: seri)
          .where((e) => e.kind == 'contribution_streak')
          .toList();
      final ayrim = MilestoneService.ayir(
        yeniler: yeniler,
        assets: [_lot(id: 'a')],
        now: now,
        girisSonrasi: false,
        ilkKez: false,
        seri: seri,
      );
      expect(ayrim.kutla, isEmpty);
    });

    test('seri, portföy değerinden önce seçilir', () {
      final secilen = MilestoneService.pickOne(const [
        Milestone(
            kind: 'portfolio_value', value: '100000', title: '', body: '',
            rank: 100000),
        Milestone(
            kind: 'contribution_streak', value: '6m', title: '', body: '',
            rank: 6),
      ]);
      expect(secilen?.kind, 'contribution_streak');
    });
  });
}

BirikimSerisi _seri({
  required int guncel,
  required int enUzun,
  required bool buAy,
}) =>
    BirikimSerisi(
      guncel: guncel,
      enUzun: enUzun,
      kalanMola: 1,
      buAyKatkiVar: buAy,
      gecmisAy: enUzun + 1,
      serit: const [],
    );
