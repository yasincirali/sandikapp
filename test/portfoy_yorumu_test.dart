import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/destek_direnc.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/portfoy_yorumu_service.dart';
import 'package:portfoy_takip/services/varlik_istatistik.dart';

/// AI portföy yorumu (0145) — istemci tarafı değişmezler.
///
/// Sunucu aynı kuralları `supabase/tests/portfoy_yorum_test.ts`'te sınar;
/// iki taraf ayrışırsa sunucu paketi reddeder ve kart "yorum alınamadı" der.
/// Bu dosya üç şeyi kilitler:
///   · Dönem: sunucunun `beklenenDonem` örnekleriyle aynı takvim kuralı.
///   · Paket: TL tutarı YOK, gösterimler sunucunun kabul ettiği biçimde.
///   · Parmak izi: küçük fiyat oynaması yorumu eskitmez, pay değişimi eskitir.
///   · Seçili dönem / varlık (0151): pencere başı sunucunun `seciliBaslangic`
///     örnekleriyle aynı; varlık paketinde fiyat ve tutar yok; eski (0145)
///     istekte yeni alanlar hiç gönderilmez.

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

  group('seçili dönem ve varlık (0151)', () {
    test('pencere başı sunucuyla aynı örnekler', () {
      String bas(SummaryPeriod p, DateTime now) =>
          isoGun(PeriodSummaryService.pencere(p, now).start);
      // `supabase/tests/portfoy_yorum_test.ts` "seçili dönem başlangıcı".
      expect(bas(SummaryPeriod.birHafta, DateTime(2026, 10, 14, 9)), '2026-10-07');
      expect(bas(SummaryPeriod.birAy, DateTime(2026, 10, 14, 9)), '2026-09-14');
      expect(bas(SummaryPeriod.ucAy, DateTime(2026, 5, 31, 9)), '2026-02-28');
      expect(bas(SummaryPeriod.besYil, DateTime(2026, 10, 14, 9)), '2021-10-14');
      expect(seciliYorumlanabilir(SummaryPeriod.gunluk), isFalse);
      expect(seciliYorumlanabilir(SummaryPeriod.birYil), isTrue);
    });

    test('eski sözleşme: kapanmış dönem paketinde yeni alan yok', () {
      final j = _paket().toJson();
      expect(j.containsKey('donem_kodu'), isFalse);
      expect(j.containsKey('kapsam'), isFalse);
      expect(j.containsKey('varlik_izi'), isFalse);
    });

    PortfoyYorumPaketi varlik({String ad = 'Türk Hava Yolları'}) =>
        PortfoyYorumPaketi.varlikKur(
          period: SummaryPeriod.ucAy,
          baslangic: DateTime(2026, 7, 14),
          bitis: DateTime(2026, 10, 14),
          positionKey: 'hisse|THYAO|TRY',
          miktar: 1250,
          varlikAdi: ad,
          ist: const DonemIstatistigi(
            ilk: 280,
            son: 312,
            yuksek: 330,
            dusuk: 265,
            enBuyukDususPct: -9.4,
            oynaklikPct: 31.2,
            destekDirenc: DestekDirenc(
              destek: FiyatBolgesi(alt: 298, ust: 302.5, temas: 3),
              direnc: FiyatBolgesi(alt: 325, ust: 330, temas: 2),
            ),
          ),
          donemPct: 11.4,
          canliBirim: 314,
          portfoyPayi: 23.5,
          pozisyonGetirisi: 48.2,
          eldeGun: 412,
          kiyasDegisimi: const {
            KiyasVarligi.dolar: 3.1,
            KiyasVarligi.altin: 14.9,
            KiyasVarligi.bist100: 6.0,
          },
          tufe: YorumTufesi(
            enflasyonPct: 7.8,
            ilkAy: DateTime(2026, 6),
            sonAy: DateTime(2026, 9),
            nominalPct: 10.2,
            reelPct: 2.2,
            nominalAdi: 'pozisyonun',
          ),
        );

    test('varlık paketi: tutar yok, her gösterim sunucu kalıbında', () {
      final p = varlik();
      expect(p.yeterli, isTrue);
      final j = p.toJson();
      expect(j['tur'], 'secili');
      expect(j['donem_kodu'], '3A');
      expect(j['kapsam'], 'varlik');
      expect(j['varlik_izi'], matches(RegExp(r'^v1:[a-f0-9]{24}$')));
      expect(j['varlik_izi'].toString().contains('THYAO'), isFalse);
      expect(j['varlik_adi'], 'Türk Hava Yolları');
      final anahtarlar = p.olcumler.map((o) => o.anahtar).toList();
      expect(anahtarlar.toSet().length, anahtarlar.length);
      expect(anahtarlar, containsAll(<String>[
        'degisim', 'en_derin_dusus', 'oynaklik', 'zirveye_uzaklik',
        'dibe_uzaklik', 'portfoy_payi', 'pozisyon_getirisi', 'elde_tutma',
        'kiyas_dolar', 'kiyas_dolar_fark', 'kiyas_bist100', 'tufe',
        'tufe_nominal', 'tufe_fark', 'reel_getiri',
        'destek_uzaklik', 'destek_temas', 'direnc_uzaklik', 'direnc_temas',
      ]));
      for (final o in p.olcumler) {
        expect(tutarIziVar(o.ad), isFalse, reason: o.ad);
        expect(_gosterimKaliplari.any((r) => r.hasMatch(o.gosterim)), isTrue,
            reason: '${o.anahtar}: "${o.gosterim}" sunucu kalıbına uymuyor');
      }
      final g = {for (final o in p.olcumler) o.anahtar: o.gosterim};
      expect(g['degisim'], '+%11,4');
      expect(g['kiyas_altin_fark'], '−3,5 puan');
      expect(g['zirveye_uzaklik'], '−%4,8');
      expect(g['tufe'], '%7,8');
      expect(g['elde_tutma'], '412 gün');
      // Destek/direnç: seviye değil, canlı fiyata (314) yüzde uzaklık.
      expect(g['destek_uzaklik'], '+%3,8');
      expect(g['direnc_uzaklik'], '−%3,4');
      expect(g['destek_temas'], '3');
    });

    test('tutar izli varlık adı modele gitmez, ölçümler kalır', () {
      final p = varlik(ad: 'TR 2030 Eurobond');
      expect(p.toJson().containsKey('varlik_adi'), isFalse);
      expect(p.yeterli, isTrue);
    });

    test('varlık parmak izi: miktar değişince eskir', () {
      expect(varlikParmakIzi('hisse|THYAO|TRY', 1250),
          varlikParmakIzi('hisse|THYAO|TRY', 1250));
      expect(varlikParmakIzi('hisse|THYAO|TRY', 1250),
          isNot(varlikParmakIzi('hisse|THYAO|TRY', 1300)));
    });

    test('puan gösterimi sunucu kalıbında', () {
      expect(puanGosterimi(8.24), '+8,2 puan');
      expect(puanGosterimi(-0.04), '0,0 puan');
      expect(puanGosterimi(-12.5), '−12,5 puan');
      expect(puanGosterimi(1200), isNull);
    });

    test('TÜFE ayları yıl yazmadan', () {
      final t = YorumTufesi(
          enflasyonPct: 2.1, ilkAy: DateTime(2026, 8), sonAy: DateTime(2026, 9));
      expect(t.aralik, 'Eyl');
      final u = YorumTufesi(
          enflasyonPct: 30, ilkAy: DateTime(2025, 9), sonAy: DateTime(2026, 9));
      expect(u.aralik, 'Eki-Eyl');
      for (final o in u.olcumler()) {
        expect(tutarIziVar(o.ad), isFalse, reason: o.ad);
      }
    });
  });
}
