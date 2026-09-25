// Portföy hedefi giriş sayfası.
//
// Hedef yalnızca gösterimdir: hiçbir hesabı değiştirmez, "Bugün" kartında
// ilerleme çubuğu olur. Hazır tutarlar Türkiye ölçeğinde (250 bin – 2,5 M)
// — ilk hedefi yazmak yerine dokunmak daha kolay; istenirse elle girilir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart';
import '../services/analytics_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

const _hazirHedefler = <int>[250000, 500000, 1000000, 2500000];

Future<void> showHedefSheet(BuildContext context, WidgetRef ref) async {
  final mevcut = ref.read(portfolioGoalProvider);
  final sonuc = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.c.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
    ),
    builder: (ctx) => _HedefSheet(mevcut: mevcut),
  );
  if (sonuc == null) return;
  await ref.read(portfolioGoalProvider.notifier).set(sonuc);
  // Kaç kişinin hedef kullandığı, kartın bu satırı hak edip etmediğini söyler.
  unawaited(AnalyticsService.instance.logGoalSet(amountTRY: sonuc));
}

class _HedefSheet extends StatefulWidget {
  const _HedefSheet({required this.mevcut});
  final int mevcut;

  @override
  State<_HedefSheet> createState() => _HedefSheetState();
}

class _HedefSheetState extends State<_HedefSheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.mevcut > 0 ? fmtNum(widget.mevcut.toDouble(), digits: 0) : '',
  );
  String? _hata;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _kaydet() {
    final v = parseTrNumber(_ctrl.text);
    if (v == null || v <= 0) {
      setState(() => _hata = context.l10n.goalInvalid);
      return;
    }
    Navigator.pop(context, v.round());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SandikSpace.screenH(context),
        SandikSpace.lg,
        SandikSpace.screenH(context),
        MediaQuery.of(context).viewInsets.bottom + SandikSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.goalTitle,
            style: context.t.headlineSmall?.copyWith(
              color: context.c.text90,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            l10n.goalHint,
            style: context.t.bodyMedium?.copyWith(color: context.c.text58),
          ),
          const SizedBox(height: SandikSpace.md),
          Wrap(
            spacing: SandikSpace.sm,
            runSpacing: SandikSpace.sm,
            children: [
              for (final h in _hazirHedefler)
                ActionChip(
                  label: Text(fmtTRYCompact(h.toDouble())),
                  onPressed: () => setState(() {
                    _ctrl.text = fmtNum(h.toDouble(), digits: 0);
                    _hata = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: SandikSpace.md),
          TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            style: TextStyle(color: context.c.text90),
            onSubmitted: (_) => _kaydet(),
            decoration: InputDecoration(
              prefixText: '₺ ',
              hintText: '1.000.000',
              errorText: _hata,
              // Dolgu/çerçeve temadan (`inputDecorationTheme` = `inputFill` kuralı).
            ),
          ),
          const SizedBox(height: SandikSpace.md),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.c.amberFill,
              foregroundColor: context.c.onAmber,
            ),
            onPressed: _kaydet,
            child: Text(l10n.save,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (widget.mevcut > 0)
            TextButton(
              onPressed: () => Navigator.pop(context, 0),
              child: Text(l10n.goalRemove,
                  style: TextStyle(color: context.c.text58)),
            ),
        ],
      ),
    );
  }
}
