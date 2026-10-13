import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/portfoy_yorumu_service.dart';

/// AI portföy yorumu (0145) — istemci tarafı değişmezler.
///
/// Sunucu aynı kuralları `supabase/tests/portfoy_yorum_test.ts`'te sınar;
/// iki taraf ayrışırsa sunucu paketi reddeder ve kart "yorum alınamadı" der.
/// Bu dosya üç şeyi kilitler:
///   · Dönem: sunucunun `beklenenDonem` örnekleriyle aynı takvim kuralı.
///   · Paket: TL tutarı YOK, gösterimler sunucunun kabul ettiği biçimde.
///   · Parmak izi: küçük fiyat oynaması yorumu eskitmez, pay değişimi eskitir.

// Sunucudaki `_shared/portfoy_yorum.ts` gösterim kalıplarının aynısı.
final _gosterimKaliplari = [
  RegExp(r'^[+−]?%-?\d{1,3}(?:\.\d{3})?(?:,\d{1,2})?$'),
  RegExp(r'^[+−]?\d{1,3}(?:,\d{1,2})? puan$'),
  RegExp(r'^\d{1,4} gün$'),
  RegExp(r'^\d{1,3}$'),
];

Asset _lot(String id, String ticker, AssetType type, double qty) => Asset(
      id: id,
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 110,
      addedDate: DateTime(2026, 9, 1),
    );

Map<int, double> _gunluk(DateTime bas, int n, double Function(int i) f) => {
      for (var i = 0; i < n; i++)
        DateTime(bas.year, bas.month, bas.day + i, 18).millisecondsSinceEpoch:
            f(i),
    };

PortfoyYorumPaketi _paket({double fonCarpan = 1}) {
  final hisse = _lot('a', 'THYAO', AssetType.hisse, 1000);
  final fon = _lot('b', 'TTE', AssetType.fon, 500);
  final d = yorumDonemi(YorumTuru.haftalik, DateTime(2026, 10, 13, 9));
  final bas = DateTime(2026, 9, 28);
  final h = _gunluk(bas, 14, (i) => 100000 + i * 1500.0 - (i == 9 ? 6000 : 0));
  final f = _gunluk(bas, 14, (i) => (60000 - i * 300.0) * fonCarpan);
  final total = {for (final k in h.keys) k: h[k]! + f[k]!};
  final bd = PortfolioHistoryBreakdown(
    total: total,
    byType: {AssetType.hisse: h, AssetType.fon: f},
    byPosition: {positionKey(hisse): h, positionKey(fon): f},
    positionType: {
      positionKey(hisse): AssetType.hisse,
      positionKey(fon): AssetType.fon,
    },
  );
  final adlar = {positionKey(hisse): 'THYAO', positionKey(fon): 'TTE'};
  String et(String k) => adlar[k] ?? k;
  final son = DateTime(d.bitis.year, d.bitis.month, d.bitis.day, 23, 59, 59);
  final ozet = PeriodSummaryService.compute(
    period: SummaryPeriod.birHafta,
    assets: [hisse, fon],
    breakdown: bd,
    now: son,
    pencereBaslangici: d.baslangic,
    etiket: et,
  );
  return PortfoyYorumPaketi.kur(
    tur: YorumTuru.haftalik,
    baslangic: d.baslangic,
    bitis: d.bitis,
    ozet: ozet,
    breakdown: bd,
    etiket: et,
  );
}

void main() {
  group('dönem — sunucuyla aynı örnekler', () {
    String aralik(YorumTuru t, DateTime s) {
      final d = yorumDonemi(t, s);
      return '${isoGun(d.baslangic)}..${isoGun(d.bitis)}';
    }

    test('hafta: yalnız kapanmış Pzt–Paz', () {
      expect(aralik(YorumTuru.haftalik, DateTime(2026, 10, 13, 9)),
          '2026-10-05..2026-10-11');
      // Pazar: içinde bulunulan hafta henüz kapanmadı.
      expect(aralik(YorumTuru.haftalik, DateTime(2026, 10, 11, 23)),
          '2026-09-28..2026-10-04');
      expect(aralik(YorumTuru.haftalik, DateTime(2026, 10, 12)),
          '2026-10-05..2026-10-11');
    });

    test('ay: önceki takvim ayı', () {
      expect(aralik(YorumTuru.aylik, DateTime(2026, 10, 13)),
          '2026-09-01..2026-09-30');
      expect(aralik(YorumTuru.aylik, DateTime(2026, 1, 5)),
          '2025-12-01..2025-12-31');
      expect(aralik(YorumTuru.aylik, DateTime(2026, 3, 1)),
          '2026-02-01..2026-02-28');
    });
  });

  group('paket', () {
    test('tutar yok, her gösterim sunucu kalıbında', () {
      final p = _paket();
      expect(p.yeterli, isTrue);
      final anahtarlar = p.olcumler.map((o) => o.anahtar).toList();
      expect(anahtarlar, contains('getiri'));
      expect(anahtarlar.toSet().length, anahtarlar.length,
          reason: 'yinelenen anahtar sunucuda reddedilir');
      expect(p.olcumler.length, lessThanOrEqualTo(30));
      for (final o in p.olcumler) {
        expect(tutarIziVar(o.ad), isFalse, reason: o.ad);
        expect(_gosterimKaliplari.any((r) => r.hasMatch(o.gosterim)), isTrue,
            reason: '${o.anahtar}: "${o.gosterim}" sunucu kalıbına uymuyor');
      }
      final json = p.toJson();
      expect(json['baslangic'], '2026-10-05');
      expect(json['bitis'], '2026-10-11');
    });

    test('tutar izi: para birimi ve 4+ hane yakalanır', () {
      for (final m in ['₺412 bin', 'Değer 412000', '1.250 TL', 'USD bazında']) {
        expect(tutarIziVar(m), isTrue, reason: m);
      }
      for (final m in ['Dönem getirisi', 'En büyük pay: THYAO']) {
        expect(tutarIziVar(m), isFalse, reason: m);
      }
    });
  });

  group('parmak izi', () {
    test('ham anahtar sızmaz ve kararlıdır', () {
      final iz = portfoyParmakIzi({'hisse:THYAO': 60, 'fon:TTE': 40});
      expect(iz, startsWith('v1:'));
      expect(iz, isNot(contains('THYAO')));
      expect(portfoyParmakIzi({'fon:TTE': 40, 'hisse:THYAO': 60}), iz);
    });

    test('küçük oynama eskitmez, pay değişimi eskitir', () {
      final iz = portfoyParmakIzi({'hisse:THYAO': 60, 'fon:TTE': 40});
      expect(portfoyParmakIzi({'hisse:THYAO': 61, 'fon:TTE': 40}), iz);
      expect(portfoyParmakIzi({'hisse:THYAO': 80, 'fon:TTE': 20}), isNot(iz));
      expect(portfoyParmakIzi({'hisse:THYAO': 60, 'fon:TTE': 40, 'x:Y': 30}),
          isNot(iz));
    });

    test('paket: dönem sonu payı değişirse iz değişir', () {
      expect(_paket().parmakIzi, _paket(fonCarpan: 1.01).parmakIzi);
      expect(_paket().parmakIzi, isNot(_paket(fonCarpan: 3).parmakIzi));
    });
  });

  test('saklı satır okunur, kanıt çipleri eşleşir', () {
    final y = PortfoyYorumu.fromRow({
      'tur': 'haftalik',
      'donem': '2026-10-05',
      'bitis': '2026-10-11',
      'parmak_izi': 'v1:abc',
      'baslik': 'Portföyün bu hafta +%4,2 değer kazandı.',
      'maddeler': [
        {
          'metin': 'Artışın büyük kısmı THYAO\'dan geldi.',
          'kanit': ['getiri', 'yok']
        },
        {'metin': 5},
      ],
      'olcumler': [
        {'anahtar': 'getiri', 'ad': 'Dönem getirisi', 'gosterim': '+%4,2'},
      ],
      'olusturuldu': '2026-10-12T07:00:00Z',
    })!;
    expect(y.maddeler, hasLength(1));
    expect(y.kanitlar(y.maddeler.single.kanit).single.gosterim, '+%4,2');
  });
}
