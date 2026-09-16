import 'package:flutter/material.dart';
import '../theme/sandik.dart';
import 'friendly_error.dart';

/// Tek snackbar yolu.
///
/// 2026-09 denetiminde 30 çağrı yeri vardı ve her biri rengi, mürekkebi,
/// süreyi ve `behavior`'ı kendi başına seçiyordu: aynı "silinemedi" mesajı
/// bir ekranda kırmızı, ötekinde tema zeminiyle çıkıyordu; beş yer ham `$e`
/// basıyordu (PostgREST tablo/kolon adları kullanıcıya gidiyordu).
///
/// Kurallar:
/// - Renkli zeminde tema `contentTextStyle`'ı (text90) KULLANILMAZ — light
///   modda 3.02:1 verir. Dolgu üstü mürekkep `onStatus` (gain/loss) ve
///   `onAmber` (amber). Bu ayrım `partnership_requests_screen`'de tek tek
///   yazılmıştı; artık burada.
/// - Hata metni için [sandikSnackError] — `friendlyError` zorunlu geçiş.
/// - Yeni snackbar öncekini kapatır (`hideCurrentSnackBar`); kuyruk
///   birikmesin, kullanıcı üç eski mesajı sırayla izlemesin.
enum SandikSnackKind { neutral, success, warning, error }

void sandikSnack(
  BuildContext context,
  String message, {
  SandikSnackKind kind = SandikSnackKind.neutral,
  Duration? duration,
  SnackBarAction? action,

  /// Verilirse "Geri al" eylemi eklenir. Yıkıcı ama geri alınabilir işlemler
  /// (takipten çıkarma, varlık silme) için.
  VoidCallback? onUndo,
}) {
  if (!context.mounted) return;
  final c = context.c;

  Color? background;
  Color? ink;
  switch (kind) {
    case SandikSnackKind.neutral:
      background = null; // tema: surface2 + text90
      ink = null;
      break;
    case SandikSnackKind.success:
      background = c.gain;
      ink = c.onStatus;
      break;
    case SandikSnackKind.warning:
      background = c.amberFill;
      ink = c.onAmber;
      break;
    case SandikSnackKind.error:
      background = c.loss;
      ink = c.onStatus;
      break;
  }

  final resolvedAction = action ??
      (onUndo == null
          ? null
          : SnackBarAction(
              label: 'Geri al',
              textColor: ink ?? c.amberText,
              onPressed: onUndo,
            ));

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: ink == null
            ? null
            : context.t.bodyMedium?.copyWith(
                color: ink,
                fontWeight: FontWeight.w600,
              ),
      ),
      backgroundColor: background,
      // Geri alınabilir eylemde kullanıcıya düşünme payı bırak — ama
      // ekranı da bloke etme.
      //
      // 5 sn'den 4'e çekildi (kullanıcı bildirimi, 2026-09-16): takip
      // listesinde sola kaydırıp silince toast alt menünün üstünde çok uzun
      // duruyordu. Silme kaydırmayla yapılıyor, yani kullanıcı eylemi zaten
      // bilinçli; 5 sn geri alma değil bekleme hissi veriyordu.
      //
      // 4 sn Material'ın kendi varsayılanı ve HIG'in eylem içeren bildirim
      // için verdiği alt sınırın üstünde. Daha kısası (3 sn) eylemli
      // snackbar'da erişilebilirlik sorunudur: ekran okuyucu metni
      // bitirmeden kapanabilir.
      duration: duration ??
          (resolvedAction != null
              ? const Duration(seconds: 4)
              : const Duration(seconds: 3)),
      action: resolvedAction,
    ),
  );
}

/// Hata snackbar'ı. Ham [error] ASLA gösterilmez; `friendlyError` çevirir.
/// [prefix] verilirse "Silinemedi. İnternet bağlantını kontrol et." gibi
/// eylem + sebep biçiminde birleşir.
void sandikSnackError(
  BuildContext context,
  Object? error, {
  String? prefix,
  SnackBarAction? action,
}) {
  final reason = friendlyError(error);
  final text = prefix == null || prefix.isEmpty ? reason : '$prefix. $reason';
  sandikSnack(context, text, kind: SandikSnackKind.error, action: action);
}
