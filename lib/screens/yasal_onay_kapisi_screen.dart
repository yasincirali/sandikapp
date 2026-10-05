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
import 'register_screen.dart' show YasalOnayKutusu;

/// Yeniden onay kapısı (2026-10-04; bayrak `yasal_kapi_en_yeni`
/// 2026-10-05'te kalktı, kapı koşulsuz).
///
/// ## Neden
/// Kullanıcı kararı: *"Eski rıza metnini onaylayanlar için ilk login'de
/// güncel doküman sunulup onay istenmeli."* `_AuthGate` bu ekranı,
/// kullanıcının Koşullar / Gizlilik / KVKK Aydınlatma / Açık Rıza Metni'nin
/// (1.2'den beri dördü) GÜNCEL sürümüne ya da kayıt kutusu taahhütlerine
/// etkin onayı yoksa gösterir
/// (`YasalOnayService.kapiDurumu`). Üç kullanıcı buraya düşer:
/// - belgelerin eski sürümünü onaylamış olan → "Güncellenen belgeler" +
///   "Neler değişti" + tek onay düğmesi;
/// - Apple/Google ile ilk kez gelen (kayıt formunu hiç görmedi) ve onay
///   kaydından önce açılmış hesap → belgeler + kayıt formundaki kutuların
///   AYNISI (18+, yurt dışı aktarım açık rızası; aynı katalog metni, aynı
///   tek kutu).
/// - Yatırım uyarısı da eksikse ([yatirimUyarisiDahil]) uyarı metni bu
///   ekrana girer: iki yasal ekran art arda gelmesin. `disclaimer_acceptances`
///   kaydı `DisclaimerAcceptanceScreen`'deki AYNI çağrıyla yazılır
///   (`DisclaimerService.kabulKaydet`) ve o kapı aynen çalışır.
///
/// Geri tuşuyla atlanamaz; tek çıkış "Çıkış yap". Zorunlu okuma (2026-10-04;
/// bayrak `zorunlu_okuma` 2026-10-05'te kalktı): listedeki her metin —
/// eksikse yatırım uyarısı da listeye girer — tam açılır, sonuna kadar
/// okunup EN SONUNDA onaylanır; hepsi onaylanmadan kutu işaretlenmez ve
/// "Okudum, kabul ediyorum" açılmaz. (Bayrak kapalıyken belgeler yalnız
/// okunuyor, uyarı metni ekranda düz yazı duruyordu; o yol silindi.) Onay `yasal_onay_kaydet` RPC'sine
/// `yeniden_onay` kanalıyla gider. Bağlantı hatasında ekran hata gösterir
/// ve kullanıcı yeniden dener; sunucu reddederse (metin kayması gibi bir
/// hata) raporlanır ve kullanıcı KİLİTLENMEZ — bir sonraki açılışta kapı
/// yeniden sorar.
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
  /// Tek kutu (kayıt ekranıyla aynı): 18+ ve yurt dışı aktarım açık rızası
  /// birlikte. İki kutulu düzen `tek_onay_kutusu` ile 2026-10-05'te kalktı.
  bool _kutu = false;
  bool _kutuHatasi = false;
  bool _kayitHatasi = false;
  final Set<String> _acilanlar = {};

  /// Zorunlu okumada sonuna kadar okunup sonunda onaylanan türler.
  final Set<String> _onaylananlar = {};

  bool get _kutularTamam => !widget.durum.kutuEksik || _kutu;

  List<ZorunluMetin> _metinler(AppLocalizations l) => ZorunluMetin.liste(l,
      yatirimUyarisiDahil: widget.yatirimUyarisiDahil);

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

  /// Kutu değişimi — zorunlu okumada metinler bitmeden kutu işaretlenmez.
  /// Hata durumuna alınmaz: kutunun kilit notu ve düğmenin üstündeki sayaç
  /// neyin beklendiğini zaten söylüyor.
  void _kutuDegistir(VoidCallback degistir) {
    if (!_belgelerTamam) return;
    setState(degistir);
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
    final kutu = widget.durum.kutuEksik
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

    final belgeler = [
      for (final m in _metinler(l))
        YasalBelgeSatiri(
          adaylar: m.adaylar,
          surum: l.yasalBelgeSurum(m.surum),
          tamam: _onaylananlar.contains(m.tur),
          tamamEtiketi: l.zorunluOkumaOnaylandi,
          onTap: () => _zorunluOku(m),
        ),
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
      // Yatırım uyarısı eksikse listede bir satır (tam metin okuyucuda).
      if (durum.kutuEksik) ...[
        const SizedBox(height: SandikSpace.lg),
        SandikSectionHeader(title: l.yasalKapiTaahhutBaslik),
        const SizedBox(height: SandikSpace.sm),
        ..._kutular(context),
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
          // Düğme kapalıyken neyin beklendiği: önce kaç metnin onaylandığı,
          // metinler bitince kutu.
          if (!_belgelerTamam || !_kutularTamam) ...[
            Text(
              !_belgelerTamam
                  ? l.zorunluOkumaSayac(
                      _onayliSayisi(l), _metinler(l).length)
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

  /// Kayıt formundaki kutunun AYNISI — metin katalogdan. Belgeler yukarıda
  /// listelendiği için kutuda bağlantı yok; kutu cümlesi düz metin
  /// (hash'lenen metinle aynı). Metinler bitene kadar kilitli ve nedenini
  /// söyler (kayıt ekranıyla aynı karar: kutu son metnin onayıyla
  /// kendiliğinden işaretlenmez, açık rıza ayrı bir eylemdir).
  List<Widget> _kutular(BuildContext context) {
    final l = context.l10n;
    return [
      YasalOnayKutusu(
        icon: Icons.gavel_rounded,
        title: l.tekOnayBaslik,
        versionLabel: 'v${YasalMetinKatalogu.kutuSurumu}',
        bodyText: l.tekOnayAciklama(_kutuUlkesi(context)),
        checkboxLabel: YasalMetinKatalogu.tekKutuCumlesi(l),
        accepted: _kutu,
        docConfirmed: _belgelerTamam,
        kilitNotu: l.zorunluOkumaKutuKilitli,
        error: _kutuHatasi && !_kutularTamam,
        errorMessage: l.tekOnayGerekli,
        onToggle: () => _kutuDegistir(() => _kutu = !_kutu),
      ),
    ];
  }
}
