import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/abd_hisseleri.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/asset_categories.dart';
import '../models/emtia_katalogu.dart';
import '../models/hizli_hesap.dart';
import '../models/eurobond.dart';
import '../models/ilk_varlik_secimi.dart';
import '../models/altin_kisayollari.dart';
import '../models/kripto_fiyat.dart';
import '../models/varlik_kimligi.dart';
import '../providers/add_asset_form_provider.dart';
import '../providers/bulk_cart_provider.dart';
import '../providers/eurobond_provider.dart';
import '../providers/kripto_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/portfoy_provider.dart';
import '../widgets/portfoy_secici.dart';
import '../services/bist_hisse_katalogu.dart';
import '../services/tefas_service.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_acilir.dart';
import '../services/crash_reporter.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../widgets/h_scroll_with_fade.dart';
import '../widgets/sandik_segment.dart';
import 'paywall_screen.dart';
import '../widgets/para_akisi_karti.dart' show KilitSatiri;
import 'bulk_add_asset_screen.dart';
import 'csv_import_screen.dart';
import 'varlik_sayfasi.dart';
import '../widgets/alarm_kur_sheet.dart' show AlarmAdayi, alarmSembolu;
import '../widgets/custom_loading_indicator.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/ekran_goruntusu_ekle.dart';
import '../widgets/tour_anchor.dart';
import '../widgets/varlik_guncelle.dart' show VarlikGuncelleUyarisi;
import '../l10n/l10n.dart';
import 'add_asset/bes_formu.dart';
import 'add_asset/mevduat_formu.dart';
import 'add_asset/tur_secici_izgara.dart';
import '../models/tur_secici_duzeni.dart';
import '../widgets/sozlesme_formu_ortak.dart';
import '../services/varlik_eklendi.dart';

part 'add_asset/kimlik_alanlari.dart';
part 'add_asset/tutar_alanlari.dart';
part 'add_asset/secici_alanlari.dart';
part 'add_asset/kayit.dart';
part 'add_asset/secici_sayfalari.dart';

const _addAssetUuid = Uuid();

// Klavye kuralı (kullanıcı, 2026-09-25): "klavye otomatik açılmamalı,
// textbox'a tıklayınca açmalı, dışarı tıklandığında kapatılabilmeli."
// Bu yüzden ekranda ve seçici/hızlı giriş sayfalarında `autofocus` yok;
// her alan `onTapOutside` ile odağı bırakır (Flutter'ın varsayılanı
// dokunmatikte dışarı dokunuşu yok sayar, yalnızca fareyle kapatır).
// Alt sayfa açılmadan önce de odak bırakılır: kapanan sayfa odağı önceki
// alana geri verdiğinde klavye kendiliğinden yeniden açılmasın.
void _klavyeyiKapat([PointerDownEvent? _]) =>
    FocusManager.instance.primaryFocus?.unfocus();

// Döviz sabitleri, hızlı giriş modeli ve durum makinesi
// `providers/add_asset_form_provider.dart`'ta (Faz 3.10).

// ─── Decimal formatter ────────────────────────────────────────────────────────

class _DecimalFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    // Allow digits, comma, dot. Only one decimal separator.
    final filtered = next.text.replaceAll(RegExp(r'[^\d.,]'), '');
    if (filtered == next.text) return next;
    return next.copyWith(
      text: filtered,
      selection: TextSelection.collapsed(offset: filtered.length),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class AddAssetScreen extends ConsumerStatefulWidget {
  final Asset? editingAsset;

  /// Sepete ekleme modu: kaydetmek yerine bulkCartProvider'a push edilir.
  final bool cartMode;

  /// Sepetten düzenleme: mevcut sepet öğesinin değerlerini prefill için.
  final BulkCartItem? cartInitial;

  /// Karşılaştırma ekranından gelen ön seçim — henüz sahip OLUNMAYAN bir
  /// varlık için tür/ticker/ad hazır gelir, kullanıcı yalnızca miktar,
  /// fiyat ve tarih girer.
  ///
  /// [editingAsset] ve [cartInitial]'dan farkı: onlar var olan bir kaydı
  /// düzenler, bu ise YENİ kayıt için yalnızca kimlik alanlarını doldurur.
  final String? prefillTicker;
  final String? prefillName;
  final AssetType? prefillType;

  /// Halka arz katılım kaydından (F6) gelen alış fiyatı ve tarihi. İkisi de
  /// İSTEĞE BAĞLI: `null` iken form eskisi gibi açılır (fiyat boş, tarih
  /// bugün). Doluyken fiyat alanı yazılı gelir; kullanıcı fiyatı kendisi
  /// girmiş sayıldığından önizleme ağa çıkmaz — işlem görmeye henüz
  /// başlamamış hissenin kotasyonu zaten yoktur. Düzenleme/sepet değerleri
  /// her zaman kazanır.
  final double? prefillPrice;
  final DateTime? prefillDate;

  /// Boş ana ekrandaki "Ne biriktiriyorsun?" seçimi (2026-10-04, ilk
  /// varlık kolaylığı). Tür her zaman, gram altın / dolar / euro'da varlık
  /// da seçili açılır; kullanıcıya yalnız miktar kalır. Düzenleme ve sepet
  /// değerleri yine kazanır (prefill kuralı).
  final IlkVarlikSecimi? hizliSecim;

  /// Genel aramadaki "5 çeyrek ≈ ₺X" satırı (2026-10-24): [hizliSecim] gibi
  /// tür + varlık seçili açılır, ayrıca MİKTAR da yazılı gelir. Ayrı bir
  /// parametre, çünkü vitrin yalnız dört varlık bilir; arama her altın
  /// türünü ve GBP'yi tanır. Seçim aynı geçişlerle uygulanır
  /// ([_hizliSecimiUygula]); düzenleme ve sepet değerleri yine kazanır.
  final HizliHesap? hizliHesap;

  /// "Varlığı güncelle" kipi (`varlik_guncelle.dart`, bayrak `goz_alici`):
  /// [editingAsset] pozisyonun görünümüdür (net miktar, ağırlıklı maliyet,
  /// ilk alış tarihi), bunlar ise yerine geçilecek lotlar. Kayıt bir
  /// DÜZENLEME değildir: onaydan sonra lotlar Sil gibi gider, form tek alım
  /// olarak eklenir (`PortfolioNotifier.pozisyonuYenidenKur`). `null` iken
  /// form birebir eskisi.
  final List<Asset>? yerineGecenLotlar;

  /// Formun hangi yüzeyden açıldığı — yalnız ölçüm (`asset_added.yol`,
  /// bkz. `AnalyticsService.eklemeYollari`). `null` → `form`. Davranışı
  /// değiştirmez.
  final String? ekleYolu;

  const AddAssetScreen({
    super.key,
    this.editingAsset,
    this.yerineGecenLotlar,
    this.cartMode = false,
    this.cartInitial,
    this.prefillTicker,
    this.prefillName,
    this.prefillType,
    this.prefillPrice,
    this.prefillDate,
    this.hizliSecim,
    this.hizliHesap,
    this.ekleYolu,
  });

  @override
  ConsumerState<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends ConsumerState<AddAssetScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _ticker;
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  late final TextEditingController _notes;
  late final TextEditingController _commission;

  // Durum makinesi `addAssetFormProvider`'da (Faz 3.10). Aşağıdaki getter'lar
  // eski alan adlarını korur ki 2000 satırlık widget ağacı dokunulmadan
  // okumaya devam etsin; YAZMA yalnızca `_n` (notifier) üzerinden yapılır.
  late final AddAssetFormArgs _args = AddAssetFormArgs(
    editingAsset: widget.editingAsset,
    cartInitial: widget.cartInitial,
    prefillTicker: widget.prefillTicker,
    prefillType: widget.prefillType ??
        widget.hizliSecim?.tur ??
        widget.hizliHesap?.tur,
    prefillDate: widget.prefillDate,
  );
  AddAssetFormState get _s => ref.read(addAssetFormProvider(_args));
  AddAssetFormNotifier get _n =>
      ref.read(addAssetFormProvider(_args).notifier);

  AssetType get _type => _s.type;
  String? get _subCategory => _s.subCategory;
  String get _unitType => _s.unitType;
  String get _currency => _s.currency;
  DateTime get _addedDate => _s.addedDate;
  bool get _saving => _s.saving;
  double? get _previewPrice => _s.previewPrice;
  bool get _previewLoading => _s.previewLoading;
  bool get _previewIsHistorical => _s.previewIsHistorical;
  String? get _bist100SelectedTicker => _s.bist100Ticker;
  TefasFund? get _selectedFund => _s.selectedFund;
  bool get _notesExpanded => _s.notesExpanded;

  static const _currencies = ['TRY', 'USD', 'EUR', 'GBP'];
  bool get _isEditing => widget.editingAsset != null;

  /// Güncelleme kipi — düzenleme gibi görünür (dolu form, portföy seçici
  /// yok), ama kayıt sil + ekle'dir.
  bool get _yenidenKur => widget.yerineGecenLotlar != null;

  /// Güncelleme onayı açık mı (görünüm durumu değil; `setState` gerekmez).
  bool _onaySoruluyor = false;

  /// Kayıt başarıyla bitti: ekleme ise duyurulur (Portföy "Tümü"de açılır,
  /// yeni satır parlar — `VarlikEklendi`), sonra form [sonuc] ile kapanır.
  /// Düzenleme ve sepet modu yeni varlık eklemez, duyurmaz.
  void _kayitBitti(Object sonuc) {
    if (!_isEditing && !widget.cartMode) {
      VarlikEklendi.duyur(
          pozisyonAnahtari:
              ref.read(portfolioProvider.notifier).sonEklenenPozisyon);
    }
    Navigator.pop(context, sonuc);
  }

  // Sözleşmeli türler (mevduat, BES) kendi formlarıyla girilir; bkz.
  // `add_asset/sozlesme_formu_ortak.dart`. Genel formun durumu onlara hiç
  // dokunmaz — tür çipi yalnızca gövdeyi değiştirir.
  final _mevduatFormu = GlobalKey<MevduatFormuState>();
  final _besFormu = GlobalKey<BesFormuState>();

  /// Bu ekranda sözleşme formu mu açık (yeni kayıt, sepet değil)?
  bool get _sozlesmeFormuAcik =>
      _type.sozlesmeli && !_isEditing && !widget.cartMode;

  /// Kayıt bayrağı genel formunkiyle aynı (`addAssetFormProvider.saving`):
  /// ekran durum alanı taşımaz (Faz 3.10 ratchet).
  /// Formda seçilen portföy (0133, `formPortfoyuProvider`); seçilmediyse o
  /// an seçili portföy, o da yoksa Ana (`null`). Bayrak kapalıyken notifier
  /// zaten yok sayar.
  String? get _hedefPortfoy {
    final secim = ref.read(formPortfoyuProvider);
    return secim != null ? secim.id : ref.read(varsayilanYeniPortfoyProvider);
  }

  Future<void> _sozlesmeKaydet() async {
    if (_saving) return;
    final SozlesmeFormu? form = _type == AssetType.mevduat
        ? _mevduatFormu.currentState as SozlesmeFormu?
        : _besFormu.currentState;
    if (form == null) return;
    _n.setSaving(true);
    final tamam = await form.kaydet(portfoyId: _hedefPortfoy);
    if (!mounted) return;
    if (tamam) {
      // Bayrak açık kalır: kapanış animasyonunda buton yeniden basılmasın
      // (genel `_save` ile aynı gerekçe).
      _kayitBitti(true);
      return;
    }
    _n.setSaving(false);
  }
  bool get _isBist100 => _s.isBist100;
  bool get _isFon => _s.isFon;
  bool get _isDoviz => _s.isDoviz;

  @override
  void initState() {
    super.initState();
    final a = widget.editingAsset;
    final c = widget.cartInitial;

    // Prefill (karşılaştırma ekranından) en SONDA gelir: var olan bir kayıt
    // düzenleniyorsa onun değerleri her zaman kazanır.
    final initName = a?.name ?? c?.name ?? widget.prefillName ?? '';
    final initTicker = a?.ticker ?? c?.ticker ?? widget.prefillTicker ?? '';
    final initQty =
        a?.quantity ?? c?.quantity ?? widget.hizliHesap?.miktar ?? 0;
    // Eurobondda kayıtlı fiyat birim değerdir (kirli/100); alan TEMİZ %
    // gösterir. Sözleşme yüklenince `_eurobondYukle` çevirip yazar — o
    // zamana kadar boş (0,9873'ü "temiz fiyat" diye göstermek yanlış olurdu).
    final eurobondKaydi = (a?.type ?? c?.type) == AssetType.eurobond;
    // Alış fiyatı okunamadan kaydedilmiş lotta (0162) kayıtlı değer o günün
    // fiyatıdır, kullanıcının maliyeti değil: alan BOŞ açılır ki "bilgi
    // eksik" akışından gelen kullanıcı tahmini kendi girdisi sanıp onaylamasın.
    final hamFiyat = eurobondKaydi || a?.maliyetBilinmiyor == true
        ? 0.0
        : a?.purchasePrice ?? c?.price ?? widget.prefillPrice ?? 0;
    // Güncellemede gelen fiyat lotların AĞIRLIKLI ortalamasıdır — kaynağın
    // gönderdiği bir sayı değil, uygulamanın hesabı. Uygulama hesabı 4
    // haneye kırpılır (#158 kuralı); 275,66181818 gibi bir ön değer
    // kullanıcıya "bunu ben mi girdim?" dedirtirdi.
    final initPrice = widget.yerineGecenLotlar != null
        ? (hamFiyat * 10000).roundToDouble() / 10000
        : hamFiyat;

    _name = TextEditingController(text: initName);
    _ticker = TextEditingController(text: initTicker);
    _quantity = TextEditingController(text: initQty > 0 ? _fmt(initQty) : '');
    _price = TextEditingController(text: initPrice > 0 ? _fmt(initPrice) : '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _commission = TextEditingController(
        text: (a?.commission ?? 0) > 0 ? _fmt(a!.commission) : '');
    // Form açılışında preview'ı bir kere tetikle. Hızlı seçim AYNI karede ve
    // önce: seçim geçişleri (`selectGold`, `selectDoviz`) sağlayıcıya yazar,
    // `initState` içinde yazmak kurulum sırasında değişiklik hatası verir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _hizliSecimiUygula();
      _refreshPricePreview();
      _eurobondYukle();
      // Vazgeç onayının ölçütü: açılıştaki (hızlı seçim uygulanmış) hâl.
      _ilkMetinler = _kullaniciMetinleri();
      _metinler.addListener(_kirliliginiGuncelle);
    });
  }

  // ── Vazgeç onayı (2026-10-20 incelemesi, HIG §6 "gerçek risk") ───────────
  //
  // Tam ekran modal; yarım girilmiş miktar/komisyon/not kaydırınca ya da
  // geri basınca sessizce kayboluyordu (toplu eklemede koruma vardı, burada
  // yoktu). Fiyat ÖLÇÜT DEĞİL: önizleme onu kendisi doldurur, kullanıcının
  // emeği sayılmaz. Bayrak yalnız temiz↔kirli dönüşünde yeniden kurar;
  // her tuşta ekranı yeniden kurmamak için `PopScope` bir
  // `ValueListenableBuilder` ile sarılır, Scaffold `child` olarak geçer.
  List<String>? _ilkMetinler;
  final _kirli = ValueNotifier<bool>(false);

  List<String> _kullaniciMetinleri() =>
      [_quantity.text.trim(), _commission.text.trim(), _notes.text.trim()];

  void _kirliliginiGuncelle() {
    final ilk = _ilkMetinler;
    if (ilk == null) return;
    final simdi = _kullaniciMetinleri();
    var farkli = false;
    for (var i = 0; i < ilk.length; i++) {
      if (ilk[i] != simdi[i]) farkli = true;
    }
    _kirli.value = farkli;
  }

  Future<void> _vazgecmeyiSor() async {
    final l = context.l10n;
    final sil = await showSandikConfirm(
      context: context,
      title: l.addAssetVazgecBaslik,
      message: l.addAssetVazgecMetin,
      confirmLabel: l.addAssetVazgecSil,
      cancelLabel: l.addAssetVazgecKal,
      destructive: true,
    );
    if (sil && mounted) Navigator.of(context).pop();
  }

  /// Düzenlenen / sepetteki eurobond lotunun sözleşmesini katalogdan yükler
  /// ve kayıtlı birim değeri temiz %'ye çevirip fiyat alanına yazar.
  /// Yüklenemezse kimlik uyarısı kaydı durdurur (gerekçe
  /// `AddAssetFormState.kimlikEksigi`); kullanıcı seçiciden yeniden seçer.
  Future<void> _eurobondYukle() async {
    if (_type != AssetType.eurobond) return;
    final isin = eurobondIsin(_ticker.text);
    if (isin == null) return;
    final birim =
        widget.editingAsset?.purchasePrice ?? widget.cartInitial?.price;
    try {
      final r = await ref.read(eurobondProvider(isin).future);
      if (!mounted || r == null || _type != AssetType.eurobond) return;
      _yaz(_n.selectEurobond(r.$1, r.$2,
          priceEmpty: _price.text.isEmpty, duzenlemeBirimDegeri: birim));
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'add_asset.eurobond_yukle');
    }
  }

  /// [AddAssetScreen.hizliSecim]'i formun KENDİ seçim geçişleriyle uygular:
  /// çipe dokunmuş gibi. Ayrı bir ön doldurma yolu yazılmadı; altın birimi
  /// (gram), döviz para birimi (TRY karşılığı) ve elle fiyat bayrağı o
  /// geçişlerin kuralı.
  void _hizliSecimiUygula() {
    final s = widget.hizliSecim;
    final h = widget.hizliHesap;
    if ((s == null && h == null) ||
        _isEditing ||
        widget.cartInitial != null) {
      return;
    }
    if (s?.altinAltTuru ?? h?.altin case final g?) {
      _yaz(_n.selectGold(g));
    } else if (s?.dovizEtiketi ?? h?.doviz case final etiket?) {
      _yaz(_n.selectDoviz(dovizOptFor(etiket)));
    }
  }

  /// "Ekstreden aktar": içe aktarma sepeti doldurur, onay Toplu Ekle'de.
  /// Toplu ekleme bitince bu form da kapanır (uygulama çubuğundaki Toplu
  /// Ekle ile aynı kural: arkada boş formda mahsur kalınmasın).
  Future<void> _ekstredenAktar() async {
    final aktarildi = await pushGuarded<bool>(
      context,
      adaptiveRoute(settings: const RouteSettings(name: 'csv_import'), builder: (_) => const CsvImportScreen()),
    );
    if (aktarildi != true || !mounted) return;
    final eklendi = await pushGuarded<bool>(
      context,
      adaptiveRoute(settings: const RouteSettings(name: 'bulk_add_asset'), builder: (_) => const BulkAddAssetScreen()),
    );
    if (eklendi == true && mounted) Navigator.of(context).pop(true);
  }

  /// Sadeleştirme 2 (2026-10-04; bayrak `ilk_varlik_kolay` 2026-10-05'te
  /// kalktı, davranış kalıcı): yeni kayıtta iki hızlı yol
  /// görünür düğme, komisyon + not "Ayrıntı ekle" altında. Düzenleme ve
  /// sepet modunda form eskisi gibi: orada kullanıcı zaten bir kaydın
  /// ayrıntısındadır.
  /// Tur hedefi `topluEkle` TEK yerde kurulur: yeni kayıtta formdaki
  /// "Ekstreden aktar" düğmesinde, düzenleme/sepette uygulama çubuğundaki
  /// Toplu Ekle ikonunda.
  Widget _topluCapa(Widget w) =>
      _kolay ? w : TourAnchor(target: TourTarget.topluEkle, child: w);

  bool get _kolay => !_isEditing && !widget.cartMode;

  @override
  void dispose() {
    _metinler.removeListener(_kirliliginiGuncelle);
    _kirli.dispose();
    for (final c in [_name, _ticker, _quantity, _price, _notes, _commission]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Bir geçişin döndürdüğü metin alanı yazımlarını controller'lara uygular.
  void _yaz(AlanYazimi y) {
    if (y.name != null) _name.text = y.name!;
    if (y.ticker != null) _ticker.text = y.ticker!;
    if (y.quantity != null) _quantity.text = y.quantity!;
    if (y.price != null) _price.text = y.price!;
  }

  // ── Preview: seçili varlık + tarih için tahmini birim fiyat ──────────────
  String? _resolveTickerForPreview() => _s.resolveTicker(_ticker.text);

  void _schedulePricePreview() => _n.schedulePreview(
        userPrice: _parse(_price.text),
        tickerText: _ticker.text,
      );

  Future<void> _refreshPricePreview() {
    if (!mounted) return Future.value();
    return _n.refreshPreview(
      userPrice: _parse(_price.text),
      tickerText: _ticker.text,
    );
  }

  String _fmt(double v) => AddAssetFormNotifier.fmtInput(v);

  double? _parse(String text) {
    // Türkçede `.` BİNLİK ayracıdır. Eski hâli `replaceAll(',', '.')` idi ve
    // "1.000" girdisini 1.0 olarak okuyordu; kullanıcı 1000 adet yazıp
    // portföyüne 1 adet kaydediyordu.
    final val = parseTrNumber(text);
    if (val == null) return null;
    // Aşırı büyük değerleri engelle (Simetrik UI için limit)
    if (val > 1000000000000) return 999999999999;
    return val;
  }

  // Kripto biriminin adı coin kodudur ("0,05 BTC"), `unitType` değil.
  String get _quantitySuffix => switch (_type) {
        AssetType.kripto => kriptoKodu(_ticker.text) ?? '',
        AssetType.emtia when !_s.emtiaElle =>
          switch (emtiaSecenegi(_ticker.text)) {
            final e? => _emtiaBirimi(e.birim),
            null => _s.quantitySuffix,
          },
        _ => _s.quantitySuffix,
      };
  List<String> get _quantityPresets => _s.quantityPresets;

  // ── Build ──────────────────────────────────────────────────────────────────

  // `ustHarf`, düz `toUpperCase` değil: Dart Türkçe bilmez, "Hisse" →
  // "HISSE", "Kripto para" → "KRIPTO PARA" (noktasız) basıyordu
  // (2026-09-27 emülatör turu). Bkz. l10n.dart.
  /// Ücretsiz varlık kotası satırı (`varlikKotasiProvider`). Yalnız sona
  /// yaklaşınca (son üç hak) ya da dolunca çıkar: her açılışta sayaç
  /// göstermek ücretsiz kullanıcıyı sürekli sınırla karşılardı. Dolunca
  /// satır paywall'u açar; var olan varlığa alım yine serbest (kota yeni
  /// varlığı sayar).
  Widget _kotaSatiri() {
    final kota = ref.watch(varlikKotasiProvider);
    if (kota == null) return const SizedBox.shrink();
    final kalan = kota.sinir - kota.kullanilan;
    if (kalan > 3) return const SizedBox.shrink();
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.md),
      child: kalan <= 0
          ? KilitSatiri(
              metin: l.varlikKotasiDolu(kota.sinir),
              kaynak: 'asset_limit_form',
            )
          : Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: SandikSpace.md, color: context.c.text58),
                const SizedBox(width: SandikSpace.sm),
                Expanded(
                  child: Text(
                    l.varlikKotasiKalan(kalan, kota.sinir),
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        ustHarf(text, context.l10n),
        style: context.t.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: context.c.text58,
        ),
      );

  /// Alan etiketi. Tek satır + kısaltma **varsayılan**: bu etiketler dar
  /// kolonlarda (Miktar/Fiyat yan yana) ve büyük metin ayarında taşıyordu.
  /// Çağıran ayrıca `Flexible` ile sarmalı — `overflow` yalnızca kısıt
  /// verilmişse iş görür.
  Widget _fieldLabel(String text) => Text(
        text,
        style: context.t.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: context.c.text90,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  /// Toplam maliyet, önizleme kartı, preset çipleri ve not rozeti metin
  /// alanlarını okur; eski kod her tuş vuruşunda tüm ekranı yeniden kuruyordu.
  /// Controller'lar zaten `Listenable`: tek dinleyiciyle aynı yeniden çizim.
  late final Listenable _metinler =
      Listenable.merge([_quantity, _price, _commission, _notes]);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Durum değişimi bu ekranı yeniden kurar; getter'lar `ref.read` ile aynı
    // değeri okur.
    ref.watch(addAssetFormProvider(_args));

    final saveLabel = widget.cartMode
        ? (widget.cartInitial != null ? context.l10n.save : 'Sepete Ekle')
        : (_isEditing ? context.l10n.update : context.l10n.add);
    final title = widget.cartMode
        ? (widget.cartInitial != null ? 'Sepette Düzenle' : 'Sepete Ekle')
        : _yenidenKur
            ? context.l10n.varlikGuncelleBaslik
            : (_isEditing ? context.l10n.editAsset : context.l10n.addAssetTitle);

    final ekran = Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(
        titleWidget: Text(
          title,
          style: context.t.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700, color: context.c.text90),
        ),
        actions: [
          if (!_isEditing && !widget.cartMode) ...[
            _topluCapa(
              IconButton(
              tooltip: context.l10n.bulkAdd,
              icon: Icon(Icons.playlist_add_rounded, color: context.c.text58),
              // Toplu ekleme başarıyla bittiğinde `true` döner; o zaman bu
              // ekran da kapanır ve kullanıcı portföye ulaşır. Aksi halde
              // arkada boş kalan bu formda mahsur kalıyordu.
              onPressed: () async {
                final added = await pushGuarded<bool>(
                  context,
                  adaptiveRoute(settings: const RouteSettings(name: 'bulk_add_asset'), builder: (_) => const BulkAddAssetScreen()),
                );
                if (added == true && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              ),
            ),
            TourAnchor(
              target: TourTarget.hizliGiris,
              child: IconButton(
                tooltip: context.l10n.quickEntryVoice,
                icon: Icon(Icons.mic_none_rounded, color: context.c.text58),
                onPressed: _showQuickEntrySheet,
              ),
            ),
          ],
        ],
      ),
      body: ListenableBuilder(
        listenable: _metinler,
        builder: (context, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _klavyeyiKapat,
        child: Form(
          key: _formKey,
          // Gerekçe `AddAssetFormState.denendi`'de.
          autovalidateMode: _s.denendi
              ? AutovalidateMode.always
              : AutovalidateMode.disabled,
          child: Column(
            children: [
              Expanded(
                // `SingleChildScrollView` + `Column`, tembel `ListView` DEĞİL
                // (2026-09-30). Tembel liste ekran dışına kayan form alanını
                // ATAR; `FormField.didChangeDependencies`'in planladığı kare
                // sonrası geri çağrı atılmış alana dokununca "RestorableStringN
                // was used after being disposed" düşüyordu (tür seçici iki
                // çiple bir satır uzayınca 844pt ekranda doğrulama → yazma
                // akışında ölçüldü; `varlik_kimlik_dogrulama_test`). Form bir
                // düzine blok: hepsini kurulu tutmak ucuz, alan durumu da
                // kaydırmada kaybolmaz.
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 4, SandikSpace.screenH(context), 24),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_kolay) ...[
                      _ikiYol(),
                      const SizedBox(height: SandikSpace.sm),
                      _ekranGoruntusuYolu(),
                      const SizedBox(height: SandikSpace.lgs),
                    ],
                    if (_yenidenKur) ...[
                      const SizedBox(height: SandikSpace.sm),
                      VarlikGuncelleUyarisi(
                          hareketSayisi: widget.yerineGecenLotlar!.length),
                      const SizedBox(height: SandikSpace.lgs),
                    ],
                    if (!_isEditing && !_yenidenKur && !widget.cartMode)
                      _kotaSatiri(),
                    _sectionLabel(context.l10n.assetType),
                    const SizedBox(height: 10),
                    _turIzgarasi(),
                    const SizedBox(height: 22),

                    // Izgara açıkken form gövdesi yok: önce "ne ekliyorsun"
                    // (gerekçe `AddAssetFormState.turIzgarasiAcik`).
                    if (_s.turIzgarasiAcik)
                      const SizedBox.shrink()
                    else if (_type.sozlesmeli) ...[
                      if (_sozlesmeFormuAcik)
                        _type == AssetType.mevduat
                            ? MevduatFormu(key: _mevduatFormu)
                            : BesFormu(key: _besFormu)
                      else
                        // Düzenleme: sözleşmeli lot genel formdan (miktar ×
                        // fiyat) değiştirilmez; birim değer ve pay adedi
                        // sözleşmeden gelir.
                        SandikCard(
                          child: Text(
                            context.l10n.contractManagedNotice,
                            style: context.t.bodyMedium
                                ?.copyWith(color: context.c.text58),
                          ),
                        ),
                    ] else ...[
                    // ── Kimlik: Bağlama göre TEK giriş alanı ──────────────
                    _sectionLabel(_identityLabel()),
                    const SizedBox(height: 10),
                    _identitySection(cs),
                    const SizedBox(height: 22),

                    // ── Miktar + Fiyat yan yana ───────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _quantityBlock(cs)),
                        const SizedBox(width: 12),
                        Expanded(child: _priceBlock(cs)),
                      ],
                    ),
                    _eurobondFaizSatiri(),
                    const SizedBox(height: 10),
                    _quantityPresetsRow(cs),
                    const SizedBox(height: 20),

                    // ── Toplam maliyet hero card ─────────────────────────
                    _totalHero(cs),
                    const SizedBox(height: 10),

                    // ── Tahmini birim fiyat preview ──────────────────────
                    _pricePreviewCard(cs),

                    // ── İşlem tarihi (chip) ──────────────────────────────
                    _dateChip(cs),
                    const SizedBox(height: 16),

                    // ── Komisyon / masraf ────────────────────────────────
                    // Bayrakta "Ayrıntı ekle" katlanmasının içinde: ilk
                    // varlığı giren kişi komisyonu çoğu zaman bilmez, boş
                    // bırakılan alan 0 sayılır (değişmedi).
                    if (!_kolay) ...[
                      _commissionBlock(cs),
                      const SizedBox(height: 16),
                    ],

                    // ── Notlar (collapsible) ─────────────────────────────
                    _notesCollapsible(cs, komisyonDahil: _kolay),
                    ],
                    // ── Portföy (çoklu portföy, 0133) ─────────────────────
                    // Yeni kayıt (genel form ya da yeni sözleşme) hangi
                    // portföye: varsayılan o an seçili portföy, yoksa Ana.
                    // Düzenlemede yok (portföy değiştirmek bütün pozisyonu
                    // taşımaktır, Portföy'deki "Taşı"). Özellik görünmüyorsa
                    // ya da adlandırılmış portföy yoksa sıfır boy.
                    // Sepet modunda da yok: toplu eklemede portföy sepet
                    // düzeyinde TEK seçimdir (`BulkAddAssetScreen`).
                    if (!_isEditing &&
                        !widget.cartMode &&
                        !_s.turIzgarasiAcik &&
                        (!_type.sozlesmeli || _sozlesmeFormuAcik))
                      PortfoyFormSecici(
                        secili: switch (ref.watch(formPortfoyuProvider)) {
                          final s? => s.id,
                          null => ref.watch(varsayilanYeniPortfoyProvider),
                        },
                        onSec: (v) => ref
                            .read(formPortfoyuProvider.notifier)
                            .state = (id: v),
                        bosluk: const EdgeInsets.only(top: SandikSpace.lgs),
                      ),
                  ],
                  ),
                ),
              ),
              // Izgara açıkken "Ekle" de yok: görünmeyen alanların uyarısını
              // gösteremeyen bir kaydet düğmesi kafa karıştırırdı.
              if ((!_type.sozlesmeli || _sozlesmeFormuAcik) &&
                  !_s.turIzgarasiAcik)
                _stickyBottomBar(saveLabel),
            ],
          ),
        ),
      ),
      ),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: _kirli,
      child: ekran,
      builder: (context, kirli, child) => PopScope(
        // Kayıt sürerken kapanmaz; kirliyken önce sorulur. Başarılı kayıt
        // `Navigator.pop` ile kapatır — PopScope onu engellemez.
        canPop: !kirli && !_saving,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || _saving) return;
          _vazgecmeyiSor();
        },
        child: child!,
      ),
    );
  }


  // ── İki hızlı yol (sadeleştirme 2, 2026-10-04) ─────────────────────────────
  // Hızlı Giriş ("GARAN 500 adet 105 lira") ve ekstre içe aktarma rakiplerden
  // ayrıştıran iki yol; bugün biri etiketsiz mikrofon ikonu, diğeri Toplu
  // Ekle'nin içinde. Burada formun en üstünde, adıyla.
  Widget _ikiYol() {
    return Row(
      children: [
        Expanded(
          child: _yolDugmesi(
            ikon: Icons.edit_note_rounded,
            etiket: context.l10n.addByTyping,
            onTap: _showQuickEntrySheet,
          ),
        ),
        const SizedBox(width: SandikSpace.sm),
        Expanded(
          child: TourAnchor(
            target: TourTarget.topluEkle,
            child: _yolDugmesi(
              ikon: Icons.content_paste_go_rounded,
              etiket: context.l10n.importFromStatement,
              onTap: _ekstredenAktar,
            ),
          ),
        ),
      ],
    );
  }

  /// Üçüncü hızlı yol (2026-10-19, yasin: "ekran görüntüsünden portföy
  /// ekleme: yap, ama dar kapsamla"): aracı kurum/banka uygulamasının
  /// portföy ekranının görüntüleri telefonda okunur, sepete girer, onay
  /// Toplu Ekle'de — "Ekstreden aktar" ile aynı bitiş. İki düğmenin altında
  /// tam genişlik: üçü yan yana dar ekranda okunmazdı.
  Widget _ekranGoruntusuYolu() {
    // Görünüş üstteki iki yolla aynı (`_yolDugmesi`); boy asgari, sabit
    // değil: büyük yazıda etiket kırpılmaz, küçülür.
    return SandikAsyncButton(
      tur: SandikAsyncTur.cerceve,
      height: null,
      icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
      onPressed: _ekranGoruntusundenEkle,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.c.amberText,
        side: BorderSide(color: context.c.hairline),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: SandikRadius.mdAll),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(context.l10n.importScreenshotAdd),
      ),
    );
  }

  Future<void> _ekranGoruntusundenEkle() async {
    final eklendi = await ekranGoruntusundenSepete(context, ref);
    if (!eklendi || !mounted) return;
    final kaydedildi = await pushGuarded<bool>(
      context,
      adaptiveRoute(
        settings: const RouteSettings(name: 'bulk_add_asset'),
        builder: (_) => const BulkAddAssetScreen(),
      ),
    );
    if (kaydedildi == true && mounted) Navigator.of(context).pop(true);
  }

  Widget _yolDugmesi({
    required IconData ikon,
    required String etiket,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(ikon, size: 18),
      // Dar ekranda iki düğme yan yana: metin kırpılmaz, küçülür.
      label: FittedBox(fit: BoxFit.scaleDown, child: Text(etiket)),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.c.amberText,
        side: BorderSide(color: context.c.hairline),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: SandikRadius.mdAll),
      ),
    );
  }

  // ── Notlar collapsible ─────────────────────────────────────────────────────
  Widget _notesCollapsible(ColorScheme cs, {bool komisyonDahil = false}) {
    final doluIcerik = _notes.text.isNotEmpty ||
        (komisyonDahil && _commission.text.isNotEmpty);
    return SandikCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(SandikRadius.md),
            onTap: _n.toggleNotes,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.notes_rounded, size: 16, color: context.c.text58),
                  const SizedBox(width: 10),
                  // Esnek (2026-09-30): 320pt × 2.0 metin ölçeğinde 6px
                  // taşıyordu. Tembel liste bu satırı ekran dışında hiç
                  // kurmadığı için `text_scale_overflow_test` görmüyordu;
                  // form tümüyle kurulunca ortaya çıktı.
                  //
                  // Expanded, `Flexible + Spacer` DEĞİL (2026-10-04): ikisi
                  // eşit pay alıyordu, metin satırın yarısına sıkışıyor ve
                  // "Ayrıntı ekle (komisyon, not)" 412pt'de kırpılıyordu.
                  // Kısa "Not ekle"de görünüm aynı; sığmazsa ikinci satıra
                  // kırılır (metin tam okunur kuralı).
                  Expanded(
                    child: Text(
                        komisyonDahil
                            ? context.l10n.addDetails
                            : context.l10n.addNote,
                        maxLines: 2,
                        style: context.t.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.c.text90)),
                  ),
                  if (doluIcerik && !_notesExpanded)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: context.c.amberFill,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  // İkon değişmez, DÖNER — öteki katlanır bölümler gibi
                  // (animasyon denetimi 2026-10-01; eskiden iki ikon
                  // arasında tek karede atlıyordu).
                  SandikAcilirOk(
                    acik: _notesExpanded,
                    child: Icon(Icons.expand_more_rounded,
                        color: context.c.text58, size: 20),
                  ),
                ],
              ),
            ),
          ),
          // Ortak katlanır bölüm: hareketi azalt'a da uyar (eskiden ham
          // `SandikMotion.state` idi).
          SandikAcilir(
            acik: _notesExpanded,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (komisyonDahil) ...[
                    _commissionBlock(cs),
                    const SizedBox(height: SandikSpace.smd),
                  ],
                  TextFormField(
                    controller: _notes,
                    style: context.t.titleMedium
                        ?.copyWith(color: context.c.text90),
                    maxLines: 3,
                    onTapOutside: _klavyeyiKapat,
                    decoration:
                        context.inputDecoration(context.l10n.notesHint),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sticky bottom CTA ──────────────────────────────────────────────────────
  Widget _stickyBottomBar(String saveLabel) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        decoration: BoxDecoration(
          color: context.c.background,
          border: Border(
            top: BorderSide(color: context.c.overlay, width: 1),
          ),
        ),
        // Tek yükleniyor davranışı (2026-10-08): gösterge ve dokunuş kilidi
        // SandikAsyncButton'da. `saving` bayrağı KALIR — formu salt okunur
        // tutar; `mesgul:` ile başarıda ekran kapanırken ve hızlı giriş
        // partisi sürerken de aynı gösterge döner (bkz. `_save` F14 notu).
        child: SandikAsyncButton(
          height: 54,
          onPressed: _sozlesmeFormuAcik ? _sozlesmeKaydet : _save,
          mesgul: _saving,
          style: FilledButton.styleFrom(
            backgroundColor: context.c.amberFill,
            foregroundColor: context.c.onAmber,
            disabledBackgroundColor:
                context.c.amberFill.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SandikRadius.md)),
            elevation: 0,
          ),
          child: Text(
            saveLabel,
            // Renk açıkça `onAmber` (açık tema denetimi 2026-10-08):
            // `titleLarge` kendi rengini (`text90`) taşır ve düğmenin
            // `foregroundColor`'ını ezer — koyu temada amber üstüne
            // beyaz "Ekle" 1,87:1 kalıyordu.
            style: context.t.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: context.c.onAmber),
          ),
        ),
      ),
    );
  }

  // ── Ortak input builder (Sandik marka) ─────────────────────────────────────
  Widget _brandInput({
    required TextEditingController controller,
    required String hint,
    String? suffixText,
    Widget? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool autocorrect = true,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      style: context.t.bodyLarge
          ?.copyWith(color: context.c.text90, fontWeight: FontWeight.w500),
      decoration: context.inputDecoration(hint).copyWith(
            suffixText: suffixText,
            suffixStyle: context.t.titleSmall?.copyWith(
                color: context.c.text58, fontWeight: FontWeight.w600),
            suffixIcon: suffix,
            suffixIconConstraints:
                const BoxConstraints(minWidth: 60, minHeight: 40),
          ),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      validator: validator,
      onChanged: onChanged,
      onTapOutside: _klavyeyiKapat,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  // ── Tür seçici: arama + gruplu ızgara ──────────────────────────────────────
  //
  // `TurSeciciIzgara`; tür ve kimlik geçişleri burada, formun VAR OLAN
  // `select*` geçişleriyle yapılır (arama → kimlik kuralı tek yerde:
  // `AddAssetFormNotifier`). Bayrak `tur_secici_izgara` 2026-10-20'de
  // emekliye ayrıldı; eski çip `Wrap`'ı (Vadeli mevduat 2026-09-14'te,
  // kripto katalog 2026-09-25, sarmalı satır #29 kararlarıyla) kalktı —
  // tür sırası ve süzme kuralları `tur_secici_duzeni.dart`'ta.

  Widget _turIzgarasi() => TourAnchor(
        target: TourTarget.turSecici,
        child: TurSeciciIzgara(
          secili: seciliKutu(_type, isAbd: _s.isAbd),
          acik: _s.turIzgarasiAcik,
          sozlesmeliAcik: !widget.cartMode && !_isEditing,
          onKutu: _kutuSec,
          onSonuc: _aramaSonucuSec,
          onDegistir: () => _n.turIzgarasi(acik: true),
        ),
      );

  /// Kutuya dokunuldu. Zaten seçili kutu yalnız katlar: "Değiştir"e basıp
  /// vazgeçen kullanıcının seçtiği hisse/fon silinmesin. ABD kutusu hisse
  /// türünü ABD pazarıyla açar (`selectHisseBorsasi`, segmentle aynı yol).
  void _kutuSec(TurKutusu k) {
    _klavyeyiKapat();
    if (seciliKutu(_type, isAbd: _s.isAbd) != k) {
      _yaz(_n.selectType(k.tur));
      if (k.abd) _yaz(_n.selectHisseBorsasi(abd: true));
      _schedulePricePreview();
    }
    _n.turIzgarasi(acik: false);
  }

  /// Arama sonucu: tür + kimlik, ilgili seçici sayfasından seçilmiş gibi.
  void _aramaSonucuSec(TurAramaSonucu s) {
    _klavyeyiKapat();
    final bosFiyat = _price.text.isEmpty;
    _yaz(_n.selectType(s.kutu.tur));
    switch (s.kutu.tur) {
      case AssetType.hisse when s.kutu.abd:
        _yaz(_n.selectHisseBorsasi(abd: true));
        _yaz(_n.selectAbdHisse(s.ticker!));
      case AssetType.hisse:
        _yaz(_n.selectBist100(s.ticker!));
      case AssetType.fon:
        _yaz(_n.selectFund(
          TefasFund(
            code: s.sembol,
            name: s.ad,
            price: 0,
            fundType: '',
            managerName: '',
          ),
          priceEmpty: bosFiyat,
        ));
      case AssetType.kripto:
        _yaz(_n.selectKripto(KriptoKatalogOgesi(kod: s.sembol, ad: s.ad),
            priceEmpty: bosFiyat));
      case AssetType.altin:
        _yaz(_n.selectGold(s.altin!));
      case AssetType.doviz:
        _yaz(_n.selectDoviz(dovizOptFor(s.dovizEtiketi)));
      case AssetType.eurobond:
        final (sz, f) = s.eurobond!;
        _yaz(_n.selectEurobond(sz, f, priceEmpty: bosFiyat));
      default:
        break;
    }
    _schedulePricePreview();
    _n.turIzgarasi(acik: false);
  }
}
