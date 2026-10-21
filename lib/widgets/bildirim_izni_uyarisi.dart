import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/bildirim_izni.dart';
import '../theme/sandik.dart';
import 'sandik_skeleton.dart' show SandikBelirme;

/// "Bildirimler kapalı" satırı: alarm/sinyal yüzeylerinde, izin
/// reddedilmişken (Ar-Ge 16:45 #1, 2026-10-21; gerekçe `BildirimIzni`).
///
/// Kapatılamaz: bir tercih değil, alarmın çalmayacağı GERÇEĞİ. İzin
/// açılınca kendiliğinden kalkar; Ayarlar'dan dönüş öne dönüş olayıdır,
/// durum orada yeniden okunur. Alarm kaydını engellemez, yalnız söyler.
class BildirimIzniUyarisi extends StatefulWidget {
  const BildirimIzniUyarisi({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  State<BildirimIzniUyarisi> createState() => _BildirimIzniUyarisiState();
}

class _BildirimIzniUyarisiState extends State<BildirimIzniUyarisi>
    with WidgetsBindingObserver {
  bool _kapali = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _oku();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _oku();
  }

  Future<void> _oku() async {
    final k = await BildirimIzni.reddedildi();
    if (mounted && k != _kapali) setState(() => _kapali = k);
  }

  @override
  Widget build(BuildContext context) =>
      SandikBelirme(child: _kapali ? _govde(context) : const SizedBox.shrink());

  Widget _govde(BuildContext context) {
    final c = context.c;
    final t = context.t;
    final l = context.l10n;
    return Padding(
      padding: widget.padding,
      child: SandikCard(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.md, SandikSpace.sm, SandikSpace.md, SandikSpace.xs),
        // Düğme metnin ALTINDA: yan yana dururken 320 pt'de büyük yazıda
        // (1.6× ve üstü) satır taşıyordu (`alarm_widgets_overflow_test`).
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Renk tek başına anlam taşımaz: ikon + cümle de "kapalı" der.
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.xs2),
              child: Icon(Icons.notifications_off_outlined,
                  color: c.amberText, size: SandikSpace.lgs),
            ),
            const SizedBox(width: SandikSpace.smd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.biKapaliBaslik,
                    style: t.bodyMedium?.copyWith(
                        color: c.text90, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    l.biKapaliAlt,
                    style: t.bodySmall?.copyWith(color: c.text58),
                  ),
                  Semantics(
                    button: true,
                    label: l.biAyarlariAcSemantics,
                    excludeSemantics: true,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: c.amberText,
                        minimumSize: SandikTouch.minSize,
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: () {
                        SandikHaptic.selection.perform();
                        BildirimIzni.ayarlariAc();
                      },
                      child: Text(l.biAyarlariAc),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
