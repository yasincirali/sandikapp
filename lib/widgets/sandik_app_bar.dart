import 'package:flutter/material.dart';
import '../theme/sandik.dart';

/// Tek üst çubuk.
///
/// 2026-09 denetimi: 14 ekranda `AppBar(` ayrı ayrı kurulmuştu — zemin
/// (`background` / `transparent` / `surface2`), başlık stili (headlineSmall /
/// headlineMedium / TextStyle), geri ikonu (5 kopya `arrow_back_ios_new_rounded`
/// 20pt) ve `elevation: 0` her seferinde yeniden yazılıyordu. Bir tema
/// değişikliği 14 yere dokunmayı gerektiriyordu.
///
/// Kurallar:
/// - Zemin ekran zemini (`context.c.background`); [transparent] yalnızca
///   gövdesi kendi zeminini çizen ekranlar için.
/// - Başlık `headlineSmall` + w700, tek satır, taşarsa üç nokta (varlık adı
///   kullanıcı girdisidir ve uzun olabilir).
/// - Geri: iOS tarzı ince ok, 20pt, `text90`; yalnızca pop edilebiliyorsa.
class SandikAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SandikAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.showBack = true,
    this.onBack,
    this.transparent = false,
    this.backgroundColor,
    this.bottom,
  }) : assert(title == null || titleWidget == null);

  final String? title;

  /// Başlık metin değilse (ikon + metin gibi).
  final Widget? titleWidget;
  final List<Widget>? actions;

  /// false: geri oku hiç çizilmez (sekme kökü gibi).
  final bool showBack;

  /// Verilmezse `Navigator.pop`. Form gönderilirken kilitlemek için
  /// `null` döndüren bir sarmalayıcı yerine [onBack] içinde koşul kur.
  final VoidCallback? onBack;
  final bool transparent;
  final Color? backgroundColor;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    return AppBar(
      backgroundColor: transparent
          ? const Color(0x00000000)
          : (backgroundColor ?? context.c.background),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: const Color(0x00000000),
      automaticallyImplyLeading: false,
      leading: canPop
          ? IconButton(
              tooltip: 'Geri',
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20, color: context.c.text90),
              onPressed: onBack ?? () => Navigator.of(context).pop(),
            )
          : null,
      title: titleWidget ??
          (title == null
              ? null
              : Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.c.text90,
                  ),
                )),
      actions: actions,
      bottom: bottom,
    );
  }
}
