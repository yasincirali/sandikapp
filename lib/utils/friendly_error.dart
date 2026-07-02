import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Hata mesajını SnackBar olarak gösterir. Tüm ekranlarda standart pattern.
void showAppError(BuildContext context, Object? error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(friendlyError(error)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A1A1A),
      ),
    );
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
