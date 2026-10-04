import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/social_auth_service.dart';
import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'custom_loading_indicator.dart';

/// Giriş ve kayıt ekranlarının altındaki "Apple / Google ile devam et" bloğu.
///
/// Tek yerde durur ki iki ekran ayrışmasın. Hangi düğmelerin çizileceğini
/// [SocialAuthService.availableProviders] söyler: Apple yalnızca iOS'ta,
/// Google yalnızca derlemeye istemci kimliği verildiyse. İkisi de yoksa
/// widget hiç yer kaplamaz — ayırıcı çizgi de çizilmez.
class SocialSignInButtons extends ConsumerStatefulWidget {
  /// Test için platform zorlaması; üretimde null (gerçek platform).
  final TargetPlatform? platformOverride;
  final bool? googleConfiguredOverride;

  /// Formun ÜSTÜNDE mi (sadeleştirme 2, bayrak `karsilama_tanitimi`)?
  /// Apple/Google e-posta kodu istemeyen en kısa yol; değerlendirme "en
  /// üste al" dedi. Üstteyken ayırıcı düğmelerin ALTINA iner ve "veya
  /// e-postayla" der; alttayken eski düzen (ayırıcı üstte, "veya").
  final bool ustte;

  const SocialSignInButtons({
    super.key,
    this.platformOverride,
    this.googleConfiguredOverride,
    this.ustte = false,
  });

  @override
  ConsumerState<SocialSignInButtons> createState() => _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends ConsumerState<SocialSignInButtons> {
  SocialProvider? _busy;

  List<SocialProvider> get _providers => widget.googleConfiguredOverride == null
      ? SocialAuthService.availableProviders(platform: widget.platformOverride)
      : SocialAuthService.availableProviders(
          platform: widget.platformOverride,
          googleConfigured: widget.googleConfiguredOverride!,
        );

  Future<void> _tap(SocialProvider p) async {
    if (_busy != null) return;
    setState(() => _busy = p);
    await ref.read(authProvider.notifier).loginWithSocial(p);
    if (!mounted) return;
    setState(() => _busy = null);
    final st = ref.read(authProvider);
    if (st.hasError) showAppError(context, st.error);
    // Başarıda AuthGate (lib/main.dart) yönlendirir — burada push yok.
  }

  @override
  Widget build(BuildContext context) {
    final providers = _providers;
    if (providers.isEmpty) return const SizedBox.shrink();
    final ayirici = Row(
      children: [
        Expanded(child: Container(height: 1, color: context.c.hairline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
          child: Text(widget.ustte ? context.l10n.orWithEmail : 'veya',
              style: context.t.bodySmall?.copyWith(color: context.c.text36)),
        ),
        Expanded(child: Container(height: 1, color: context.c.hairline)),
      ],
    );
    final dugmeler = [
      for (final p in providers) ...[
        _SocialButton(
          provider: p,
          busy: _busy == p,
          enabled: _busy == null,
          onTap: () => _tap(p),
        ),
        const SizedBox(height: SandikSpace.sm2),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.ustte
          ? [
              ...dugmeler,
              const SizedBox(height: SandikSpace.sm),
              ayirici,
              const SizedBox(height: SandikSpace.lg),
            ]
          : [
              ayirici,
              const SizedBox(height: SandikSpace.md),
              ...dugmeler,
            ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final SocialProvider provider;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  const _SocialButton({
    required this.provider,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (provider) {
      SocialProvider.apple => 'Apple ile devam et',
      SocialProvider.google => 'Google ile devam et',
    };
    final icon = switch (provider) {
      SocialProvider.apple => Icons.apple,
      SocialProvider.google => Icons.g_mobiledata_rounded,
    };
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          opacity: enabled || busy ? 1 : 0.5,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: context.c.surface2,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              border: Border.all(color: context.c.hairline),
            ),
            alignment: Alignment.center,
            child: busy
                ? const CustomLoadingIndicator(size: 20)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 22, color: context.c.text90),
                      const SizedBox(width: SandikSpace.sm),
                      Text(
                        label,
                        style: context.t.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.c.text90,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
