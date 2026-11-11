import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import 'custom_loading_indicator.dart';
import 'sandik_ikon_gecisi.dart';

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

/// Düğmenin "✓ oldu" anını çağırandan isteyen sinyal (Ar-Ge 11 Kas 19:04 #3).
///
/// ## Neden bool değil, sinyal
/// Başarıyı yalnız çağıran bilir: ekranların `onPressed`'i hatayı çoğu
/// zaman kendisi yakalar (alan altında `_hata`, snack) ve normal döner.
/// "İş fırlatmadan bitti" = başarı saymak, yakalanmış hatada da ✓
/// gösterirdi. Bu yüzden çağıran başarı yolunda, sayfayı kapatmadan hemen
/// önce `await basari.goster()` der; ✓ evresi bitince kapanış onun
/// elinde koşar. Hata yolunda çağrılmaz → ✓ yok, eski hata yolu aynen.
///
/// `goster()` [SandikAsyncButton.onPressed]'in İÇİNDE beklenir: düğme bu
/// sürede de meşgul sayılır, çift dokunma kilidi ✓ evresinde sürer.
/// Bağlı düğme yoksa (iş klavyedeki "Bitti"den başladı ve düğme ağaçta
/// değil, ya da sinyal hiç bir düğmeye verilmedi) yalnız titreşim verir ve
/// beklemeden döner — kapanış asla bu yüzden takılmaz.
class SandikBasariSinyali {
  _SandikAsyncButtonState? _dugme;

  /// Düğmede ✓'yi gösterir, başarı titreşimini verir ve ✓ evresi bitince
  /// döner. Çağıran döndükten sonra `mounted` bakıp sayfayı kapatır.
  Future<void> goster() async {
    final d = _dugme;
    if (d == null || !d.mounted) {
      SandikHaptic.basari.perform();
      return;
    }
    await d._basariGoster();
  }
}

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
    this.mesgul = false,
    this.basari,
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
    this.mesgul = false,
    this.basari,
  })  : expand = false,
        height = null;

  /// Görünüş. Varsayılan dolu amber (form altı ana eylem). Çerçeve/metin
  /// temanın `OutlinedButton`/`TextButton` stiline düşer.
  final SandikAsyncTur tur;

  /// Etiketin önündeki ikon (`FilledButton.icon` karşılığı). Meşgulken
  /// ikon + etiketin tamamı göstergeyle yer değiştirir.
  final Widget? icon;

  /// Aynı iş düğmeden GEÇMEDEN de başlayabiliyorsa (klavyede "Bitti", OTP'de
  /// 6. hane) ekranın bayrağı: düğme aynı göstergeyle kilitlenir. Ekran
  /// kendi göstergesini etikete koymaz — tek gösterge buradan çizilir.
  final bool mesgul;

  /// İsteğe bağlı başarı durumu ([SandikBasariSinyali]). `null` (varsayılan)
  /// → eski davranış birebir: ✓ yok, iş bitince etiket geri gelir.
  ///
  /// Verilirse ve çağıran başarıda `goster()` derse gösterge yerinde ✓'ye
  /// döner (`state` sönüm + 0.9→1 ölçek, [SandikIkonGecisi.gecis]), başarı
  /// titreşimi gelir, ✓ [SandikMotion.modal] kadar görünür, sonra
  /// çağıranın kapanışı koşar. Hareketi azalt açıkken ✓ geçişsiz belirir
  /// ama görünme süresi KALIR: bekleme hareket değil, okuma payıdır.
  /// Yalnız işin ardından sayfanın kapandığı akışta kullanılır (TASARIM_DILI
  /// §4 Düğmeler); sayfa açık kalıyorsa sonuç zaten ekranda görünür.
  final SandikBasariSinyali? basari;

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

class _SandikAsyncButtonState extends State<SandikAsyncButton>
    with SingleTickerProviderStateMixin {
  bool _busy = false;

  /// ✓ evresi sürüyor (düğme hâlâ kilitli).
  bool _basarili = false;

  /// ✓'nin görünme süresinin saati. `Future.delayed` yerine denetleyici:
  /// süre boyunca kare istenir, testte `pumpAndSettle` evreyi sonuna kadar
  /// ilerletir (asılı kalan zamanlayıcı bırakmaz); düğme ağaçtan kalkarsa
  /// `dispose` saati durdurur, bekleyen `goster()` hemen döner.
  late final AnimationController _basariSaati =
      AnimationController(vsync: this, duration: SandikMotion.modal);

  @override
  void initState() {
    super.initState();
    widget.basari?._dugme = this;
  }

  @override
  void didUpdateWidget(SandikAsyncButton old) {
    super.didUpdateWidget(old);
    if (old.basari != widget.basari) {
      if (old.basari?._dugme == this) old.basari?._dugme = null;
      widget.basari?._dugme = this;
    }
  }

  @override
  void dispose() {
    if (widget.basari?._dugme == this) widget.basari?._dugme = null;
    _basariSaati.dispose();
    super.dispose();
  }

  Future<void> _basariGoster() async {
    SandikHaptic.basari.perform();
    setState(() => _basarili = true);
    try {
      await _basariSaati.forward(from: 0).orCancel;
    } on TickerCanceled {
      // Düğme evre bitmeden ağaçtan kalktı; çağıran `mounted` bakar.
    }
  }

  Future<void> _handleTap() async {
    // Kilit: ikinci dokunuş sessizce yok sayılır.
    if (_busy || widget.mesgul || widget.onPressed == null) return;
    // Haptic kilidin ARDINDAN: yutulan ikinci dokunuş titreşim de vermemeli,
    // aksi halde kullanıcı isteğin gittiğini sanır.
    widget.haptic.perform();
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      // İş bittiğinde/hata verdiğinde kilidi mutlaka aç. Widget ağaçtan
      // kalkmışsa setState çağırma. ✓ de iner: sayfa kapanmadıysa (çağıran
      // ✓'den sonra açık bıraktı) düğme eski hâline döner.
      if (mounted) {
        setState(() {
          _busy = false;
          _basarili = false;
        });
      }
    }
  }

  /// Etiketin üstündeki yuva: ✓ > gösterge > boş. Bileşenin kendi
  /// göstergesi (ekranlarda elle meşgul hâli yasak; burası tek kaynak).
  Widget _yuva(BuildContext context, bool mesgul) {
    if (_basarili) {
      return Semantics(
        key: const ValueKey('basari'),
        // Tek duyuru: ✓ belirdiğinde bir kez "Kaydedildi"; etiket görünmez
        // olduğundan düğmenin tek metni bu.
        liveRegion: true,
        label: context.l10n.dugmeBasarili,
        child: const ExcludeSemantics(
          child: Icon(Icons.check_rounded, size: CustomLoadingIndicator.small),
        ),
      );
    }
    if (mesgul) {
      return const CustomLoadingIndicator(
        key: ValueKey('busy'),
        size: CustomLoadingIndicator.small,
      );
    }
    return const SizedBox.shrink(key: ValueKey('bos'));
  }

  @override
  Widget build(BuildContext context) {
    // Meşgulken null → Flutter'ın kendi pasif görünümü devreye girer.
    // ✓ evresi de meşgul sayılır: çift dokunma kilidi sürer.
    final mesgul = _busy || widget.mesgul || _basarili;
    final basinca = widget.onPressed == null || mesgul ? null : _handleTap;
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
          opacity: mesgul ? 0 : 1,
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          child: etiket,
        ),
        // Gösterge → ✓ aynı yuvada, aç/kapa ikonuyla aynı geçiş
        // (`SandikIkonGecisi.gecis`). Hareketi azaltta süre sıfır: ✓
        // ölçeksiz, sönümsüz yerine geçer.
        AnimatedSwitcher(
          duration: SandikMotion.stateOf(context),
          switchInCurve: SandikMotion.enter,
          switchOutCurve: SandikMotion.exit,
          transitionBuilder: SandikIkonGecisi.gecis,
          child: _yuva(context, mesgul),
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
    this.zemin,
  });

  final Future<void> Function()? onTap;
  final Widget child;

  /// Hedefin kutusu (dolgu, çerçeve). Meşgulken GİZLENMEZ — yalnız
  /// [child] (ikon/etiket) göstergeye yer açar. Kutuyu çocuğun içine
  /// çizen hedef meşgulken tümden kayboluyordu (onay diyaloğundaki "Yine
  /// de sil", web ekran görüntüsü 2026-10-08).
  final Decoration? zemin;

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
      child: _zeminli(Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
              opacity: _busy && widget.showIndicator ? 0 : 1,
              child: widget.child),
          if (_busy && widget.showIndicator)
            CustomLoadingIndicator(size: widget.indicatorSize),
        ],
      )),
    );
  }

  Widget _zeminli(Widget icerik) {
    final z = widget.zemin;
    return z == null ? icerik : DecoratedBox(decoration: z, child: icerik);
  }
}
