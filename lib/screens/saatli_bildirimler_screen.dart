import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import '../widgets/saatli_bildirim.dart';
import '../widgets/sandik_app_bar.dart';

/// Ayarlar › Bildirimler › Saatli bildirimler (0188). Alarmlarım'daki
/// bölümün kendisi: iki yerde iki ayrı liste yazılmasın diye aynı bileşen.
class SaatliBildirimlerScreen extends StatelessWidget {
  const SaatliBildirimlerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sh = SandikSpace.screenH(context);
    return Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(title: context.l10n.saatliBaslik),
      body: ListView(
        padding: EdgeInsets.fromLTRB(sh, SandikSpace.sm, sh, SandikSpace.xl),
        children: const [SaatliBildirimBolumu()],
      ),
    );
  }
}
