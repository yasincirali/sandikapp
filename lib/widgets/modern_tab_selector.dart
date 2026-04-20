import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../theme/sandik.dart';
import 'package:google_fonts/google_fonts.dart';

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
        final availW = constraints.maxWidth - 12; // 6px padding each side
        final tabW = availW / count;
        final pillLeft = 6.0 + _selectedIndex * tabW;

        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: Sandik.surface1,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              // Animated sliding pill
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                left: pillLeft,
                top: 6,
                width: tabW,
                height: 36,
                child: Container(
                  decoration: BoxDecoration(
                    color: Sandik.amber,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Sandik.amber.withValues(alpha: 0.35),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
              // Tab labels (rendered above the pill)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: List.generate(count, (i) {
                      final sel = i == _selectedIndex;
                      return SizedBox(
                        width: tabW,
                        child: GestureDetector(
                          onTap: () => widget.onChanged(_ids[i]),
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 150),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight:
                                    sel ? FontWeight.w600 : FontWeight.w500,
                                color:
                                    sel ? Colors.black87 : Sandik.text36,
                              ),
                              child: Text(_labels[i]),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
