import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/sandik.dart';

/// Bağlantı hatalarında kullanıcıya gösterilen ortak mesaj.
///
/// **Neden VPN'i ayrıca anıyor (kullanıcı bildirimi, 2026-09-22):** VPN
/// açıkken uygulama çalışmıyor. Sebep tek değil ve hiçbiri istemciden
/// kesin olarak ayırt edilemiyor — VPN sağlayıcısının DNS'i Supabase /
/// Yahoo / TEFAS alan adlarını çözemiyor, çıkış düğümü engelli, ya da
/// TLS araya giren bir sertifikayla kesiliyor. İstemcinin gördüğü şey her
/// üçünde de sıradan bir ağ hatası (`SocketException`, `HandshakeException`,
/// `ClientException`, timeout).
///
/// Bu yüzden VPN TESPİT EDİLMEZ, yalnızca İHTİMAL olarak söylenir. Mesaj
/// iki olasılığı birden taşır: kullanıcı VPN kullanmıyorsa cümlenin ilk
/// yarısı ("internet bağlantını kontrol et") zaten doğru cevaptır, VPN
/// kullanıyorsa ikinci yarısı ona denemesi gereken şeyi söyler. Kesin
/// olmayan bir teşhisi kesinmiş gibi yazmak ("VPN'inizi kapatın"), VPN'i
/// olmayan kullanıcıyı yanlış yere bakmaya gönderirdi.
const String kBaglantiHatasiMesaji =
    'Bağlantı kurulamadı. İnternetini kontrol et; '
    'VPN kullanıyorsan kapatıp tekrar dene.';

/// Mesajı KULLANICIYA YAZILMIŞ istisna — `friendlyError` metni olduğu gibi
/// gösterir.
///
/// 2026-09-23 denetimi U13: boş kayıt formunda "Ad soyad girin." yerine
/// "Bir şeyler ters gitti" çıkıyordu. Uygulamanın kendi `AuthException`'ı
/// `_humanize`'a düşüyordu ve orası yalnızca Türkçe HARF (ğüşıöç…) içeren
/// metni geçiriyordu — "Ad soyad girin.", "Kod girin." gibi düz ASCII
/// Türkçe cümleler ve İngilizce arayüzdeki l10n metinleri eleniyordu.
/// Harf sezgisi "bizim cümlemiz mi" sorusunu yanıtlayamaz; bunu TÜR
/// yanıtlar. Bu arayüzü uygulayan sınıf, mesajına ham sunucu/teknik
/// metin koymamayı üstlenir (ör. `AuthService` ham `AuthApiException.message`
/// yerine `friendlyError(e)` sarar). `utils` → `services` bağımlılığı
/// kurmamak için sözleşme burada, uygulayan sınıf serviste.
abstract interface class KullaniciMesajli implements Exception {
  String get message;
}

/// Hata kullanıcının BAĞLANTISINDAN mı kaynaklanıyor?
///
/// Sınıflandırma `CrashReporter.agHatasiMi` ile AYNI aileyi tanır — orası
/// "bunu çökme sayma" kararını, burası "kullanıcıya ne yazalım" kararını
/// verir. İkisi ayrışırsa Crashlytics'in sessizce geçtiği bir hata
/// ekranda ham `Exception` olarak görünürdü.
///
/// `friendly_error` model/servis katmanına bağımlı olmadığı için liste
/// burada tekrar edilir; `baglanti_hatasi_mesaji_test` iki tarafın da
/// aynı imzaları tanıdığını doğrular.
bool baglantiHatasiMi(Object? error) {
  if (error == null) return false;
  if (error is SocketException ||
      error is TimeoutException ||
      error is HttpException ||
      error is HandshakeException) {
    return true;
  }
  final metin = error.toString();
  for (final iz in const [
    'SocketException',
    'TimeoutException',
    'HttpException',
    'HandshakeException',
    'Failed host lookup',
    'ClientException',
    'Connection closed',
    'Connection reset',
    'Connection refused',
    'Connection timed out',
    'Software caused connection abort',
    'Network is unreachable',
    'No route to host',
    // TLS araya girdiğinde (kurumsal/filtreleyen VPN) görünen imzalar.
    'CERTIFICATE_VERIFY_FAILED',
    'certificate verify failed',
    'Connection closed before full header was received',
    'Connection attempt cancelled',
    'Request has been aborted',
  ]) {
    if (metin.contains(iz)) return true;
  }
  return false;
}

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

  // Bağlantı ailesi TEK mesajda birleşti (2026-09-22). Eskiden üç ayrı
  // cümle vardı (host lookup / timeout / http) ve hiçbiri VPN'den söz
  // etmiyordu; VPN açık kullanıcı "İnternet bağlantını kontrol et" okuyup
  // internetinin çalıştığını görünce uygulamanın bozuk olduğunu sanıyordu.
  // Ayrım kullanıcı için anlamlı değildi: üçünde de yapılacak şey aynı.
  if (error is KullaniciMesajli && error.message.trim().isNotEmpty) {
    message = error.message.trim();
  } else if (baglantiHatasiMi(error)) {
    message = kBaglantiHatasiMesaji;
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
    // AuthService.validatePassword ile aynı kural: 8 karakter + harf + rakam.
    return 'Şifre çok zayıf. En az 8 karakter, bir harf ve bir rakam kullan.';
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

/// Onay dialogu — iki eylem, tek görsel dil.
///
/// 2026-09 denetimi: 13 dosyada `AlertDialog`, 5 dosyada
/// `CupertinoAlertDialog`; aynı "varlığı sil" diyaloğu iki ekranda ayrı
/// yazılmıştı, çıkış onayı `siz` derken sepet onayı `sen` diyordu. Bu
/// fonksiyon markanın tek onay yüzeyi: [destructive] true ise vurgu `loss`
/// ve uyarı ikonu, değilse amber soru ikonu. [detail] mesajın altına
/// açıklayıcı bir kutu koyar (ör. "bu bir satış değil" uyarısı).
///
/// `true` = onaylandı; kapatma/vazgeçme `false`.
Future<bool> showSandikConfirm({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Onayla',
  String cancelLabel = 'Vazgeç',
  bool destructive = false,
  Widget? detail,
  bool barrierDismissible = true,
}) async {
  if (!context.mounted) return false;
  final palette = context.c;
  final isLight = context.isLight;
  final accent = destructive ? palette.loss : palette.amberText;
  final icon =
      destructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded;
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Sandık onay',
    barrierColor: _barrierColor(isLight),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return Opacity(
        opacity: curved.value,
        child: Transform.scale(
          scale: 0.94 + 0.06 * curved.value,
          child: _SandikDialogShell(
            accent: accent,
            icon: icon,
            title: title,
            message: message,
            detail: detail,
            actions: [
              _DialogButton(
                label: cancelLabel,
                color: palette.text58,
                filled: false,
                onTap: () => Navigator.of(ctx).pop(false),
              ),
              _DialogButton(
                label: confirmLabel,
                color: accent,
                filled: true,
                onTap: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ),
      );
    },
  );
  return result == true;
}

/// Perde rengi — aydınlıkta hafif, karanlıkta koyu; iki dialog da bunu kullanır.
Color _barrierColor(bool isLight) =>
    Colors.black.withValues(alpha: isLight ? 0.32 : 0.55);

/// Dialog kabuğu — ikon rozeti, başlık, mesaj, isteğe bağlı detay kutusu,
/// eylem satırı. `_SandikDialog` (tek buton, canlı mesaj) ve onay dialogu
/// aynı kabuğu paylaşır.
class _SandikDialogShell extends StatelessWidget {
  const _SandikDialogShell({
    required this.accent,
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
    this.detail,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String message;
  final Widget? detail;
  final List<Widget> actions;

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
              color: context.isLight ? context.c.surface2 : context.c.surface1,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.30)),
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
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Icon(icon, color: accent, size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: context.t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.c.text90,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: context.t.bodyMedium?.copyWith(
                    height: 1.4,
                    color: context.c.text58,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 14),
                  detail!,
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Semantics(
          button: true,
          label: label,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled ? color.withValues(alpha: 0.14) : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: filled ? 0.45 : 0.25),
              ),
            ),
            child: Text(
              label,
              style: context.t.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    barrierColor: _barrierColor(isLight),
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
    // Kabuk onay dialoguyla ORTAK (_SandikDialogShell); burada yalnızca
    // tek eylem ve canlı mesaj var.
    return _SandikDialogShell(
      accent: accent,
      icon: icon,
      title: title,
      message: message,
      actions: [
        _DialogButton(
          label: actionLabel,
          color: accent,
          filled: true,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
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
  // Türkçe harf içeren mesajı geçir — kendi `Exception('…')`larımız için
  // eski sezgi. Uygulamanın AuthException'ı artık [KullaniciMesajli] ile
  // tür üzerinden geçer (U13); bu satır ona güvenmez.
  if (RegExp(r'[ğüşıöçĞÜŞİÖÇ]').hasMatch(stripped)) return stripped;
  return 'Bir şeyler ters gitti, tekrar dene.';
}
