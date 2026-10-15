import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../providers/bulk_cart_provider.dart';
import '../providers/premium_provider.dart';
import '../services/crash_reporter.dart';
import '../services/csv_import_service.dart';
import '../services/price_service.dart';
import '../models/asset_type.dart' show tefasOneki;
import '../services/ekstre/ekran_goruntusu.dart';
import '../services/ekstre/ekran_okuyucu.dart';
import '../services/ekstre/ekstre_ice_aktarma.dart';
import '../services/remote_config_service.dart';
import 'paywall_screen.dart';
import '../services/supabase_service.dart';
import '../services/tefas_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/tr_format.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/para_akisi_karti.dart' show KilitSatiri;
import '../widgets/sandik_app_bar.dart';
import '../l10n/l10n.dart';

/// Ekstre dosyası seç (PDF / Excel / CSV) ya da tablo yapıştır → önizle →
/// sepete ekle.
///
/// ## Dosyadan okuma (2026-10-01, kullanıcı: "tüm formattakileri çözüp
/// uygulamaya dahil edebilmeli… müşterinin ilk gelişini hızlandıracak")
/// Dosya `ekstreyiOku` ile okunur ve ANLAŞILIR (sütun rolleri başlık +
/// içerikten); sonuç kanonik sekmeli metin olarak aşağıdaki metin alanına
/// konur ve aynı `CsvImportService.parse` yolundan geçer. Böylece kullanıcı
/// okunanı görür, gerekirse elle düzeltir; satış/tür/fiyat kuralları tek
/// yerde kalır. Motor emin değilse eşleme kartı uyarır ve "Sütunları
/// düzelt" ile kullanıcı hangi sütunun ne olduğunu seçer.
///
/// Dosya seçici `file_selector` (flutter.dev): iOS'ta belge seçici, fotoğraf
/// izni istemez (`file_picker` bu yüzden seçilmedi — docs/EKSTRE_MOTORU.md).
///
/// Sepete ekler, KAYDETMEZ: kullanıcı toplu ekleme ekranında satırları
/// düzeltip tek seferde kaydeder (fiyatı boş satırların kapanışı orada
/// çekilir). `true` ile döner — çağıran sepeti tazeler.
class CsvImportScreen extends ConsumerStatefulWidget {
  const CsvImportScreen({super.key});

  @override
  ConsumerState<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends ConsumerState<CsvImportScreen> {
  final _ctrl = TextEditingController();
  CsvImportResult? _result;

  /// Dosyadan okunduysa motorun anlamı (eşleme kartı + düzeltme).
  EkstreOkumaSonucu? _ekstre;
  String? _dosyaAdi;
  bool _okunuyor = false;

  /// Kartın altında satır içi bilgi (kopyalandı, AI sonucu). Toast DEĞİL:
  /// bu ekranda toast kullanılmaz (toast_temizligi_test #25); mesaj
  /// eylemin yapıldığı kartta kalır.
  String? _kartMesaji;

  /// Metin yolu açık rızası verildi mi (0147). Yalnız rıza verildikten
  /// sonra kartta "onayı geri çek" bağlantısı çıkar; sayfa açılışında
  /// sunucuya sorulmaz (rıza ilk "Yapay zekâyla eşle"de istenir).
  bool _aiRizasi = false;

  /// Ekran görüntüsü okumasının sonucu (bayrak `ekran_goruntusu_maliyet`):
  /// düğmenin altında satır içi, toast değil (bu ekranda toast yok).
  String? _gorselMesaji;

  /// Adla yazılmış fonlar için TEFAS listesi alınamadı: her ad için ayrı
  /// "tanınmadı" demek yerine tek, nedenini söyleyen satır.
  bool _fonListesiAlinamadi = false;

  static const _ornek = 'Sembol;Adet;Fiyat;Tarih\n'
      'THYAO;100;312,40;05.03.2026\n'
      'TCD;250;;10.01.2026\n'
      'USD;500;32,10;';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Metin → önizleme. Dosyadan okunduysa vadeli mevduatlar (metne girmez:
  /// CSV yolu sözleşmeli türü bilerek reddeder) ve tanınmayan fonlar da
  /// eklenir — kullanıcı neyin GİRMEDİĞİNİ de görür.
  void _parse() {
    final e = _ekstre;
    final metin = _ctrl.text;
    final temel = metin.trim().isEmpty && e != null
        ? const CsvImportResult(rows: [], errors: [])
        : CsvImportService.parse(metin);
    if (e == null) {
      setState(() => _result = temel);
      return;
    }
    final l = context.l10n;
    setState(() => _result = CsvImportResult(
          rows: [...temel.rows, ...e.mevduatKalemleri()],
          errors: [
            ...temel.errors,
            if (_fonListesiAlinamadi && e.cozulemeyenFonlar.isNotEmpty)
              l.importFundListFailed
            else
              for (final ad in e.cozulemeyenFonlar)
                l.importFundNotRecognized(ad),
            for (final ad in e.fiyatiAlinamayanFonlar)
              l.importFundPriceMissing(ad),
            ...e.notlar,
          ],
        ));
  }

  /// Banka ekstresi fonu adla yazar; kod TEFAS unvanından (tek ve kesin
  /// eşleşme, `fonKoduBul`). Liste önbellekten gelir (24 saat); alınamazsa
  /// adlı satırlar içe aktarılmaz, önizleme nedenini söyler.
  bool get _hareketlerle => RemoteConfigService.instance.ekstreHareketleri;

  Future<EkstreOkumaSonucu> _fonAdlariniCoz(EkstreOkumaSonucu s) async {
    _fonListesiAlinamadi = false;
    // Hareketlerde geçen kod gerçek bir fon mu, liste söyler
    // (`hareketKodlari`): dönemde tamamen satılmış fon varlık tablosunda
    // yoktur, adını çözmek gerekmese de listeye bakılır.
    final hareketIcin = _hareketlerle && s.hareketler.isNotEmpty;
    if (s.cozulecekFonAdlari.isEmpty && !hareketIcin) return s;
    try {
      final fonlar = await TefasService.instance.fetchAllFunds();
      // `fetchAllFunds` ağ hatasını yutar ve BOŞ liste döner (fırlatmaz).
      // Boş listeyle her fon "tanınmadı" olur ve kullanıcı nedenini
      // göremez: banka ekstresindeki fonların hepsi sessizce düşüyordu
      // (yasin, 2026-10-05: "hata vermiyor ama varlıkları ayıklayamıyor").
      // Boş liste = alınamadı; uyarı ve yeniden deneme yolu görünür.
      if (fonlar.isEmpty) {
        _fonListesiAlinamadi = true;
        return s;
      }
      return s.kodlarla([for (final f in fonlar) (kod: f.code, unvan: f.name)]);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'ekstre_fon_listesi');
      _fonListesiAlinamadi = true;
      return s;
    }
  }

  /// Yalnız tutar yazan belge ("Varlık Geçmişi Formu", 2026-10-15): adet =
  /// tutar ÷ belge günündeki fiyat. Fiyat seriden okunur (BES sözleşmesinin
  /// geçmiş gün fiyatıyla aynı yol); alınamayan fon eklenmez, önizleme
  /// "fiyatı alınamadı" der.
  Future<EkstreOkumaSonucu> _tutarFiyatlariniAl(EkstreOkumaSonucu s) async {
    final gun = s.belgeTarihi;
    final kodlar = s.tutarFonKodlari;
    if (gun == null || kodlar.isEmpty) return s;
    final ay = (DateTime.now().difference(gun).inDays / 30).ceil();
    final aralik = ay <= 1
        ? '1mo'
        : ay <= 3
            ? '3mo'
            : ay <= 6
                ? '6mo'
                : ay <= 12
                    ? '1y'
                    : '3y';
    final fiyatlar = <String, double>{};
    for (final k in kodlar) {
      try {
        final seri =
            await PriceService.instance.fetchHistory('$tefasOneki$k', aralik);
        final f = gunFiyati(seri, gun);
        if (f != null) fiyatlar[k] = f;
      } catch (e, st) {
        CrashReporter.report(e, st, reason: 'ekstre_tutar_fiyati');
      }
    }
    return s.fiyatlarla(fiyatlar);
  }

  /// Önizleme başlığı — sonuç gelince görünür alana kaydırılır.
  final _sonucAnahtari = GlobalKey();

  /// Önizle düğmesi: sonuç düğmenin ALTINDA, ekran
  /// dışında çiziliyordu; kullanıcı düğmeye basınca hiçbir şey olmadı sanıp
  /// iki kez bastı (2026-10-02 müşteri testi). Sonuca kaydırılır.
  void _onizleVeGoster() {
    _parse();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _sonucAnahtari.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(ctx,
          duration: SandikMotion.surfaceOf(context),
          curve: SandikMotion.enter,
          alignment: 0.1);
    });
  }

  /// Önizleme tarihi — ekstredeki biçimle aynı (`21.01.2026`); yerel ayar
  /// verisine bağlı değil.
  static String _tarih(DateTime d) => '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Satırda gösterilen kod: iç önek/sonek olmadan (`ASELS.IS` → `ASELS`,
  /// `TEFAS:MAC` → `MAC`). Türü satırın ikonu söyler.
  static String _gorunenKod(String ticker) => ticker
      .replaceFirst(RegExp(r'^(TEFAS|KRIPTO):', caseSensitive: false), '')
      .replaceAll('.IS', '')
      .replaceAll('=X', '')
      .trim();

  static const _turler = [
    XTypeGroup(
      label: 'Ekstre',
      extensions: ['pdf', 'xlsx', 'xls', 'csv', 'txt', 'tsv', 'html', 'htm'],
      mimeTypes: [
        'application/pdf',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-excel',
        'text/csv',
        'text/plain',
        'text/tab-separated-values',
        'text/html',
      ],
      uniformTypeIdentifiers: [
        'com.adobe.pdf',
        'org.openxmlformats.spreadsheetml.sheet',
        'com.microsoft.excel.xls',
        'public.comma-separated-values-text',
        'public.tab-separated-values-text',
        'public.plain-text',
        'public.html',
      ],
    ),
  ];

  Future<void> _dosyaSec() async {
    final XFile? dosya;
    try {
      dosya = await openFile(acceptedTypeGroups: _turler);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'ekstre_dosya_secici');
      if (mounted) showAppError(context, e);
      return;
    }
    if (dosya == null || !mounted) return;
    setState(() => _okunuyor = true);
    try {
      final sonuc = await _tutarFiyatlariniAl(
          await _fonAdlariniCoz(await ekstreyiOku(await dosya.readAsBytes())));
      if (!mounted) return;
      _ekstre = sonuc;
      _dosyaAdi = dosya.name;
      _ctrl.text = sonuc.kanonikMetin(hareketlerle: _hareketlerle);
      // Kaydırma YOK: dosyadan okununca hemen altta eşleme kartı belirir
      // (görünür geri bildirim) ve kullanıcı önce onu doğrulamalı.
      _parse();
    } catch (e, st) {
      // Okuma hatası mesajı bizimdir (`EkstreOkumaHatasi`); beklenmeyen
      // her şey Crashlytics'e — hangi biçimin kırıldığını görmek için.
      if (e is! EkstreOkumaHatasi) {
        CrashReporter.report(e, st, reason: 'ekstre_okunamadi');
      }
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _okunuyor = false);
    }
  }

  /// Ekran görüntüsünden adet ve ortalama maliyet (bayrak
  /// `ekran_goruntusu_maliyet`, 2026-10-13; yasin: "bankalarda ekstrelerde
  /// varlıkların ortalama maliyetleri, alım zamanları yazmıyor").
  ///
  /// Metin alanında ekstre varsa yalnız MALİYET yazılır (adet ekstreden
  /// kalır, `maliyetleriUygula`); boşsa görüntünün kendisi kanonik metin
  /// olur. Görüntü cihazda okunur (`ekran_okuyucu.dart`), sunucuya gitmez.
  /// Premium: paywall açıkken ücretsizde paywall'a götürür.
  Future<void> _ekranGoruntusuSec() async {
    final l = context.l10n;
    if (ref.read(radarKilitliProvider)) {
      await PaywallScreen.show(context, source: 'ekran_goruntusu');
      return;
    }
    final List<XFile> gorseller;
    try {
      gorseller = await ImagePicker().pickMultiImage();
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'ekran_goruntusu_secici');
      if (mounted) showAppError(context, e);
      return;
    }
    if (gorseller.isEmpty || !mounted) return;
    setState(() => _gorselMesaji = null);
    try {
      final fonlar = await _fonListesiSessiz();
      final gruplar = <List<EkranVarligi>>[];
      for (final g in gorseller) {
        final hucreler = await ekranGoruntusunuOku(await g.readAsBytes());
        gruplar.add(ekranGoruntusunuAnla(hucreler, fonlar: fonlar));
      }
      final varliklar = ekranVarliklariniBirlestir(gruplar);
      if (!mounted) return;
      final mesaj = <String>[];
      final mevcut = _ctrl.text.trim();
      if (varliklar.isEmpty) {
        mesaj.add(l.importScreenshotNone);
      } else if (mevcut.isNotEmpty) {
        final r = maliyetleriUygula(mevcut, varliklar);
        mesaj.add(r.uygulanan > 0
            ? l.importScreenshotCostsApplied(r.uygulanan)
            : l.importScreenshotNoCost);
        if (r.bolunmus.isNotEmpty) {
          mesaj.add(l.importScreenshotSkipped(r.bolunmus.join(', ')));
        }
        if (r.ekstredeYok.isNotEmpty) {
          mesaj.add(l.importScreenshotNotInStatement(r.ekstredeYok.join(', ')));
        }
        if (r.uygulanan > 0) _ctrl.text = r.metin;
      } else {
        final metin = ekranKanonikMetni(varliklar);
        if (metin.isEmpty) {
          mesaj.add(l.importScreenshotNone);
        } else {
          _ctrl.text = metin;
          mesaj.add(l.importScreenshotRead(
              varliklar.where((v) => v.kod != null && v.adet != null).length));
        }
      }
      for (final v in varliklar) {
        if (v.kod == null && v.ad != null) {
          mesaj.add(l.importFundNotRecognized(v.ad!));
        }
      }
      setState(() => _gorselMesaji = mesaj.join('\n'));
      if (_ctrl.text.trim().isNotEmpty) _parse();
    } catch (e, st) {
      if (e is! EkstreOkumaHatasi) {
        CrashReporter.report(e, st, reason: 'ekran_goruntusu_okunamadi');
      }
      if (mounted) showAppError(context, e);
    }
  }

  /// Görüntüdeki fon kodlarını ve adlarını tanımak için TEFAS listesi.
  /// Alınamazsa boş: yalnız BIST hisseleri tanınır (hata göstermez,
  /// tanınmayan fon adı zaten "tanınmadı" satırıyla görünür).
  Future<List<({String kod, String unvan})>> _fonListesiSessiz() async {
    try {
      final fonlar = await TefasService.instance.fetchAllFunds();
      return [for (final f in fonlar) (kod: f.code, unvan: f.name)];
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'ekran_goruntusu_fon_listesi');
      return const [];
    }
  }

  /// AI sütun eşleme (bayrak `ekstre_ai_esleme`, 0121). Belge cihazdan
  /// çıkmaz: yalnız anonim iskelet (`ekstreIskeleti`) gider, yalnız sütun
  /// numaraları döner; değerler yine belgeden okunur. Kullanıcı düğmeye
  /// basmadan hiçbir şey gönderilmez. Metin yolunda (`ekstre_metin_yolu`)
  /// kelimeler de gider, rakamlar yine gitmez (`ekstreMetni`).
  Future<void> _aiIleEsle() async {
    final e = _ekstre;
    // Çift dokunuş koruması ve gösterge düğmede (SandikAsyncButton,
    // 2026-10-08 tek yükleniyor davranışı); eski `_aiEsleniyor` bayrağı
    // yalnızca bunu yapıyordu.
    if (e == null) return;
    final l = context.l10n;
    setState(() => _kartMesaji = null);
    try {
      // Metin yolu (bayrak `ekstre_metin_yolu`, 0147): kelimeler açık,
      // rakamlar maskeli; sunucu önce banka şablonu hafızasına bakar.
      // Şablonun eşlemesi sağlamayı geçmezse bir kez şablonsuz sorulur.
      final metinYolu = RemoteConfigService.instance.ekstreMetinYolu;
      // Rıza işlemi isteyen kişiden, istediği anda (yasin 2026-10-13:
      // "herkese peşinen değil de işlemi talep ettiklerinde sorsak").
      if (metinYolu && !await _aiRizasiAl()) return;
      final govde = metinYolu ? ekstreMetni(e) : ekstreIskeleti(e);
      final ilk = await SupabaseService.instance.ekstreEsle(govde);
      var yeni = e.aiEslemesiyle(ilk.tablolar, sablondan: ilk.sablondan);
      if (yeni == null && ilk.sablondan) {
        final ikinci = await SupabaseService.instance
            .ekstreEsle(govde, sablonsuz: true);
        yeni = e.aiEslemesiyle(ikinci.tablolar);
      }
      if (!mounted) return;
      if (yeni == null) {
        setState(() => _kartMesaji = l.importAiNoMatch);
        return;
      }
      final cozulmus = await _fonAdlariniCoz(yeni);
      if (!mounted) return;
      _ekstre = cozulmus;
      _ctrl.text = cozulmus.kanonikMetin(hareketlerle: _hareketlerle);
      _parse();
    } on EkstreAiHatasi catch (h) {
      if (!mounted) return;
      if (h.premium) {
        await PaywallScreen.show(context, source: 'ekstre_ai');
      } else if (h.riza) {
        // Rıza başka cihazda geri çekilmiş: bir sonraki dokunuşta sorulur.
        setState(() {
          _aiRizasi = false;
          _kartMesaji = l.importAiRizaGerekli;
        });
      } else {
        setState(
            () => _kartMesaji = h.kota ? l.importAiLimit : l.importAiFailed);
      }
    } catch (err, st) {
      CrashReporter.report(err, st, reason: 'ekstre_ai_esleme');
      if (mounted) setState(() => _kartMesaji = l.importAiFailed);
    }
  }

  /// Metin yolu açık rızası: kayıtlıysa sormaz; değilse sayfa açar,
  /// kabul edilirse sunucuya yazar. Vazgeç / kapatma → `false`, hiçbir şey
  /// gönderilmez.
  Future<bool> _aiRizasiAl() async {
    if (_aiRizasi) return true;
    final svc = SupabaseService.instance;
    if (await svc.ekstreAiRizasiVarMi() == true) {
      if (mounted) setState(() => _aiRizasi = true);
      return true;
    }
    if (!mounted) return false;
    final kabul = await showSandikSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AiRizaSayfasi(),
    );
    if (kabul != true) return false;
    await svc.ekstreAiRizasiAyarla(true);
    if (mounted) setState(() => _aiRizasi = true);
    return true;
  }

  Future<void> _aiRizasiniGeriCek() async {
    final l = context.l10n;
    try {
      await SupabaseService.instance.ekstreAiRizasiAyarla(false);
      if (mounted) {
        setState(() {
          _aiRizasi = false;
          _kartMesaji = l.importAiRizaGeriCekildi;
        });
      }
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  Future<void> _iskeletiKopyala() async {
    final e = _ekstre;
    if (e == null) return;
    final l = context.l10n;
    await Clipboard.setData(ClipboardData(text: ekstreIskeleti(e)));
    if (mounted) setState(() => _kartMesaji = l.importDiagnosticCopied);
  }

  Future<void> _eslemeyiDuzelt() async {
    final e = _ekstre;
    final ana = e?.ana;
    if (e == null || ana == null) return;
    final yeni = await showSandikSheet<Map<EkstreRol, int>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.c.surface1,
      builder: (_) => _EslemeSayfasi(anlam: ana),
    );
    if (yeni == null || !mounted) return;
    final duzeltilmis = e.anaDuzeltildi(yeni);
    _ekstre = duzeltilmis;
    _ctrl.text = duzeltilmis.kanonikMetin(hareketlerle: _hareketlerle);
    _parse();
  }

  void _addToCart() {
    final r = _result;
    if (r == null || r.isEmpty) return;
    final cart = ref.read(bulkCartProvider.notifier);
    for (final row in r.rows) {
      cart.add(row);
    }
    // Başarı toast'ı YOK (kullanıcı kararı, 2026-09-16): ekran kapanıp toplu
    // ekleme sepetine dönülüyor, satırlar orada listeleniyor. Sayıyı ayrıca
    // söylemek aynı bilgiyi iki kez veriyordu.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = _result;
    return Scaffold(
      backgroundColor: c.background,
      appBar: SandikAppBar(title: context.l10n.csvImportTitle),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 12,
              SandikSpace.screenH(context), 32),
          children: [
            Text(
              context.l10n.csvImportBody,
              style: context.t.bodyMedium?.copyWith(color: c.text58),
            ),
            const SizedBox(height: SandikSpace.md),
            // BİLİNÇLİ İSTİSNA (tek yükleniyor davranışı, 2026-10-08):
            // SandikAsyncButton DEĞİL. (1) Meşgulken etiket "Okunuyor…"
            // olur — standart bileşen etiketi gizler, aşama kaybolurdu.
            // (2) `_dosyaSec` önce sistem dosya seçicisini bekler; standart
            // düğme seçici açıkken de dönerdi. Burada gösterge yalnız dosya
            // seçildikten sonraki okuma sırasında, düğme o sırada pasif.
            FilledButton.icon(
              onPressed: _okunuyor ? null : _dosyaSec,
              icon: _okunuyor
                  ? const CustomLoadingIndicator(size: 18)
                  : const Icon(Icons.upload_file_rounded),
              label: Text(_okunuyor
                  ? context.l10n.importReading
                  : context.l10n.importPickFile),
            ),
            // Ekran görüntüsünden maliyet (bayrak `ekran_goruntusu_maliyet`).
            // Metin doluysa (ekstre okundu) etiket "Maliyetleri … doldur".
            if (RemoteConfigService.instance.ekranGoruntusuMaliyet) ...[
              const SizedBox(height: SandikSpace.sm),
              SandikAsyncButton(
                tur: SandikAsyncTur.cerceve,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                onPressed: _okunuyor ? null : _ekranGoruntusuSec,
                child: Text(_ctrl.text.trim().isEmpty
                    ? context.l10n.importScreenshotAdd
                    : context.l10n.importScreenshotFillCosts),
              ),
              const SizedBox(height: SandikSpace.xs),
              Text(
                context.l10n.importScreenshotHint,
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
              if (_gorselMesaji != null)
                Padding(
                  padding: const EdgeInsets.only(top: SandikSpace.xs),
                  child: Text(
                    _gorselMesaji!,
                    style: context.t.bodySmall?.copyWith(color: c.text90),
                  ),
                ),
            ],
            if (_ekstre != null) ...[
              const SizedBox(height: SandikSpace.md),
              _EslemeKarti(
                sonuc: _ekstre!,
                dosyaAdi: _dosyaAdi ?? '',
                onDuzelt: _eslemeyiDuzelt,
                onAi: _aiIleEsle,
                // Premium'a özel (yasin, 2026-10-05). Kilitliyken düğme yerine
                // paywall'a götüren kilit satırı; sunucu da ayrıca denetler.
                aiKilitli: ref.watch(radarKilitliProvider),
                aiGorunur: ref.watch(premiumOzellikleriGorunurProvider) ||
                    RemoteConfigService.instance.ekstreAiEsleme,
                mesaj: _kartMesaji,
                onRizaGeriCek: _aiRizasi ? _aiRizasiniGeriCek : null,
                onKopyala: _iskeletiKopyala,
              ),
            ],
            const SizedBox(height: SandikSpace.md),
            Text(
              context.l10n.importOrPaste,
              style: context.t.labelLarge?.copyWith(color: c.text58),
            ),
            const SizedBox(height: SandikSpace.sm),
            Container(
              padding: const EdgeInsets.all(SandikSpace.sm),
              decoration: context.surfaceCard(),
              child: Text(
                _ornek,
                style: context.t.bodySmall?.copyWith(
                  color: c.text58,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: SandikSpace.md),
            TextField(
              controller: _ctrl,
              minLines: 6,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              style: context.t.bodyMedium?.copyWith(
                color: c.text90,
                fontFamily: 'monospace',
              ),
              decoration: context.inputDecoration(context.l10n.pasteHere),
              // HER değişimde setState — koşulsuz.
              //
              // **Ölçülen arıza (kullanıcı bildirimi, 2026-09-16):** metin
              // yapıştırıldığı hâlde "Önizle" pasif kalıyordu. Koşul
              // `_result != null` idi; ilk yazışta `_result` zaten null
              // olduğu için setState HİÇ çağrılmıyor, ekran yeniden
              // çizilmiyor ve buton `_ctrl.text` BOŞKEN hesaplanmış
              // `onPressed: null` hâliyle kalıyordu. Kullanıcı ancak başka
              // bir şey rebuild tetiklerse (kaydırma, odak değişimi)
              // butonu açabiliyordu.
              //
              // Buton `_ctrl.text`'i doğrudan okuyor, yani metnin her
              // değişimi bir rebuild gerektiriyor. Eski önizlemeyi temizleme
              // işi koşullu kalabilir ama setState kalamaz.
              onChanged: (_) {
                setState(() {
                  // Metin değişti: önceki önizleme artık o metne ait değil.
                  if (_result != null) _result = null;
                  // Elle düzenlenen metin artık dosyanın eşlemesine ait
                  // değil — eşleme kartı yanlış şey söylemesin.
                  _ekstre = null;
                });
              },
            ),
            const SizedBox(height: SandikSpace.md),
            FilledButton.icon(
              onPressed: _ctrl.text.trim().isEmpty ? null : _onizleVeGoster,
              icon: const Icon(Icons.preview_rounded),
              label: Text(context.l10n.preview),
            ),
            if (r != null) ...[
              const SizedBox(height: SandikSpace.lg),
              Text(
                key: _sonucAnahtari,
                '${context.l10n.csvRowsRead(r.rows.length)}'
                '${r.errors.isEmpty ? '' : context.l10n.csvRowsSkipped(r.errors.length)}',
                style: context.t.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.text90,
                ),
              ),
              const SizedBox(height: SandikSpace.sm),
              for (final row in r.rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: SandikSpace.xs),
                  child: Row(
                    children: [
                      Icon(row.type.icon,
                          size: 16, color: row.type.onSurface(context)),
                      const SizedBox(width: SandikSpace.sm),
                      Expanded(
                        child: Text(
                          row.mevduat != null
                              ? context.l10n.importDepositRow(
                                  row.name,
                                  fmtTRY(row.quantity, digits: 2),
                                  fmtPct(row.mevduat!.yillikFaiz),
                                  row.mevduat!.vadeGun)
                              : '${row.satis ? '${context.l10n.cartSellTag} · ' : ''}'
                                  '${_gorunenKod(row.ticker)} · ${fmtNumFlex(row.quantity)} '
                                  '${row.unitType == 'piece' ? context.l10n.unitPiece : row.unitType}'
                                  ' · ${row.price > 0 ? (row.currency == 'TRY' ? '₺${fmtNumFlex(row.price)}' : '${fmtNumFlex(row.price)} ${row.currency}') : context.l10n.closePriceWillBeFetched}'
                                  // İşlem tarihi: ekstre alış ve satışları kendi
                                  // tarihiyle deftere yazar; kullanıcı önizlemede
                                  // doğru okunduğunu görmeli.
                                  ' · ${_tarih(row.addedDate)}',
                          style: context.t.bodySmall
                              ?.copyWith(color: row.satis ? c.loss : c.text90),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final e in r.errors)
                Padding(
                  padding: const EdgeInsets.only(bottom: SandikSpace.xs),
                  child: Text(e,
                      style: context.t.bodySmall?.copyWith(color: c.loss)),
                ),
              const SizedBox(height: SandikSpace.md),
              FilledButton.icon(
                onPressed: r.isEmpty ? null : _addToCart,
                icon: const Icon(Icons.playlist_add_check_rounded),
                label: Text('Sepete ekle (${r.rows.length})'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dosyadan okunan tablonun eşleme özeti: hangi sütun ne sayıldı, ne kadar
/// eminiz, neler atlandı.
class _EslemeKarti extends StatelessWidget {
  const _EslemeKarti({
    required this.sonuc,
    required this.dosyaAdi,
    required this.onDuzelt,
    required this.onAi,
    required this.aiKilitli,
    required this.aiGorunur,
    required this.mesaj,
    required this.onKopyala,
    this.onRizaGeriCek,
  });

  final EkstreOkumaSonucu sonuc;
  final String dosyaAdi;
  final VoidCallback onDuzelt;
  final Future<void> Function() onAi;
  final bool aiKilitli;

  /// Ekstre AI eşleme görünür mü (paywall açık ya da admin; 2026-10-09).
  final bool aiGorunur;
  final String? mesaj;
  final VoidCallback onKopyala;

  /// Metin yolu rızası verilmişse geri çekme (0147); yoksa `null`.
  final Future<void> Function()? onRizaGeriCek;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final a = sonuc.ana;
    final tarih = sonuc.belgeTarihi;
    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dosyaAdi,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.labelLarge?.copyWith(color: c.text58),
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            context.l10n.importMappingTitle,
            style: context.t.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: c.text90),
          ),
          const SizedBox(height: SandikSpace.sm),
          if (a != null)
            for (final r in EkstreRol.values)
              if (a.roller[r] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: SandikSpace.xxs),
                  child: Text(
                    '${r.ad} ← ${a.basliklar[a.roller[r]!]}',
                    style: context.t.bodySmall?.copyWith(color: c.text90),
                  ),
                ),
          if (a != null && a.eminDegil) ...[
            const SizedBox(height: SandikSpace.sm),
            Text(
              context.l10n.importLowConfidence,
              style: context.t.bodySmall?.copyWith(color: c.amberText),
            ),
          ],
          for (final n in a?.notlar ?? const <String>[])
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.xs),
              child: Text(
                n,
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
            ),
          // Tarih sütunu olmayan döküm: satırlar ekstre gününü aldı ve maliyet
          // o günün fiyatı — kullanıcı K/Z'nin nereden başladığını bilsin.
          if (tarih != null && sonuc.tutarFonlari.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.xs),
              child: Text(
                context.l10n.importAmountOnly(DateFormat('d MMM yyyy',
                        Localizations.localeOf(context).languageCode)
                    .format(tarih)),
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
            ),
          if (tarih != null &&
              a != null &&
              !a.roller.containsKey(EkstreRol.tarih))
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.xs),
              child: Text(
                context.l10n.importStatementDate(DateFormat('d MMM yyyy',
                        Localizations.localeOf(context).languageCode)
                    .format(tarih)),
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
            ),
          // Hareketlerden gerçek alış (bayrak `ekstre_hareketleri`): maliyet
          // ekstre günü fiyatı değil — kullanıcı neyin değiştiğini bilsin.
          if (RemoteConfigService.instance.ekstreHareketleri &&
              sonuc.hareketleIncelenen() > 0)
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.xs),
              child: Text(
                context.l10n.importTradesApplied(sonuc.hareketleIncelenen()),
                style: context.t.bodySmall?.copyWith(color: c.text90),
              ),
            ),
          if (sonuc.mevduatlar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.xs),
              child: Text(
                context.l10n.importDepositsFound(sonuc.mevduatlar.length),
                style: context.t.bodySmall?.copyWith(color: c.text90),
              ),
            ),
          if (a != null) ...[
            const SizedBox(height: SandikSpace.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onDuzelt,
                child: Text(context.l10n.importFixColumns),
              ),
            ),
          ],
          if (sonuc.aiOnerisi)
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.xs),
              child: Text(
                context.l10n.importAiSuggested,
                style: context.t.bodySmall?.copyWith(color: c.amberText),
              ),
            ),
          // AI sütun eşleme (bayrak `ekstre_ai_esleme`): henüz AI önerisi
          // alınmamış her ekstrede. Ne gittiği düğmenin üstünde yazar
          // (Gizlilik 1.6). İlk sürüm yalnız motor emin değilken
          // gösteriyordu; yasin (2026-10-08) admin hesabıyla "ekstremi ai ile
          // ayıklatamıyorum" dedi: motorun kendinden emin okuduğu ama
          // eksik/yanlış çıkardığı ekstrede kullanıcının elinde AI yolu
          // kalmıyordu. Motor emin olsa da kullanıcı isterse AI'a sorar.
          // Yalnız tutarlı belgede AI'ın bulacağı adet sütunu yok (2026-10-15).
          if (aiGorunur && !sonuc.aiOnerisi && sonuc.tutarFonlari.isEmpty) ...[
            const SizedBox(height: SandikSpace.xs),
            if (aiKilitli)
              KilitSatiri(
                  metin: context.l10n.prmKilitEkstreAi, kaynak: 'ekstre_ai')
            else ...[
              Text(
                // Metin yolunda "belge telefonundan çıkmaz" doğru değil.
                RemoteConfigService.instance.ekstreMetinYolu
                    ? context.l10n.importAiHintText
                    : context.l10n.importAiHint,
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: SandikAsyncButton.kompakt(
                  tur: SandikAsyncTur.metin,
                  onPressed: onAi,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  child: Text(context.l10n.importAiButton),
                ),
              ),
            ],
          ],
          if (onRizaGeriCek case final geriCek?)
            Align(
              alignment: Alignment.centerLeft,
              child: SandikAsyncButton.kompakt(
                tur: SandikAsyncTur.metin,
                onPressed: geriCek,
                child: Text(context.l10n.importAiRizaGeriCek),
              ),
            ),
          // Tanılama (bayrak `ekstre_tanilama`, 2026-10-05): motor dosyayı
          // tam anlamadıysa anonim iskelet kopyalanır; belge cihazdan çıkmaz,
          // kullanıcı metni kendisi gönderir. Anlaşılan dosyada gösterilmez.
          if (RemoteConfigService.instance.ekstreTanilama &&
              (a == null ||
                  a.eminDegil ||
                  sonuc.kanonikMetin().isEmpty ||
                  sonuc.cozulemeyenFonlar.isNotEmpty)) ...[
            const SizedBox(height: SandikSpace.xs),
            Text(
              context.l10n.importDiagnosticHint,
              style: context.t.bodySmall?.copyWith(color: c.text58),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onKopyala,
                icon: const Icon(Icons.content_copy_rounded, size: 18),
                label: Text(context.l10n.importCopyDiagnostic),
              ),
            ),
          ],
          if (mesaj != null)
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.xs),
              child: Text(
                mesaj!,
                style: context.t.bodySmall?.copyWith(color: c.text90),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rol başına sütun seçimi. Her seçenek başlık + ilk dolu örnek değerle
/// gösterilir ki başlıksız tablo da seçilebilsin ("Sütun 3 · THYAO").
class _EslemeSayfasi extends StatefulWidget {
  const _EslemeSayfasi({required this.anlam});

  final EkstreAnlami anlam;

  @override
  State<_EslemeSayfasi> createState() => _EslemeSayfasiState();
}

class _EslemeSayfasiState extends State<_EslemeSayfasi> {
  late final Map<EkstreRol, int> _secim = Map.of(widget.anlam.roller);

  String _etiket(int sutun) {
    final a = widget.anlam;
    final ornek = a.veri
        .map((s) => sutun < s.length ? s[sutun] : '')
        .firstWhere((h) => h.trim().isNotEmpty, orElse: () => '');
    return ornek.isEmpty
        ? a.basliklar[sutun]
        : '${a.basliklar[sutun]} · $ornek';
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.anlam;
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          SandikSpace.md,
          SandikSpace.md,
          SandikSpace.md,
          SandikSpace.md + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.importFixColumns,
            style: context.t.titleMedium?.copyWith(
                fontWeight: FontWeight.w800, color: context.c.text90),
          ),
          const SizedBox(height: SandikSpace.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final r in EkstreRol.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SandikSpace.sm),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(r.ad,
                              style: context.t.bodyMedium
                                  ?.copyWith(color: context.c.text90)),
                        ),
                        Expanded(
                          child: DropdownButton<int>(
                            isExpanded: true,
                            // null: büyük yazıda satır büyür, metin dikeyde
                            // kesilmez (büyük yazı taraması 2026-10-12).
                            itemHeight: null,
                            value: _secim[r] ?? -1,
                            items: [
                              DropdownMenuItem(
                                value: -1,
                                child: Text(l10n.importColumnNone),
                              ),
                              for (var i = 0; i < a.basliklar.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(_etiket(i),
                                      overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (v) => setState(() {
                              if (v == null || v < 0) {
                                _secim.remove(r);
                              } else {
                                // Bir sütun tek role: başka rolden alınır.
                                _secim.removeWhere((_, c) => c == v);
                                _secim[r] = v;
                              }
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_secim),
            child: Text(l10n.importApply),
          ),
        ],
      ),
    );
  }
}

/// Metin yolu açık rızası (0147 `ekstre_ai_rizalari`), ilk "Yapay zekâyla
/// eşle"de. Portföy yorumu rızası deseni (`portfoy_yorumu_karti.dart`):
/// isteğe bağlı; "Vazgeç" ya da aşağı çekip kapatmak hiçbir şey göndermez.
class _AiRizaSayfasi extends StatelessWidget {
  const _AiRizaSayfasi();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    final yatay = SandikSpace.screenH(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(yatay, 0, yatay, SandikSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.importAiRizaBaslik,
                style: t.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
            const SizedBox(height: SandikSpace.sm),
            Text(l.importAiRizaMetin,
                style: t.bodyMedium?.copyWith(color: c.text58)),
            const SizedBox(height: SandikSpace.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.importAiRizaKabul),
            ),
            const SizedBox(height: SandikSpace.sm),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: SandikTouch.minSize),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.importAiRizaVazgec),
            ),
          ],
        ),
      ),
    );
  }
}
