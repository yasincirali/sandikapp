import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../theme/sandik.dart';

class ModernTabSelector extends StatefulWidget {
  final List<AppUser> partners;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const ModernTabSelector({
    super.key,
    required this.partners,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  State<ModernTabSelector> createState() => _ModernTabSelectorState();
}

class _ModernTabSelectorState extends State<ModernTabSelector> {
  List<String?> get _ids => [null, '', ...widget.partners.map((p) => p.id)];

  List<String> get _labels => [
        'Birlikte',
        'Ben',
        ...widget.partners.map((p) => p.displayName.split(' ')[0]),
      ];

  int get _selectedIndex {
    final i = _ids.indexOf(widget.selectedId);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final count = _ids.length;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final totalW = constraints.maxWidth;
        final tabW = totalW / count;
        final pillLeft = _selectedIndex * tabW;

        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: context.c.overlay,
              width: 1.0,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Sliding pill
              AnimatedPositioned(
                duration: SandikMotion.of(context, const Duration(milliseconds: 220)),
                curve: Curves.easeInOutCubic,
                left: pillLeft + 4,
                top: 4,
                width: tabW - 8,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.c.amberFill,
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    boxShadow: [
                      BoxShadow(
                        color: context.c.amberFill.withValues(alpha: 0.40),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                ),
              ),
              // Tab labels
              Positioned.fill(
                child: Row(
                  children: List.generate(count, (i) {
                    final sel = i == _selectedIndex;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onChanged(_ids[i]),
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: SandikMotion.stateOf(context),
                            curve: SandikMotion.enter,
                            style: context.t.bodyMedium!.copyWith(
                              fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                              color: sel ? context.c.onAmber : context.c.text36,
                            ),
                            child: Text(_labels[i]),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
