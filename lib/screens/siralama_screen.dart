import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../services/remote_config_service.dart';
import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_segment.dart';
import 'leaderboard_screen.dart';
import 'zirve_portfoyler_screen.dart';

/// Sıralama sayfasının sekmeleri.
enum SiralamaSekmesi {
  /// Yarış'ın ortak sıralaması (ortak yoksa kendi getirin + ortak daveti).
  ortaklarim,

  /// Zirvedeki Portföyler — küresel, anonim, açık rızalı havuz.
  herkes,
}

/// Yarış girişlerinin (Performans kupası, Profil kartı) açtığı ekran.
///
/// Karar TEK yerde (sadeleştirme madde 8, 2026-10-04): bayrak
/// `siralama_tek_sayfa` açıksa Sıralama › Ortaklarım, kapalıysa eski
/// `LeaderboardScreen` birebir. Bayrak dokunma anında okunur; giriş
/// noktaları kendi koşulunu yazmaz.
Widget yarisGirisEkrani() => RemoteConfigService.instance.siralamaTekSayfa
    ? const SiralamaScreen()
    : const LeaderboardScreen();

/// Zirve kartının açtığı ekran: bayrak açıksa Sıralama › Herkes, kapalıysa
/// eski `ZirvePortfoylerScreen`. İki yolda da açılış dönemi kartın
/// (Performans seçicisinden eşlenen) dönemi.
Widget zirveGirisEkrani(ZirveDonem donem) =>
    RemoteConfigService.instance.siralamaTekSayfa
        ? SiralamaScreen(sekme: SiralamaSekmesi.herkes, donem: donem)
        : ZirvePortfoylerScreen(baslangic: donem);

/// Yarış + Zirve tek "Sıralama" sayfası (sadeleştirme listesi madde 8,
/// bayrak `siralama_tek_sayfa`, varsayılan KAPALI).
///
/// ## Neden
/// Sıralama kavramı üç yere dağılmıştı: Yarış ekranı (Performans kupası,
/// Profil kartı), Zirvedeki Portföyler (Performans grafiğinin altı) ve
/// yüzdelik şeridi. Kullanıcı "kim önde?" sorusunu iki ayrı ekranda,
/// iki ayrı dönem seçicisiyle arıyordu. Tek sayfa, iki sekme: "Ortaklarım"
/// (tanıdıklarla yarış) ve "Zirvedekiler" (anonim havuz; kullanıcı 2026-10-04
/// "Herkes" yerine bu adı istedi — sekme kimlerin olduğunu söylesin).
///
/// ## Ne değişmez
/// - Gövdeler KOPYA değil: `YarisGovdesi` ve `ZirveGovdesi` eski ekranların
///   kendi gövdeleri; bayrak kapalıyken o ekranlar aynı gövdeyi çizer.
/// - Rıza akışları gövdelerin içinde: Yarış opt-in'i (0081) ve Zirve açık
///   rızası (0091) hangi kapıdan gelinirse gelinsin aynen sorulur.
/// - Ölçü ve hesap: seçimlerinin getirisi (TWR, 0095). Sayfa yalnız
///   yerleşimi birleştirir; Ortaklarım `ortaklar`, Herkes `anonim`
///   geriye tarih kuralıyla ölçmeye devam eder.
///
/// ## Dönem
/// Tek dönem iki sekmede ortak (1H · 1A · 1Y — Yarış'ın 7/30/365 günü
/// ile birebir); sekme değişince seçim korunur ve seçici AYNI bileşendir
/// (`ZirveDonemSecici`). Seçici gövdelerin içinde kalır: katılım/rıza
/// kartı gösterilirken anlamsız bir seçici çizilmez.
///
/// ## Neden yalnız etkin sekme kurulur
/// İki gövdenin de kendi yoklayıcısı var (Yarış 15 sn, Zirve 45 sn). İkisini
/// birden canlı tutmak (`IndexedStack`) görünmeyen sekme için ağ ve CPU
/// harcardı; sekme değişince gövde yeniden kurulur, iki gövde de önbellekten
/// (bayat ROI, son rıza) anında açılır.
///
/// Küresel bayrak (`global_leaderboard_enabled`) kapalıyken "Herkes" yok:
/// sekme şeridi çizilmez, sayfa Ortaklarım'dır.
class SiralamaScreen extends ConsumerStatefulWidget {
  const SiralamaScreen({
    super.key,
    this.sekme = SiralamaSekmesi.ortaklarim,
    this.donem = ZirveDonem.ay,
    this.zirveRizaYukleyici,
  });

  /// Açılış sekmesi — giriş noktası verir.
  final SiralamaSekmesi sekme;

  /// Açılış dönemi. Yarış ekranının varsayılanı da 30 gündü (1A).
  final ZirveDonem donem;

  /// Test için Herkes sekmesinin rıza durumu (`ZirveGovdesi.rizaYukleyici`).
  @visibleForTesting
  final Future<bool?> Function()? zirveRizaYukleyici;

  @override
  ConsumerState<SiralamaScreen> createState() => _SiralamaScreenState();
}

class _SiralamaScreenState extends ConsumerState<SiralamaScreen> {
  late SiralamaSekmesi _sekme = widget.sekme;
  late ZirveDonem _donem = widget.donem;

  @override
  Widget build(BuildContext context) {
    final herkesVar = RemoteConfigService.instance.globalLeaderboardEnabled;
    final sekme = herkesVar ? _sekme : SiralamaSekmesi.ortaklarim;
    final hp = SandikSpace.screenH(context);
    final l = context.l10n;
    final etiketler = [l.rankingTabPartners, l.rankingTabEveryone];

    final Widget govde = switch (sekme) {
      SiralamaSekmesi.ortaklarim => YarisGovdesi(
          donemIdx: ZirveDonem.values.indexOf(_donem),
          onDonem: (i) => setState(() => _donem = ZirveDonem.values[i]),
          sekmeli: true,
        ),
      SiralamaSekmesi.herkes => ZirveGovdesi(
          donem: _donem,
          onDonem: (d) => setState(() => _donem = d),
          rizaYukleyici: widget.zirveRizaYukleyici,
        ),
    };

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(
        title: l.rankingTitle,
        // Ayrılma menüsü ve "Getiri nasıl hesaplanıyor?" Yarış'ın; Herkes
        // sekmesinin ayrılma düğmesi kendi gövdesinin altında.
        actions: sekme == SiralamaSekmesi.ortaklarim
            ? yarisEylemleri(context, ref)
            : const <Widget>[],
        transparent: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (herkesVar)
              Padding(
                padding: EdgeInsets.fromLTRB(hp, SandikSpace.xs, hp, 0),
                child: SandikSegment(
                  adet: SiralamaSekmesi.values.length,
                  secili: sekme.index,
                  onSec: (i) =>
                      setState(() => _sekme = SiralamaSekmesi.values[i]),
                  // Kırpma yok: dar ekran / büyük yazı ölçeğinde küçülür.
                  oge: (context, i, _) => FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(etiketler[i], maxLines: 1, softWrap: false),
                  ),
                ),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: SandikMotion.stateOf(context),
                switchInCurve: SandikMotion.enter,
                switchOutCurve: SandikMotion.exit,
                child: KeyedSubtree(key: ValueKey(sekme), child: govde),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
