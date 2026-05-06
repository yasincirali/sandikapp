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
        final totalW = constraints.maxWidth;
        final tabW = totalW / count;
        final pillLeft = _selectedIndex * tabW;

        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1.0,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Sliding pill
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                left: pillLeft + 4,
                top: 4,
                width: tabW - 8,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: Sandik.amber,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Sandik.amber.withValues(alpha: 0.40),
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
                            duration: const Duration(milliseconds: 150),
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                              color: sel ? Colors.black87 : Sandik.text36,
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
