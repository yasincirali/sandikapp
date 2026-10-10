import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/gorunum_kapsami.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';

import 'helpers/kaynak.dart';

/// Tek kapsam kaynağı (çoklu portföy adım 0, 2026-10-10): "görünen lotlar"
/// yedi yüzeyde elle kuruluyordu; hepsi `gorunum_kapsami.dart`'a bağlandı.
///
/// Bu dosya SAF REFACTOR'ün kanıtıdır: eski elle kurulan listeler aşağıda
/// AYNEN (ekranlardan kopyalanmış hâlleriyle) duruyor ve yeni fonksiyonun
/// her kapsamda aynı lotları AYNI SIRAYLA ürettiği, tek sahipli kapsamda
/// aynı liste NESNESİNİ döndürdüğü denetlenir. Portföy süzgecinin kendi
/// testleri `coklu_portfoy_test.dart`'ta.

Asset _lot(String id, String owner, String ticker,
        {AssetType type = AssetType.hisse,
        AssetKind kind = AssetKind.buy,
        double qty = 10,
        String? portfoy,
        DateTime? deleted}) =>
    Asset(
      id: id,
      userId: owner,
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 120,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
      deletedAt: deleted,
      portfoyId: portfoy,
    );

// ── ESKİ YOLLAR (ekranlardan birebir) ──────────────────────────────────────

/// `portfolio_screen` / `portfolio_performance_screen` (2026-10-10 öncesi).
List<List<Asset>> _eskiOwnerLots(
    String? view, List<Asset> mine, Map<String, List<Asset>> partnerMap) {
  final List<List<Asset>> ownerLots;
  if (view == '') {
    ownerLots = [mine];
  } else if (view != null) {
    ownerLots = [partnerMap[view] ?? const []];
  } else {
    ownerLots = [mine, ...partnerMap.values];
  }
  return ownerLots;
}

/// `home_screen.ledgerAssets` ve `all_transactions_screen._ledger`.
List<Asset> _eskiLedger(
    String? view, List<Asset> mine, Map<String, List<Asset>> partners) {
  if (view == '') return mine;
  if (view != null && view.isNotEmpty) return partners[view] ?? const [];
  return [
    ...mine,
    for (final list in partners.values) ...list,
  ];
}

/// `home_screen.gorunumVarliklari`.
List<Asset> _eskiGorunumVarliklari(
    String? view, List<Asset> mine, Map<String, List<Asset>> partners) {
  if (view == '') return gosterilecekVarliklar(mine);
  if (view != null && view.isNotEmpty) {
    return gosterilecekVarliklar(partners[view] ?? const []);
  }
  return [
    ...gosterilecekVarliklar(mine),
    for (final list in partners.values) ...gosterilecekVarliklar(list),
  ];
}

/// `watchlist_provider.kiyasVarliklari` (pasif ortak kuralıyla).
List<Asset> _eskiKiyas(String? view, List<Asset> myAssets,
    Map<String, List<Asset>> partnerAssets, Set<String> activePartnerIds) {
  List<Asset> aktif(String id) => activePartnerIds.contains(id)
      ? (partnerAssets[id] ?? const [])
      : const [];
  if (view == '') return myAssets;
  if (view != null) return aktif(view);
  return <Asset>[
    ...myAssets,
    for (final id in activePartnerIds) ...aktif(id),
  ];
}

List<String> _ids(Iterable<Asset> l) => [for (final a in l) a.id];

void main() {
  final mine = [
    _lot('m1', 'me', 'THYAO'),
    _lot('m2', 'me', 'THYAO', kind: AssetKind.sell, qty: 4),
    _lot('m3', 'me', 'AKBNK', type: AssetType.fon),
    _lot('m4', 'me', 'SISE', deleted: DateTime(2026, 2, 1)),
    _lot('m5', 'me', 'KCHOL', kind: AssetKind.dividend, qty: 0),
  ];
  final partners = <String, List<Asset>>{
    'p1': [
      _lot('a1', 'p1', 'THYAO'),
      _lot('a2', 'p1', 'GARAN', type: AssetType.fon),
    ],
    'p2': [_lot('b1', 'p2', 'KCHOL')],
  };
  const views = <String?>['', 'p1', 'p2', 'yok', null];

  group('eski elle kurulan listelerle BİREBİR', () {
    for (final v in views) {
      test('sahip defterleri — kapsam ${v ?? "Birlikte"}', () {
        final eski = _eskiOwnerLots(v, mine, partners);
        final yeni =
            kapsamSahipDefterleri(kisi: v, benim: mine, ortaklar: partners);
        expect(
            [for (final l in yeni) _ids(l)], [for (final l in eski) _ids(l)]);
        // Sahip başına toplam aynı (aggregate sahiplik sınırı korunur).
        expect(ownerScopedTotalValue(yeni), ownerScopedTotalValue(eski));
        expect(ownerScopedGainLoss(yeni), ownerScopedGainLoss(eski));
      });

      test('düz defter — kapsam ${v ?? "Birlikte"}', () {
        final eski = _eskiLedger(v, mine, partners);
        final yeni = kapsamDefteri(kisi: v, benim: mine, ortaklar: partners);
        expect(_ids(yeni), _ids(eski));
      });

      test('ana sayfa görünüm varlıkları — kapsam ${v ?? "Birlikte"}', () {
        final eski = _eskiGorunumVarliklari(v, mine, partners);
        final yeni = [
          for (final l in kapsamSahipDefterleri(
              kisi: v, benim: mine, ortaklar: partners))
            ...gosterilecekVarliklar(l),
        ];
        expect([for (final a in yeni) '${a.id}|${a.quantity}|${a.totalValue}'],
            [for (final a in eski) '${a.id}|${a.quantity}|${a.totalValue}']);
      });

      test('tür süzgeci (Performans keep) — kapsam ${v ?? "Birlikte"}', () {
        // `portfolio_performance_screen` `keep()`: filtre hem düz listeye
        // hem sahip gruplarına AYNI uygulanır.
        bool keep(Asset a) => a.isActive && a.type == AssetType.hisse;
        final eski = [
          for (final l in _eskiOwnerLots(v, mine, partners))
            l.where(keep).toList()
        ];
        final yeni = [
          for (final l in kapsamSahipDefterleri(
              kisi: v, benim: mine, ortaklar: partners))
            l.where(keep).toList()
        ];
        expect(
            [for (final l in yeni) _ids(l)], [for (final l in eski) _ids(l)]);
      });
    }
  });

  group('pasif ortak (kiyasVarliklari kuralı)', () {
    // p2 haritada ama aktif değil.
    const aktif = {'p1'};
    for (final v in views) {
      test('kapsam ${v ?? "Birlikte"}', () {
        final eski = _eskiKiyas(v, mine, partners, aktif);
        final yeni = kiyasVarliklari(
            view: v,
            myAssets: mine,
            partnerAssets: partners,
            activePartnerIds: aktif);
        expect(_ids(yeni), _ids(eski));
      });
    }

    test('pasif ortağın lotu Birlikte\'ye girmez', () {
      final r = kapsamDefteri(
          kisi: null, benim: mine, ortaklar: partners, aktifOrtaklar: aktif);
      expect(_ids(r), isNot(contains('b1')));
    });
  });

  group('kimlik (önbellekler identical karşılaştırır)', () {
    test('Ben + Tümü: aynı liste nesnesi', () {
      expect(
          identical(
              kapsamDefteri(kisi: '', benim: mine, ortaklar: partners), mine),
          isTrue);
      expect(
          identical(
              kapsamSahipDefterleri(kisi: '', benim: mine, ortaklar: partners)
                  .single,
              mine),
          isTrue);
    });

    test('ortak: ortağın liste nesnesi', () {
      expect(
          identical(kapsamDefteri(kisi: 'p1', benim: mine, ortaklar: partners),
              partners['p1']),
          isTrue);
    });

    test('portföy değeri olan lot portföy seçilmeden süzülmez', () {
      // Bayrak kapalıyken seçim hep Tümü: sunucudan portföylü satır gelse
      // bile hiçbir kapsam onu ayırmaz.
      final karisik = [
        ...mine,
        _lot('m9', 'me', 'EREGL', portfoy: 'emeklilik'),
      ];
      expect(
          identical(kapsamDefteri(kisi: '', benim: karisik, ortaklar: partners),
              karisik),
          isTrue);
    });
  });

  group('kaynak sözleşmesi: ekranlar kapsamı elle kurmaz', () {
    // Yeni bir yüzey "if (_view == '') ... else ..." kopyasını geri
    // getirirse portföy süzgeci orada uygulanmaz ve aynı portföy iki
    // ekranda iki toplam gösterir.
    const dosyalar = [
      'lib/screens/home_screen.dart',
      'lib/screens/portfolio_screen.dart',
      'lib/screens/portfolio_performance_screen.dart',
      'lib/screens/all_transactions_screen.dart',
    ];
    for (final d in dosyalar) {
      test(d, () {
        final k = ekranKaynagiSync(d).replaceAll(RegExp(r'\s+'), ' ');
        expect(k, contains('kapsam'),
            reason: '$d kapsamı gorunum_kapsami üzerinden kurmalı');
        expect(k.contains('ownerLots = [pState.assets'), isFalse);
        expect(k.contains('...partnerMap.values'), isFalse);
        expect(
            k.contains('for (final list in allPartnerAssets.values) ...list'),
            isFalse);
        expect(
            k.contains(
                'for (final list in widget.allPartnerAssets.values) ...list'),
            isFalse);
      });
    }
  });
}
