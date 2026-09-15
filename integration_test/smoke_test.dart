// Duman testi — GERÇEK uygulama + GERÇEK (yerel) Supabase.
//
// Yol haritası 3.16: "giriş → varlık ekle → portföyü gör" akışı uçtan uca,
// widget testi değil. Bu dosya `flutter test integration_test/` ile bir
// cihaz/emülatörde koşar; sunucu tarafı `supabase start` ile ayağa kalkan
// yerel yığındır (`supabase/migrations/0000_base_schema.sql` + `seed.sql`).
// Hosted bir test projesi GEREKMEZ — bekleyen dış bağımlılık buydu.
//
// ## Neden `app.main()` çağrılıyor, `SandikApp` doğrudan pump edilmiyor
// Duman testinin değeri açılış zincirinin kendisinde: tercih ısıtma,
// SecureSessionStorage ile Supabase.initialize, bildirim servisi, deep link,
// auth kapısı. Bunları testte yeniden kurmak, üretim yolunu değil kopyasını
// sınamak olurdu. Firebase yapılandırması CI'da yok; `main` bunu zaten
// yakalayıp Firebase'siz devam ediyor (aynı davranış üretimde de var).
//
// ## Neden `pumpAndSettle` yok
// Yükleme göstergeleri ve nabız iskeletleri sürekli animasyon; `settle`
// hiç dönmez. Bunun yerine `_bekle`: her 200 ms'de bir kare basıp finder'ı
// yoklar, süre dolunca ağacı döker.
//
// ## Yasal uyarı ekranı
// Tohum kullanıcı onboarding'i tamamlamış ama yasal uyarıyı ONAYLAMAMIŞ
// durumda (bkz. seed.sql — sürüm/hash bayatlamasın diye). Test onu gerçek
// kullanıcı gibi geçer: onay satırına dokunur, "Kabul" düğmesine basar.
//
// Çalıştırma (yerel):
//   supabase start
//   flutter test integration_test/smoke_test.dart \
//     --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
//     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o env | sed -n 's/^ANON_KEY="\(.*\)"/\1/p')
// (10.0.2.2 = Android emülatöründen ana makine; iOS simülatöründe 127.0.0.1)

import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:portfoy_takip/main.dart' as app;
import 'package:portfoy_takip/screens/onboarding_screen.dart';

/// `seed.sql` ile birebir.
const _smokeEmail = 'smoke@sandik.test';
const _smokePassword = 'Duman1234';

/// Aynı yığında test iki kez koşarsa çakışmasın diye zaman damgalı ad.
final _varlikAdi = 'Duman ${DateTime.now().millisecondsSinceEpoch % 100000}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('giriş → varlık ekle → portföyde görünür', (tester) async {
    // Semantics etiketleriyle bulma (`Varlık ekle`, `Diğer türü`) için.
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    app.main();

    // ── 1) Giriş ────────────────────────────────────────────────────────────
    await _bekle(tester, find.text('Giriş Yap'),
        neden: 'giriş ekranı', sure: const Duration(seconds: 30));
    await tester.enterText(_alan(tester, 'E-posta'), _smokeEmail);
    await tester.enterText(_alan(tester, 'Şifre'), _smokePassword);
    await tester.pump();
    await tester.tap(find.text('Giriş Yap'));

    // ── 2) Yasal uyarı (ilk girişte) ────────────────────────────────────────
    // Ekran gelirse geç; gelmezse (tohum onaylı olsaydı) doğrudan ana ekran.
    final onaySatiri =
        find.text('Yukarıdaki yasal uyarıyı okudum ve kabul ediyorum.');
    final anaEkranFab = find.bySemanticsLabel('Varlık ekle');
    await _bekleKosul(
      tester,
      () => onaySatiri.evaluate().isNotEmpty || anaEkranFab.evaluate().isNotEmpty,
      neden: 'yasal uyarı ya da ana ekran',
      sure: const Duration(seconds: 45),
    );
    if (onaySatiri.evaluate().isNotEmpty) {
      await tester.tap(onaySatiri);
      await tester.pump();
      // Onay düğmesi: ekrandaki tek ETKİN CupertinoButton (onay işaretsiz
      // düğme `onPressed: null`).
      final onayDugmesi = find.byWidgetPredicate(
          (w) => w is CupertinoButton && w.onPressed != null);
      await _bekle(tester, onayDugmesi, neden: 'yasal uyarı onay düğmesi');
      await tester.tap(onayDugmesi.first);
    }

    // ── 3) Ana ekran: FAB → Varlık Ekle ─────────────────────────────────────
    // Auth kapısı portföy verisi gelene kadar splash'te bekler (en çok 6 sn),
    // sonra ana gezinme açılır.
    await _bekle(tester, anaEkranFab,
        neden: 'ana ekran (Varlık ekle FAB)', sure: const Duration(seconds: 45));

    // Tanıtım turu AÇIKSA kapat — katman Navigator'ı sarıyor ve her
    // rotanın üstünde durup dokunmaları yutuyor (`OnboardingTourHost`).
    // Tohum kullanıcısı `onboarding_completed = true` taşıyor ama tur
    // başka bir yoldan da açılabiliyor (sürüm notu / "yenilikler"); CI'da
    // varlık ekleme ekranındaki tür çipleri bu yüzden hiç bulunamıyordu.
    // Açık değilse bu çağrı zararsızdır.
    OnboardingScreen.turuKapatTestIcin();
    await tester.pump();
    await tester.tap(anaEkranFab);
    await _bekle(tester, find.text('Varlık Ekle'), neden: 'varlık ekleme ekranı');

    // "Diğer" türü: sembolsüz, elle fiyatlı — ağ araması yok, TEFAS/Yahoo
    // erişimi olmayan bir CI koşucusunda bile deterministik.
    //
    // ## Neden beklemek ve kaydırmak ZORUNLU (CI, 2026-09-15)
    // Ekran açılır açılmaz `tap` çağrılıyordu ve CI'da şu hatayla
    // düşüyordu:
    //
    //   Found 0 widgets with a semantics label named "Diğer türü"
    //
    // İki ayrı sebep birden: (a) `Varlık Ekle` başlığı görünse bile tür
    // çiplerinin semantics ağacı henüz kurulmamış olabiliyor — yerelde
    // hızlı makinede denk gelmiyor, CI emülatöründe geliyor; (b) çipler
    // `HScrollWithFade` içinde yatay kaydırmalı ve "Diğer" SON sırada,
    // yani dar ekranda görünür alanın dışında kalıyor. `tap` merkez
    // noktası istediği için ekran dışındaki bir widget'a dokunamaz.
    // Çip METNİNDEN bulunuyor, semantics etiketinden DEĞİL.
    //
    // `find.bySemanticsLabel('Diğer türü')` CI'da hiç eşleşmedi; teşhis
    // ekranda "Diğer" metninin VARLIĞINI doğruladı (tür çipleri
    // yerindeydi, tur katmanı da kapatılmıştı). Semantics etiketi
    // `assetTypeSemantics` şablonundan üretiliyor ve eşleşmenin neden
    // tutmadığı belirsizdi — metin finder'ı o belirsizliğin tamamını
    // atlıyor ve testin asıl ölçtüğü şeye (akış) odaklanıyor.
    //
    // Erişilebilirlik etiketinin kendisi ayrıca `touch_target_size_test`
    // ve widget testleriyle korunuyor; duman testinin işi o değil.
    // `.first`: "Diğer" bu ekranın dışında da geçebilir (dağılım
    // listesinde bir kategori adı olarak). Tür çipi satırı VARLIK TÜRÜ
    // başlığının hemen altında ve ağaç sırasında önce gelir — sayfadaki
    // ilk "Diğer" odur.
    final digerCip = find.text('Diğer').first;
    await _bekle(tester, digerCip, neden: 'tür çipleri (Diğer)');
    // `ensureVisible` doğru Scrollable'ı widget'ın KENDİ ağacından bulur;
    // `scrollUntilVisible` + `byType(Scrollable).first` sayfadaki başka
    // bir kaydırıcıyı yakalayabilirdi.
    await tester.ensureVisible(digerCip);
    await tester.pump();
    await tester.tap(digerCip, warnIfMissed: false);
    await tester.pump();
    await _bekle(tester, _ipucu(tester, 'Varlık adı'), neden: 'ad alanı');
    await tester.enterText(_ipucu(tester, 'Varlık adı'), _varlikAdi);
    // Miktar ve komisyon alanlarının ikisinin de ipucu '0'; ağaç sırasında
    // miktar önce gelir (bkz. add_asset_screen build sırası).
    await tester.enterText(_ipucu(tester, '0'), '2');
    await tester.enterText(_ipucu(tester, 'Otomatik'), '100');
    await tester.pump();

    final ekleDugmesi = find.widgetWithText(FilledButton, 'Ekle');
    await tester.ensureVisible(ekleDugmesi);
    await tester.tap(ekleDugmesi);

    // ── 4) Portföy sekmesinde görünür ───────────────────────────────────────
    // Kayıt başarılıysa ekran `true` ile kapanır ve gezinme Portföy
    // sekmesine geçer (main_navigation_screen `_showAddAsset`). Sonradan
    // açılabilecek alt sayfalar (widget önerisi, kilometre taşı) ağacı
    // değiştirmez; metin arama onların altında da bulur.
    await _bekle(tester, find.textContaining(_varlikAdi),
        neden: 'portföyde yeni varlık', sure: const Duration(seconds: 45));
  });
}

/// `labelText` ile TextFormField (giriş ekranı).
Finder _alan(WidgetTester tester, String label) => find.byWidgetPredicate(
      (w) => w is TextFormField && _labelOf(tester, w) == label,
      description: 'TextFormField(label: $label)',
    );

/// `hintText` ile TextFormField (varlık ekleme ekranı) — ilk eşleşen.
Finder _ipucu(WidgetTester tester, String hint) => find
    .byWidgetPredicate(
      (w) => w is TextFormField && _hintOf(tester, w) == hint,
      description: 'TextFormField(hint: $hint)',
    )
    .first;

String? _labelOf(WidgetTester tester, TextFormField f) =>
    _decorationOf(tester, f)?.labelText;

String? _hintOf(WidgetTester tester, TextFormField f) =>
    _decorationOf(tester, f)?.hintText;

/// TextFormField dekorasyonu ancak inşa edilmiş TextField'dan okunur.
InputDecoration? _decorationOf(WidgetTester tester, TextFormField f) {
  final icler = find
      .descendant(of: find.byWidget(f), matching: find.byType(TextField))
      .evaluate();
  if (icler.isEmpty) return null;
  final tf = icler.first.widget;
  return tf is TextField ? tf.decoration : null;
}

/// Finder görünene kadar kare basar; süre dolunca ağacı döküp başarısız olur.
Future<void> _bekle(
  WidgetTester tester,
  Finder finder, {
  required String neden,
  Duration sure = const Duration(seconds: 20),
}) =>
    _bekleKosul(tester, () => finder.evaluate().isNotEmpty,
        neden: neden, sure: sure);

Future<void> _bekleKosul(
  WidgetTester tester,
  bool Function() kosul, {
  required String neden,
  Duration sure = const Duration(seconds: 20),
}) async {
  final bitis = DateTime.now().add(sure);
  while (DateTime.now().isBefore(bitis)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (kosul()) return;
  }
  // Ağaç dökümü CI logunda KIRPILIYOR (derinlik yüzünden satırlar çok
  // uzun) ve "hangi ekrandaydık" sorusunu yanıtlamıyordu. Ekrandaki
  // görünür metinler o soruyu tek satırda yanıtlar — asıl aranan bu.
  final metinler = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .where((t) => t.trim().isNotEmpty)
      .take(40)
      .toList();
  debugPrint('EKRANDAKİ METİNLER: $metinler');
  // Tanıtım turu ekranın üstüne biniyorsa dokunmalar ona gider;
  // varlığını ayrıca bildir (2026-09-15 teşhisi).
  debugPrint('TUR KATMANI VAR MI: '
      '${find.byType(ModalBarrier).evaluate().length} ModalBarrier');
  // Semantics ETİKETLERİ — `find.bySemanticsLabel` TAM eşleşme arıyor ve
  // aradığı dize, ekranda görünen metinden farklı olabiliyor. Ağaçtaki
  // `Semantics` widget'larının kendi `label`'larını basmak bu belirsizliği
  // tek turda bitirir.
  final etiketler = find
      .byType(Semantics)
      .evaluate()
      .map((e) => (e.widget as Semantics).properties.label)
      .whereType<String>()
      .where((l) => l.trim().isNotEmpty)
      .take(50)
      .toList();
  debugPrint('SEMANTICS ETİKETLERİ: $etiketler');
  debugDumpApp();
  fail('Beklenen görünmedi: $neden (${sure.inSeconds} sn)');
}
