import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/disa_aktarim/disa_aktarim_service.dart';
import '../theme/sandik.dart';

/// "PDF mi Excel mi" sorusu (Premium dışa aktarım, 2026-10-10). Ayarlar'daki
/// iki seçenekli sayfalarla (brifing saati) aynı kalıp: başlık + iki satır.
/// Vazgeçilirse `null`.
Future<DisaAktarimBicimi?> disaAktarimBicimiSor(BuildContext context) {
  final l = context.l10n;
  return showSandikSheet<DisaAktarimBicimi>(
    context: context,
    backgroundColor: context.c.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SandikSpace.lg, SandikSpace.lg, SandikSpace.lg, SandikSpace.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l.dsBicimBaslik,
                style: ctx.t.titleMedium?.copyWith(
                    color: ctx.c.text90, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          for (final (bicim, ikon, etiket, alt) in [
            (
              DisaAktarimBicimi.pdf,
              Icons.picture_as_pdf_rounded,
              l.dsPdf,
              l.dsPdfAlt
            ),
            (
              DisaAktarimBicimi.excel,
              Icons.table_chart_rounded,
              l.dsExcel,
              l.dsExcelAlt
            ),
          ])
            ListTile(
              leading: Icon(ikon, color: ctx.c.amberText),
              title: Text(etiket,
                  style: ctx.t.bodyLarge?.copyWith(color: ctx.c.text90)),
              subtitle: Text(alt,
                  style: ctx.t.bodySmall?.copyWith(color: ctx.c.text58)),
              onTap: () => Navigator.pop(ctx, bicim),
            ),
          const SizedBox(height: SandikSpace.sm),
        ],
      ),
    ),
  );
}
