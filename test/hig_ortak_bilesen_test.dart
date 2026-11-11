import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/main.dart';
import 'package:portfoy_takip/models/ohlc.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/bildirim_izni.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/bes_sozlesme_pozisyonu.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/widgets/degisim_parlamasi.dart';
import 'package:portfoy_takip/widgets/disclaimer_widget.dart';
import 'package:portfoy_takip/widgets/bes_fon_satiri.dart';
import 'package:portfoy_takip/widgets/bildirim_izni_uyarisi.dart';
import 'package:portfoy_takip/widgets/bildirim_satiri.dart';
import 'package:portfoy_takip/widgets/grafik_arac_cubugu.dart';
import 'package:portfoy_takip/services/destek_direnc.dart';
import 'package:portfoy_takip/widgets/portfoy_yorumu_karti.dart';
import 'package:portfoy_takip/widgets/pozisyon_islemleri.dart';
import 'package:portfoy_takip/widgets/sandik_baglam_menusu.dart';
import 'package:portfoy_takip/widgets/sandik_app_bar.dart';
import 'package:portfoy_takip/widgets/sandik_async_button.dart';
import 'package:portfoy_takip/widgets/sandik_error_view.dart';
import 'package:portfoy_takip/widgets/sandik_icerik_sutunu.dart';
import 'package:portfoy_takip/services/takvim_ics.dart';
import 'package:portfoy_takip/widgets/takvime_ekle_dugmesi.dart';
import 'package:portfoy_takip/widgets/sandik_ikon_gecisi.dart';
import 'package:portfoy_takip/widgets/sandik_paylas_dugmesi.dart';
import 'package:portfoy_takip/widgets/sandik_segment.dart';
import 'package:portfoy_takip/widgets/sandik_siralama_dugmesi.dart';
import 'package:portfoy_takip/widgets/sandik_yenile.dart';
import 'package:portfoy_takip/widgets/sayi_klavyesi_cubugu.dart';
import 'package:portfoy_takip/widgets/seri_son_guncelleme.dart';
import 'package:portfoy_takip/widgets/sozlesme_formu_ortak.dart';
import 'package:portfoy_takip/widgets/tarih_cipleri.dart';
import 'package:portfoy_takip/widgets/tur_filtre_cipleri.dart';

/// BES fon satırı (2026-10-29): Portföy sözleşme paneli + sözleşme kartı.
final _besFonVitrini = besFonSatirlari(aggregatePositions([
  for (final (kod, sub) in [('AH5', 'katki'), ('AEK', 'dk')])
    Asset(
      id: kod,
      userId: 'u',
      name: 'MetLife Emeklilik · $kod',
      ticker: 'TEFAS:$kod',
      type: AssetType.bes,
      subCategory: sub,
      quantity: 1000,
      purchasePrice: 1,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: 1.2,
      sozlesmeId: 's',
    ),
]));

const _siralamaVitrini = [
  SandikSiralamaSecenegi(
      deger: 0,
      baslik: 'Değere göre',
      altBaslik: 'Yüksekten düşüğe',
      ikon: Icons.arrow_downward_rounded),
  SandikSiralamaSecenegi(
      deger: 1,
      baslik: 'Kâra göre',
      altBaslik: 'En yüksek önce',
      ikon: Icons.trending_up_rounded),
];

/// Apple HIG kontrol listesinin ölçülebilir kısmı (`docs/TASARIM_DILI.md`
/// §5, yasin 2026-10-10: "bişey değiştirirken bunu standart olarak
/// sorgulayalım").
///
/// `touch_target_size_test` kaynak tarar ve yalnız sabit sayıları görür;
/// burada ortak bileşenler GERÇEKTEN çizilir ve Flutter'ın kendi erişilebilirlik
/// kılavuzlarıyla ölçülür: iOS 44×44 pt, her dokunulabilir öğenin ekran
/// okuyucu etiketi, metin kontrastı (WCAG AA), yazı ×2'de taşma. Material'in
/// 48 dp önerisi (`androidTapTargetGuideline`) bilerek kilitlenmedi: tek eşik
/// `SandikTouch.min` 44; segment ve satırlar 44'te kalır, Material düğmeleri
/// zaten 48 alır (karar: TASARIM_DILI.md §7). Ekranlar bu
/// bileşenlerden kurulduğu için buradaki bir gerileme her ekrana yayılır.
/// Yeni ortak bileşen eklenince `vitrin`'e de eklenir.
void main() {
  // "Bildirimler kapalı" satırı vitrinde görünsün (izin reddedilmiş say).
  setUpAll(() async {
    BildirimIzni.testOkuyucu = () async => true;
    HataDenemeKaydi.denendi('hig_vitrin');
    // `SeriSonGuncelleme` tarihi Türkçe ay adıyla yazar.
    await initializeDateFormatting('tr_TR');
  });
  tearDownAll(() {
    BildirimIzni.testOkuyucu = null;
    HataDenemeKaydi.sifirlaTest();
  });

  Widget vitrin({required Brightness parlaklik, double yaziOlcegi = 1}) {
    final palet =
        parlaklik == Brightness.dark ? SandikPalette.dark : SandikPalette.light;
    return MaterialApp(
      theme: SandikApp.buildTheme(palet, parlaklik),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 1400),
          textScaler: TextScaler.linear(yaziOlcegi),
        ),
        child: Builder(builder: (context) {
          return Scaffold(
            appBar: SandikAppBar(
              title: 'Başlık',
              onBack: () {},
              actions: [
                IconButton(
                  tooltip: 'Yenile',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () {},
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(SandikSpace.md),
              children: [
                // "Tekrar dene" denenip yine hata: ikincil "bize yaz"
                // bağlantısı da görünür (2026-10-24); 44 pt + etiket. Listenin
                // başında: tembel liste sonda kalanı çizmeyebilir.
                SizedBox(
                  height: 320,
                  child: SandikErrorView(
                    error: Exception('x'),
                    onRetry: () async {},
                    ekranAdi: 'hig_vitrin',
                  ),
                ),
                SandikAsyncButton(
                  onPressed: () async {},
                  child: const Text('Kaydet'),
                ),
                const SizedBox(height: SandikSpace.md),
                // Başarı durumu (Ar-Ge 11 Kas 19:04 #3) "Onayla"nın yanında:
                // ayrı satır, tembel listede aşağıdakileri dışarı itiyordu.
                // Ayrı testte basılıp ✓ hâli de ölçülür.
                Row(children: [
                  SandikAsyncButton.kompakt(
                    onPressed: () async {},
                    child: const Text('Onayla'),
                  ),
                  const SizedBox(width: SandikSpace.sm),
                  Builder(builder: (context) {
                    final sinyal = SandikBasariSinyali();
                    return SandikAsyncButton.kompakt(
                      key: const ValueKey('basari-vitrin'),
                      basari: sinyal,
                      onPressed: () => sinyal.goster(),
                      child: const Text('Kaydet'),
                    );
                  }),
                ]),
                const SizedBox(height: SandikSpace.md),
                const BildirimIzniUyarisi(),
                // Grafik eski seriyle kaldığında (önce-eski-seri, 2026-10-24).
                SeriSonGuncelleme(zaman: DateTime(2026, 10, 23, 14, 32)),
                const SizedBox(height: SandikSpace.md),
                // Tek sıralama düğmesi (2026-10-25): Portföy ikon kutusu
                // (varsayılan dışı seçimde amber) ve takip listesi etiketli.
                Row(children: [
                  SandikSiralamaDugmesi<int>.ikon(
                    secenekler: _siralamaVitrini,
                    secili: 1,
                    varsayilan: 0,
                    semantikEtiket: 'Varlıkları sırala',
                    onSec: (_) {},
                  ),
                  SandikSiralamaDugmesi<int>.etiketli(
                    secenekler: _siralamaVitrini,
                    secili: 0,
                    semantikEtiket: 'Sıralama: Değere göre',
                    onSec: (_) {},
                  ),
                ]),
                const SizedBox(height: SandikSpace.md),
                // Çan satırı (2026-10-29): açık hâli — "Aç" düğmesi ve
                // kapatma düğmesi 44 pt, başlık/gövde ×2 yazıda taşmaz.
                Builder(builder: (context) => BildirimSatiri(
                  renk: context.c.amberText,
                  ikon: Icons.visibility_rounded,
                  baslik: 'Takip listende bugün 3 sert hareket',
                  rozet: 'TAKİP',
                  govde: 'Günlük değişim (önceki kapanışa göre): THYAO '
                      '+%5,3 ₺312,40 · ASELS −%5,5 ₺150,20.',
                  zaman: 'Bugün 18:25',
                  faded: false,
                  onAc: () {},
                  onDismiss: () {},
                  baslangictaAcik: true,
                )),
                const SizedBox(height: SandikSpace.md),
                SandikAsyncTap(
                  onTap: () async {},
                  semanticLabel: 'Fiyatları yenile',
                  child: const SizedBox(
                    width: SandikTouch.min,
                    height: SandikTouch.min,
                    child: Icon(Icons.sync_rounded),
                  ),
                ),
                const SizedBox(height: SandikSpace.md),
                FilledButton(onPressed: () {}, child: const Text('Devam')),
                OutlinedButton(onPressed: () {}, child: const Text('Vazgeç')),
                TextButton(onPressed: () {}, child: const Text('Ayrıntı')),
                // Aç/kapa ikonu geçişi (2026-10-20): dokunma alanını taşıyan
                // düğme verir, bileşen yalnız ikon.
                IconButton(
                  tooltip: 'Takibe al',
                  onPressed: () {},
                  icon: const SandikIkonGecisi(Icons.star_border_rounded),
                ),
                const SizedBox(height: SandikSpace.md),
                SandikSegment(
                  adet: 3,
                  secili: 0,
                  onSec: (_) {},
                  oge: (c, i, s) => Center(child: Text(['1H', '1A', '1Y'][i])),
                ),
                const SizedBox(height: SandikSpace.md),
                // Uygulamanın tek süzme çipi (seçici denetimi 2026-10-12).
                Wrap(spacing: SandikSpace.sm, children: [
                  SandikFiltreCipi(ad: 'Tümü', secili: true, onTap: () {}),
                  SandikFiltreCipi(
                      ad: 'Hisse',
                      secili: false,
                      onTap: () {},
                      ikon: Icons.show_chart_rounded),
                ]),
                const SizedBox(height: SandikSpace.md),
                // Tarih hızlı seçim satırı (2026-11-11): Bugün · Dün · son
                // iş günü · Başka tarih — her çip `SandikFiltreCipi`.
                TarihCipleri(
                  bugun: DateTime(2026, 11, 9),
                  secili: DateTime(2026, 10, 1),
                  onSecildi: (_) {},
                  takvim: () async => null,
                ),
                const SizedBox(height: SandikSpace.md),
                SandikTappable(
                  onTap: () {},
                  semanticLabel: 'Varlık satırı',
                  child: const SizedBox(
                    height: SandikTouch.min,
                    child: Text('THYAO'),
                  ),
                ),
                // Solan basma (eski `SandikBasma`, Ar-Ge 5 Kas 22:40 #3).
                SandikTappable(
                  onTap: () {},
                  soluk: true,
                  haptic: SandikHaptic.none,
                  semanticLabel: 'Solan satır',
                  child: const SizedBox(
                    height: SandikTouch.min,
                    child: Text('ASELS'),
                  ),
                ),
                const SizedBox(height: SandikSpace.md),
                // Özel içerikli diyalog kabuğu (Ar-Ge 5 Kas 22:40 #7):
                // içindeki düğme 44 pt, metin kontrastı kart zemininde.
                SandikDiyalogKabugu(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Yatırım uyarısı',
                          style: context.t.titleLarge
                              ?.copyWith(color: context.c.text90)),
                      const SizedBox(height: SandikSpace.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                            onPressed: () {}, child: const Text('Kapat')),
                      ),
                    ],
                  ),
                ),
                // Anahtar etiketsiz tek başına durmaz: satır metniyle
                // birleşir (ya da `SwitchListTile.adaptive`).
                MergeSemantics(
                  child: Row(children: [
                    const Expanded(child: Text('Bildirimler')),
                    Switch.adaptive(value: true, onChanged: (_) {}),
                  ]),
                ),
                const SizedBox(height: SandikSpace.md),
                // Grafik araç çubuğu: varlık detayı, varlık sayfası ve
                // Karşılaştır aynı bileşeni kurar (2026-10-10 gece).
                GrafikAracCubugu(
                  katmanlar: true,
                  ma20Acik: true,
                  logAcik: false,
                  mumAcik: true,
                  ema50Acik: false,
                  ema200Acik: false,
                  ozel: GrafikOzelCipi(acikSayi: 0, kilitli: true, onTap: () {}),
                  aralik: MumAraligi.dk5,
                  gecerliAraliklar: const [
                    MumAraligi.dk1,
                    MumAraligi.dk5,
                    MumAraligi.dk15,
                    MumAraligi.saat1,
                  ],
                  kapanistan: false,
                ),
                // Çipler 30 Eki'den beri "Göstergeler" düğmesinin ardında;
                // vitrinde açık hâlleri ayrıca durur ki ölçüm sürsün.
                Wrap(spacing: 6, children: [
                  GrafikCipi(label: 'MA20', active: true, onTap: () {}),
                  GrafikCipi(label: 'EMA50', active: false, onTap: () {}),
                  GrafikCipi(
                      label: 'ƒx', active: false, kilitli: true, onTap: () {}),
                ]),
                const SizedBox(height: SandikSpace.md),
                // Uygulamanın tek paylaş düğmesi (2026-10-30): kart köşesi,
                // bölüm başlığı ve Profil davet kodu aynı bileşen.
                SandikPaylasDugmesi(onPressed: () {}, tooltip: 'Paylaş'),
                // Belge hazırlayan hâli (aylık rapor PDF'i, 2026-10-31).
                SandikPaylasDugmesi.istekli(
                    onPaylas: (_) async {}, tooltip: 'PDF olarak paylaş'),
                const SizedBox(height: SandikSpace.md),
                // Performans dipnotunun kısa biçimi (2026-11-07): "Ayrıntı"
                // bağlantısı 44 pt ve etiketli olmalı.
                const DisclaimerWidget(kisa: true),
                const SizedBox(height: SandikSpace.md),
                // "Takvime ekle" ikon düğmesi (2026-11-11): 44 pt, etiketli.
                TakvimeEkleDugmesi(
                  etkinlikler: [
                    TakvimEtkinligi(
                        uid: 'vitrin', gun: DateTime(2027, 1, 15), baslik: 'v'),
                  ],
                  dosyaAdi: 'vitrin',
                  konu: 'v',
                ),
                const SizedBox(height: SandikSpace.md),
                // Fiyat turu değişim parlaması (2026-11-11): dinlenme hâlinde
                // tutar metni birebir; yazı ×2'de taşmaz, kontrast korunur.
                const Align(
                  alignment: Alignment.centerRight,
                  child: DegisimParlamasi(
                    deger: 1240,
                    metin: '₺1.240',
                    kimlik: 'vitrin',
                    child: Text('₺1.240'),
                  ),
                ),
                const SizedBox(height: SandikSpace.md),
                // Varlık sayfasının Al · Sat · Temettü çubuğu: şerit ve
                // (bayrak `goz_alici`) yüzen cam kapsül.
                PozisyonIslemCubugu(
                  islemler: PozisyonIslemi.values,
                  onIslem: (_) {},
                ),
                PozisyonIslemCubugu(
                  yuzen: true,
                  islemler: PozisyonIslemi.values,
                  onIslem: (_) {},
                ),
                const SizedBox(height: SandikSpace.md),
                // Uzun basma kısayolu (bayrak `goz_alici`): satırın kendi
                // etiketi ve dokunma alanı korunur.
                SandikBaglamMenusu(
                  baslik: 'THYAO',
                  eylemler: [
                    SandikBaglamEylemi(
                        etiket: 'Al', ikon: Icons.add_rounded, onSec: () {}),
                    SandikBaglamEylemi(
                        etiket: 'Sil',
                        ikon: Icons.delete_outline_rounded,
                        yikici: true,
                        onSec: () {}),
                  ],
                  child: SandikTappable(
                    onTap: () {},
                    semanticLabel: 'Menülü satır',
                    child: const SizedBox(
                      height: SandikTouch.min,
                      child: Text('ASELS'),
                    ),
                  ),
                ),
                const SizedBox(height: SandikSpace.md),
                // Sözleşme formlarının tarih alanı (2026-11-10): etiket üstte
                // sarar; kutu 44 pt, etiketiyle birlikte okunur.
                SozlesmeTarihi(
                  etiket: 'Hakkı kullandığın tarih',
                  tarih: DateTime(2026, 5, 1),
                  degisti: (_) {},
                ),
                const SizedBox(height: SandikSpace.md),
                for (final f in _besFonVitrini)
                  BesFonSatiriGorunumu(
                    satir: f,
                    tutar: '₺1.200',
                    kisaAd: 'Altın Katılım',
                    onTap: f.devlet ? null : () {},
                  ),
                const SizedBox(height: SandikSpace.md),
                // AI yorum kartının destek/direnç satırı (2026-10-17): nötr
                // renk, metin kontrastı ve ×2 yazıda taşma.
                SeviyeSatiri(
                  seviyeler: const DestekDirenc(
                    destek: FiyatBolgesi(alt: 41.2, ust: 42, temas: 3),
                    direnc: FiyatBolgesi(alt: 46.5, ust: 47.1, temas: 2),
                  ),
                  fiyatYaz: (v) => '₺${v.toStringAsFixed(2)}',
                ),
                const SizedBox(height: SandikSpace.md),
                // Okunabilir içerik sütunu (2026-11-07): 390 pt'de no-op;
                // içindeki metin ×2'de de taşmamalı.
                const SandikIcerikSutunu(
                  child: Text('Okunabilir sütunda uzun bir açıklama satırı'),
                ),
                const SizedBox(height: SandikSpace.md),
                // iOS sayı klavyesi çubuğu (2026-11-11): Sonraki/Bitti 44 pt,
                // etiket düğme metni, ×2 yazıda çubuk büyür, taşmaz.
                SayiKlavyesiCubugu(onSonraki: () {}, onBitti: () {}),
                const SizedBox(height: SandikSpace.md),
                SandikSectionHeader(title: 'Bölüm'),
                // Tek çekip yenile sarmalayıcısı (2026-11-11): içindeki
                // metin ×2'de taşmaz, kontrast temadan; dokunma hedefi yok.
                SizedBox(
                  height: 64,
                  child: SandikYenile(
                    onRefresh: () async {},
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        Text('Aşağı çekince liste yenilenir'),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 260,
                  child: SandikErrorView(
                    error: Exception('x'),
                    onRetry: () async {},
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  for (final parlaklik in Brightness.values) {
    final ad = parlaklik == Brightness.dark ? 'koyu' : 'açık';

    testWidgets('ortak bileşenler HIG dokunma hedefi ve etiket ($ad)',
        (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(vitrin(parlaklik: parlaklik));
      await t.pump();
      // Bize yaz bağlantısı vitrinde gerçekten çizili (ölçüme girsin).
      expect(find.byKey(const ValueKey('hata-bize-yaz')), findsOneWidget);
      await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('sıralama sayfası satırları 44 pt, etiketli ($ad)',
        (t) async {
      final handle = t.ensureSemantics();
      final dugmeler =
          find.byWidgetPredicate((w) => w is SandikSiralamaDugmesi);
      for (final i in [0, 1]) {
        // Her biçim temiz vitrinde: sayfa kapanınca liste kayabiliyor.
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(vitrin(parlaklik: parlaklik));
        await t.pump();
        expect(dugmeler, findsNWidgets(2));
        await t.tap(dugmeler.at(i));
        await t.pumpAndSettle();
        expect(find.byIcon(Icons.check_rounded), findsOneWidget,
            reason: 'seçili satır yalnız renkle değil onay işaretiyle');
        await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(t, meetsGuideline(textContrastGuideline));
      }
      handle.dispose();
    });

    testWidgets('başarı durumu: ✓ hâlinde boy aynı, etiketli ($ad)',
        (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(vitrin(parlaklik: parlaklik));
      await t.pump();
      final dugme = find.byKey(const ValueKey('basari-vitrin'));
      final boy = t.getSize(dugme);
      await t.tap(find.descendant(of: dugme, matching: find.text('Kaydet')));
      await t.pump();
      await t.pump(SandikMotion.state);
      expect(find.descendant(of: dugme, matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget);
      expect(t.getSize(dugme), boy, reason: '✓ evresinde düğme zıplamaz');
      expect(find.bySemanticsLabel('Kaydedildi'), findsOneWidget,
          reason: '✓ yalnız ikonla değil, okunan etiketle');
      expect(boy.height, greaterThanOrEqualTo(SandikTouch.min));
      await t.pumpAndSettle();
      handle.dispose();
    });

    testWidgets('ortak bileşenler metin kontrastı ($ad)', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(vitrin(parlaklik: parlaklik));
      await t.pump();
      await expectLater(t, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  // Cam/HIG incelemesi (2026-10-12): bayrak `goz_alici` açıkken aynı
  // vitrin — tek sıra grafik araçları, yüzen kapsül, bağlam menüsü — iOS ve
  // Android'de aynı ölçütlerden geçer.
  group('bayrak goz_alici açık', () {
    setUp(() => RemoteConfigService.testAcik = {'goz_alici'});
    tearDown(() {
      RemoteConfigService.testAcik = {};
      debugDefaultTargetPlatformOverride = null;
    });
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      for (final parlaklik in Brightness.values) {
        testWidgets('dokunma, etiket, kontrast (${platform.name}, '
            '${parlaklik.name})', (t) async {
          debugDefaultTargetPlatformOverride = platform;
          final handle = t.ensureSemantics();
          await t.pumpWidget(vitrin(parlaklik: parlaklik));
          await t.pump();
          await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(t, meetsGuideline(textContrastGuideline));
          handle.dispose();
          debugDefaultTargetPlatformOverride = null;
        });
      }
      testWidgets('yazı ×2 taşmıyor (${platform.name})', (t) async {
        debugDefaultTargetPlatformOverride = platform;
        await t.pumpWidget(vitrin(parlaklik: Brightness.dark, yaziOlcegi: 2));
        await t.pump();
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  testWidgets('yazı ×2 (Dynamic Type) ortak bileşenleri taşırmıyor', (t) async {
    await t.pumpWidget(vitrin(parlaklik: Brightness.dark, yaziOlcegi: 2));
    await t.pump();
    expect(t.takeException(), isNull);
  });

  // Vitrinin sonunda: tembel liste ilk karede oraya kadar çizmez, kaydırılır.
  // ×2 yazı ayrı, yalın düzende: vitrinin dibindeki `SandikErrorView`
  // (260 pt kutu) ×2'de zaten taşıyor ve bu bileşenin konusu değil.
  testWidgets('çekip yenile (SandikYenile) vitrinde: etiket, kontrast',
      (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(vitrin(parlaklik: Brightness.dark));
    await t.pump();
    await t.scrollUntilVisible(find.byType(SandikYenile), 300,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(find.byType(SandikYenile), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(t, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('çekip yenile (SandikYenile) ×2 yazıda taşmıyor', (t) async {
    final palet = SandikPalette.dark;
    await t.pumpWidget(MaterialApp(
      theme: SandikApp.buildTheme(palet, Brightness.dark),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(
          body: SandikYenile(
            onRefresh: () async {},
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [Text('Aşağı çekince liste yenilenir')],
            ),
          ),
        ),
      ),
    ));
    await t.drag(find.byType(ListView), const Offset(0, 300));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  group('okunabilir içerik sütunu (iPad, HIG readable width)', () {
    const kutu = Key('sutun-icerik');
    const sliverKutu = Key('sutun-sliver');

    Future<void> ciz(WidgetTester t, double genislik) async {
      t.view.physicalSize = Size(genislik, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            SizedBox(
              height: 100,
              child: SingleChildScrollView(
                child: SandikIcerikSutunu(
                  child: Container(key: kutu, height: 40),
                ),
              ),
            ),
            Expanded(
              child: CustomScrollView(slivers: [
                SandikIcerikSutunu.sliver(slivers: [
                  SliverToBoxAdapter(
                      child: Container(key: sliverKutu, height: 40)),
                ]),
              ]),
            ),
          ]),
        ),
      ));
    }

    testWidgets('1366 pt\'de içerik ≤ 720 ve ortada', (t) async {
      await ciz(t, 1366);
      for (final k in [kutu, sliverKutu]) {
        final r = t.getRect(find.byKey(k));
        expect(r.width, lessThanOrEqualTo(SandikIcerikSutunu.azamiGenislik));
        expect(r.center.dx, closeTo(1366 / 2, 0.5));
      }
    });

    testWidgets('390 pt\'de değişmez (iPhone düzeni birebir)', (t) async {
      await ciz(t, 390);
      for (final k in [kutu, sliverKutu]) {
        final r = t.getRect(find.byKey(k));
        expect(r.left, 0);
        expect(r.width, 390);
      }
    });

    test('sütun ana sekmelerde ve varlık ekranında kullanılır, Profil hariç',
        () {
      for (final f in [
        'lib/screens/home_screen.dart',
        'lib/screens/portfolio_screen.dart',
        'lib/screens/portfolio_performance/kartlar.dart',
        'lib/screens/settings_screen.dart',
        'lib/screens/asset_detail_screen.dart',
        'lib/screens/varlik_sayfasi.dart',
        'lib/screens/watchlist_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('SandikIcerikSutunu'),
            reason: '$f okunabilir sütunu kullanmalı');
      }
    });
  });

  test('ikon düğmesinde ekran okuyucu etiketi (tooltip) var', () {
    // HIG "Accessibility": yalnız ikondan oluşan düğme VoiceOver'da "düğme"
    // diye okunur, ne yaptığı söylenmez. `IconButton.tooltip` hem uzun
    // basma ipucu hem semantik etikettir. 2026-10-10 denetiminde 11 düğme
    // etiketsizdi, hepsi etiketlendi; yeni IconButton etiketsiz girmez.
    // `IconButton.styleFrom(` bir stil yardımcısıdır, düğme değil.
    final etiketsiz = <String>[];
    final desen =
        RegExp(r'\bIconButton(\.(filled|filledTonal|outlined))?\s*\(');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in desen.allMatches(src)) {
        var derinlik = 0;
        var son = m.end - 1;
        for (var j = m.end - 1; j < src.length; j++) {
          if (src[j] == '(') derinlik++;
          if (src[j] == ')' && --derinlik == 0) {
            son = j;
            break;
          }
        }
        if (!src.substring(m.end, son).contains('tooltip:')) {
          final satir = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          etiketsiz.add('${f.path}:$satir');
        }
      }
    }
    expect(etiketsiz, isEmpty,
        reason: 'IconButton\'a `tooltip:` ver (l10n\'lu ekranda '
            'context.l10n).\n${etiketsiz.join('\n')}');
  });
}
