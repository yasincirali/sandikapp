import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../providers/ozellik_onerisi_provider.dart';
import '../providers/preferences_provider.dart';
import '../screens/add_watchlist_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../screens/price_alerts_screen.dart';
import '../screens/siralama_screen.dart';
import '../services/analytics_service.dart';
import '../services/ozellik_onerisi.dart';
import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import 'sandik_skeleton.dart';

/// Ana ekran (Bugün kartının altı) ve Portföy sekmesi (listenin üstü):
/// kullanılmayan bir özelliğe götüren tek kart (`ozellik_onerisi.dart`;
/// yasin isteği 2026-10-20). İki yer aynı sağlayıcıyı okur; birinde
/// kapatmak ikisinden de kaldırır.
///
/// "Bilgi eksik" satırıyla ([VeriKalitesiSeridi]) aynı kalıp: SandikCard,
/// ikon + iki satır + kapat. Dokununca özelliğin ekranı açılır; dokunmak da
/// kapatmak da öneriyi kalıcı olarak düşürür ve sıradakini [bekleme] kadar
/// erteler. Bayraksız: mevcut ekranlara yönlendiren ek, söyleyecek bir şey
/// yoksa yer kaplamaz.
class OzellikOnerisiKarti extends ConsumerWidget {
  const OzellikOnerisiKarti({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SandikBelirme(child: _govde(context, ref));

  Widget _govde(BuildContext context, WidgetRef ref) {
    final oneri = ref.watch(ozellikOnerisiProvider);
    if (oneri == null) return const SizedBox.shrink();
    final c = context.c;
    final t = context.t;
    final l = context.l10n;
    final (ikon, baslik, alt) = switch (oneri) {
      OzellikOnerisi.alarm => (
          Icons.notifications_active_outlined,
          l.onerAlarmBaslik,
          l.onerAlarmAlt
        ),
      OzellikOnerisi.takip => (
          Icons.bookmark_add_outlined,
          l.onerTakipBaslik,
          l.onerTakipAlt
        ),
      OzellikOnerisi.ortak => (
          Icons.group_add_outlined,
          l.onerOrtakBaslik,
          l.onerOrtakAlt
        ),
      OzellikOnerisi.zirve => (
          Icons.emoji_events_outlined,
          l.onerZirveBaslik,
          l.onerZirveAlt
        ),
    };
    return Padding(
      padding: padding,
      child: SandikCard(
        padding: const EdgeInsets.only(
            left: SandikSpace.md, top: SandikSpace.xs, bottom: SandikSpace.xs),
        onTap: () => _ac(context, ref, oneri),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Row(
            children: [
              Icon(ikon, color: c.amberText, size: SandikSpace.lgs),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        baslik,
                        style: t.bodyMedium?.copyWith(
                            color: c.text90, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        alt,
                        style: t.bodySmall?.copyWith(color: c.text58),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: l.onerKapat,
                icon: Icon(Icons.close_rounded, size: 18, color: c.text36),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: SandikTouch.min, minHeight: SandikTouch.min),
                onPressed: () {
                  SandikHaptic.selection.perform();
                  _dusur(ref, oneri);
                  AnalyticsService.instance
                      .logOzellikOnerisi(oneri: oneri.anahtar, eylem: 'kapat');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Öneriyi kalıcı düşürür ve sıradakini erteler (kapat da dokun da).
  static void _dusur(WidgetRef ref, OzellikOnerisi oneri) {
    ref
        .read(ozellikOnerisiKapatilanProvider.notifier)
        .set({...ref.read(ozellikOnerisiKapatilanProvider), oneri.anahtar});
    ref
        .read(ozellikOnerisiSonKapatmaProvider.notifier)
        .set(DateTime.now().millisecondsSinceEpoch);
  }

  static void _ac(BuildContext context, WidgetRef ref, OzellikOnerisi oneri) {
    AnalyticsService.instance
        .logOzellikOnerisi(oneri: oneri.anahtar, eylem: 'ac');
    // Demo: hepsi yazma gerektiren akışlar; demo kapısı kendi açıklamasını
    // gösterir, öneri düşmez (gerçek hesapta yine görünsün).
    if (DemoModu.yazmaKapisi('ozellik_onerisi')) return;
    _dusur(ref, oneri);
    switch (oneri) {
      case OzellikOnerisi.alarm:
        pushGuarded(
          context,
          adaptiveRoute<void>(
            settings: const RouteSettings(name: 'price_alerts'),
            builder: (_) => const PriceAlertsScreen(),
          ),
        );
      case OzellikOnerisi.takip:
        pushGuarded(
          context,
          adaptiveRoute<void>(
            settings: const RouteSettings(name: 'add_watchlist'),
            builder: (_) => const AddWatchlistScreen(),
            fullscreenDialog: true,
          ),
        );
      case OzellikOnerisi.ortak:
        // Ortak daveti Profil'de (davet kodu kartı); yeni ekran değil, sekme.
        MainNavigationScreen.sekmeIstegi.value =
            MainNavigationScreen.profilSekmesi;
      case OzellikOnerisi.zirve:
        pushGuarded(
          context,
          adaptiveRoute<void>(
            settings: const RouteSettings(name: 'zirve_giris_ekrani'),
            builder: (_) => zirveGirisEkrani(ZirveDonem.ay),
          ),
        );
    }
  }
}
