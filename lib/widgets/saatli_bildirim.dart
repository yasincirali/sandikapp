import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoDatePicker, CupertinoDatePickerMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/arama_gruplari.dart';
import '../models/saatli_bildirim.dart';
import '../models/varlik_kimligi.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart' show OzellikDurumu;
import '../providers/quiet_hours_provider.dart';
import '../providers/saatli_bildirim_provider.dart';
import '../screens/price_alerts_screen.dart' show alarmAdaylari;
import '../services/crash_reporter.dart';
import '../services/ozellik_olcumu.dart';
import '../services/price_service.dart';
import '../services/saatli_bildirim_service.dart';
import '../services/symbol_search_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import 'alarm_kur_sheet.dart' show alarmSembolu;
import 'arama_satiri.dart';
import 'para_akisi_karti.dart' show KilitSatiri;
import 'sandik_arama_alani.dart';
import 'sandik_async_button.dart';
import 'tur_filtre_cipleri.dart' show SandikFiltreCipi;

/// Paywall kaynağı ve ölçüm kodu (aynı ad, `ozellik_olcumu_test`).
const saatliKaynak = 'saatli_bildirim';

/// Saatli bildirim kurma akışı (0188) — üç giriş noktasının tek yolu:
/// Alarmlarım'daki bölüm, varlık ekranının zil menüsü ve Ayarlar'daki
/// sayfa.
///
/// [sembol] verilmezse önce varlık seçtirir (portföy/takip şartı yok:
/// boş aramada kendi varlıkların, yazınca bütün katalog). Kilitliyse
/// paywall açılır; gizliyse (tablo yok, paywall kapalı ve admin değil)
/// hiçbir şey olmaz — çağıran zaten girişi çizmez.
Future<void> saatliBildirimAkisi(
  BuildContext context,
  WidgetRef ref, {
  String? sembol,
  String? ad,
}) async {
  switch (ref.read(saatliBildirimDurumuProvider)) {
    case OzellikDurumu.gizli:
      return;
    case OzellikDurumu.kilitli:
      KilitSatiri.ac(context, kaynak: saatliKaynak, ozellik: saatliKaynak);
      return;
    case OzellikDurumu.acik:
      break;
  }
  var secim = sembol == null ? null : (sembol: sembol, ad: ad ?? sembol);
  secim ??= await _varlikSec(context, ref);
  if (secim == null || !context.mounted) return;

  final liste =
      ref.read(saatliBildirimlerProvider).valueOrNull ?? const <SaatliBildirim>[];
  if (!saatliYeniVarlikEklenebilir(liste, secim.sembol)) {
    sandikSnack(
        context,
        context.l10n.saatliSinir(
            SaatliBildirim.enFazlaVarlik, SaatliBildirim.enFazlaSaat),
        kind: SandikSnackKind.warning);
    return;
  }
  final mevcut = liste.where((b) => b.symbol == secim!.sembol).firstOrNull;
  await showSandikSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    baslik: mevcut?.label ?? secim.ad,
    altMetin: context.l10n.saatliEnFazlaSaat(SaatliBildirim.enFazlaSaat),
    builder: (_) => SaatSecimSayfasi(
      sembol: secim!.sembol,
      ad: mevcut?.label ?? secim.ad,
      mevcut: mevcut,
    ),
  );
}

/// Sunucu reddini (`saatli_siniri`) kullanıcı diline çevirir. Kilit yoksa
/// sınırdır (5 varlık / 5 saat); kilitliyse çağıran zaten paywall'u açar.
String saatliHataMetni(BuildContext context, Object e) => saatliSiniriHatasiMi(e)
    ? context.l10n
        .saatliSinir(SaatliBildirim.enFazlaVarlik, SaatliBildirim.enFazlaSaat)
    : friendlyError(e);

/// Seçicinin döndürdüğü varlık: alarm alfabesindeki sembol + görünen ad.
typedef SaatliSecim = ({String sembol, String ad});

Future<SaatliSecim?> _varlikSec(BuildContext context, WidgetRef ref) =>
    showSandikSheet<SaatliSecim>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      baslik: context.l10n.saatliVarlikSec,
      builder: (_) => SaatliVarlikSecici(
        kendi: [
          for (final a in alarmAdaylari(ref))
            // Aday portföy/takip kaydından türünü taşır; taşımıyorsa
            // (eski çağıran) tür sembolden çıkarılır — arama satırıyla aynı
            // kural. Kimlik kurulamıyorsa satır yine görünür, hisse sayılır:
            // kullanıcının kendi varlığı listeden düşmemeli.
            a.kimlik ??
                VarlikKimligi.fromSymbolHit(
                    SymbolHit(ticker: a.sembol, name: a.ad, source: '')) ??
                VarlikKimligi.hisse(a.sembol, a.ad),
        ],
      ),
    );

/// Varlık seçici: boş sorguda portföy + takip, yazınca katalog araması
/// (`SymbolSearchService`, takibe alma ekranıyla aynı servis ve bekleme).
/// Sembol alarmla aynı alfabede (`alarmSembolu`): sunucunun fiyatlayamadığı
/// eurobond listelenmez.
///
/// ## Görünüm (2026-11-26, yasin: "bu tasarım çok kötü… uygulama
/// standartlarına ve tasarım diline uygun olmalı")
/// Eski hâl çıplak ad listesiydi: kenar payı yok (kabuk pay vermez, alan ve
/// satırlar ekran kenarına yapışıyordu), rozet/sembol/fiyat yok, arama alanı
/// takibe alma ekranındakinden farklı. Şimdi takibe alma ekranının dili:
/// - Alan `SandikAramaAlani`, satır `AramaSatirKutusu` (rozet, ad,
///   "sembol · tür", fiyat + günlük değişim) — aynı varlık iki seçicide iki
///   farklı satır göstermesin.
/// - Boş sorguda kendi varlıkların tür başlıkları altında, `AssetType`
///   sırasıyla (filtre çipi ve tür dökümüyle aynı sıra); aramada
///   `aramaGrupla` (en alakalı tür üstte). Gruplar KESİLMEZ: sayfada tür
///   çipi yok, "Tümü (n)" ikinci bir dokunuş isterdi; arama zaten en çok
///   20 sonuç verir.
/// - Saatli bildirimi zaten olan varlıkta satır sonu "3 saat": kişi
///   seçmeden neyi düzenleyeceğini görür; ötekilerde ok (sayfa açar).
/// - Fiyat takibe alma ekranının yolundan (`PriceService.fetchQuotes`, tek
///   toplu istek, önbellekli); bilinmiyorsa yazılmaz, sayı uydurulmaz.
class SaatliVarlikSecici extends ConsumerStatefulWidget {
  const SaatliVarlikSecici({super.key, required this.kendi});

  /// Portföy + takip varlıkları; `ticker` alarm sembolüdür.
  final List<VarlikKimligi> kendi;

  @override
  ConsumerState<SaatliVarlikSecici> createState() =>
      _SaatliVarlikSeciciState();
}

class _SaatliVarlikSeciciState extends ConsumerState<SaatliVarlikSecici> {
  final _ctrl = TextEditingController();
  Timer? _bekleme;
  String _sorgu = '';
  bool _araniyor = false;
  List<VarlikKimligi> _sonuc = const [];

  /// Görünen satırların kotasyonu — sembol (büyük harf) → kotasyon.
  Map<String, YahooQuote> _kotasyon = const {};

  @override
  void initState() {
    super.initState();
    _fiyatla(widget.kendi.map((k) => k.ticker));
  }

  @override
  void dispose() {
    _bekleme?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _degisti(String q) {
    _bekleme?.cancel();
    _sorgu = q.trim();
    if (_sorgu.isEmpty) {
      setState(() {
        _sonuc = const [];
        _araniyor = false;
      });
      return;
    }
    setState(() => _araniyor = true);
    _bekleme = Timer(SymbolSearchService.aramaBeklemesi, () async {
      final aranan = _sorgu;
      List<VarlikKimligi> sonuc;
      try {
        final hits = await SymbolSearchService.instance.search(aranan);
        sonuc = [
          for (final h in hits)
            if (alarmSembolu(h.ticker, null) != null)
              if (VarlikKimligi.fromSymbolHit(h) case final k?) k,
        ];
      } catch (_) {
        // Arama başarısızsa liste boş kalır; kişi yeniden yazabilir
        // (takibe alma ekranıyla aynı davranış).
        sonuc = const [];
      }
      if (!mounted || aranan != _sorgu) return;
      setState(() {
        _sonuc = sonuc;
        _araniyor = false;
      });
      _fiyatla(sonuc.map((k) => k.ticker));
    });
  }

  /// Eksik kotasyonları TEK toplu istekle çeker (takibe alma ekranının
  /// `_fiyatla`'sı). Hata sessiz değil, arka plan raporuna gider; satır
  /// fiyatsız kalır.
  void _fiyatla(Iterable<String> semboller) {
    final eksik = [
      for (final s in semboller.toSet())
        if (!_kotasyon.containsKey(s.toUpperCase())) s,
    ];
    if (eksik.isEmpty) return;
    CrashReporter.arkaPlan(() async {
      final q = await PriceService.instance.fetchQuotes(eksik);
      if (!mounted || q.isEmpty) return;
      setState(() => _kotasyon = {..._kotasyon, ...q});
    }(), reason: 'SaatliSecici.fiyat');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l10n;
    final hp = SandikSpace.screenH(context);
    final saatSayisi = {
      for (final b in ref.watch(saatliBildirimlerProvider).valueOrNull ??
          const <SaatliBildirim>[])
        b.symbol: b.saatler.length,
    };
    final bos = _sorgu.isEmpty;
    final List<AramaGrubu> gruplar;
    if (bos) {
      gruplar = aramaGrupla(widget.kendi, sinir: widget.kendi.length)
        ..sort((a, b) => a.tur.index.compareTo(b.tur.index));
    } else {
      gruplar = aramaGrupla(_sonuc, sinir: _sonuc.length);
    }
    final altPay = MediaQuery.paddingOf(context).bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hp, SandikSpace.md, hp, 0),
          child: SandikAramaAlani(
            controller: _ctrl,
            onChanged: _degisti,
            autofocus: widget.kendi.isEmpty,
            placeholder: l.saatliAra,
          ),
        ),
        if (_araniyor)
          Padding(
            padding: const EdgeInsets.only(top: SandikSpace.xs2),
            child: Text(l.searchingEllipsis,
                textAlign: TextAlign.center,
                style: context.t.bodySmall?.copyWith(color: c.text36)),
          ),
        Flexible(
          child: !bos && !_araniyor && gruplar.isEmpty
              ? Padding(
                  padding: EdgeInsets.fromLTRB(
                      hp, SandikSpace.lg, hp, SandikSpace.lg + altPay),
                  child: Text(l.saatliSonucYok,
                      textAlign: TextAlign.center,
                      style: context.t.bodyMedium?.copyWith(color: c.text58)),
                )
              : ListView(
                  shrinkWrap: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                      hp, SandikSpace.sm, hp, SandikSpace.md + altPay),
                  children: [
                    for (final g in gruplar) ...[
                      SandikSectionHeader(
                        minHeight: SandikTouch.min,
                        title: g.tur.labelOf(l),
                      ),
                      for (final k in g.ogeler) _satir(k, saatSayisi[k.ticker]),
                      const SizedBox(height: SandikSpace.sm),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  /// Satır: dokunmak varlığı seçer. Ekran okuyucu tek cümle duyar (ad,
  /// sembol, fiyat, kurulu bildirim); satırın kendi metinleri tekrar
  /// okunmasın diye dışlanır.
  Widget _satir(VarlikKimligi k, int? saat) {
    final c = context.c;
    final l = context.l10n;
    final kotasyon = _kotasyon[k.ticker.toUpperCase()];
    final etiket = [
      k.name,
      if (aramaSembolEtiketi(k) case final e?) e,
      if (aramaFiyatMetni(k, kotasyon) case final f?) f,
      if (saat != null) l.saatliKuruluEtiket(saat),
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.sm),
      child: SandikTappable(
        onTap: () => Navigator.pop<SaatliSecim>(
            context, (sembol: k.ticker, ad: k.name)),
        semanticLabel: etiket,
        child: ExcludeSemantics(
          child: AramaSatirKutusu(
            kimlik: k,
            kotasyon: kotasyon,
            sonu: Padding(
              padding: const EdgeInsets.only(right: SandikSpace.smd),
              // Zil + "3 saat": sayı tek başına neyin saati olduğunu
              // söylemiyordu; renk yok, durum metinle (renk körlüğü).
              child: saat != null
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.notifications_none_rounded,
                          size: 14, color: c.text58),
                      const SizedBox(width: SandikSpace.xxs),
                      Text(l.saatliSaatSayisi(saat),
                          style:
                              context.t.labelSmall?.copyWith(color: c.text58)),
                    ])
                  : Icon(Icons.chevron_right_rounded,
                      size: 20, color: c.text36),
            ),
          ),
        ),
      ),
    );
  }
}

/// Saat seçimi: 15 dakika adımlı saat çarkı (iOS sistem kalıbı, iki
/// platformda aynı), seçilen saatler en çok beş çip. Kayıt sayfanın
/// düğmesinin İÇİNDE (tek yükleniyor davranışı); hata düğmenin altında,
/// sayfa açık kalır, seçim kaybolmaz.
class SaatSecimSayfasi extends ConsumerStatefulWidget {
  const SaatSecimSayfasi({
    super.key,
    required this.sembol,
    required this.ad,
    this.mevcut,
  });

  final String sembol;
  final String ad;
  final SaatliBildirim? mevcut;

  @override
  ConsumerState<SaatSecimSayfasi> createState() => _SaatSecimSayfasiState();
}

class _SaatSecimSayfasiState extends ConsumerState<SaatSecimSayfasi> {
  late final List<int> _saatler = [...?widget.mevcut?.saatler];
  // Varsayılan çark konumu: 09:00 (piyasa açılışı öncesi, ilk akla gelen).
  int _cark = 9 * 60;
  String? _hata;
  final _basari = SandikBasariSinyali();

  void _ekle() {
    if (_saatler.contains(_cark) ||
        _saatler.length >= SaatliBildirim.enFazlaSaat) {
      return;
    }
    SandikHaptic.selection.perform();
    setState(() {
      _saatler
        ..add(_cark)
        ..sort();
      _hata = null;
    });
  }

  Future<void> _kaydet() async {
    final me = ref.read(authProvider).valueOrNull;
    if (me == null || !SaatliBildirim.saatlerGecerli(_saatler)) return;
    try {
      await ref.read(saatliBildirimlerProvider.notifier).kaydet(
            userId: me.id,
            symbol: widget.sembol,
            label: widget.ad,
            saatler: _saatler,
          );
    } catch (e) {
      if (!mounted) return;
      // Sunucu Premium yok dediyse (hak sunucuya henüz düşmedi ya da bitti)
      // paywall; sınırsa kullanıcı dilinde sınır cümlesi.
      if (saatliSiniriHatasiMi(e) &&
          ref.read(saatliBildirimDurumuProvider) == OzellikDurumu.kilitli) {
        Navigator.pop(context);
        return;
      }
      setState(() => _hata = saatliHataMetni(context, e));
      return;
    }
    OzellikOlcumu.say(Ozellik.saatliBildirim);
    await _basari.goster();
    // Başarı snack'ı YOK (çizgi adı sayfası kararı): onay düğmedeki ✓ +
    // titreşim; satır listede hemen görünür.
    if (mounted) Navigator.pop(context);
  }

  Future<void> _sil() async {
    final id = widget.mevcut?.id;
    if (id == null) return;
    try {
      await ref.read(saatliBildirimlerProvider.notifier).sil(id);
    } catch (e) {
      if (mounted) setState(() => _hata = friendlyError(e));
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final sessiz = ref.watch(quietHoursProvider).valueOrNull;
    final sessizSaat = _saatler
        .where((s) =>
            SaatliBildirim.sessizPencerede(s, sessiz?.start, sessiz?.end))
        .firstOrNull;
    final dolu = _saatler.length >= SaatliBildirim.enFazlaSaat;
    final simdi = DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.saatliAciklama,
            style: context.t.bodyMedium?.copyWith(color: c.text58)),
        const SizedBox(height: SandikSpace.md),
        if (_saatler.isNotEmpty) ...[
          Text(l10n.saatliSaatlerEtiket,
              style: context.t.labelLarge?.copyWith(color: c.text58)),
          const SizedBox(height: SandikSpace.sm),
          Wrap(
            spacing: SandikSpace.sm,
            runSpacing: SandikSpace.sm,
            children: [
              for (final s in _saatler)
                SandikFiltreCipi(
                  key: ValueKey('saatliCip_$s'),
                  ad: SaatliBildirim.saatMetni(s),
                  secili: true,
                  semantik: l10n.saatliSaatSil(SaatliBildirim.saatMetni(s)),
                  onTap: () => setState(() {
                    _saatler.remove(s);
                    _hata = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: SandikSpace.md),
        ],
        if (!dolu) ...[
          SizedBox(
            height: SandikSpace.xl * 5,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              use24hFormat: true,
              minuteInterval: SaatliBildirim.adimDk,
              initialDateTime: DateTime(
                  simdi.year, simdi.month, simdi.day, _cark ~/ 60, _cark % 60),
              onDateTimeChanged: (d) => _cark = d.hour * 60 + d.minute,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('saatliSaatEkle'),
              onPressed: _ekle,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.saatliSaatEkle),
            ),
          ),
        ],
        // Sessiz saatlerle çakışma: tek satır, ikon + cümle (yalnız renk değil).
        if (sessizSaat != null)
          Padding(
            key: const ValueKey('saatliSessizUyari'),
            padding: const EdgeInsets.only(top: SandikSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(Icons.bedtime_outlined,
                      size: SandikSpace.md, color: c.text58),
                ),
                const SizedBox(width: SandikSpace.sm),
                Expanded(
                  child: Text(
                      l10n.saatliSessizUyari(
                          SaatliBildirim.saatMetni(sessizSaat)),
                      style: context.t.bodySmall?.copyWith(color: c.text58)),
                ),
              ],
            ),
          ),
        const SizedBox(height: SandikSpace.md),
        SandikAsyncButton(
          key: const ValueKey('saatliKaydet'),
          basari: _basari,
          onPressed: _saatler.isEmpty ? null : _kaydet,
          child: Text(l10n.save),
        ),
        if (_hata != null)
          Padding(
            padding: const EdgeInsets.only(top: SandikSpace.sm),
            child: Text(_hata!,
                key: const ValueKey('saatliHata'),
                style: context.t.bodySmall?.copyWith(color: c.loss)),
          ),
        if (widget.mevcut != null)
          SandikAsyncButton(
            key: const ValueKey('saatliSil'),
            tur: SandikAsyncTur.metin,
            onPressed: _sil,
            child: Text(l10n.delete),
          ),
        const SizedBox(height: SandikSpace.md),
      ],
    );
  }
}

/// Alarmlarım'daki ve Ayarlar sayfasındaki "Saatli bildirimler" bölümü.
///
/// Gizliyse (tablo yok; paywall kapalı ve admin değil) hiç çizilmez —
/// "yakında" yazılmaz. Kilitliyse satırlar (Premium'u biten kullanıcının
/// kayıtları silinmez) soluk görünür, altında "Premium'la yeniden
/// gönderilir" kilidi; kayıt yoksa tek kilit satırı. Açıksa satırlar ve
/// "+" (beş varlığa kadar).
class SaatliBildirimBolumu extends ConsumerWidget {
  const SaatliBildirimBolumu({super.key, this.ustBosluk = 0});

  /// Bölüm çizilirse üstündeki boşluk; gizliyken yer kaplamasın diye burada.
  final double ustBosluk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durum = ref.watch(saatliBildirimDurumuProvider);
    if (durum == OzellikDurumu.gizli) return const SizedBox.shrink();
    final c = context.c;
    final l10n = context.l10n;
    final liste =
        ref.watch(saatliBildirimlerProvider).valueOrNull ?? const <SaatliBildirim>[];
    final kilitli = durum == OzellikDurumu.kilitli;
    final eklenebilir =
        !kilitli && liste.length < SaatliBildirim.enFazlaVarlik;
    final kilit = KilitSatiri(
      metin: liste.isEmpty ? l10n.saatliKilitSatiri : l10n.saatliYenidenGonderilir,
      kaynak: 'saatli_bildirim', // literal: ozellik_olcumu_test kaynağı tarar
      ozellik: saatliKaynak,
    );
    return Column(
      key: const ValueKey('saatliBolumu'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: ustBosluk),
        SandikSectionHeader(
          title: l10n.saatliBaslik,
          minHeight: SandikTouch.min,
          trailing: eklenebilir
              ? IconButton(
                  key: const ValueKey('saatliEkle'),
                  tooltip: l10n.saatliEkle,
                  icon: Icon(Icons.add_rounded, color: c.amberText),
                  onPressed: () => saatliBildirimAkisi(context, ref),
                )
              : null,
        ),
        SandikCard(
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.md2, vertical: SandikSpace.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (liste.isEmpty && !kilitli)
                _BosSatir(onTap: () => saatliBildirimAkisi(context, ref)),
              for (var i = 0; i < liste.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: c.hairline),
                _SaatliSatir(
                  bildirim: liste[i],
                  kilitli: kilitli,
                  onTap: () => saatliBildirimAkisi(context, ref,
                      sembol: liste[i].symbol, ad: liste[i].label),
                ),
              ],
              if (kilitli) ...[
                if (liste.isNotEmpty)
                  Divider(height: 1, thickness: 1, color: c.hairline),
                kilit,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BosSatir extends StatelessWidget {
  const _BosSatir({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      child: SandikTappable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(Icons.schedule_rounded,
                      size: SandikSpace.lgs, color: c.amberText),
                ),
                const SizedBox(width: SandikSpace.smd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.saatliEkle,
                          style: context.t.titleMedium?.copyWith(color: c.text90)),
                      Text(context.l10n.saatliAciklama,
                          style: context.t.bodySmall?.copyWith(color: c.text58)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaatliSatir extends StatelessWidget {
  const _SaatliSatir({
    required this.bildirim,
    required this.kilitli,
    required this.onTap,
  });

  final SaatliBildirim bildirim;
  final bool kilitli;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final saatler = bildirim.saatler.map(SaatliBildirim.saatMetni).join(' · ');
    // Kilitliyken soluk: gönderilmediği renkle değil, alttaki kilit
    // cümlesiyle de söylenir. Dokunuş akışa gider (kilitliyse paywall).
    final metin = kilitli ? c.text58 : c.text90;
    return Semantics(
      button: true,
      child: SandikTappable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bildirim.label,
                          style: context.t.titleMedium?.copyWith(color: metin)),
                      Text(saatler,
                          style: context.t.bodySmall?.copyWith(color: c.text58)),
                    ],
                  ),
                ),
                ExcludeSemantics(
                  child: Icon(Icons.chevron_right_rounded,
                      size: SandikSpace.lgs, color: c.text36),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
