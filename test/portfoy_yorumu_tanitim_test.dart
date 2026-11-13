import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart' show positionKey;
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/portfoy_yorumu_service.dart';
import 'package:portfoy_takip/widgets/portfoy_yorumu_karti.dart';

/// Ücretsiz hesabın kilitli AI yorum kartı cümlesi (2026-11-13).
///
/// Kilitlenen: sayı yalnız cihazdaki paketten gelir; paket yeterli değilse,
/// getiri yoksa ya da %0,0'a yuvarlanıyorsa eski düz cümle kalır (uydurma
/// yok). "En çok etkileyen" TL katkısıdır, yüzde değil; akış düşülür ve
/// yalnız dönemin yönünde etki yapan aday olur.
PortfoyYorumPaketi _p(double? getiri, String? etkili,
        {YorumTuru tur = YorumTuru.aylik, bool yeterli = true}) =>
    PortfoyYorumPaketi(
      tur: tur,
      baslangic: DateTime(2026, 10, 1),
      bitis: DateTime(2026, 10, 31),
      parmakIzi: 'v1:t',
      olcumler: [
        if (yeterli) const YorumOlcumu('getiri', 'Dönem getirisi', '+%3,2'),
        const YorumOlcumu('pozisyon_sayisi', 'Dönem sonunda varlık sayısı', '4'),
      ],
      donemGetirisi: getiri,
      enEtkili: etkili,
    );

Asset _lot(String id, String ticker, DateTime added, {double qty = 10}) => Asset(
      id: id,
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 100,
      addedDate: added,
    );

void main() {
  final tr = lookupAppLocalizations(const Locale('tr'));
  const sabit = "Portföyünü yapay zekâyla yorumlamak Premium'da.";

  group('portfoyKilitMetni', () {
    test('artış + en etkili varlık', () {
      expect(portfoyKilitMetni(tr, _p(3.24, 'THYAO')),
          "Geçen ay portföyün %3,2 arttı, en çok THYAO etkiledi · nedenini yapay zekâ Premium'da anlatır.");
    });

    test('düşüş nötr "azaldı", varlık yoksa kısa cümle', () {
      expect(portfoyKilitMetni(tr, _p(-1.96, null)),
          "Geçen ay portföyün %2,0 azaldı · nedenini yapay zekâ Premium'da anlatır.");
    });

    test('haftalık dönem adı', () {
      expect(portfoyKilitMetni(tr, _p(0.5, 'ALTIN', tur: YorumTuru.haftalik)),
          startsWith('Geçen hafta portföyün %0,5 arttı'));
    });

    test('veri yok / yetersiz / sıfır → bugünkü cümle', () {
      expect(portfoyKilitMetni(tr, null), sabit);
      expect(portfoyKilitMetni(tr, _p(null, 'THYAO')), sabit);
      expect(portfoyKilitMetni(tr, _p(4.0, 'THYAO', yeterli: false)), sabit);
      expect(portfoyKilitMetni(tr, _p(0.04, 'THYAO')), sabit);
      expect(portfoyKilitMetni(tr, _p(double.nan, 'THYAO')), sabit);
    });

    test('paket sunucuya kilit alanlarını göndermez', () {
      final j = _p(3.2, 'THYAO').toJson();
      expect(j.containsKey('donem_getirisi'), isFalse);
      expect(j.toString().contains('THYAO'), isFalse);
    });
  });

  group('enEtkiliPozisyon', () {
    final bas = DateTime(2026, 10, 1);
    final son = DateTime(2026, 10, 31, 23, 59, 59);
    int ms(int gun) => DateTime(2026, 10, gun).millisecondsSinceEpoch;
    final thy = _lot('a', 'THYAO', DateTime(2026, 1, 1));
    final asl = _lot('b', 'ASELS', DateTime(2026, 1, 1));
    final sise = _lot('c', 'SISE', DateTime(2026, 1, 1));
    // ASELS'e ay içinde ₺1.000 alım: değeri 1.000 → 2.080, fiyat etkisi 80.
    final aslAlim = _lot('d', 'ASELS', DateTime(2026, 10, 15));
    final seri = {
      positionKey(thy): {ms(1): 1000.0, ms(31): 1100.0}, // +100
      positionKey(asl): {ms(1): 1000.0, ms(31): 2080.0}, // +1080 − 1000 akış
      positionKey(sise): {ms(1): 5000.0, ms(31): 4700.0}, // −300
    };
    final adlar = {for (final a in [thy, asl, sise]) positionKey(a): a.ticker};
    String et(String k) => adlar[k] ?? k;

    String? calis(double yon) => PeriodSummaryService.enEtkiliPozisyon(
          byPosition: seri,
          assets: [thy, asl, sise, aslAlim],
          fromMs: bas.millisecondsSinceEpoch,
          toMs: son.millisecondsSinceEpoch,
          yon: yon,
          etiket: et,
        );

    test('artan dönem: alım düşülür, TL katkısı en büyük olan', () {
      // Akış düşülmeseydi ASELS (+1.080) çıkardı; fiyat etkisi 80 < 100.
      expect(calis(1.2), 'THYAO');
    });

    test('azalan dönem: yalnız düşüş yönünde etki yapan', () {
      expect(calis(-0.8), 'SISE');
    });

    test('yön sıfır → isim yok', () {
      expect(calis(0), isNull);
    });
  });
}
