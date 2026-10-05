import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/auth_provider.dart';
import '../services/crash_reporter.dart';
import '../services/disclaimer_service.dart';
import '../services/sunucu_secimi.dart';
import '../services/yasal_metin_katalogu.dart';
import '../services/yasal_onay_service.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/sigan_metin.dart';
import '../widgets/zorunlu_okuma.dart';
import 'legal_doc_screen.dart';
import 'register_screen.dart' show YasalKutuBaglantilari, YasalOnayKutusu;

/// Yeniden onay kapısı (2026-10-04; bayrak `yasal_kapi_en_yeni`
/// 2026-10-05'te kalktı, kapı koşulsuz).
///
/// ## Neden
/// Kullanıcı kararı: *"Eski rıza metnini onaylayanlar için ilk login'de
/// güncel doküman sunulup onay istenmeli."* `_AuthGate` bu ekranı,
/// kullanıcının Koşullar / Gizlilik / KVKK Aydınlatma / Açık Rıza Metni'nin
/// (1.2'den beri dördü) GÜNCEL sürümüne ya da kutu taahhüdüne etkin kaydı
/// yoksa gösterir (`YasalOnayService.kapiDurumu`). Üç kullanıcı buraya
/// düşer:
/// - belgelerin eski sürümünü onaylamış olan → "Güncellenen belgeler" +
///   "Neler değişti" + tek onay düğmesi;
/// - Apple/Google ile ilk kez gelen (kayıt formunu hiç görmedi) ve onay
///   kaydından önce açılmış hesap → kayıt formundakinin AYNISI (aynı
///   katalog metni, aynı tek kutu);
/// - Yatırım uyarısı da eksikse ([yatirimUyarisiDahil]) uyarı metni bu
///   ekrana girer: iki yasal ekran art arda gelmesin. `disclaimer_acceptances`
///   kaydı `DisclaimerAcceptanceScreen`'deki AYNI çağrıyla yazılır
///   (`DisclaimerService.kabulKaydet`) ve o kapı aynen çalışır.
///
/// ## Ne okunur, neye dokunulur (okuma sadeleştirme, 2026-10-05)
/// Kayıt ekranıyla AYNI kural (kullanıcı kararı: *"Tüm hepsini içinden
/// onaylatmak çok uzun bir process gibi oldu."*):
/// - Açık Rıza Metni — eksikse sonuna kadar okunur, rıza metnin sonunda
///   verilir; geçerliyse bağlantı olarak durur, ikinci kez istenmez.
/// - Yatırım uyarısı — eksikse tam metni okunup onaylanır.
/// - Koşullar, Gizlilik, KVKK — bağlantı (salt okunur). Biri eksikse ya da
///   kutu eksikse ([YasalKapiDurumu.kutuGerekli]) kutu gösterilir: Koşulların
///   kabulü + 18+ + "bilgilendirildim" kutuyla verilir. Kutu metinlere
///   kilitli değildir.
/// Geri tuşuyla atlanamaz; tek çıkış "Çıkış yap". 1.3'te listedeki her
/// metin (dört belge + uyarı) sonuna kadar okunup sonunda onaylanıyor ve
/// kutu onlara kilitleniyordu.
///
/// Onay `yasal_onay_kaydet` RPC'sine `yeniden_onay` kanalıyla gider.
/// Bağlantı hatasında ekran hata gösterir ve kullanıcı yeniden dener;
/// sunucu reddederse (metin kayması gibi bir hata) raporlanır ve kullanıcı
/// KİLİTLENMEZ — bir sonraki açılışta kapı yeniden sorar.
class YasalOnayKapisiScreen extends ConsumerStatefulWidget {
  const YasalOnayKapisiScreen({
    super.key,
    required this.userId,
    required this.durum,
    required this.onTamam,
    this.yatirimUyarisiDahil = false,
  });

  final String userId;
  final YasalKapiDurumu durum;
  final bool yatirimUyarisiDahil;

  /// Onay yazıldı (ya da sunucu hatasında fail-open): kapı kapanır.
  final VoidCallback onTamam;

  /// Yalnız widget testi: `DisclaimerService.kabulKaydet` yerine çağrılır
  /// (servis kurulurken Supabase ister; testte ayağa kalkmaz).
  @visibleForTesting
  static Future<bool> Function({required String userId, required String locale})?
      uyariKaydiTesti;

  @override
  ConsumerState<YasalOnayKapisiScreen> createState() =>
      _YasalOnayKapisiScreenState();
}

class _YasalOnayKapisiScreenState extends ConsumerState<YasalOnayKapisiScreen> {
  /// Tek kutu (kayıt ekranıyla aynı, kutu 1.1).
  bool _kutu = false;
  bool _kutuHatasi = false;
  bool _kayitHatasi = false;

  /// Bağlantıyla açılan belgeler (`belge_acildi` kanıt notu, "Açıldı" izi).
  final Set<String> _acilanlar = {};

  /// Sonuna kadar okunup sonunda onaylanan türler.
  final Set<String> _onaylananlar = {};

  late final YasalKutuBaglantilari _kutuBaglantilari =
      YasalKutuBaglantilari(_belgeyiAc);

  @override
  void dispose() {
    _kutuBaglantilari.dispose();
    super.dispose();
  }

  bool get _kutuGerekli => widget.durum.kutuGerekli;
  bool get _kutularTamam => !_kutuGerekli || _kutu;

  /// Sonuna kadar okunacaklar: Açık Rıza Metni (eksikse) + uyarı (dahilse).
  List<ZorunluMetin> _metinler(AppLocalizations l) => ZorunluMetin.liste(l,
      yatirimUyarisiDahil: widget.yatirimUyarisiDahil,
      riza: widget.durum.rizaEksik);

  int _onayliSayisi(AppLocalizations l) =>
      _metinler(l).where((m) => _onaylananlar.contains(m.tur)).length;

  bool get _belgelerTamam {
    final l = context.l10n;
    return _onayliSayisi(l) == _metinler(l).length;
  }

  Future<void> _zorunluOku(ZorunluMetin m) async {
    setState(() => _acilanlar.add(m.tur));
    final sonuc = await zorunluOkumaAc(context, m);
    if (!mounted || sonuc == null) return;
    if (sonuc.onaylandi && sonuc.sonunaKadarOkundu) {
      setState(() => _onaylananlar.add(m.tur));
    }
  }

  /// Bağlantı belgesini salt okunur açar (kayıt ekranıyla aynı yol).
  Future<void> _belgeyiAc(YasalBelge b) async {
    setState(() => _acilanlar.add(b.tur));
    await belgeyiAc(context, b);
  }

  String _kutuUlkesi(BuildContext context) =>
      SunucuSecimi.instance.aktifOrNull?.ulke ??
      context.l10n.tekOnayUlkeBilinmiyor;

  Future<void> _onayla() async {
    // Düğme zaten kapalı; çift güvence (ör. erişilebilirlik eylemi).
    if (!_belgelerTamam) return;
    if (!_kutularTamam) {
      setState(() => _kutuHatasi = true);
      return;
    }
    final locale = Localizations.localeOf(context).toString();
    final kutu = _kutuGerekli
        ? KapiKutuBaglami(
            dil: context.l10n.localeName,
            kutuUlkesi: _kutuUlkesi(context),
          )
        : null;
    setState(() => _kayitHatasi = false);
    // İki servis de kendi hatasını sınıflandırır ve fırlatmaz; bu `try`
    // yalnız beklenmeyen bir hatanın zone'a düşmemesi için: o durumda
    // kullanıcı hata satırını görür ve yeniden dener.
    final KapiKayitSonucu sonuc;
    try {
      if (widget.yatirimUyarisiDahil) {
        // `DisclaimerAcceptanceScreen` ile AYNI kayıt (bozmama): hata akışı
        // durdurmaz, düşerse o kapı bir sonraki açılışta yine sorar.
        final test = YasalOnayKapisiScreen.uyariKaydiTesti;
        await (test != null
            ? test(userId: widget.userId, locale: locale)
            : DisclaimerService.instance
                .kabulKaydet(userId: widget.userId, locale: locale));
      }
      sonuc = await YasalOnayService.instance.kapiOnaylariniKaydet(
        userId: widget.userId,
        durum: widget.durum,
        belgeDegiskenleri: LegalDocs.yerTutucuDegerleri(),
        acilanBelgeler: _acilanlar,
        sonunaKadarOkunanlar: {..._onaylananlar},
        kutu: kutu,
        yatirimUyarisiDahil: widget.yatirimUyarisiDahil,
        locale: locale,
      );
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'YasalOnayKapisi.onayla');
      if (mounted) setState(() => _kayitHatasi = true);
      return;
    }
    if (!mounted) return;
    if (sonuc == KapiKayitSonucu.agHatasi) {
      setState(() => _kayitHatasi = true);
      return;
    }
    widget.onTamam();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final durum = widget.durum;
    final hp = SandikSpace.screenH(context);
    final metinler = _metinler(l);

    // Sıra Ayarlar ve kayıt ekranıyla aynı: Koşullar, Gizlilik, KVKK, Açık
    // Rıza Metni, (eksikse) yatırım uyarısı.
    final belgeler = [
      for (final b in YasalBelge.values)
        if (b.sonunaKadarOkunur && durum.rizaEksik)
          _zorunluSatir(l, ZorunluMetin.belge(l, b))
        else
          YasalBelgeSatiri(
            adaylar: ZorunluMetin.belge(l, b).adaylar,
            surum: l.yasalBelgeSurum(b.surum),
            tamam: _acilanlar.contains(b.tur),
            tamamEtiketi: l.yasalBelgeAcildi,
            onayli: false,
            onTap: () => _belgeyiAc(b),
          ),
      if (widget.yatirimUyarisiDahil)
        _zorunluSatir(l, ZorunluMetin.yatirimUyarisi(l)),
    ];

    final icerik = <Widget>[
      Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: context.c.amberFill.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child:
              Icon(Icons.gavel_rounded, size: 32, color: context.c.amberText),
        ),
      ),
      const SizedBox(height: SandikSpace.lg),
      Text(
        durum.guncellemeMi ? l.yasalKapiBaslikGuncel : l.yasalKapiBaslikIlk,
        textAlign: TextAlign.center,
        style: context.t.headlineMedium?.copyWith(color: context.c.text90),
      ),
      const SizedBox(height: SandikSpace.sm),
      Text(
        durum.guncellemeMi ? l.yasalKapiAciklamaGuncel : l.yasalKapiAciklamaIlk,
        textAlign: TextAlign.center,
        style: context.t.bodyMedium?.copyWith(color: context.c.text58),
      ),
      if (durum.guncellemeMi) ...[
        const SizedBox(height: SandikSpace.lg),
        SandikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.yasalKapiNelerDegisti,
                style: context.t.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.c.amberText,
                ),
              ),
              const SizedBox(height: SandikSpace.xs2),
              Text(
                l.yasalKapiDegisiklikNotu,
                style: context.t.bodyMedium?.copyWith(
                  color: context.c.text58,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: SandikSpace.lg),
      Text(
        l.zorunluOkumaBelgelerAciklama,
        style: context.t.bodyMedium?.copyWith(color: context.c.text58),
      ),
      const SizedBox(height: SandikSpace.sm),
      SandikCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < belgeler.length; i++) ...[
              if (i > 0) Divider(height: 1, color: context.c.overlay),
              belgeler[i],
            ],
          ],
        ),
      ),
      // Belgeler yalnız Türkçe (çevirisi hukuk işi); İngilizce arayüzde
      // bunu baştan söyle.
      if (l.localeName != 'tr') ...[
        const SizedBox(height: SandikSpace.sm),
        Text(
          l.yasalBelgelerTurkce,
          style: context.t.bodySmall?.copyWith(color: context.c.text36),
        ),
      ],
      if (_kutuGerekli) ...[
        const SizedBox(height: SandikSpace.lg),
        SandikSectionHeader(title: l.yasalKapiTaahhutBaslik),
        const SizedBox(height: SandikSpace.sm),
        _kutuWidget(context),
      ],
    ];

    final altBolum = Padding(
      padding: EdgeInsets.fromLTRB(hp, SandikSpace.sm, hp, SandikSpace.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_kayitHatasi) ...[
            Text(
              l.yasalKapiKayitHatasi,
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: context.c.loss),
            ),
            const SizedBox(height: SandikSpace.sm),
          ],
          // Düğme kapalıyken neyin beklendiği: okunacak metinlerin sayacı,
          // metinler bitince (ya da hiç yoksa) kutu.
          if (!_belgelerTamam || !_kutularTamam) ...[
            Text(
              !_belgelerTamam
                  ? l.zorunluOkumaSayac(_onayliSayisi(l), metinler.length)
                  : l.yasalKapiKutuGerekli,
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
            const SizedBox(height: SandikSpace.sm),
          ],
          SandikAsyncButton(
            onPressed: _belgelerTamam && _kutularTamam ? _onayla : null,
            child: SiganMetin(
              [l.yasalKapiOnayla, l.yasalKapiOnaylaKisa],
              textAlign: TextAlign.center,
            ),
          ),
          TextButton(
            onPressed: () => ref.read(authProvider.notifier).logout(),
            child: Text(
              l.yasalKapiCikis,
              style: context.t.bodyMedium?.copyWith(color: context.c.text36),
            ),
          ),
        ],
      ),
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.c.background,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    // Tablette okunur sütun; telefonda tam genişlik.
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ListView(
                      padding: EdgeInsets.symmetric(
                          horizontal: hp, vertical: SandikSpace.lg),
                      children: icerik,
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: altBolum,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sonuna kadar okunacak metnin satırı (Açık Rıza Metni, uyarı).
  Widget _zorunluSatir(AppLocalizations l, ZorunluMetin m) => YasalBelgeSatiri(
        adaylar: m.adaylar,
        surum: l.yasalBelgeSurum(m.surum),
        tamam: _onaylananlar.contains(m.tur),
        tamamEtiketi: l.zorunluOkumaOnaylandi,
        bekleyenEtiketi: l.zorunluOkumaSatirEtiketi,
        onTap: () => _zorunluOku(m),
      );

  /// Kayıt formundaki kutunun AYNISI — metin katalogdan, üç belge adı
  /// cümle içinde bağlantı. Kilitsiz: Koşulların kabulü rızanın
  /// okunmasından bağımsız bir eylemdir (kayıt ekranıyla aynı karar).
  Widget _kutuWidget(BuildContext context) {
    final l = context.l10n;
    return YasalOnayKutusu(
      icon: Icons.gavel_rounded,
      title: l.tekOnayBaslik,
      versionLabel: 'v${YasalMetinKatalogu.kutuSurumu}',
      bodyText: l.tekOnayAciklama(_kutuUlkesi(context)),
      checkboxLabel: YasalMetinKatalogu.tekKutuCumlesi(l),
      checkboxSpan: _kutuBaglantilari.span(context),
      accepted: _kutu,
      error: _kutuHatasi && !_kutularTamam,
      errorMessage: l.tekOnayGerekli,
      onToggle: () => setState(() => _kutu = !_kutu),
    );
  }
}
