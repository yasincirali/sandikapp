import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/cizim_alarmi.dart' show kCizgiAdiAzami;
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart' show friendlyError;
import 'sandik_async_button.dart';

/// Çizgi alarmının adı — kurarken (trend/ışın zili) ve Alarmlarım'dan
/// yeniden adlandırırken aynı sayfa (yasin 2026-10-29: *"Çizgi alarmında
/// isim verebilelim"*).
///
/// ## Neden isteğe bağlı
/// Ad boş kalırsa alarm bugünkü gibi varlığın adıyla kurulur: tek dokunuşla
/// alarm kuran kullanıcı ikinci bir zorunlu adımla karşılaşmaz, düğme hep
/// basılabilir. Yazılan ad `label`'a "THYAO · Destek 245" olarak girer
/// ([cizgiAlarmEtiketi]); push başlığı, çan ve Alarmlarım onu okur.
///
/// ## Neden alan açılışta odaklanmaz (kurarken)
/// Sayfa yatay grafikten açılır; telefon yan dururken klavye ekranın
/// neredeyse tamamını örter (alarm sayfasındaki `odakla: false` kararı).
/// Yeniden adlandırmada amaç yazmak: [odakla] açık.
///
/// Yazma düğmenin İÇİNDE koşar (tek yükleniyor davranışı); hata sayfayı
/// kapatmaz, alanın altında söylenir.
Future<void> showCizgiAdiSayfasi(
  BuildContext context, {
  required String baslik,
  required String dugme,
  required Future<void> Function(String isim) kaydet,
  String baslangic = '',
  bool odakla = false,
}) =>
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => CizgiAdiSayfasi(
        baslik: baslik,
        dugme: dugme,
        kaydet: kaydet,
        baslangic: baslangic,
        odakla: odakla,
      ),
    );

class CizgiAdiSayfasi extends StatefulWidget {
  const CizgiAdiSayfasi({
    super.key,
    required this.baslik,
    required this.dugme,
    required this.kaydet,
    this.baslangic = '',
    this.odakla = false,
  });

  final String baslik;
  final String dugme;
  final Future<void> Function(String isim) kaydet;
  final String baslangic;
  final bool odakla;

  @override
  State<CizgiAdiSayfasi> createState() => _CizgiAdiSayfasiState();
}

class _CizgiAdiSayfasiState extends State<CizgiAdiSayfasi> {
  late final _ctrl = TextEditingController(text: widget.baslangic);
  String? _hata;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    try {
      await widget.kaydet(_ctrl.text.trim());
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'CizgiAdiSayfasi.kaydet');
      if (mounted) setState(() => _hata = friendlyError(e));
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final sh = SandikSpace.screenH(context);
    // Kısa ekran (yatay telefon, ~390 pt): alan ile düğme yan yana, açıklama
    // ve sayaç yok — dikey dizilimde düğme ana ekran çubuğunun altında
    // kalıyordu (e2e 2026-10-29). Dik ekranda düzen değişmez.
    final kisa = MediaQuery.sizeOf(context).height < 480;
    final alan = TextField(
      key: const ValueKey('cizgiAdiAlani'),
      controller: _ctrl,
      autofocus: widget.odakla,
      maxLength: kCizgiAdiAzami,
      // Kısa ekranda sayaç satırı yer kaplamasın; sınır yine geçerli.
      buildCounter: kisa
          ? (_, {required currentLength, required isFocused, maxLength}) =>
              null
          : null,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _kaydet(),
      onChanged: (_) {
        if (_hata != null) setState(() => _hata = null);
      },
      style: context.t.bodyLarge?.copyWith(color: c.text90),
      decoration: context.inputDecoration(
        l.cizgiAdiIpucu,
        labelText: l.cizgiAdiEtiket,
        errorText: _hata,
      ),
    );
    final dugme = SandikAsyncButton.kompakt(
      key: const ValueKey('cizgiAdiKaydet'),
      style: FilledButton.styleFrom(
        backgroundColor: c.amberFill,
        foregroundColor: c.onAmber,
        minimumSize: kisa
            ? const Size(0, SandikTouch.min)
            : const Size.fromHeight(SandikTouch.min),
      ),
      onPressed: _kaydet,
      child: Text(widget.dugme),
    );
    // Ana ekran çubuğu / çentik payı (yatayda altta ~21 pt, yanlarda çentik).
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            sh,
            kisa ? SandikSpace.xs : SandikSpace.sm2,
            sh,
            MediaQuery.of(context).viewInsets.bottom +
                (kisa ? SandikSpace.md : SandikSpace.lg)),
        // Büyük yazıda düğme kesilmesin: sığmazsa kaydırılır.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SandikTutamac()),
              SizedBox(height: kisa ? SandikSpace.xs : SandikSpace.sm),
              Text(
                widget.baslik,
                style: (kisa ? context.t.titleLarge : context.t.headlineSmall)
                    ?.copyWith(color: c.text90, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: kisa ? SandikSpace.sm : SandikSpace.md),
              if (kisa)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: alan),
                    const SizedBox(width: SandikSpace.sm),
                    Padding(
                      padding: const EdgeInsets.only(top: SandikSpace.xs),
                      child: dugme,
                    ),
                  ],
                )
              else ...[
                alan,
                Text(l.cizgiAdiAciklama,
                    style: context.t.bodySmall?.copyWith(color: c.text58)),
                const SizedBox(height: SandikSpace.md),
                dugme,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
