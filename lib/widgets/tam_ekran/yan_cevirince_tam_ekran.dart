import 'package:flutter/material.dart';

/// Telefon dikten yana dönünce [ac]'ı bir kez çağırır.
///
/// ## Neden yalnız geçişte
/// Tam ekran grafiğin tek girişi yan çevirmek (dik ekrandaki çip
/// 2026-09-17'de kullanıcı kararıyla kalktı). Sayfa zaten yatayken
/// açıldıysa ya da kullanıcı tam ekranı kapat düğmesiyle kapatıp yatay
/// kaldıysa grafik yeniden itilmez: aksi hâlde kapatmak imkânsız olurdu.
/// Yeni bir açılış için telefon önce dik dönmelidir.
///
/// ## Neden tablette yok
/// En kısa kenarı 600 dp ve üstü olan cihazda yatay ekran zaten geniş;
/// dik/yatay geçiş bir niyet bildirmez (iPad'de klavye kılıfıyla yatay
/// çalışmak olağan). Widget testlerinin varsayılan 800×600 yüzeyi de bu
/// yüzden tetiklemez.
///
/// ## Neden yalnız en üstteki sayfada
/// Bir sheet ya da başka sayfa üstteyken yan çevirmek o sayfanın işidir;
/// `ModalRoute.isCurrent` değilse hiçbir şey yapılmaz.
class YanCevirinceTamEkran extends StatefulWidget {
  const YanCevirinceTamEkran({
    super.key,
    required this.etkin,
    required this.ac,
    required this.child,
  });

  /// Bu yüzeyde tam ekran grafik var mı (mum kaynağı olan varlık).
  final bool etkin;
  final Future<void> Function(BuildContext context) ac;
  final Widget child;

  @override
  State<YanCevirinceTamEkran> createState() => _YanCevirinceTamEkranState();
}

class _YanCevirinceTamEkranState extends State<YanCevirinceTamEkran> {
  Orientation? _onceki;
  bool _acik = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final boyut = MediaQuery.sizeOf(context);
    final yon = boyut.width > boyut.height
        ? Orientation.landscape
        : Orientation.portrait;
    final onceki = _onceki;
    _onceki = yon;
    if (onceki != Orientation.portrait || yon != Orientation.landscape) return;
    if (!widget.etkin || _acik || boyut.shortestSide >= 600) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _acik = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _acik = false;
        return;
      }
      try {
        await widget.ac(context);
      } finally {
        _acik = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
