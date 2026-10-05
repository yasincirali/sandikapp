import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/services/fon_akisi.dart';
import 'package:portfoy_takip/services/hisse_hacmi.dart';
import 'package:portfoy_takip/services/radar_okuma.dart';
import 'package:portfoy_takip/services/varlik_analizi.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart' show fonCumlesi;

/// Radar okunuşu (Balina F1 tamamlama, 2026-10-05) — saf kurallar.
///
/// ## Kilitlenen davranışlar
/// 1. Cümle ile işaret ÇELİŞMEZ: net > 0 iken cümle "girdi", < 0 iken
///    "çıktı", 0 iken "dengede" der (her kademe için).
/// 2. Sunucu olayı varsa kademe en üst; olay ters yöndeyse cümle yön
///    söylemez ("büyük para hareketi oldu").
/// 3. Geçmiş yetmezse ölçek yok (uydurma "olağan" yok).
/// 4. Eşikler: fon 1,5 / 3 kat; hacim 1,3 / 2 kat; kripto ±2 / ±5 puan.
/// 5. Saatlik akış 24 yuva, eksik saat boş, 3 saatten bayat → yok; net alım
///    formülü sunucuyla aynı.
/// 6. Not modeli: girdide olmayan kanıt anahtarı düşer, gösterim aynen kalır.
DateTime _g(int ay, int gun) => DateTime.utc(2026, ay, gun);

FonAkisOzeti _fon(double son,
    {List<double?> onceki = const [100e6, -100e6, 100e6, -100e6],
    List<FonBalinaOlayi> olaylar = const []}) {
  final haftalar = [
    for (var i = 0; i < onceki.length; i++)
      HaftaAkisi(
          baslangic: _g(9, 28).subtract(Duration(days: 7 * (onceki.length - i))),
          net: onceki[i]),
    HaftaAkisi(baslangic: _g(9, 28), net: son),
  ];
  return FonAkisOzeti(
    haftalar: haftalar,
    sonHaftaNet: son,
    sonHaftaIlkGun: _g(9, 28),
    veriTarihi: _g(10, 2),
    buyukluk: 5e9,
    yatirimci: null,
    yatirimciDegisimi: null,
    olaylar: olaylar,
    ay1: null,
    ay3: null,
    seri: null,
  );
}

FonBalinaOlayi _olay(double tutar, DateTime tarih) => FonBalinaOlayi(
    tarih: tarih, tutar: tutar, buyuklukOrani: 0.04, sapmaKati: 5);

HacimOzeti _hacim({
  double? kat,
  List<HacimOlayi> olaylar = const [],
  double? aliciPayi,
}) {
  final son = HacimGunu(
      tarih: _g(10, 2), kapanis: 10, paraHacmi: 1e9, aliciPayi: aliciPayi);
  return HacimOzeti(
    gunler: [son],
    sonGun: son,
    ortalama: kat == null ? null : 1e9 / kat,
    kat: kat,
    fiyatDegisim: 0.01,
    olaylar: olaylar,
    aliciPayi: aliciPayi,
  );
}

void main() {
  final l = AppLocalizationsTr();

  group('fon', () {
    test('cümle ve işaret çelişmez (her kademe)', () {
      for (final son in [
        -900e6, -250e6, -120e6, -40e6, 0.0, 40e6, 120e6, 250e6, 900e6,
      ]) {
        final o = fonOkunusu(_fon(son));
        final cumle = fonCumlesi(l, o);
        if (son > 0) {
          expect(cumle, contains('girdi'), reason: '$son');
          expect(cumle, isNot(contains('çıktı')));
        } else if (son < 0) {
          expect(cumle, contains('çıktı'), reason: '$son');
          expect(cumle, isNot(contains('girdi')));
        } else {
          expect(cumle, contains('dengedeydi'));
        }
      }
    });

    test('eşikler: 1,5 kat hareketli, 3 kat çok hareketli', () {
      // Önceki haftaların |net| ortalaması 100 mn.
      expect(fonOkunusu(_fon(149e6)).kademe, Kademe.sakin);
      expect(fonOkunusu(_fon(150e6)).kademe, Kademe.hareketli);
      expect(fonOkunusu(_fon(-299e6)).kademe, Kademe.hareketli);
      expect(fonOkunusu(_fon(300e6)).kademe, Kademe.cokHareketli);
      expect(fonOkunusu(_fon(300e6)).kat, closeTo(3, 1e-9));
    });

    test('geçmiş yetmezse ölçek yok; veri olmayan hafta sayılmaz', () {
      final o = fonOkunusu(_fon(500e6, onceki: [100e6, null, 100e6]));
      expect(o.kademe, isNull);
      expect(o.kat, isNull);
      expect(fonCumlesi(l, o), l.rdrFonGiris);
    });

    test('son haftada sunucu olayı → en üst kademe', () {
      final o = fonOkunusu(
          _fon(20e6, olaylar: [_olay(400e6, _g(9, 30))]));
      expect(o.kademe, Kademe.cokHareketli);
      expect(o.karsiYonOlay, isFalse);
    });

    test('olay net yönün tersiyse cümle yön söylemez', () {
      final o = fonOkunusu(
          _fon(20e6, olaylar: [_olay(-400e6, _g(9, 29))]));
      expect(o.yon, Yon.giris);
      expect(o.karsiYonOlay, isTrue);
      expect(fonCumlesi(l, o), l.rdrFonKarisik);
    });

    test('önceki haftanın olayı son haftayı etkilemez', () {
      final o = fonOkunusu(_fon(20e6, olaylar: [_olay(400e6, _g(9, 22))]));
      expect(o.kademe, Kademe.sakin);
    });
  });

  group('hacim', () {
    test('eşikler 1,3 / 2 kat; kat yoksa ölçek yok', () {
      expect(hacimKademesi(_hacim(kat: 1.29)), Kademe.sakin);
      expect(hacimKademesi(_hacim(kat: 1.3)), Kademe.hareketli);
      expect(hacimKademesi(_hacim(kat: 2)), Kademe.cokHareketli);
      expect(hacimKademesi(_hacim()), isNull);
    });

    test('son gün olağandışı hacim günüyse en üst kademe', () {
      final o = _hacim(kat: 1.1, olaylar: [
        HacimOlayi(
            tarih: _g(10, 2),
            yukselis: true,
            paraHacmi: 1e9,
            ortalamaKati: 3.4,
            fiyatDegisim: 0.05),
      ]);
      expect(hacimKademesi(o), Kademe.cokHareketli);
    });
  });

  group('kripto', () {
    test('±2 / ±5 puan; sakin bandında yön dengededir', () {
      expect(kriptoOkunusu(_hacim(aliciPayi: 0.515))!.yon, Yon.denge);
      expect(kriptoOkunusu(_hacim(aliciPayi: 0.515))!.kademe, Kademe.sakin);
      expect(kriptoOkunusu(_hacim(aliciPayi: 0.52))!.kademe, Kademe.hareketli);
      expect(kriptoOkunusu(_hacim(aliciPayi: 0.52))!.yon, Yon.giris);
      expect(kriptoOkunusu(_hacim(aliciPayi: 0.45))!.kademe,
          Kademe.cokHareketli);
      expect(kriptoOkunusu(_hacim(aliciPayi: 0.45))!.yon, Yon.cikis);
      expect(kriptoOkunusu(_hacim()), isNull);
    });
  });

  group('saatlik', () {
    final simdi = DateTime.utc(2026, 10, 5, 12, 20);
    KriptoSaati s(int saat, double para, double pay) => KriptoSaati(
        saat: DateTime.utc(2026, 10, 5, saat), paraHacmi: para, aliciPayi: pay);

    test('net alım = 2 × para × pay − para', () {
      expect(s(1, 100, 0.6).netAlim, closeTo(20, 1e-9));
      expect(s(1, 100, 0.4).netAlim, closeTo(-20, 1e-9));
      expect(s(1, 100, 0.5).netAlim, 0);
    });

    test('24 yuva, eksik saat boş, en istekli saat pozitif en büyük', () {
      final a = saatlikAkis([s(12, 100, 0.55), s(10, 300, 0.7), s(11, 50, 0.2)],
          simdi: simdi)!;
      expect(a.saatler, hasLength(24));
      expect(a.saatler.last!.saat.hour, 12);
      expect(a.saatler[a.saatler.length - 4], isNull);
      expect(a.enIstekli!.saat.hour, 10);
    });

    test('yalnız satış ağır basıyorsa en istekli saat yok', () {
      final a = saatlikAkis([s(12, 100, 0.4)], simdi: simdi)!;
      expect(a.enIstekli, isNull);
    });

    test('3 saatten eski veri → akış yok (kaynak durmuş)', () {
      expect(saatlikAkis([s(8, 100, 0.6)], simdi: simdi), isNull);
      expect(saatlikAkis(const [], simdi: simdi), isNull);
    });

    test('bozuk satır reddedilir', () {
      expect(
          KriptoSaati.satirdan(
              {'saat': '2026-10-05T10:00:00Z', 'para_hacmi': 1, 'alici_payi': 1.2}),
          isNull);
      expect(
          KriptoSaati.satirdan(
              {'saat': 'x', 'para_hacmi': 1, 'alici_payi': 0.5}),
          isNull);
    });
  });

  group('kategori sırası', () {
    test('tek fonlu kategori ya da eksik alan reddedilir', () {
      final tam = {
        'sira': 1,
        'fon_kodu': 'TTE',
        'net_akis': 1e8,
        'kendi': true,
        'kategori': 'Hisse Senedi Fonu',
        'fon_sayisi': 6,
      };
      expect(KategoriSirasi.satirdan(tam)!.kendi, isTrue);
      expect(KategoriSirasi.satirdan({...tam, 'fon_sayisi': 1}), isNull);
      expect(KategoriSirasi.satirdan({...tam, 'sira': 0}), isNull);
      expect(KategoriSirasi.satirdan({...tam}..remove('kategori')), isNull);
    });
  });

  group('not modeli', () {
    test('kanıt girdide yoksa düşer; gösterim yeniden biçimlenmez', () {
      final n = VarlikNotu.satirdan({
        'ticker': 'TEFAS:TTE',
        'tur': 'haftalik',
        'donem': '2026-09-28',
        'baslik': 'Fona geçen hafta +₺137,66M net para girdi.',
        'rozet': 'buyuk_giris',
        'maddeler': [
          {
            'metin': 'Net akış +₺137,66M oldu.',
            'kanit': ['net_akis', 'uydurma'],
          },
          {'metin': '  ', 'kanit': <String>[]},
        ],
        'girdi': {
          'kod': 'TTE',
          'baslangic': '2026-09-28',
          'bitis': '2026-10-04',
          'olcumler': [
            {
              'anahtar': 'net_akis',
              'ad': 'Son hafta net akış',
              'gosterim': '+₺137,66M',
              'kaynak': 'TEFAS',
              'tarih': '2026-10-02',
              'deger': 137660000,
            },
          ],
        },
      })!;
      expect(n.maddeler, hasLength(1));
      expect(n.maddeler.single.kanitlar.single.gosterim, '+₺137,66M');
      expect(n.kod, 'TTE');
      expect(n.kaynaklar, ['TEFAS']);
      expect(n.bitis, _g(10, 4));
    });

    test('başlıksız satır ve bozuk dönem reddedilir', () {
      expect(
          AnalizOzeti.satirdan(
              {'ticker': 'X', 'donem': '2026-09-28', 'baslik': ''}),
          isNull);
      expect(
          AnalizOzeti.satirdan(
              {'ticker': 'X', 'donem': 'dün', 'baslik': 'a'}),
          isNull);
      expect(
          AnalizOzeti.satirdan({
            'ticker': 'THYAO.IS',
            'donem': '2026-09-28',
            'baslik': 'a',
            'madde_sayisi': 3,
          })!
              .maddeSayisi,
          3);
    });
  });
}
