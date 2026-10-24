import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/destek.dart';
import '../l10n/l10n.dart';
import '../services/crash_reporter.dart';
import '../services/destek_maili.dart';
import '../services/gorunen_hata.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';

/// "Tekrar dene"ye ne zaman, hangi ekranda basıldı: süreç içi kayıt.
///
/// ## Neden bileşenin dışında (2026-10-24, "Sorun sürüyorsa bize yaz")
/// Bağlantı yalnız "Tekrar dene" en az bir kez denenip YİNE hata alınınca
/// görünür. Ama denemenin sonucu bileşenin ölümüdür: çağıranların çoğu
/// yeniden denemede yükleniyor görünümüne geçer, hata dönünce YENİ bir
/// [SandikErrorView] kurar. Bileşenin kendi State'i o sırada kaybolur;
/// "denendi" bilgisi State'te tutulsaydı bağlantı hiç görünmezdi. Bu yüzden
/// deneme zamanı ekran anahtarıyla burada tutulur ve yeni kurulan görünüm
/// "benden ÖNCE, yakın zamanda bu ekranda deneme oldu mu" diye sorar.
///
/// Anahtar: [SandikErrorView.ekranAdi], yoksa rotanın adı (`RouteSettings`
/// adları ekran ölçümü için zaten var), o da yoksa boş anahtar.
///
/// [pencere] (2 dk): deneme bu kadar eskiyse sayılmaz. Gerekçe: deneme
/// başarılı olur, kullanıcı çok sonra aynı ekranda başka bir hatayla
/// karşılaşırsa bağlantı ilk hatada görünmesin (geçici kesintide ekran
/// sakin kalsın, rapor kararı). Ağ zaman aşımları 30 sn içinde döner;
/// 2 dk yavaş bir denemeyi de kapsar.
///
/// Kalıcı değil (yalnız bellek): uygulama yeniden açılınca sıfırdan
/// başlamak doğru davranış, kullanıcı verisi değil.
abstract final class HataDenemeKaydi {
  static final _son = <String, DateTime>{};

  /// Test için saat enjeksiyonu (`GorunenHata.now` ile aynı desen).
  static DateTime Function() now = DateTime.now;

  static const pencere = Duration(minutes: 2);

  static void denendi(String anahtar) => _son[anahtar] = now();

  /// [dogum] anında kurulan hata görünümü bağlantıyı göstersin mi? Yalnız
  /// deneme görünümden ÖNCE (ya da aynı anda) ve [pencere] içinde olduysa:
  /// denemeden önce kurulmuş görünüm, sonucu belli olmadan bağlantıyı
  /// göstermez.
  static bool bagGorunsunMu(String anahtar, DateTime dogum) {
    final t = _son[anahtar];
    if (t == null || t.isAfter(dogum)) return false;
    return dogum.difference(t) <= pencere;
  }

  /// [dogum]'dan SONRA deneme oldu mu? (Aynı görünüm yeni bir hatayla
  /// güncellendiğinde, `didUpdateWidget`.)
  static bool sonradanDenendiMi(String anahtar, DateTime dogum) {
    final t = _son[anahtar];
    return t != null && t.isAfter(dogum);
  }

  @visibleForTesting
  static void sifirlaTest() {
    _son.clear();
    now = DateTime.now;
  }
}

/// Hata görünümü.
///
/// Hata anı, arayüzün en çok güven vermesi gereken andır: içerik ani biçimde
/// yerine geçerse "bozuldu" hissi verir. Bu yüzden görünüm sert değil,
/// kısa bir fade + yukarı kayma ile belirir.
///
/// "Tekrar dene" bir kez denenip yine hata gelince altında ikinci, sakin bir
/// bağlantı belirir: "Sorun sürüyorsa bize yaz" (destek e-postası; gövde
/// `destek_maili.dart`). Ana eylem "Tekrar dene" kalır: bağlantı düğme
/// değil, ikincil metin rengiyle yazılmış bir satır. Ne zaman görüneceği
/// [HataDenemeKaydi]'nda.
class SandikErrorView extends StatefulWidget {
  final Object error;
  final VoidCallback? onRetry;

  /// E-postadaki "Ekran" satırı ve deneme kaydının anahtarı. İsteğe bağlı:
  /// verilmezse rotanın adı kullanılır.
  final String? ekranAdi;

  const SandikErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.ekranAdi,
  });

  @override
  State<SandikErrorView> createState() => _SandikErrorViewState();
}

class _SandikErrorViewState extends State<SandikErrorView> {
  /// Bu görünümün kurulduğu an; denemenin önce mi sonra mı olduğuna bakılır.
  late DateTime _dogum;

  @override
  void initState() {
    super.initState();
    _dogum = HataDenemeKaydi.now();
  }

  /// E-posta uygulaması açılamadı: adres kopyalanabilir metin olarak durur.
  bool _mailAcilamadi = false;

  String _anahtar(BuildContext context) =>
      widget.ekranAdi ?? ModalRoute.of(context)?.settings.name ?? '';

  @override
  void didUpdateWidget(SandikErrorView eski) {
    super.didUpdateWidget(eski);
    // Bazı çağıranlar denemede yükleniyor göstermez, aynı görünüme yeni
    // hatayı verir. Yeni hata + bu görünüm kurulduktan sonra deneme = yine
    // hata alındı demek; görünüm o andan doğmuş sayılır.
    if (!identical(eski.error, widget.error) &&
        HataDenemeKaydi.sonradanDenendiMi(_anahtar(context), _dogum)) {
      _dogum = HataDenemeKaydi.now();
    }
  }

  void _tekrarDene() {
    HataDenemeKaydi.denendi(_anahtar(context));
    widget.onRetry?.call();
  }

  Future<void> _bizeYaz() async {
    final ekran = _anahtar(context);
    final s = await destekSurumu();
    final uri = destekHataMaili(
      error: widget.error,
      surum: s.surum,
      build: s.build,
      platform: destekPlatformu(),
      ekran: ekran.isEmpty ? null : ekran,
    );
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SandikErrorView.bizeYaz');
    }
    if (!ok && mounted) setState(() => _mailAcilamadi = true);
  }

  Future<void> _adresiKopyala() async {
    await Clipboard.setData(const ClipboardData(text: kDestekEposta));
    if (!mounted) return;
    sandikSnack(context, context.l10n.hataAdresKopyalandi);
  }

  @override
  Widget build(BuildContext context) {
    // Görünen hata: bu oturumda puan istenmez (`GorunenHata`). Yalnız bir
    // zaman damgası; yeniden çizimde tekrar yazması zararsız, hata hâlâ
    // ekranda demektir.
    GorunenHata.kaydet();
    // Erişilebilirlik: "hareketi azalt" açıkken içerik doğrudan görünür.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final bizeYaz = widget.onRetry != null &&
        HataDenemeKaydi.bagGorunsunMu(_anahtar(context), _dogum);

    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: context.c.loss, size: 40),
            const SizedBox(height: 16),
            Text(
              friendlyError(widget.error),
              textAlign: TextAlign.center,
              style: context.t.titleMedium?.copyWith(color: context.c.text58),
            ),
            if (widget.onRetry != null) ...[
              const SizedBox(height: 20),
              // SandikTappable sarmalı: her basılabilir eleman basıldığını
              // hissettirmeli. Tekrar deneme bir yeniden-yükleme eylemi,
              // seçim değil — bu yüzden medium ton.
              SandikTappable(
                onTap: _tekrarDene,
                haptic: SandikHaptic.medium,
                semanticLabel: 'Tekrar dene',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SandikSpace.lg,
                    vertical: SandikSpace.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.12),
                    borderRadius: SandikRadius.mdAll,
                    border: Border.all(
                      color: context.c.amberFill.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    'Tekrar Dene',
                    style: context.t.titleMedium?.copyWith(
                      color: context.c.amberText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            if (bizeYaz) ...[
              const SizedBox(height: SandikSpace.sm),
              _BizeYazBaglantisi(onTap: _bizeYaz),
            ],
            if (bizeYaz && _mailAcilamadi) ...[
              const SizedBox(height: SandikSpace.sm),
              _AdresKutusu(onKopyala: _adresiKopyala),
            ],
          ],
        ),
      ),
    );

    if (reduceMotion) return content;

    // 0 → 1 tek atış: hata görünümü bir kez belirir, tekrar animasyonlanmaz.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: SandikMotion.surface,
      curve: SandikMotion.enter,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
      child: content,
    );
  }
}

/// İkincil, sakin bağlantı: dolgu ve çerçeve yok, ikincil metin rengi.
/// Ana eylem "Tekrar dene" olarak kalsın; bu satır göz alıcı olursa
/// kullanıcı denemeden yazmaya yönelir. Dokunma alanı yine ≥44 pt.
class _BizeYazBaglantisi extends StatelessWidget {
  const _BizeYazBaglantisi({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SandikTappable(
        key: const ValueKey('hata-bize-yaz'),
        onTap: onTap,
        semanticLabel: context.l10n.hataBizeYazEtiket,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              minHeight: SandikTouch.min, minWidth: SandikTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mail_outline_rounded,
                    size: 16, color: context.c.text58),
                const SizedBox(width: SandikSpace.xs),
                Flexible(
                  child: Text(
                    context.l10n.hataBizeYaz,
                    textAlign: TextAlign.center,
                    style: context.t.bodyMedium?.copyWith(
                      color: context.c.text58,
                      decoration: TextDecoration.underline,
                      decorationColor: context.c.text36,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// E-posta uygulaması açılamadı: adres seçilebilir metin + kopyala düğmesi.
/// Snack yetmez: birkaç saniyede kaybolur, adresi yazmaya fırsat kalmaz.
class _AdresKutusu extends StatelessWidget {
  const _AdresKutusu({required this.onKopyala});
  final VoidCallback onKopyala;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('hata-adres-kutusu'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.hataMailAcilamadi,
            textAlign: TextAlign.center,
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
          const SizedBox(height: SandikSpace.xs),
          SelectableText(
            kDestekEposta,
            textAlign: TextAlign.center,
            style: context.t.bodyMedium?.copyWith(color: context.c.text90),
          ),
          SandikTappable(
            onTap: onKopyala,
            semanticLabel: context.l10n.hataAdresiKopyala,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  minHeight: SandikTouch.min, minWidth: SandikTouch.min),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_rounded,
                        size: 16, color: context.c.amberText),
                    const SizedBox(width: SandikSpace.xs),
                    Text(
                      context.l10n.hataAdresiKopyala,
                      style: context.t.bodyMedium
                          ?.copyWith(color: context.c.amberText),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}
