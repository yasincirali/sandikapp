import 'package:flutter/material.dart';
import '../theme/sandik.dart';
import 'custom_loading_indicator.dart';

/// Asenkron bir işi tetikleyen butonlar için tek sarmalayıcı.
///
/// Amaç "aksiyon kesinliği": kullanıcı heyecanla arka arkaya dokunduğunda
/// aynı isteğin iki kez gitmesini engeller. İş bitene kadar buton kilitlenir
/// ve yerinde [CustomLoadingIndicator] görünür.
///
/// Davranış sözleşmesi — iş mantığı bu widget'ta DEĞİŞMEZ:
/// - [onPressed] birebir aynı şekilde, aynı sayıda (en fazla bir kez eşzamanlı)
///   çağrılır. Sarmalayıcı ne argüman ekler ne de sonucu yorumlar.
/// - Hata yutulmaz; [onPressed] fırlatırsa istisna çağırana geri iletilir.
///   Sarmalayıcı yalnızca kilidi `finally` içinde serbest bırakır.
/// - [onPressed] null ise buton pasif — mevcut `FilledButton` semantiği aynen.
///
/// ## Tek yükleniyor davranışı (yasin, 2026-10-08: "arkasında istek giden
/// buton kliklerini tespit edelim ve hepsinde aynı loading aksiyonu
/// alınsın")
/// İstek atan HER düğme bu bileşenden (ya da düğme olmayan hedefte
/// [SandikAsyncTap]'ten) geçer: iş sürerken düğme pasif, etiketin yerinde
/// küçük [CustomLoadingIndicator], ikinci dokunuş sessizce yutulur, düğmenin
/// boyu değişmez. Görünüş [tur] ile seçilir (dolu / çerçeve / metin); ekran
/// kendi `_busy` bayrağını ve kendi döneni yazmaz. İstisnalar (bilinçli):
/// iyimser güncellemeler (anahtar, oy, kaydırarak silme — sonuç anında
/// görünür, hata olursa geri alınır) ve hesap silme tam ekran perdesi.
/// Kilit `test/yukleniyor_tek_davranis_test.dart`.
enum SandikAsyncTur { dolu, cerceve, metin }

class SandikAsyncButton extends StatefulWidget {
  const SandikAsyncButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.expand = true,
    this.height = 52,
    this.haptic = SandikHaptic.medium,
    this.tur = SandikAsyncTur.dolu,
    this.icon,
  });

  /// Kompakt düğme (diyalog, kart içi eylem): boy ve genişlik içerikten.
  /// [tur] varsayılanı burada [SandikAsyncTur.metin] değil, çağıran seçer.
  const SandikAsyncButton.kompakt({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.haptic = SandikHaptic.medium,
    this.tur = SandikAsyncTur.dolu,
    this.icon,
  })  : expand = false,
        height = null;

  /// Görünüş. Varsayılan dolu amber (form altı ana eylem). Çerçeve/metin
  /// temanın `OutlinedButton`/`TextButton` stiline düşer.
  final SandikAsyncTur tur;

  /// Etiketin önündeki ikon (`FilledButton.icon` karşılığı). Meşgulken
  /// ikon + etiketin tamamı göstergeyle yer değiştirir.
  final Widget? icon;

  /// Asenkron iş. Devam ederken buton kilitlidir.
  final Future<void> Function()? onPressed;

  /// Varsayılan [SandikHaptic.medium]: form altı ana eylem butonu genelde
  /// kalıcı bir sonuç üretir (kaydet, gönder, satın al).
  final SandikHaptic haptic;

  /// Boştayken gösterilen içerik (genelde `Text`).
  final Widget child;

  final ButtonStyle? style;

  /// true ise satırın tamamını kaplar (form altı ana eylem).
  final bool expand;

  /// `null` → içerikten (kompakt).
  final double? height;

  @override
  State<SandikAsyncButton> createState() => _SandikAsyncButtonState();
}

class _SandikAsyncButtonState extends State<SandikAsyncButton> {
  bool _busy = false;

  Future<void> _handleTap() async {
    // Kilit: ikinci dokunuş sessizce yok sayılır.
    if (_busy || widget.onPressed == null) return;
    // Haptic kilidin ARDINDAN: yutulan ikinci dokunuş titreşim de vermemeli,
    // aksi halde kullanıcı isteğin gittiğini sanır.
    widget.haptic.perform();
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      // İş bittiğinde/hata verdiğinde kilidi mutlaka aç. Widget ağaçtan
      // kalkmışsa setState çağırma.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Meşgulken null → Flutter'ın kendi pasif görünümü devreye girer.
    final basinca = widget.onPressed == null || _busy ? null : _handleTap;
    final ikon = widget.icon;
    final etiket = ikon == null
        ? widget.child
        : Row(mainAxisSize: MainAxisSize.min, children: [
            ikon,
            const SizedBox(width: SandikSpace.sm),
            Flexible(child: widget.child),
          ]);
    // Gösterge etiketle AYNI kutuda: düğmenin boyu meşgulken değişmez
    // (etiket görünmez ama yer tutar), satır zıplamaz.
    final icerik = Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: _busy ? 0 : 1,
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          child: etiket,
        ),
        if (_busy)
          const CustomLoadingIndicator(
            key: ValueKey('busy'),
            size: CustomLoadingIndicator.small,
          ),
      ],
    );
    final Widget dugme = switch (widget.tur) {
      SandikAsyncTur.dolu => FilledButton(
          onPressed: basinca,
          style: widget.style ??
              FilledButton.styleFrom(
                backgroundColor: context.c.amberFill,
                foregroundColor: context.c.onAmber,
                disabledBackgroundColor:
                    context.c.amberFill.withValues(alpha: 0.5),
                disabledForegroundColor:
                    context.c.onAmber.withValues(alpha: 0.7),
                shape: RoundedRectangleBorder(
                  borderRadius: SandikRadius.mdAll,
                ),
              ),
          child: icerik,
        ),
      SandikAsyncTur.cerceve =>
        OutlinedButton(onPressed: basinca, style: widget.style, child: icerik),
      SandikAsyncTur.metin =>
        TextButton(onPressed: basinca, style: widget.style, child: icerik),
    };
    final h = widget.height;
    final kutulu = h == null ? dugme : SizedBox(height: h, child: dugme);
    return widget.expand
        ? SizedBox(width: double.infinity, child: kutulu)
        : kutulu;
  }
}

/// Buton olmayan asenkron dokunma hedefleri (ikon butonu, liste satırı) için
/// aynı tek-uçuş garantisini veren sarmalayıcı.
///
/// [SandikTappable]'ın basma animasyonunu korur; iş sürerken dokunmayı yutar
/// ve isteğe bağlı olarak içeriği yükleme göstergesiyle değiştirir.
class SandikAsyncTap extends StatefulWidget {
  const SandikAsyncTap({
    super.key,
    required this.onTap,
    required this.child,
    this.showIndicator = true,
    this.indicatorSize = CustomLoadingIndicator.small,
    this.semanticLabel,
    this.haptic = SandikHaptic.medium,
  });

  final Future<void> Function()? onTap;
  final Widget child;

  /// false ise içerik yerinde kalır, yalnızca dokunma kilitlenir.
  final bool showIndicator;
  final double indicatorSize;
  final String? semanticLabel;

  /// Varsayılan [SandikHaptic.medium]: asenkron bir iş tetikleyen dokunuşlar
  /// genelde kalıcı sonuçludur (kaydet, gönder, onayla) — seçim tıkırtısından
  /// daha belirgin olmalı.
  final SandikHaptic haptic;

  @override
  State<SandikAsyncTap> createState() => _SandikAsyncTapState();
}

class _SandikAsyncTapState extends State<SandikAsyncTap> {
  bool _busy = false;

  Future<void> _handleTap() async {
    if (_busy || widget.onTap == null) return;
    setState(() => _busy = true);
    try {
      await widget.onTap!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SandikTappable(
      onTap: widget.onTap == null || _busy ? null : _handleTap,
      // Meşgulken onTap null → SandikTappable haptic'i de tetiklemez;
      // yutulan ikinci dokunuş sessiz kalır, bu doğru davranış.
      haptic: widget.haptic,
      semanticLabel: widget.semanticLabel,
      // Gösterge içeriğin ÜSTÜNDE, içerik görünmez ama yer tutar: hedefin
      // boyu meşgulken değişmez ([SandikAsyncButton] ile aynı kural).
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
              opacity: _busy && widget.showIndicator ? 0 : 1,
              child: widget.child),
          if (_busy && widget.showIndicator)
            CustomLoadingIndicator(size: widget.indicatorSize),
        ],
      ),
    );
  }
}
