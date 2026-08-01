import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Colors,
        Icons;
import 'package:google_fonts/google_fonts.dart';
import '../services/disclaimer_service.dart';
import '../theme/sandik.dart';
import '../widgets/custom_loading_indicator.dart';

/// Varolan kullanıcılar için splash sonrası disclaimer onay ekranı.
/// Geri butonu yok — onaylanmadan uygulama kullanılamaz.
class DisclaimerAcceptanceScreen extends StatefulWidget {
  final String userId;
  final VoidCallback onAccepted;

  const DisclaimerAcceptanceScreen({
    super.key,
    required this.userId,
    required this.onAccepted,
  });

  @override
  State<DisclaimerAcceptanceScreen> createState() =>
      _DisclaimerAcceptanceScreenState();
}

class _DisclaimerAcceptanceScreenState
    extends State<DisclaimerAcceptanceScreen> {
  bool _accepted = false;
  bool _loading = false;
  bool _showError = false;

  Future<void> _confirm() async {
    if (!_accepted || _loading) return;
    setState(() => _loading = true);
    try {
      await DisclaimerService.instance.recordAcceptance(
        userId: widget.userId,
        appVersion: '1.0.0+1',
        platform: Platform.isIOS ? 'ios' : 'android',
        locale: 'tr_TR',
      );
    } catch (_) {
      // Kayıt hatası olsa bile onayı kabul et — kayıt kritik değil
    }
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onAccepted());
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: GoogleFonts.dmSans(decoration: TextDecoration.none),
      child: CupertinoPageScaffold(
        backgroundColor: Sandik.background,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            children: [
              // Başlık
              Row(
                children: [
                  const Icon(Icons.gavel_rounded, size: 22, color: Sandik.amber),
                  const SizedBox(width: 10),
                  Text(
                    'Yasal Uyarı',
                    style: context.t.headlineMedium?.copyWith(
                      color: Sandik.amber,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'v$disclaimerVersion',
                    style: context.t.bodySmall?.copyWith(
                      color: Sandik.text36,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Uygulamayı kullanmaya devam etmek için lütfen aşağıdaki yasal uyarıyı okuyun ve onaylayın.',
                style: context.t.bodyMedium?.copyWith(
                  color: Sandik.text58,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // Disclaimer kutusu
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  disclaimerText,
                  style: context.t.titleSmall?.copyWith(
                    color: Sandik.text58,
                    height: 1.7,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Onay checkbox
              GestureDetector(
                onTap: () => setState(() {
                  _accepted = !_accepted;
                  if (_accepted) _showError = false;
                }),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _showError
                        ? Sandik.loss.withValues(alpha: 0.07)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    border: Border.all(
                      color: _showError
                          ? Sandik.loss.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _accepted
                              ? Sandik.amber
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(SandikRadius.sm),
                          border: Border.all(
                            color: _accepted
                                ? Sandik.amber
                                : (_showError ? Sandik.loss : Sandik.text36),
                            width: 2,
                          ),
                        ),
                        child: _accepted
                            ? const Icon(Icons.check_rounded,
                                size: 14, color: Sandik.dark)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Yukarıdaki yasal uyarıyı okudum ve kabul ediyorum.',
                          style: context.t.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: _showError ? Sandik.loss : Sandik.text90,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showError) ...[
                const SizedBox(height: 8),
                Text(
                  'Devam etmek için yasal uyarıyı kabul etmelisiniz.',
                  style: context.t.bodySmall?.copyWith(color: Sandik.loss),
                ),
              ],
              const SizedBox(height: 28),

              // Onayla butonu
              CupertinoButton(
                onPressed: (_loading || !_accepted) ? null : _confirm,
                padding: EdgeInsets.zero,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: (_loading || !_accepted)
                        ? Sandik.amber.withValues(alpha: 0.45)
                        : Sandik.amber.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    border: Border.all(
                        color: Sandik.amber.withValues(alpha: 0.60)),
                    boxShadow: [
                      BoxShadow(
                        color: Sandik.amber.withValues(alpha: 0.28),
                        blurRadius: 18,
                        spreadRadius: -4,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: _loading
                      ? const CustomLoadingIndicator(size: 20)
                      : Text(
                          'Kabul Ediyorum',
                          style: context.t.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Sandik.dark,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
