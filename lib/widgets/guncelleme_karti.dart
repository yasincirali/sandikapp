import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/magaza.dart';
import '../l10n/l10n.dart';
import '../providers/gunler_provider.dart';
import '../providers/preferences_provider.dart';
import '../theme/sandik.dart';
import 'sandik_skeleton.dart';

/// Ana sayfa yumuşak güncelleme kartı (2026-10-23, Ar-Ge): "Yeni sürüm
/// hazır". Console'da `onerilen_build_*` bu build'in üstündeyse görünür
/// ([yumusakGuncellemeGorunur]); zorunlu kapıdan farklı olarak hiçbir şeyi
/// kilitlemez.
///
/// Neden: düzeltme mağazaya çıktığında eski sürümdeki kullanıcı haftalarca
/// aynı hatayı görüp puan veriyordu; mağazanın kendi otomatik güncellemesi
/// her telefonda açık değil.
///
/// Metin GENEL ("son düzeltmeler ve yenilikler"): sürüm notları uygulamanın
/// içinde yaşar, eski build yeni sürümün başlığını bilemez; bilmediği şeyi
/// yazmaz. Yuva ana sayfa dürtüsüyle paylaşılır ([anaSayfaDurtusuProvider];
/// sıra bilgi eksik > takvim > güncelleme > öneri). Kapatmak o önerilen
/// build'i bir daha sormaz.
class GuncellemeKarti extends ConsumerWidget {
  const GuncellemeKarti({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SandikBelirme(child: _govde(context, ref));

  Widget _govde(BuildContext context, WidgetRef ref) {
    if (ref.watch(anaSayfaDurtusuProvider) != AnaSayfaDurtusu.guncelleme) {
      return const SizedBox.shrink();
    }
    final c = context.c;
    final t = context.t;
    final l = context.l10n;
    return Padding(
      padding: padding,
      child: SandikCard(
        padding: const EdgeInsets.only(
            left: SandikSpace.md, top: SandikSpace.xs, bottom: SandikSpace.xs),
        onTap: _magazayiAc,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Row(
            children: [
              Icon(Icons.system_update_rounded,
                  color: c.amberText, size: SandikSpace.lgs),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.softUpdateTitle,
                        style: t.bodyMedium?.copyWith(
                            color: c.text90, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        l.softUpdateBody,
                        style: t.bodySmall?.copyWith(color: c.text58),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: l.softUpdateDismiss,
                icon: Icon(Icons.close_rounded, size: 18, color: c.text36),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: SandikTouch.min, minHeight: SandikTouch.min),
                onPressed: () {
                  SandikHaptic.selection.perform();
                  ref
                      .read(guncellemeKapatilanBuildProvider.notifier)
                      .set(ref.read(onerilenBuildProvider));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mağaza sayfası — zorunlu kapıyla aynı adres (`Magaza`). Kart açık
  /// kalır: kullanıcı mağazadan dönüp güncellemediyse yine görür.
  static void _magazayiAc() {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    launchUrl(
      Uri.parse(ios ? Magaza.appStoreUrl : Magaza.playUrl),
      mode: LaunchMode.externalApplication,
    );
  }
}

