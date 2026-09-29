import 'package:flutter/widgets.dart';

import '../theme/sandik.dart';

/// Değer değişince metnin rengini kısa süre YÖN rengine boyar (artışta
/// kazanç, düşüşte kayıp), sonra asıl rengine döner.
///
/// ## Neden (hareket/UX denetimi 2026-09-29, "kaçırılmış fırsat")
/// Ana sayfadaki toplam değer fiyat turu bitince sessizce değişiyordu;
/// Zirve ekranında rakamlar sayarak akarken uygulamanın en çok bakılan
/// sayısı "canlı" olduğunu hiç söylemiyordu. Vurgu yalnızca RENK: konum/
/// ölçek hareketi yok. Bu yüzey günde onlarca kez görülür; hareket yorardı,
/// renk bilgi verir ve "hareketi azalt" açıkken de kalır (azaltılmış
/// hareket renk geçişini kapsamaz).
///
/// Ne zaman YAKMAZ:
///  - ilk kurulum ve 0'dan ilk değere geçiş (açılış yüklemesi fiyat
///    hareketi değil),
///  - [kimlik] değişince (Ben → ortak → Birlikte: toplam doğal olarak başka),
///  - [etkin] `false` iken (tutar gizli — renk yönü ele verirdi),
///  - kuruştan küçük farklar (yuvarlama gürültüsü).
class DegisimVurgusu extends StatefulWidget {
  const DegisimVurgusu({
    super.key,
    required this.deger,
    required this.renk,
    required this.builder,
    this.kimlik,
    this.etkin = true,
  });

  /// Karşılaştırılan değer (ekrandaki birimden bağımsız, ör. TRY toplam).
  final double deger;

  /// Metnin dinlenme rengi.
  final Color renk;

  /// O anki renkle metni kurar.
  final Widget Function(BuildContext context, Color renk) builder;

  /// Değerin "kime ait" olduğu; değişirse vurgu yakılmaz.
  final Object? kimlik;

  final bool etkin;

  @override
  State<DegisimVurgusu> createState() => _DegisimVurgusuState();
}

class _DegisimVurgusuState extends State<DegisimVurgusu>
    with SingleTickerProviderStateMixin {
  // Dinlenme hâli value = 1 (asıl renk). Yakınca 0'dan 1'e döner.
  late final AnimationController _c =
      AnimationController(vsync: this, duration: SandikMotion.flow, value: 1);
  bool _artis = true;

  @override
  void didUpdateWidget(covariant DegisimVurgusu old) {
    super.didUpdateWidget(old);
    final fark = widget.deger - old.deger;
    if (!widget.etkin ||
        old.kimlik != widget.kimlik ||
        old.deger.abs() < 0.005 ||
        fark.abs() < 0.005) {
      return;
    }
    _artis = fark > 0;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yon = _artis ? context.c.gain : context.c.loss;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => widget.builder(
        context,
        _c.value >= 1
            ? widget.renk
            // Hemen yön rengine çıkar, yavaşça asıl renge söner: gözün
            // yakalaması gereken an değişimin kendisi.
            : Color.lerp(yon, widget.renk, SandikMotion.enter.transform(_c.value))!,
      ),
    );
  }
}
