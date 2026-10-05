import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/analiz_provider.dart';
import '../providers/hafta_ozeti_provider.dart';
import '../providers/premium_provider.dart';
import '../services/crash_reporter.dart';
import '../services/supabase_service.dart';
import '../services/varlik_analizi.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../widgets/para_akisi_karti.dart' show KilitSatiri;
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_skeleton.dart';
import 'hafta_ozeti_screen.dart' show HaftaRozetCipi;

/// Yapay zekâ notu (S17-B, 2026-10-05) — madde + kanıt çipi + geri bildirim.
///
/// ## Kanıt çipi neden
/// Not bir yapay zekâ metni; okur "bu sayı nereden" diye sormalı ve
/// cevabı aynı yerde görmeli. Her maddenin altında dayandığı ölçümler
/// (ad · sunucunun yazdığı gösterim · kaynak) durur. Sayı kapısı
/// (`_shared/analiz.ts`) metindeki her sayının bu gösterimlerden birinde
/// AYNEN geçtiğini zaten doğruladı; çip bunu okura görünür kılar.
///
/// ## "Yanlış bir sayı gördüm"
/// Kapı yanlış ölçümü yakalayamaz (girdi yanlışsa metin de "doğru" yanlış
/// olur). Okurun işareti `not_geri_bildirim`'e düşer; haftalık maliyet
/// raporuyla birlikte gözden geçirilir.
///
/// Paywall açık ve kullanıcı Premium değilse yalnız başlık + kilit satırı;
/// sunucu da (RLS) zaten tam satırı vermez.
class AnalizNotuScreen extends ConsumerStatefulWidget {
  const AnalizNotuScreen({
    super.key,
    required this.ticker,
    required this.tur,
    required this.donem,
    required this.kod,
    this.baslik,
  });

  final String ticker;

  /// 'haftalik' | 'aylik'.
  final String tur;
  final DateTime donem;
  final String kod;

  /// Kilitliyken gösterilecek başlık (ücretsiz katman).
  final String? baslik;

  @override
  ConsumerState<AnalizNotuScreen> createState() => _AnalizNotuScreenState();
}

class _AnalizNotuScreenState extends ConsumerState<AnalizNotuScreen> {
  int? _oy;
  bool _yanlisBildirildi = false;

  @override
  void initState() {
    super.initState();
    _oncekiniYukle();
  }

  /// Önceki oy/bildirim. Okunamazsa sessiz (oy boş başlar); kullanıcı yine
  /// oy verebilir, satır upsert ile tekilleşir.
  Future<void> _oncekiniYukle() async {
    try {
      final r = await SupabaseService.instance.notGeriBildirimim(
          ticker: widget.ticker, tur: widget.tur, donem: widget.donem);
      if (r == null || !mounted) return;
      setState(() {
        _oy ??= r.oy;
        _yanlisBildirildi = _yanlisBildirildi || r.yanlisSayi;
      });
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'AnalizNotuScreen._oncekiniYukle');
    }
  }

  /// Seçili oya yeniden dokunmak oyu geri alır.
  Future<void> _oyVer(int oy) async {
    final onceki = _oy;
    final yeni = onceki == oy ? null : oy;
    setState(() => _oy = yeni);
    try {
      await SupabaseService.instance.notGeriBildirim(
          ticker: widget.ticker,
          tur: widget.tur,
          donem: widget.donem,
          oy: switch (yeni) {
            1 => NotGeriBildirimi.yararli,
            -1 => NotGeriBildirimi.yararsiz,
            _ => NotGeriBildirimi.geriAl,
          });
    } catch (e) {
      if (!mounted) return;
      setState(() => _oy = onceki);
      showAppError(context, e);
    }
  }

  Future<void> _yanlisSayi() async {
    final aciklama = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
      builder: (_) => const _YanlisSayiSayfasi(),
    );
    if (aciklama == null || !mounted) return;
    try {
      await SupabaseService.instance.notGeriBildirim(
          ticker: widget.ticker,
          tur: widget.tur,
          donem: widget.donem,
          yanlisSayi: true,
          yanlisSayiAciklamasi: aciklama.isEmpty ? null : aciklama);
      if (!mounted) return;
      setState(() => _yanlisBildirildi = true);
      sandikSnack(context, context.l10n.anzTesekkur,
          kind: SandikSnackKind.success);
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final kilitli = ref.watch(radarKilitliProvider);
    final not = kilitli
        ? null
        : ref.watch(
            varlikNotuProvider((widget.ticker, widget.tur, widget.donem)));
    final baslikMetni = widget.tur == 'aylik'
        ? l10n.anzAylikDetayBaslik(widget.kod)
        : l10n.anzDetayBaslik(widget.kod);
    final yatay = SandikSpace.screenH(context);

    Widget govde;
    // Başlık listeden geldiyse not VAR; satır yine de boş dönerse sunucu
    // kapısı (premium_icerik_gorebilir) gizlemiştir: istemci bayrağı henüz
    // gelmemiş ya da RC okunamamış olabilir. Kullanıcı "açılamadı" hatası
    // değil, kilidi görsün.
    final sunucuKilitledi =
        !kilitli && widget.baslik != null && not!.hasValue && not.value == null;
    if (kilitli || sunucuKilitledi) {
      govde = ListView(
        padding:
            EdgeInsets.fromLTRB(yatay, SandikSpace.md, yatay, SandikSpace.xl),
        children: [
          if (widget.baslik != null)
            Text(widget.baslik!,
                style: t.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
          const SizedBox(height: SandikSpace.md),
          KilitSatiri(metin: l10n.prmKilitNot, kaynak: 'analiz_notu'),
        ],
      );
    } else {
      govde = not!.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(SandikSpace.md),
          child: SandikSkeletonList(rows: 3),
        ),
        error: (_, __) => _Bos(metin: l10n.anzOkunamadi),
        data: (n) => n == null
            ? _Bos(metin: l10n.anzOkunamadi)
            : _Not(
                not: n,
                oy: _oy,
                onOy: _oyVer,
                yanlisBildirildi: _yanlisBildirildi,
                onYanlis: _yanlisSayi,
              ),
      );
    }

    return Scaffold(
      appBar: SandikAppBar(title: baslikMetni),
      body: govde,
    );
  }
}

class _Bos extends StatelessWidget {
  const _Bos({required this.metin});
  final String metin;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(SandikSpace.lg),
          child: Text(metin,
              textAlign: TextAlign.center,
              style: context.t.bodyMedium?.copyWith(color: context.c.text58)),
        ),
      );
}

class _Not extends StatelessWidget {
  const _Not({
    required this.not,
    required this.oy,
    required this.onOy,
    required this.yanlisBildirildi,
    required this.onYanlis,
  });

  final VarlikNotu not;
  final int? oy;
  final ValueChanged<int> onOy;
  final bool yanlisBildirildi;
  final VoidCallback onYanlis;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final yer = Localizations.localeOf(context).toString();
    final gunAy = DateFormat('d MMM', yer);
    final rozet = haftaRozetiSunucudan(not.rozet);
    final aralik = not.baslangic != null && not.bitis != null
        ? l10n.flowRange(gunAy.format(not.baslangic!), gunAy.format(not.bitis!))
        : gunAy.format(not.donem);
    final yatay = SandikSpace.screenH(context);
    return ListView(
      padding:
          EdgeInsets.fromLTRB(yatay, SandikSpace.md, yatay, SandikSpace.xl),
      children: [
        if (rozet != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: HaftaRozetCipi(rozet: rozet),
          ),
        const SizedBox(height: SandikSpace.sm),
        Text(not.baslik,
            style: t.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
        const SizedBox(height: SandikSpace.xs),
        Text(l10n.anzMeta('${not.maddeler.length}', aralik),
            style: t.bodySmall?.copyWith(color: c.text58)),
        const SizedBox(height: SandikSpace.md),
        SandikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < not.maddeler.length; i++) ...[
                if (i > 0) const SizedBox(height: SandikSpace.md),
                _Madde(madde: not.maddeler[i], gunAy: gunAy),
              ],
            ],
          ),
        ),
        const SizedBox(height: SandikSpace.sm),
        Text(
          l10n.anzAltSatir(
              not.kaynaklar.join(', '),
              not.bitis == null
                  ? gunAy.format(not.donem)
                  : gunAy.format(not.bitis!)),
          style: t.bodySmall?.copyWith(color: c.text36),
        ),
        const SizedBox(height: SandikSpace.lg),
        Row(
          children: [
            Expanded(
              child: Text(l10n.anzIseYaradi,
                  style: t.bodyMedium?.copyWith(color: c.text90)),
            ),
            IconButton(
              tooltip: l10n.anzYararli,
              onPressed: () => onOy(1),
              icon: Icon(
                  oy == 1 ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
                  color: oy == 1 ? c.gain : c.text58),
            ),
            IconButton(
              tooltip: l10n.anzYararsiz,
              onPressed: () => onOy(-1),
              icon: Icon(
                  oy == -1
                      ? Icons.thumb_down_alt
                      : Icons.thumb_down_alt_outlined,
                  color: oy == -1 ? c.loss : c.text58),
            ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
            onPressed: yanlisBildirildi ? null : onYanlis,
            icon: const Icon(Icons.flag_outlined, size: SandikSpace.md),
            label:
                Text(yanlisBildirildi ? l10n.anzTesekkur : l10n.anzYanlisSayi),
          ),
        ),
      ],
    );
  }
}

class _Madde extends StatelessWidget {
  const _Madde({required this.madde, required this.gunAy});

  final NotMaddesi madde;
  final DateFormat gunAy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: SandikSpace.xs2),
          child: Container(
            width: SandikSpace.xs2,
            height: SandikSpace.xs2,
            decoration: BoxDecoration(color: c.text58, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: SandikSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(madde.metin, style: t.bodyMedium?.copyWith(color: c.text90)),
              if (madde.kanitlar.isNotEmpty) ...[
                const SizedBox(height: SandikSpace.xs),
                Wrap(
                  spacing: SandikSpace.xs,
                  runSpacing: SandikSpace.xs,
                  children: [
                    for (final k in madde.kanitlar)
                      _KanitCipi(olcum: k, gunAy: gunAy),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "Son hafta net akış · +₺137,66M · TEFAS 3 Eki". Sayı, sunucunun
/// yazdığı gösterimle AYNI (yeniden biçimlenmez).
class _KanitCipi extends StatelessWidget {
  const _KanitCipi({required this.olcum, required this.gunAy});

  final NotOlcumu olcum;
  final DateFormat gunAy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    final kaynak = olcum.tarih == null
        ? olcum.kaynak
        : '${olcum.kaynak} ${gunAy.format(olcum.tarih!)}';
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: SandikRadius.smAll,
        border: Border.all(color: c.hairline),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${olcum.ad} · ', style: TextStyle(color: c.text58)),
          TextSpan(
              text: olcum.gosterim,
              style: TextStyle(color: c.text90, fontWeight: FontWeight.w700)),
          TextSpan(text: ' · $kaynak', style: TextStyle(color: c.text36)),
        ]),
        style: t.labelSmall,
      ),
    );
  }
}

class _YanlisSayiSayfasi extends StatefulWidget {
  const _YanlisSayiSayfasi();

  @override
  State<_YanlisSayiSayfasi> createState() => _YanlisSayiSayfasiState();
}

class _YanlisSayiSayfasiState extends State<_YanlisSayiSayfasi> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          Text(l10n.anzYanlisSayi,
              style: context.t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700, color: context.c.text90)),
          const SizedBox(height: SandikSpace.sm),
          TextField(
            controller: _ctrl,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(hintText: l10n.anzYanlisIpucu),
          ),
          const SizedBox(height: SandikSpace.sm),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
            child: Text(l10n.anzGonder),
          ),
        ],
      ),
    );
  }
}
