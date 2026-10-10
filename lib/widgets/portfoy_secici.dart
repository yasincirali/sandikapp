import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/gorunum_kapsami.dart';
import '../models/portfoy.dart';
import '../providers/portfoy_provider.dart';
import '../providers/preferences_provider.dart';
import '../screens/paywall_screen.dart';
import '../screens/portfoy_yonetimi_screen.dart';
import '../services/analytics_service.dart';
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'sandik_async_button.dart';

/// Portföy seçici şeridi — "Ben" kapsamının ALTINDA (Portföy ve Performans).
///
/// ## Neden çip şeridi, segment değil
/// `SandikSegment` 2–4 sabit seçenek içindir; portföy sayısı Premium'da
/// sınırsız. Yatay kayan çipler adı ne olursa olsun tam yazar (metin tam
/// okunur kuralı) ve sık geçilen hedeflere (Tümü / Ana / bir portföy) tek
/// dokunuş verir — `OrtakSecici`'nin "sık hedef tek dokunuş" kararıyla aynı.
///
/// ## Ne zaman çizilir
/// Yalnız [cokluPortfoyGorunurProvider] doğruyken ve liste yüklendiyse.
/// Kapalıyken HİÇBİR şey çizilmez (sıfır boy): ekranın yerleşimi birebir
/// eski. Adlandırılmış portföy yokken şerit yalnız "Tümü" ve "+ Yeni
/// portföy"dür — özelliği bulmanın tek yolu.
///
/// Seçim [seciliPortfoyProvider]'a yazılır; iki ekran aynı seçimi okur.
class PortfoySecici extends ConsumerWidget {
  const PortfoySecici({
    super.key,
    this.onDegisti,
    this.bosluk = EdgeInsets.zero,
  });

  /// Seçim değişince (ekranın tohum/önbellek atma işi için).
  final VoidCallback? onDegisti;

  /// Şerit ÇİZİLDİĞİNDE çevresine bırakılacak boşluk; çizilmezse hiç yer
  /// kaplamaz (bayrak kapalıyken ekranın ölçüleri birebir eski).
  final EdgeInsets bosluk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(cokluPortfoyGorunurProvider)) return const SizedBox.shrink();
    final liste = ref.watch(portfoylerProvider).valueOrNull;
    if (liste == null) return const SizedBox.shrink();
    final secim = ref.watch(portfoyKapsamiProvider).secim;
    final l = context.l10n;

    void sec(String yeni) {
      if (yeni == secim) return;
      CrashReporter.arkaPlan(ref.read(seciliPortfoyProvider.notifier).set(yeni),
          reason: 'portfoySecici.sec');
      onDegisti?.call();
    }

    final cipler = <Widget>[
      PortfoyCipi(
        key: const ValueKey('portfoy-cip-tumu'),
        etiket: l.portfoyTumu,
        secili: secim == PortfoySecimi.tumu,
        onTap: () => sec(PortfoySecimi.tumu),
      ),
      if (liste.isNotEmpty)
        PortfoyCipi(
          key: const ValueKey('portfoy-cip-ana'),
          etiket: l.portfoyAna,
          secili: secim == PortfoySecimi.ana,
          onTap: () => sec(PortfoySecimi.ana),
        ),
      for (final p in liste)
        PortfoyCipi(
          key: ValueKey('portfoy-cip-${p.id}'),
          etiket: p.ad,
          secili: secim == p.id,
          onTap: () => sec(p.id),
        ),
      PortfoyCipi(
        key: const ValueKey('portfoy-cip-yeni'),
        etiket: l.portfoyYeni,
        ikon: Icons.add_rounded,
        secili: false,
        onTap: () => CrashReporter.arkaPlan(
            yeniPortfoyAkisi(context, ref, sonra: onDegisti),
            reason: 'portfoySecici.yeni'),
      ),
      if (liste.isNotEmpty)
        PortfoyCipi(
          key: const ValueKey('portfoy-cip-yonet'),
          etiket: l.portfoyYonet,
          ikon: Icons.tune_rounded,
          yalnizIkon: true,
          secili: false,
          onTap: () => pushGuarded(
            context,
            adaptiveRoute<void>(builder: (_) => const PortfoyYonetimiScreen()),
          ),
        ),
    ];

    return Padding(
      padding: bosluk,
      child: Semantics(
        container: true,
        label: l.portfoySeciciEtiketi,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < cipler.length; i++) ...[
                if (i > 0) const SizedBox(width: SandikSpace.sm),
                cipler[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Şeridin tek çipi. Açık sınıf: yönetim ve form seçicisi aynı görünüşü
/// kullanır.
class PortfoyCipi extends StatelessWidget {
  const PortfoyCipi({
    super.key,
    required this.etiket,
    required this.secili,
    required this.onTap,
    this.ikon,
    this.yalnizIkon = false,
  });

  final String etiket;
  final bool secili;
  final VoidCallback onTap;
  final IconData? ikon;

  /// Yalnız ikon çizilir; [etiket] ekran okuyucuya gider.
  final bool yalnizIkon;

  @override
  Widget build(BuildContext context) {
    final renk = secili ? context.c.amberText : context.c.text90;
    final stil = context.t.titleSmall?.copyWith(
      color: renk,
      fontWeight: secili ? FontWeight.w700 : FontWeight.w500,
    );
    return SandikTappable(
      onTap: onTap,
      selected: secili,
      semanticLabel: etiket,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            minHeight: SandikTouch.min, minWidth: SandikTouch.min),
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          padding: EdgeInsets.symmetric(
              horizontal: yalnizIkon ? SandikSpace.smd : SandikSpace.md),
          decoration: context.chip(selected: secili),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ikon != null) Icon(ikon, size: 18, color: renk),
              if (ikon != null && !yalnizIkon)
                const SizedBox(width: SandikSpace.xs),
              if (!yalnizIkon)
                ExcludeSemantics(child: Text(etiket, maxLines: 1, style: stil)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "+ Yeni portföy": sınır doluysa paywall (kaynak `portfoy_limit`), değilse
/// ad sayfası; oluşturulan portföy SEÇİLİR (kullanıcı neden oluşturduysa
/// ona bakmak ister). Dönen değer yeni portföy ya da `null`.
Future<Portfoy?> yeniPortfoyAkisi(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? sonra,
  bool sec = true,
}) async {
  if (DemoModu.yazmaKapisi('portfoy')) return null; // Demo: hesap ister (F1).
  if (ref.read(portfoySiniriDoluProvider)) {
    unawaited(AnalyticsService.instance
        .logPremiumGateShown(feature: 'portfoy_limit'));
    await PaywallScreen.show(context, source: 'portfoy_limit');
    return null;
  }
  final l = context.l10n;
  final notifier = ref.read(portfoylerProvider.notifier);
  Portfoy? yeni;
  await showPortfoyAdiSayfasi(
    context,
    baslik: l.portfoyYeni,
    dugme: l.portfoyOlustur,
    kaydet: (ad) async => yeni = await notifier.olustur(ad),
  );
  final p = yeni;
  if (p != null && sec) {
    await ref.read(seciliPortfoyProvider.notifier).set(p.id);
    sonra?.call();
  }
  return p;
}

/// Ad sayfası (oluştur / yeniden adlandır). Yazma düğmenin İÇİNDE koşar
/// (tek yükleniyor davranışı); hata sayfayı kapatmaz, alanın altında
/// söylenir. Ad kuralı sunucuyla aynı ([Portfoy.adGecerli]) ve basmadan önce
/// gösterilir (girdi kuralları istemcide).
Future<void> showPortfoyAdiSayfasi(
  BuildContext context, {
  required String baslik,
  required String dugme,
  required Future<void> Function(String ad) kaydet,
  String baslangic = '',
}) =>
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => PortfoyAdiSayfasi(
        baslik: baslik,
        dugme: dugme,
        kaydet: kaydet,
        baslangic: baslangic,
      ),
    );

class PortfoyAdiSayfasi extends StatefulWidget {
  const PortfoyAdiSayfasi({
    super.key,
    required this.baslik,
    required this.dugme,
    required this.kaydet,
    this.baslangic = '',
  });

  final String baslik;
  final String dugme;
  final Future<void> Function(String ad) kaydet;
  final String baslangic;

  @override
  State<PortfoyAdiSayfasi> createState() => _PortfoyAdiSayfasiState();
}

class _PortfoyAdiSayfasiState extends State<PortfoyAdiSayfasi> {
  late final _ctrl = TextEditingController(text: widget.baslangic);
  String? _hata;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final l = context.l10n;
    final ad = _ctrl.text;
    if (!Portfoy.adGecerli(ad)) {
      setState(() => _hata = l.portfoyAdiGecersiz);
      return;
    }
    try {
      await widget.kaydet(ad.trim());
    } on PortfoyAdiKullaniliyor {
      if (mounted) setState(() => _hata = l.portfoyAdiKullaniliyor);
      return;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'PortfoyAdiSayfasi.kaydet');
      if (mounted) setState(() => _hata = friendlyError(e));
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SandikSpace.screenH(context),
        SandikSpace.lg,
        SandikSpace.screenH(context),
        MediaQuery.of(context).viewInsets.bottom + SandikSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.baslik,
            style: context.t.headlineSmall?.copyWith(
              color: context.c.text90,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: SandikSpace.md),
          TextField(
            key: const ValueKey('portfoy-adi-alani'),
            controller: _ctrl,
            autofocus: true,
            maxLength: Portfoy.adAzami,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _kaydet(),
            onChanged: (_) {
              if (_hata != null) setState(() => _hata = null);
            },
            style: context.t.bodyLarge?.copyWith(color: context.c.text90),
            decoration: context.inputDecoration(
              l.portfoyAdiIpucu,
              labelText: l.portfoyAdi,
              errorText: _hata,
            ),
          ),
          const SizedBox(height: SandikSpace.md),
          SandikAsyncButton.kompakt(
            key: const ValueKey('portfoy-adi-kaydet'),
            style: FilledButton.styleFrom(
              backgroundColor: context.c.amberFill,
              foregroundColor: context.c.onAmber,
            ),
            onPressed: _kaydet,
            child: Text(widget.dugme,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Ekleme formlarının portföy seçimi (tek varlık, toplu sepet, sözleşme).
///
/// Değer [secili] (`null` = Ana); varsayılanı çağıran
/// `varsayilanYeniPortfoyProvider`'dan verir (o an seçili portföy, yoksa
/// Ana). Özellik görünmüyorsa ya da adlandırılmış portföy yoksa HİÇBİR şey
/// çizmez — form birebir eski ve kayıt Ana'ya gider.
class PortfoyFormSecici extends ConsumerWidget {
  const PortfoyFormSecici({
    super.key,
    required this.secili,
    required this.onSec,
    this.bosluk = EdgeInsets.zero,
  });

  final String? secili;
  final ValueChanged<String?> onSec;

  /// Çizildiğinde çevresindeki boşluk.
  final EdgeInsets bosluk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(cokluPortfoyGorunurProvider)) return const SizedBox.shrink();
    final liste = ref.watch(portfoylerProvider).valueOrNull ?? const [];
    if (liste.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final cipler = <Widget>[
      PortfoyCipi(
        key: const ValueKey('form-portfoy-ana'),
        etiket: l.portfoyAna,
        secili: secili == null,
        onTap: () => onSec(null),
      ),
      for (final p in liste)
        PortfoyCipi(
          key: ValueKey('form-portfoy-${p.id}'),
          etiket: p.ad,
          secili: secili == p.id,
          onTap: () => onSec(p.id),
        ),
    ];
    return Padding(
      padding: bosluk,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.portfoySeciciEtiketi,
            style: context.t.labelLarge?.copyWith(color: context.c.text58),
          ),
          const SizedBox(height: SandikSpace.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < cipler.length; i++) ...[
                  if (i > 0) const SizedBox(width: SandikSpace.sm),
                  cipler[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
