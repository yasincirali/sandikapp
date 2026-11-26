import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

import '../l10n/l10n.dart';
import '../theme/sandik.dart';

/// Varlık arama alanı — takibe alma ekranı ve saatli bildirimin "Varlık
/// seç" sayfası AYNI alanı çizer (2026-11-26, yasin: "uygulama
/// standartlarına ve tasarım diline uygun olmalı"). Eskiden seçici
/// Material `TextField` kullanıyordu: dolgu, ikon boyu ve silme düğmesi
/// arama ekranındakinden farklıydı; aynı iş iki ayrı alan gibi görünüyordu.
///
/// Yatay pay çağıranda: arama ekranında alanın sağında "Vazgeç" durur,
/// sayfada alan iki kenardan `SandikSpace.screenH` içeride.
class SandikAramaAlani extends StatelessWidget {
  const SandikAramaAlani({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.placeholder,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => CupertinoTextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: autofocus,
        autocorrect: false,
        textInputAction: TextInputAction.search,
        placeholder: placeholder,
        placeholderStyle:
            context.t.bodyMedium?.copyWith(color: context.c.text36),
        style: context.t.bodyMedium?.copyWith(color: context.c.text90),
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.smd, vertical: SandikSpace.smd),
        // Cupertino'nun hazır silme düğmesi (gri dolu daire,
        // `systemGrey`) sandık paletine yabancı kalıyordu — koyu
        // zeminde açık gri bir yumru. Kendi düğmemiz: 20pt
        // saydam-beyaz daire, 12pt çarpı, 44pt dokunma alanı.
        // `controller.clear()` onChanged tetiklemez; sorgu elle
        // sıfırlanır ki sonuçlar ve "son bakılanlar" geri gelsin.
        suffixMode: OverlayVisibilityMode.editing,
        suffix: SandikTappable(
          semanticLabel: context.l10n.clearSearch,
          onTap: () {
            controller.clear();
            onChanged('');
          },
          child: Container(
            width: SandikTouch.min,
            height: SandikTouch.min,
            alignment: Alignment.center,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: context.c.text36.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close_rounded,
                  size: 12, color: context.c.text90),
            ),
          ),
        ),
        prefix: Padding(
          padding: const EdgeInsets.only(left: SandikSpace.sm2),
          child:
              Icon(Icons.search_rounded, size: 18, color: context.c.text58),
        ),
        decoration: BoxDecoration(
          // Seçici alt sayfasıyla aynı dolgu (tema `inputFill`).
          color: context.inputFill,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: context.c.hairline),
        ),
      );
}
