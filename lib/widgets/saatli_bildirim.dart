import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoDatePicker, CupertinoDatePickerMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/saatli_bildirim.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart' show OzellikDurumu;
import '../providers/quiet_hours_provider.dart';
import '../providers/saatli_bildirim_provider.dart';
import '../screens/price_alerts_screen.dart' show alarmAdaylari;
import '../services/ozellik_olcumu.dart';
import '../services/saatli_bildirim_service.dart';
import '../services/symbol_search_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import 'alarm_kur_sheet.dart' show alarmSembolu;
import 'para_akisi_karti.dart' show KilitSatiri;
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

typedef _Secim = ({String sembol, String ad});

Future<_Secim?> _varlikSec(BuildContext context, WidgetRef ref) =>
    showSandikSheet<_Secim>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      baslik: context.l10n.saatliVarlikSec,
      builder: (_) => _VarlikSecici(
        kendi: [
          for (final a in alarmAdaylari(ref)) (sembol: a.sembol, ad: a.ad)
        ],
      ),
    );

/// Varlık seçici: boş sorguda portföy + takip, yazınca katalog araması
/// (`SymbolSearchService`, takibe alma ekranıyla aynı servis ve bekleme).
/// Sembol alarmla aynı alfabede (`alarmSembolu`): sunucunun fiyatlayamadığı
/// eurobond listelenmez.
class _VarlikSecici extends StatefulWidget {
  const _VarlikSecici({required this.kendi});
  final List<_Secim> kendi;

  @override
  State<_VarlikSecici> createState() => _VarlikSeciciState();
}

class _VarlikSeciciState extends State<_VarlikSecici> {
  Timer? _bekleme;
  String _sorgu = '';
  List<_Secim> _sonuc = const [];

  @override
  void dispose() {
    _bekleme?.cancel();
    super.dispose();
  }

  void _degisti(String q) {
    _bekleme?.cancel();
    _sorgu = q.trim();
    if (_sorgu.isEmpty) {
      setState(() => _sonuc = const []);
      return;
    }
    _bekleme = Timer(SymbolSearchService.aramaBeklemesi, () async {
      final aranan = _sorgu;
      final hits = await SymbolSearchService.instance.search(aranan);
      if (!mounted || aranan != _sorgu) return;
      setState(() => _sonuc = [
            for (final h in hits)
              if (alarmSembolu(h.ticker, null) case final s?)
                (sembol: s, ad: h.name),
          ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final liste = _sorgu.isEmpty ? widget.kendi : _sonuc;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          autofocus: widget.kendi.isEmpty,
          onChanged: _degisti,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.l10n.saatliAra,
            prefixIcon: const Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: SandikSpace.sm),
        Flexible(
          child: liste.isEmpty && _sorgu.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.all(SandikSpace.md),
                  child: Text(context.l10n.saatliSonucYok,
                      textAlign: TextAlign.center,
                      style: context.t.bodyMedium?.copyWith(color: c.text58)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: liste.length,
                  itemBuilder: (_, i) {
                    final s = liste[i];
                    return Semantics(
                      button: true,
                      child: SandikTappable(
                        onTap: () => Navigator.pop(context, s),
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(minHeight: SandikTouch.min),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: SandikSpace.sm),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(s.ad,
                                  style: context.t.titleMedium
                                      ?.copyWith(color: c.text90)),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: SandikSpace.md),
      ],
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
