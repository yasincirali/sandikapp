import 'dart:io' show exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/magaza.dart';
import '../l10n/l10n.dart';
import '../services/sunucu_secimi.dart';
import '../theme/sandik.dart';

/// Köprü sürümünün iki kapısı — uygulamanın ÖNÜNE geçer (K1).
///
/// 1. **Güncelleme gerekli** (`min_build_*` > bu build): geçiş gecesi eski
///    sürümler Tokyo'ya kilitli kalmasın diye. Önceliklidir — güncellenmemiş
///    bir istemcinin sunucu değiştirmesi zaten mümkün değil.
/// 2. **Yeniden başlat** (Remote Config başka sunucu söylüyor): Supabase
///    çalışırken yeniden kurulmaz (singleton servisler istemciyi tutar);
///    kullanıcı kapatıp açar, açılışta yeni sunucu seçilir.
///
/// Kapı aktifken alttaki uygulama çizilmez: yarım kalmış bir ekranda
/// kullanıcı Tokyo'ya (dondurulmuş) yazmaya çalışıp hata görmesin.
class SunucuKapisi extends StatelessWidget {
  const SunucuKapisi({super.key, required this.child});

  final Widget child;

  /// Android "Uygulamayı kapat": İŞLEMİ bitirir. `SystemNavigator.pop()`
  /// yalnız aktiviteyi kapatıyor, Dart tarafını öldürmeyebiliyordu —
  /// 2026-09-27 emülatör denemesinde yeniden açılışta AYNI kapı ve AYNI
  /// eski sunucu geri geldi (bir önceki denemede gelmemişti: tutarsız).
  /// Kapının tek işi temiz yeniden başlatmayı garanti etmek; `exit(0)`
  /// sonraki açılışı soğuk başlangıç yapar. Yalnız Android: iOS'ta uygulama
  /// kendini kapatmaz (App Store yönergesi), kullanıcı kaydırıp kapatır.
  /// Testte değiştirilir.
  @visibleForTesting
  static void Function() kapat = () => exit(0);

  @override
  Widget build(BuildContext context) {
    final secim = SunucuSecimi.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: secim.guncellemeGerekli,
      builder: (context, guncelle, _) {
        if (guncelle) return const _GuncellemeGerekli();
        return ValueListenableBuilder<bool>(
          valueListenable: secim.yenidenBaslatGerekli,
          builder: (context, yeniden, _) =>
              yeniden ? const _YenidenBaslat() : child,
        );
      },
    );
  }
}

class _GuncellemeGerekli extends StatelessWidget {
  const _GuncellemeGerekli();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    return _KapiIskeleti(
      ikon: Icons.system_update_rounded,
      baslik: l.forceUpdateTitle,
      mesaj: l.forceUpdateBody,
      dugme: l.forceUpdateButton,
      onDugme: () => launchUrl(
        Uri.parse(ios ? Magaza.appStoreUrl : Magaza.playUrl),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}

class _YenidenBaslat extends StatelessWidget {
  const _YenidenBaslat();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // iOS'ta uygulama kendini kapatmaz (App Store yönergesi) — yalnız anlatılır.
    final android = defaultTargetPlatform == TargetPlatform.android;
    return _KapiIskeleti(
      ikon: Icons.cloud_sync_rounded,
      baslik: l.serverMovedTitle,
      mesaj: android ? l.serverMovedBodyAndroid : l.serverMovedBodyIos,
      dugme: android ? l.serverMovedCloseButton : null,
      onDugme: android ? () => SunucuKapisi.kapat() : null,
    );
  }
}

class _KapiIskeleti extends StatelessWidget {
  const _KapiIskeleti({
    required this.ikon,
    required this.baslik,
    required this.mesaj,
    this.dugme,
    this.onDugme,
  });

  final IconData ikon;
  final String baslik;
  final String mesaj;
  final String? dugme;
  final VoidCallback? onDugme;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SandikSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(ikon, size: 56, color: c.amberText),
                const SizedBox(height: SandikSpace.lg),
                Text(baslik,
                    textAlign: TextAlign.center,
                    style: t.headlineSmall?.copyWith(color: c.text90)),
                const SizedBox(height: SandikSpace.smd),
                Text(mesaj,
                    textAlign: TextAlign.center,
                    style: t.bodyLarge?.copyWith(color: c.text58)),
                if (dugme != null) ...[
                  const SizedBox(height: SandikSpace.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: onDugme, child: Text(dugme!)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
