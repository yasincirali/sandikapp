import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/price_service.dart';

import 'helpers/kaynak.dart';

/// Kullanıcı kararı (2026-09-23): *"Veriler grafik performans ekranından da
/// performans sayfasında da tutarlı olmalıdır."*
///
/// ## Ölçülen ayrışma
/// Aynı gün, aynı portföy:
///
/// | Yüzey | Gram | Çeyrek |
/// |---|---|---|
/// | Varlık ekranı | −%0,78 | −%1,25 |
/// | Performans › Altın | −%1,11 | −%1,11 |
///
/// ## Kök neden
/// Canlı fiyat her ayar için AYRI kotasyondan gelir (truncgil `YIA`,
/// `CEYREKALTIN`…) ve işçilik primi gün içinde oynar. Grafik serisi ise TEK
/// kaynaktan türer (`gram22k × sabit ağırlık`) ve `altinKalibrasyonHaritasi`
/// SABİT bir çarpan uygular.
///
/// **Sabit çarpan yüzdeyi değiştiremez** — matematiksel olarak imkânsız:
/// `(x·k)/(y·k) = x/y`. Dolayısıyla Performans'ta tüm ayarlar ZORUNLU olarak
/// aynı yüzdeyi gösteriyordu. −%1,11 de portföy karışımının ağırlıklı
/// ortalamasıydı (gram ~%30 ağırlıkta: 0,30×0,78 + 0,70×1,25 = 1,11).
///
/// ## Çözüm
/// Serinin ŞEKLİ korunur, İKİ UCU ürünün kendi rakamlarına oturtulur.
void main() {
  group('çarpan neden yetmiyordu (kök neden kanıtı)', () {
    test('SABİT çarpan yüzdeyi DEĞİŞTİREMEZ', () {
      const ilk = 6174.68, son = 6126.21;
      final hamPct = (son / ilk - 1) * 100;
      for (final k in [0.9, 1.0, 1.03, 1.55]) {
        final kalibrePct = ((son * k) / (ilk * k) - 1) * 100;
        expect(kalibrePct, closeTo(hamPct, 1e-9),
            reason: 'çarpan oransaldır — seviyeyi kaydırır, eğimi DEĞİL');
      }
    });

    test('−%1,11 portföy karışımının ağırlıklı ortalaması', () {
      // Ekrandaki rakamın nereden geldiğini belgeler.
      const gramPct = 0.78, ceyrekPct = 1.25;
      const gramAgirlik = 0.30;
      final ortalama = gramAgirlik * gramPct + (1 - gramAgirlik) * ceyrekPct;
      expect(ortalama, closeTo(1.11, 0.01));
    });
  });

  group('ürün bazlı uçlar — varlık ekranıyla PARİTE', () {
    // Kullanıcının ekranındaki gerçek rakamlar.
    const seriIlk = 6174.68, seriSon = 6126.21; // ham gram22k, −%0,785

    test('her ayar KENDİ yüzdesini gösterir', () {
      for (final (tic, canli, pct) in [
        ('ALTIN_GRAM', 6126.21, -0.78),
        ('ALTIN_CEYREK', 10670.62, -1.25),
      ]) {
        final ag = PriceService.goldWeightFactor(tic);
        final u = altinUrunUclari(canliBirimTRY: canli, gunlukPct: pct)!;
        final ilk = altinUrunNoktasi(
            seriDeger: seriIlk * ag,
            ts: 0,
            seriIlk: seriIlk * ag,
            seriIlkTs: 0,
            seriSon: seriSon * ag,
            seriSonTs: 100,
            urunIlk: u.ilk,
            urunSon: u.son);
        final son = altinUrunNoktasi(
            seriDeger: seriSon * ag,
            ts: 100,
            seriIlk: seriIlk * ag,
            seriIlkTs: 0,
            seriSon: seriSon * ag,
            seriSonTs: 100,
            urunIlk: u.ilk,
            urunSon: u.son);
        expect((son / ilk - 1) * 100, closeTo(pct, 0.01),
            reason: '$tic: Performans varlık ekranıyla eşleşmeli');
      }
    });

    test('son nokta CANLI kotasyona oturur', () {
      final u = altinUrunUclari(canliBirimTRY: 10670.62, gunlukPct: -1.25)!;
      expect(u.son, 10670.62, reason: '`liveTotal` ezmesiyle uyumlu olmalı');
    });

    test('ilk nokta ürünün GÜN BAŞI fiyatı', () {
      final u = altinUrunUclari(canliBirimTRY: 10670.62, gunlukPct: -1.25)!;
      // 10670,62 / (1 − 0,0125) = 10805,69
      expect(u.ilk, closeTo(10805.69, 0.01));
    });
  });

  group('ŞEKİL korunur — uydurma dalga YOK', () {
    test('serideki tepe çizimde de tepe kalır', () {
      const ilk = 6174.68, son = 6126.21;
      final u = altinUrunUclari(canliBirimTRY: 10670.62, gunlukPct: -1.25)!;
      final ham = [ilk, 6200.0, 6150.0, son];
      final cizilen = [
        for (var i = 0; i < ham.length; i++)
          altinUrunNoktasi(
              seriDeger: ham[i],
              ts: i,
              seriIlk: ilk,
              seriIlkTs: 0,
              seriSon: son,
              seriSonTs: ham.length - 1,
              urunIlk: u.ilk,
              urunSon: u.son)
      ];
      expect(cizilen[1], greaterThan(cizilen[0]),
          reason: 'gün içi hareket gerçek veriden gelmeli');
      expect(cizilen[2], lessThan(cizilen[1]));
      expect(cizilen.last, closeTo(u.son, 0.01));
    });

    test('DÜZ ham seri iki uç arasında DOĞRU çizilir — dalga yok', () {
      // 2026-09-24'e kadar tüm gün ürünün SON değeri çiziliyordu: çizginin
      // başı, gösterilen yüzdeyle çelişiyordu.
      final u = altinUrunUclari(canliBirimTRY: 1000, gunlukPct: -1.0)!;
      double nokta(int ts) => altinUrunNoktasi(
          seriDeger: 500,
          ts: ts,
          seriIlk: 500,
          seriIlkTs: 0,
          seriSon: 500,
          seriSonTs: 10,
          urunIlk: u.ilk,
          urunSon: u.son);
      expect(nokta(0), closeTo(u.ilk, 1e-9));
      expect(nokta(5), closeTo((u.ilk + u.son) / 2, 1e-9));
      expect(nokta(10), closeTo(u.son, 1e-9));
    });
  });

  group('kullanıcı bildirimi 2026-09-24: "Altın neden bugün hep sabit geldi"',
      () {
    // Spot gün içinde +%0,9'a çıkıp +%0,5'te bitiyor; yurt içi günlük yüzde
    // ise (dünkü kapanıştan) yalnızca +%0,05.
    const ham = [6000.0, 6030.0, 6054.0, 6030.0];
    final u = altinUrunUclari(canliBirimTRY: 6100, gunlukPct: 0.05)!;
    List<double> ciz() => [
          for (var i = 0; i < ham.length; i++)
            altinUrunNoktasi(
                seriDeger: ham[i],
                ts: i,
                seriIlk: ham.first,
                seriIlkTs: 0,
                seriSon: ham.last,
                seriSonTs: ham.length - 1,
                urunIlk: u.ilk,
                urunSon: u.son)
        ];

    test('eski formül dalgayı yüzdeler oranında EZİYORDU (kanıt)', () {
      // ilk + (son − ilk) × ilerleme: genlik 0,05 / 0,5 = 1/10'a iner.
      final eski = [
        for (final v in ham)
          u.ilk + (u.son - u.ilk) * (v - ham.first) / (ham.last - ham.first)
      ];
      final tepe = (eski.reduce((a, b) => a > b ? a : b) / eski.first - 1);
      expect(tepe, lessThan(0.001),
          reason: 'gün içi +%0,9 tepe, %0,1 altına eziliyordu — %0,5 '
              'asgari eksen bandında çizgi düz görünür');
    });

    test('yeni formül dalgayı korur, uçlar ürünün kendi rakamı', () {
      final c = ciz();
      expect(c.first, closeTo(u.ilk, 1e-9));
      expect(c.last, closeTo(u.son, 1e-9));
      final tepe = c.reduce((a, b) => a > b ? a : b) / c.first - 1;
      // Spot tepesi +%0,9; iki yüzde arasındaki −%0,45'lik fark zamana
      // yayılır (tepe anında −%0,3) → ~+%0,6. Eski formülde +%0,09.
      expect(tepe, closeTo(0.006, 0.0005),
          reason: 'dalga görünür kalmalı');
      expect(c[2], greaterThan(c[1]));
      expect(c[3], lessThan(c[2]));
    });

    test('yüzdeler zıt işaretliyse eğri TERS dönmez', () {
      // Spot +%0,5, yurt içi −%0,2: eski formülde spot'un yükselişi
      // çizimde düşüş olurdu.
      final ters = altinUrunUclari(canliBirimTRY: 6100, gunlukPct: -0.2)!;
      final a = altinUrunNoktasi(
          seriDeger: 6000, ts: 0, seriIlk: 6000, seriIlkTs: 0,
          seriSon: 6030, seriSonTs: 3, urunIlk: ters.ilk, urunSon: ters.son);
      final b = altinUrunNoktasi(
          seriDeger: 6054, ts: 2, seriIlk: 6000, seriIlkTs: 0,
          seriSon: 6030, seriSonTs: 3, urunIlk: ters.ilk, urunSon: ters.son);
      expect(b, greaterThan(a), reason: 'spot tepesi çizimde de tepe');
    });
  });

  group('uydurma sayı yasağı (sözleşme maddesi 3)', () {
    test('günlük yüzde YOKSA null — eski çarpan yoluna düşülür', () {
      expect(altinUrunUclari(canliBirimTRY: 1000, gunlukPct: null), isNull);
    });

    test('fiyat yoksa null', () {
      expect(altinUrunUclari(canliBirimTRY: 0, gunlukPct: -1), isNull);
      expect(altinUrunUclari(canliBirimTRY: -5, gunlukPct: -1), isNull);
    });

    test('−%100 ve ötesi null (bölme anlamsız)', () {
      expect(altinUrunUclari(canliBirimTRY: 1000, gunlukPct: -100), isNull);
      expect(altinUrunUclari(canliBirimTRY: 1000, gunlukPct: -150), isNull);
    });

    test('NaN/sonsuz reddedilir', () {
      expect(altinUrunUclari(canliBirimTRY: 1000, gunlukPct: double.nan),
          isNull);
      expect(
          altinUrunUclari(canliBirimTRY: double.infinity, gunlukPct: -1),
          isNull);
    });
  });

  group('YA HEP YA HİÇ — karışık yol ayrışma üretir', () {
    // Kullanıcı bildirimi (2026-09-23): varlık ekranında çeyrek −%1,43,
    // 22 ayar gram −%0,48. truncgil İKİSİNE DE −%0,72 diyor (canlı
    // API'den ölçüldü) — tüm ayarlar aynı altından üretildiği için
    // AYNI oranda değişirler. Kullanıcının mantığı doğruydu.
    test('iki AYRI yol iki AYRI yüzde verir (kök neden)', () {
      const seriIlk = 6174.68, seriSon = 6126.21; // GC=F eğimi −%0,785
      const truncgilPct = -0.72;

      // A yüzeyi: ürün bazlı (truncgil yüzdesi)
      final u = altinUrunUclari(
          canliBirimTRY: 6126.21, gunlukPct: truncgilPct)!;
      final urunYolu = (u.son / u.ilk - 1) * 100;

      // B yüzeyi: eski çarpan (serinin kendi eğimi)
      final carpanYolu = (seriSon / seriIlk - 1) * 100;

      expect(urunYolu, isNot(closeTo(carpanYolu, 0.001)),
          reason: 'karışık yol ayrışmanın TA KENDİSİ');
      expect(urunYolu, closeTo(-0.72, 0.01));
      expect(carpanYolu, closeTo(-0.785, 0.01));
    });

    test('AYNI yoldan geçince tüm ayarlar AYNI yüzde', () {
      const pct = -0.72; // truncgil hepsine aynısını veriyor
      final gram = altinUrunUclari(canliBirimTRY: 6126.21, gunlukPct: pct)!;
      final ceyrek = altinUrunUclari(canliBirimTRY: 10747.75, gunlukPct: pct)!;
      final pa = (gram.son / gram.ilk - 1) * 100;
      final pb = (ceyrek.son / ceyrek.ilk - 1) * 100;
      expect(pa, closeTo(pb, 0.001),
          reason: 'gram ile çeyrek aynı oranda değişir — kullanıcı haklı');
      expect(pa, closeTo(pct, 0.01));
    });

    test('karar GLOBAL — çağrıya özgü DEĞİL', () {
      // İkinci ayrışma kaynağı: Performans TÜM lot'ları gönderir,
      // varlık ekranı TEK varlık. Karar `assets`e bakıyorsa her ekran
      // kendi başına karar verir ve ikisi ayrışır.
      final src = ekranKaynagiSync('lib/services/history_service.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains(
              'final urunBazliKullan = PriceService.instance.altinGunlukYuzdeTam;'),
          isTrue,
          reason: 'karar global bayraktan gelmeli; `assets` üzerinden '
              'hesaplanırsa ekranlar ayrışır');
    });

    test('bayrak "ya hep ya hiç" taşır', () {
      final src = ekranKaynagiSync('lib/services/price_service.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('bool get altinGunlukYuzdeTam'), isTrue);
      expect(tek.contains('return altinlar.every(_gunlukDegisimPct.containsKey);'),
          isTrue,
          reason: 'bir ayar bile eksikse hiçbiri ürün bazlı yola girmemeli');
    });
  });

  group('YEDEK yolda da ayarlar TUTARLI', () {
    // truncgil düştüğünde `Change` alanı kaybolur ve tüm ayarlar eski
    // çarpan yoluna düşerdi — birbirleriyle tutarlı ama yüzde
    // uluslararası seriden gelirdi.
    //
    // Artık yedek yol (Yahoo `GC=F`/`XAUTRY=X`) kendi günlük yüzdesini
    // TÜM ayarlara taşıyor — truncgil'in de yaptığı bu (ölçüldü:
    // YIA, CEYREKALTIN, YARIMALTIN, ATAALTIN hepsi −%0,72).
    test('yedek yüzde TÜM ayarlara aynı uygulanır', () {
      final src = ekranKaynagiSync('lib/services/price_service.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('regularMarketChangePercent: yedekGunlukPct,'), isTrue,
          reason: 'yedek yol yüzdeyi taşımazsa `altinGunlukYuzdeTam` '
              'false kalır ve ürün bazlı yol hiç açılmaz');
    });

    test('her iki yedek dalı da yüzde yakalar', () {
      final src = ekranKaynagiSync('lib/services/price_service.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      // spot dalı (XAUTRY=X)
      expect(tek.contains('yedekGunlukPct = q?.regularMarketChangePercent;'),
          isTrue);
      // iki dal da aynı değişkeni doldurmalı
      expect('yedekGunlukPct = q?.regularMarketChangePercent;'
              .allMatches(tek).isNotEmpty, isTrue);
    });

    test('truncgil düşüşü SESSİZ kalmaz', () {
      // "Kod çalışıyor, sayı yanlış ve sessiz" sınıfının önüne geçmek için
      // sebep Crashlytics'e düşer; yedek yol yine çalışır.
      final src = ekranKaynagiSync('lib/services/price_service.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains("reason: 'truncgil_dustu'"), isTrue,
          reason: 'düşüş sebebi teşhis edilebilmeli');
    });
  });

  group('yol bağlı', () {
    test('gün içi çizim ürün uçlarını kullanır', () {
      final src = ekranKaynagiSync('lib/services/history_service.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('final uclar = urunBazliKullan ? altinUrunUclari('),
          isTrue,
          reason: 'altın gün içi slotu ürün bazlı hizalanmalı — ve karar '
              '"ya hep ya hiç" bayrağından gelmeli');
      expect(tek.contains('PriceService.instance.gunlukDegisimPct('), isTrue,
          reason: 'ürünün kendi günlük yüzdesi okunmalı');
    });

    test('günlük yüzde kaynaktan SAKLANIYOR', () {
      final src = ekranKaynagiSync('lib/services/price_service.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains(
              '_gunlukYaz(e.key, p, e.value.regularMarketChangePercent);'),
          isTrue,
          reason: 'saklanmazsa hizalama yapılamaz');
      // Yüzde ve gün başı AYNI kotasyondan birlikte yazılır (2026-09-24).
      expect(tek.contains('_gunlukDegisimPct[s] = pct;'), isTrue);
      expect(tek.contains('_gunlukReferans[s] = fiyat / taban;'), isTrue);
      expect(tek.contains('double? gunlukDegisimPct(String symbol)'), isTrue);
    });
  });
}
