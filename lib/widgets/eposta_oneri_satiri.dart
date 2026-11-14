import 'package:flutter/cupertino.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import '../utils/eposta_onerisi.dart';

/// "Bunu mu demek istedin? ahmet@gmail.com" — e-posta alanının hemen altına
/// konur; kayıt, giriş ve şifremi unuttum aynı bileşeni kullanır.
///
/// Neden alan bırakılmayı BEKLEMEZ (yasin 2026-11-14, TestFlight: "düzeltme
/// önerisi gelmedi"): ilk sürüm öneriyi alan dokunulmuş sayılınca
/// (klavyede "ileri" ya da alan dışına dokunma) gösteriyordu; cihazda bu an
/// her yoldan yakalanmadı ve öneri hiç çıkmadı. Artık adres biçimce
/// geçerli olduğu anda görünür. Yazarken kısa süreli öneri ("gmail.co" →
/// "gmail.com") zararsız: bir harf sonra kendiliğinden kaybolur.
///
/// Öneri kaydı ENGELLEMEZ; gerçek ama az bilinen alan adını reddetmek yanlış
/// pozitifin bedelini kullanıcıya ödetirdi. Tüm satır tek dokunma hedefi
/// (CupertinoButton, en az 44 pt); adres amber + w600 ile ayrışır ki anlam
/// yalnız renkte kalmasın.
class EPostaOneriSatiri extends StatefulWidget {
  const EPostaOneriSatiri({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<EPostaOneriSatiri> createState() => _EPostaOneriSatiriState();
}

class _EPostaOneriSatiriState extends State<EPostaOneriSatiri> {
  String? _oneri;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_hesapla);
    _oneri = ePostaYazimOnerisiGecerliyse(widget.controller.text);
  }

  @override
  void didUpdateWidget(EPostaOneriSatiri eski) {
    super.didUpdateWidget(eski);
    if (eski.controller != widget.controller) {
      eski.controller.removeListener(_hesapla);
      widget.controller.addListener(_hesapla);
      _hesapla();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_hesapla);
    super.dispose();
  }

  void _hesapla() {
    final yeni = ePostaYazimOnerisiGecerliyse(widget.controller.text);
    if (yeni != _oneri) setState(() => _oneri = yeni);
  }

  void _uygula() {
    final o = _oneri;
    if (o == null) return;
    SandikHaptic.selection.perform();
    widget.controller.value = TextEditingValue(
      text: o,
      selection: TextSelection.collapsed(offset: o.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _oneri;
    if (o == null) return const SizedBox.shrink();
    final stil = context.t.bodyMedium?.copyWith(color: context.c.text58);
    return Align(
      alignment: Alignment.centerLeft,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
        minimumSize: SandikTouch.minSize,
        onPressed: _uygula,
        child: Text.rich(
          TextSpan(style: stil, children: [
            TextSpan(text: context.l10n.ePostaOneriSoru),
            TextSpan(
              text: o,
              style: stil?.copyWith(
                color: context.c.amberText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
