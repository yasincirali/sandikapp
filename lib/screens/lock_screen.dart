import 'package:flutter/material.dart';

import '../services/biometric_lock_service.dart';
import '../theme/sandik.dart';
import '../l10n/l10n.dart';

/// Kilit ekranı — biyometrik kilit açıkken öne dönüşte ve soğuk açılışta.
///
/// İçerik GÖSTERMEZ: arkadaki portföy bu ekranın altında değil, hiç
/// kurulmamış durumda (`_AuthGate` kilit açılana kadar ana ekranı
/// oluşturmaz). Aksi halde uygulama değiştirici karesi ya da bir an için
/// görünen tutar kilidi anlamsız kılardı.
///
/// Açılışta doğrulama KENDİLİĞİNDEN istenir; kullanıcı iptal ederse
/// düğmeyle tekrar dener. Çıkış yolu yok — kilidi kapatmanın yeri Ayarlar
/// ve oraya kilit açılmadan gidilemez; bu bilinçli.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
  }

  Future<void> _tryUnlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await BiometricLockService.instance.authenticate();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
    });
    if (ok) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: c.amberFill.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: c.amberFill.withValues(alpha: 0.35)),
                  ),
                  child: Icon(Icons.lock_outline_rounded,
                      size: 34, color: c.amberText),
                ),
                const SizedBox(height: SandikSpace.lg),
                Text(
                  context.l10n.lockTitle,
                  textAlign: TextAlign.center,
                  style: context.t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.text90,
                  ),
                ),
                const SizedBox(height: SandikSpace.sm),
                Text(
                  _failed
                      ? context.l10n.lockFailed
                      : context.l10n.lockPrompt,
                  textAlign: TextAlign.center,
                  style: context.t.bodyMedium?.copyWith(color: c.text58),
                ),
                const SizedBox(height: SandikSpace.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _tryUnlock,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: Text(_busy ? context.l10n.lockVerifying : context.l10n.unlock),
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
