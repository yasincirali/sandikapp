import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/sandik.dart';

/// Teknik hatayı kullanıcı dostu Türkçe mesaja çevirir.
///
/// UI'da `Text('Hata: $e')` yerine `Text(friendlyError(e))` kullan —
/// SocketException, TimeoutException, AuthApiException gibi düşük seviye
/// mesajları kullanıcıya gösterme.
///
/// `verbose: true` debug için orijinal mesajı parantez içinde ekler.
String friendlyError(Object? error, {bool verbose = false}) {
  if (error == null) return 'Bilinmeyen bir hata oluştu.';

  String message;

  if (error is SocketException ||
      error.toString().contains('SocketException') ||
      error.toString().contains('Failed host lookup')) {
    message = 'İnternet bağlantını kontrol et.';
  } else if (error is TimeoutException ||
      error.toString().contains('TimeoutException')) {
    message = 'Sunucu yanıt vermedi. Bağlantını kontrol edip tekrar dene.';
  } else if (error is HttpException ||
      error.toString().contains('HttpException')) {
    message = 'Sunucuya ulaşılamadı. Lütfen sonra tekrar dene.';
  } else if (error is FormatException) {
    message = 'Sunucudan gelen veri okunamadı.';
  } else if (error is AuthApiException) {
    message = _authMessage(error.message);
  } else if (error is AuthException) {
    message = _authMessage(error.toString());
  } else if (error is PostgrestException) {
    // RLS/permission veya constraint hatası
    if (error.code == '23505') {
      message = 'Bu kayıt zaten var.';
    } else if (error.code == '42501' || error.message.contains('permission')) {
      message = 'Bu işlem için yetkin yok.';
    } else {
      message = 'Veri işlemi başarısız oldu.';
    }
  } else if (error is StorageException) {
    message = 'Dosya işlemi başarısız oldu.';
  } else {
    message = _humanize(error.toString());
  }

  if (verbose) {
    return '$message  (${error.runtimeType})';
  }
  return message;
}

String _authMessage(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('invalid login credentials') ||
      lower.contains('invalid_credentials') ||
      lower.contains('invalid email or password')) {
    return 'E-posta veya şifre hatalı.';
  }
  if (lower.contains('email not confirmed')) {
    return 'E-posta adresini doğrula. Gelen kutunu kontrol et.';
  }
  if (lower.contains('user already registered') ||
      lower.contains('already registered')) {
    return 'Bu e-posta zaten kayıtlı.';
  }
  if (lower.contains('user not found')) {
    return 'Kullanıcı bulunamadı.';
  }
  if (lower.contains('too many requests') || lower.contains('rate limit')) {
    return 'Çok fazla deneme. Lütfen birkaç dakika sonra tekrar dene.';
  }
  if (lower.contains('weak password') || lower.contains('password should')) {
    return 'Şifre çok zayıf. En az 6 karakter kullan.';
  }
  if (lower.contains('jwt expired') || lower.contains('token expired')) {
    return 'Oturumun süresi doldu. Tekrar giriş yap.';
  }
  return 'Giriş işlemi başarısız oldu.';
}

/// Marka renkli hata dialogu.
void showAppError(BuildContext context, Object? error) {
  if (!context.mounted) return;
  showSandikDialog(
    context: context,
    kind: SandikDialogKind.error,
    title: 'Hata',
    message: friendlyError(error),
  );
}

/// Marka renkli başarı dialogu.
Future<void> showAppSuccess(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = 'Tamam',
}) {
  return showSandikDialog(
    context: context,
    kind: SandikDialogKind.success,
    title: title,
    message: message,
    actionLabel: actionLabel,
  );
}

/// Marka renkli bilgi/uyarı dialogu.
Future<void> showAppInfo(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = 'Tamam',
}) {
  return showSandikDialog(
    context: context,
    kind: SandikDialogKind.info,
    title: title,
    message: message,
    actionLabel: actionLabel,
  );
}

enum SandikDialogKind { error, success, info }

/// Sandık marka kimliğine uygun modal dialog.
///
/// - Koyu yüzey (`Sandik.surface1`) + amber/loss/gain kenar highlight
/// - Renkli ikon rozeti + başlık + mesaj + tek buton
/// - Cupertino/Material scaffold ayrımı fark etmeksizin çalışır
/// Her saniye yeniden çağrılarak canlı mesaj üretir. `null` dönerse
/// dialog kendini kapatır (ör. geri sayım bitti).
typedef LiveMessageBuilder = String? Function();

Future<void> showSandikDialog({
  required BuildContext context,
  required SandikDialogKind kind,
  required String title,
  required String message,
  String actionLabel = 'Tamam',
  /// Verilirse [message] yerine kullanılır ve saniyede bir tazelenir —
  /// geri sayım gibi değişen içerikler için. `null` döndüğü an dialog
  /// otomatik kapanır.
  LiveMessageBuilder? liveMessage,
}) {
  if (!context.mounted) return Future.value();
  // Renkler `context`ten okunur: bu dialog light modda da açılıyor ve
  // sabit koyu yüzey + koyu metin okunmaz hale geliyordu.
  final palette = context.c;
  final bool isLight = context.isLight;
  final Color accent;
  final IconData icon;
  switch (kind) {
    case SandikDialogKind.error:
      accent = palette.loss;
      icon = Icons.error_outline_rounded;
      break;
    case SandikDialogKind.success:
      accent = palette.gain;
      icon = Icons.check_circle_outline_rounded;
      break;
    case SandikDialogKind.info:
      accent = palette.amberText;
      icon = Icons.info_outline_rounded;
      break;
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Sandık dialog',
    barrierColor: Colors.black.withValues(alpha: isLight ? 0.32 : 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return Opacity(
        opacity: curved.value,
        child: Transform.scale(
          scale: 0.94 + 0.06 * curved.value,
          child: _SandikDialog(
            accent: accent,
            icon: icon,
            title: title,
            message: message,
            actionLabel: actionLabel,
            liveMessage: liveMessage,
          ),
        ),
      );
    },
  );
}

class _SandikDialog extends StatefulWidget {
  const _SandikDialog({
    required this.accent,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    this.liveMessage,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final LiveMessageBuilder? liveMessage;

  @override
  State<_SandikDialog> createState() => _SandikDialogState();
}

class _SandikDialogState extends State<_SandikDialog> {
  Timer? _ticker;
  late String _message;

  @override
  void initState() {
    super.initState();
    _message = widget.liveMessage?.call() ?? widget.message;
    if (widget.liveMessage != null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final next = widget.liveMessage!();
        if (!mounted) return;
        if (next == null) {
          // Geri sayım bitti — dialogu açık tutmanın anlamı yok.
          _ticker?.cancel();
          Navigator.of(context).maybePop();
          return;
        }
        if (next != _message) setState(() => _message = next);
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Color get accent => widget.accent;
  IconData get icon => widget.icon;
  String get title => widget.title;
  String get message => _message;
  String get actionLabel => widget.actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
            decoration: BoxDecoration(
              color: context.isLight
                  ? context.c.surface2
                  : context.c.surface1,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accent.withValues(alpha: 0.30),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(alpha: context.isLight ? 0.14 : 0.35),
                  blurRadius: 30,
                  spreadRadius: -6,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 40,
                  spreadRadius: -12,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Icon(icon, color: accent, size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.c.text90,
                    letterSpacing: -0.01 * 18,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    height: 1.4,
                    color: context.c.text58,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.45),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        actionLabel,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
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

String _humanize(String raw) {
  final stripped = raw
      .replaceFirst(RegExp(r'^(Exception|Error|_TypeError):\s*'), '')
      .trim();
  if (stripped.isEmpty || stripped.length > 120) {
    return 'Bir şeyler ters gitti, tekrar dene.';
  }
  // Türkçe mesajları (kendi AuthException'larımız) olduğu gibi göster
  if (RegExp(r'[ğüşıöçĞÜŞİÖÇ]').hasMatch(stripped)) return stripped;
  return 'Bir şeyler ters gitti, tekrar dene.';
}
