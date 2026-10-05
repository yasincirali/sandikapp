
import 'package:flutter_test/flutter_test.dart';
import 'helpers/kaynak.dart';

/// "Yatırım tavsiyesi değildir" uyarısı sinyal/analiz gösteren HER yüzeyde
/// bulunmalı.
///
/// Neden ratchet: Play'in Financial Services politikası ve App Store'un
/// finans kategorisi, analiz/sinyal gösteren uygulamalarda görünür bir
/// sorumluluk reddi arıyor. Kapsam 2026-09-15 denetiminde TAM çıktı ama
/// hiçbir test korumuyordu — yeni bir sinyal yüzeyi eklenirken sessizce
/// atlanabilirdi. Beyan sırasında "her ekranda var" demek, ancak bunu
/// kilitleyen bir test varsa sürdürülebilir bir iddiadır.
///
/// İki katman ayrı ayrı korunuyor:
///   1. UYGULAMA İÇİ — `DisclaimerWidget` sinyal/analiz ekranlarında
///   2. PUSH — bildirim gövdesinde, çünkü kullanıcı uygulamayı hiç
///      açmadan okuyabiliyor (asıl politika riski burada)
void main() {
  String oku(String yol) => ekranKaynagiSync(yol);

  group('uygulama içi yüzeyler', () {
    /// Sinyal, teknik analiz ya da performans yorumu gösteren ekranlar.
    /// Yeni bir tane eklenirse listeye de eklenmeli — testin kendisi
    /// kapsamın kaydıdır.
    const yuzeyler = <String>[
      'lib/screens/home_screen.dart', // ana ekran + sinyal bottom sheet
      'lib/screens/asset_detail_screen.dart',
      'lib/screens/portfolio_performance_screen.dart',
      'lib/screens/signal_settings_screen.dart',
      'lib/screens/varlik_sayfasi.dart',
    ];

    for (final yol in yuzeyler) {
      test('$yol DisclaimerWidget taşır', () {
        expect(
          oku(yol).contains('DisclaimerWidget'),
          isTrue,
          reason: 'Sinyal/analiz gösteren ekran görünür sorumluluk reddi '
              'olmadan yayınlanamaz (Play Financial Services).',
        );
      });
    }
  });

  group('tekrar yok — panel ibareyi barındıran ekrana bırakır', () {
    // Emülatör testi #20 (2026-09-29): varlık ekranında aynı uyarı ÜÇ kez
    // vardı (panelin üstü, panelin altı, ekranın kendi ibaresi). Kural
    // "sinyal gösteren her yüzey ibare taşır"dır, "her katman" değil:
    // ibare panelin hemen altında, onu barındıran ekranda TEK kez durur.
    const panel = 'lib/screens/asset_detail/sinyal_widgetlari.dart';
    int sayi(String kaynak) =>
        RegExp(r'DisclaimerWidget\(').allMatches(kaynak).length;

    test('TechnicalSignalPanel kendi içinde ibare basmaz', () {
      expect(sayi(oku(panel)), 0,
          reason: 'panel ibaresi ekranın ibaresiyle üst üste biner');
    });

    for (final yol in const [
      'lib/screens/asset_detail_screen.dart',
      'lib/screens/varlik_sayfasi.dart',
    ]) {
      test('$yol paneli gösterir ve ibareyi TEK kez taşır', () {
        final k = oku(yol);
        expect(k.contains('TechnicalSignalPanel'), isTrue);
        expect(sayi(k), 1);
      });
    }
  });

  test('uyarı metni üç şeyi birden söyler', () {
    final w = oku('lib/widgets/disclaimer_widget.dart');
    // 3.20: metin sözlüğe taşındı; widget doğru ANAHTARI kullanmalı ve o
    // anahtarın Türkçe metni üç şeyi de söylemeye devam etmeli.
    expect(w.contains('l10n.disclaimerText'), isTrue);
    final metin = trMetni('disclaimerText');
    // Üçü de politika metinlerinde ayrı ayrı aranıyor: "tavsiye değil",
    // "danışmana sor", "geçmiş performans garanti değil".
    expect(metin.contains('yatırım tavsiyesi'), isTrue);
    expect(metin.contains('mali danışman'), isTrue);
    expect(
      metin.contains('Geçmiş performans'),
      isTrue,
      reason: 'Geçmiş getiri gösteren her üründe aranan standart cümle.',
    );
  });

  test('push bildirimi gövdesinde de uyarı var', () {
    // Kullanıcı bildirimi uygulamayı HİÇ AÇMADAN okuyor; ekrandaki uyarı
    // oraya ulaşmıyor. Politika riskinin asıl yoğunlaştığı yer burası.
    final fn = oku('supabase/functions/analyze-signals/index.ts');
    expect(
      fn.contains("'Yatırım tavsiyesi değildir.'"),
      isTrue,
      reason: 'analyze-signals buildMessage() disclaimer sabitini '
          'taşımalı.',
    );
    // Sabit tanımlı olsa da gövdeye EKLENMEZSE işe yaramaz.
    //
    // `buildMessage` iki dal döndürür (nötr + yönlü) ve ikisi disclaimer'ı
    // FARKLI biçimde ekliyor — biri `... + disclaimer,`, diğeri
    // `. ${disclaimer}` şeklinde. Bu yüzden biçim eşleştirmek yerine
    // fonksiyonun gövdesini kesip her `body:` bloğunda 'disclaimer'
    // kelimesinin geçtiğini doğruluyoruz.
    final basla = fn.indexOf('function buildMessage');
    final bit = fn.indexOf('\n}', basla);
    expect(basla, greaterThan(-1), reason: 'buildMessage bulunamadı');
    final govde = fn.substring(basla, bit);

    // Gövdeler çok satırlı (şablon dizgi + string birleştirme), bu yüzden
    // önce boşlukları tekilleştir: satır kırılması eşleşmeyi bozmasın.
    final duz = govde.replaceAll(RegExp(r'\s+'), ' ');

    // Her `return { ... }` bloğu bir bildirim varyantıdır.
    final donusler = RegExp(r'return \{.*?\};')
        .allMatches(duz)
        .map((m) => m.group(0)!)
        .toList();
    expect(
      donusler.length,
      greaterThanOrEqualTo(2),
      reason: 'buildMessage nötr ve yönlü olmak üzere en az iki varyant '
          'döndürmeli.',
    );
    for (final d in donusler) {
      expect(
        d.contains('disclaimer'),
        isTrue,
        reason: 'Bu bildirim varyantı uyarısız gidiyor: $d',
      );
    }
  });

  test('kayıt ekranı onayında da geçer', () {
    // Kullanıcı daha ilk adımda bilgilendirilmiş olmalı — KVKK açık rıza
    // "bilgilendirilmiş" olmayı ister.
    //
    // 2026-10-04: kayıt tek kutulu (açıklaması `tekOnayAciklama`) ve
    // yatırım uyarısının TAM metni zorunlu okuma listesinde (bayraklar
    // 2026-10-05'te kalktı). İddia aynı: kayıt ekranındaki kutu metni
    // uyarıyı taşır. Adım düzeninden (2026-10-05) beri uyarı kaydın 1.
    // adımı: `YasalAdimPlani.kayit()` (adımları `yasal_adim_plani_test`).
    final kayit = oku('lib/screens/register_screen.dart');
    expect(kayit.contains('bodyText: context.l10n.tekOnayAciklama('), isTrue);
    expect(kayit.contains('YasalAdimPlani.kayit()'), isTrue);
    expect(oku('lib/services/yasal_adim_plani.dart'),
        contains('_kur(uyari: true, riza: true, kutu: true)'));
    expect(
      oku('lib/l10n/app_tr.arb').contains(
          '"tekOnayAciklama": "Uygulama yatırım tavsiyesi değildir'),
      isTrue,
    );
  });
}
