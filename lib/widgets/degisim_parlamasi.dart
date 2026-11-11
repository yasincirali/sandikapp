import 'package:flutter/widgets.dart';

import '../theme/sandik.dart';
import 'degisim_vurgusu.dart';

/// Liste satırındaki tutar/fiyat fiyat turunda değişince kısa süre YÖN
/// tonunda zemin alır ve yanında tek seferlik ▲/▼ belirir; ikisi birlikte
/// söner (~[SandikMotion.flow]).
///
/// ## Neden (Ar-Ge 11 Kas 18:04 #2)
/// 30 sn'lik ortak fiyat turu (`tazelik_ritmi.dart`) Portföy ve Takip
/// listesinde rakamı sessizce değiştiriyordu; kullanıcı "canlı mı" diye
/// çekip yeniliyordu. Aracı kurum uygulamalarındaki "tick flash"ın sakin
/// hâli: yalnız değer değişince, değişim başına BİR kez, döngü yok.
///
/// ## Neden [DegisimVurgusu] değil
/// O, tek büyük sayının METİN rengini boyar (Ana sayfa toplamı). Satırda
/// tutar zaten `text90` ve küçük; metin rengi değişimi gözden kaçıyordu,
/// zemin tonu kaçmıyor. Yakma kuralı ikisinde ortak: [degisimYonu].
///
/// ## Ne zaman YAKMAZ
///  - ilk kurulumda (satır ilk kez çizildi ya da kaydırmada yeniden kuruldu:
///    State yeni, kıyaslanacak eski değer yok),
///  - [kimlik] değişince (başka satır, adet değişti, para birimi değişti —
///    kullanıcının kendi eylemi fiyat hareketi değil),
///  - [etkin] `false` iken ya da az önce `false` idiyse (tutar gizli: renk
///    ve ok yönü ele verirdi; gözü açmak da bir değişim değil),
///  - [metin] aynı kaldıysa (ekranda görünen bir şey değişmedi),
///  - sekme görünmezken (`TickerMode` kapalı): saat durur, kullanıcı
///    döndüğünde eski bir değişimin tonu donmuş görünürdü.
///
/// ## Hareketi azalt
/// Zemin tonu solmaz (hiç çizilmez); ok aynı sürenin İKİ katı sabit durur
/// ve tek karede kalkar. Yön bilgisi kaybolmaz, ama hiçbir şey akmaz. Ok
/// solmadığı için kısa kalsaydı göz yakalayamadan giderdi.
///
/// ## Erişilebilirlik
/// Ok `ExcludeSemantics` altında; canlı bölge yok. 30 sn'de bir onlarca
/// satır değişir — her birini okumak ekran okuyucuyu boğardı. Güncel değer
/// satırın kendi etiketinde zaten okunuyor. Yön yalnız renkle verilmez:
/// ok şekli de söyler (renk körlüğü).
///
/// Yerleşimi DEĞİŞTİRMEZ: zemin ve ok `Stack` taşmasında çizilir; rakam
/// ok belirince kaymaz. Her karede yalnız bu küçük alan yeniden kurulur
/// (`AnimatedBuilder` + `RepaintBoundary`), satırın geri kalanı değil.
class DegisimParlamasi extends StatefulWidget {
  const DegisimParlamasi({
    super.key,
    required this.deger,
    required this.metin,
    required this.child,
    this.kimlik,
    this.etkin = true,
    this.okSonda = false,
  });

  /// Karşılaştırılan sayısal değer (yön buradan).
  final double deger;

  /// Ekranda görünen biçimlenmiş metin; değişmediyse yakmaz.
  final String metin;

  /// Değerin "neye ait" olduğu (satır, adet, birim); değişirse yakmaz.
  final Object? kimlik;

  final bool etkin;

  /// Ok metnin ardında (sola yaslı tutar) — varsayılan önünde (sağa yaslı
  /// sütunda solda boşluk vardır, sağda genişlet oku/düğme durur).
  final bool okSonda;

  final Widget child;

  @override
  State<DegisimParlamasi> createState() => _DegisimParlamasiState();
}

class _DegisimParlamasiState extends State<DegisimParlamasi>
    with SingleTickerProviderStateMixin {
  // Yalnız ilk değişimde kurulur: listede onlarca satır var, çoğu hiç
  // yanmaz; `_YeniVarlikParlamasi` ile aynı tembel desen.
  AnimationController? _c;
  bool _artis = true;

  @override
  void didUpdateWidget(covariant DegisimParlamasi old) {
    super.didUpdateWidget(old);
    final yon = degisimYonu(
      eski: old.deger,
      yeni: widget.deger,
      ayniKimlik: old.kimlik == widget.kimlik,
      // Gizliden açılış da bir fiyat hareketi değil.
      etkin: widget.etkin && old.etkin,
      esik: 0,
    );
    if (yon == null || old.metin == widget.metin) return;
    if (!TickerMode.getValuesNotifier(context).value.enabled) return;
    _artis = yon;
    final azalt = MediaQuery.disableAnimationsOf(context);
    final c = _c ??= AnimationController(vsync: this, value: 1);
    c.duration = azalt ? SandikMotion.flow * 2 : SandikMotion.flow;
    c.forward(from: 0);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: c,
        child: widget.child,
        builder: (context, child) => _katman(context, c.value, child!),
      ),
    );
  }

  Widget _katman(BuildContext context, double v, Widget child) {
    final aktif = v < 1;
    final azalt = MediaQuery.disableAnimationsOf(context);
    final yon = _artis ? context.c.gain : context.c.loss;
    // Hemen tepe tonda başlar, ease-out ile söner: gözün yakalaması gereken
    // an değişimin kendisi (`DegisimVurgusu` ile aynı eğri).
    final kalan = aktif ? 1 - SandikMotion.enter.transform(v) : 0.0;
    final okSaydamlik = !aktif ? 0.0 : (azalt ? 1.0 : kalan);
    final ok = ExcludeSemantics(
      child: Text(
        _artis ? '▲' : '▼',
        key: const ValueKey('degisim-parlamasi-ok'),
        style: context.t.labelMedium?.copyWith(color: yon, height: 1),
      ),
    );
    // Çocuk HER karede aynı konumda (Stack'in 1. öğesi): yapı değişseydi
    // metin öğesi yeniden kurulurdu.
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          left: -SandikSpace.xs,
          right: -SandikSpace.xs,
          top: -SandikSpace.xxs,
          bottom: -SandikSpace.xxs,
          child: aktif && !azalt
              ? DecoratedBox(
                  key: const ValueKey('degisim-parlamasi-ton'),
                  decoration: BoxDecoration(
                    color: yon.withValues(alpha: 0.18 * kalan),
                    borderRadius: SandikRadius.smAll,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        child,
        Positioned(
          top: 0,
          bottom: 0,
          left: widget.okSonda ? null : 0,
          right: widget.okSonda ? 0 : null,
          child: okSaydamlik == 0
              ? const SizedBox.shrink()
              : Center(
                  // Okun KENDİ genişliği kadar dışarı: sabit piksel değil,
                  // yazı büyüyünce ok da büyür ve yine bitişik kalır.
                  child: FractionalTranslation(
                    translation: Offset(widget.okSonda ? 1.25 : -1.25, 0),
                    child: Opacity(opacity: okSaydamlik, child: ok),
                  ),
                ),
        ),
      ],
    );
  }
}
