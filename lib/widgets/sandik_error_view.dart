import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/destek.dart';
import '../l10n/l10n.dart';
import '../providers/cevrimdisi_provider.dart';
import '../services/crash_reporter.dart';
import '../services/ozellik_olcumu.dart';
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
///
/// ## Bağlantı dönünce bir kez kendiliğinden dener (rapor 2026-11-08 02:30 #1)
/// Metroda "Bağlantı kurulamadı" düşen ekran, istasyondan çıkınca da düğme
/// bekliyordu. Görünüm açıkken [cevrimdisiProvider] dolu → boş geçerse
/// (ana sayfadaki "İnternet yok" şeridiyle AYNI sinyal: son fiyat turu ağ
/// hatasıyla bitti → ilk yanıt alındı) [_tekrarDene] bir kez çağrılır;
/// deneme düğmeyle aynı yoldan [HataDenemeKaydi]'na yazılır, yani yine
/// hata gelirse "bize yaz" bağlantısı da düğmeyle aynı kuralla belirir.
/// Kurallar:
/// - Yalnız GEÇİŞ tetikler: görünüm kurulduğundan beri hiç çevrimdışı
///   durum görmediyse (sunucu hatası, yetki hatası) kendiliğinden deneme
///   yok; o hatayı bağlantının dönmesi düzeltmez.
/// - Geçiş başına tek deneme, döngü yok: deneme başarısızsa görünüm yine
///   düğmeyi bekler; bir sonraki deneme ancak yeni bir kopma → dönüş
///   geçişiyle gelir. Pil ve istek sınırı korunur.
/// - Görünüm aynı, ek satır yok: davranış açıklama istemiyor.
///
/// Neden `ConsumerStatefulWidget` değil: hata görünümü 20+ ekranda ve
/// ProviderScope kurmayan widget testlerinde de çiziliyor. `ref` orada
/// "No ProviderScope found" ile düşerdi. Kapsam [UncontrolledProviderScope]
/// ile ARANIR; yoksa dinleme kurulmaz ve görünüm bugünkü gibi yalnız
/// düğmeyle çalışır. Çağıranlarda değişiklik gerekmez.
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

  /// Bağlantı sinyalinin aboneliği; kapsam yoksa `null` (bkz. sınıf notu).
  ProviderSubscription<CevrimdisiDurum?>? _baglantiAboneligi;
  ProviderContainer? _kapsam;

  /// Bu görünüm kurulduğundan beri (ya da son kendiliğinden denemeden
  /// beri) çevrimdışı durum görüldü mü? Geçiş ancak bu doluyken tetikler.
  bool _cevrimdisiGoruldu = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `dependOn…`: kapsam değişirse (nadiren, iç içe ProviderScope) yeniden
    // abone olunur. Kapsam yoksa sessizce düğmeyle yetinilir.
    final kapsam = context
        .dependOnInheritedWidgetOfExactType<UncontrolledProviderScope>()
        ?.container;
    if (identical(kapsam, _kapsam)) return;
    _baglantiAboneligi?.close();
    _baglantiAboneligi = null;
    _kapsam = kapsam;
    if (kapsam == null) return;
    _baglantiAboneligi = kapsam.listen<CevrimdisiDurum?>(
      cevrimdisiProvider,
      _baglantiDegisti,
      fireImmediately: true,
    );
  }

  void _baglantiDegisti(CevrimdisiDurum? onceki, CevrimdisiDurum? simdi) {
    if (simdi != null) {
      _cevrimdisiGoruldu = true;
      return;
    }
    if (onceki == null || !_cevrimdisiGoruldu || widget.onRetry == null) {
      return;
    }
    // Geçiş tüketildi: aynı dönüşte ikinci deneme yok.
    _cevrimdisiGoruldu = false;
    // Sinyal fiyat turunun ortasında (bir Notifier'ın async gövdesinde)
    // değişir; yeniden denemeyi oradan çağırmak başka bir sağlayıcıyı o
    // turun içinde geçersiz kılardı. Bir sonraki kareden sonra, görünüm
    // hâlâ ekrandaysa denenir.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tekrarDene();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _baglantiAboneligi?.close();
    super.dispose();
  }

  void _tekrarDene() {
    HataDenemeKaydi.denendi(_anahtar(context));
    widget.onRetry?.call();
  }

  Future<void> _bizeYaz() async {
    OzellikOlcumu.say(Ozellik.bizeYaz);
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
              friendlyError(widget.error, l10n: context.l10n),
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
                semanticLabel: context.l10n.retry,
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
                    context.l10n.retry,
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
