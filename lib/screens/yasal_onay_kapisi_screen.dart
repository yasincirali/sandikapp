import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/auth_provider.dart';
import '../services/crash_reporter.dart';
import '../services/disclaimer_service.dart';
import '../services/remote_config_service.dart';
import '../services/sunucu_secimi.dart';
import '../services/yasal_metin_katalogu.dart';
import '../services/yasal_onay_service.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/sigan_metin.dart';
import '../widgets/zorunlu_okuma.dart';
import 'legal_doc_screen.dart';
import 'register_screen.dart' show YasalOnayKutusu;

/// Yeniden onay kapısı (bayrak `yasal_kapi_en_yeni`, 2026-10-04).
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
///   kutu düzeni kararı `tek_onay_kutusu`).
/// - Yatırım uyarısı da eksikse ([yatirimUyarisiDahil]) uyarı metni bu
///   ekrana girer: iki yasal ekran art arda gelmesin. `disclaimer_acceptances`
///   kaydı `DisclaimerAcceptanceScreen`'deki AYNI çağrıyla yazılır
///   (`DisclaimerService.kabulKaydet`) ve o kapı aynen çalışır.
///
/// Geri tuşuyla atlanamaz; tek çıkış "Çıkış yap". Belgeler okunabilir
/// (`LegalDocScreen`, yalnız okuma). Zorunlu okumada (bayrak
/// `zorunlu_okuma`, 2026-10-04) listedeki her metin — eksikse yatırım
/// uyarısı da listeye girer — tam açılır, sonuna kadar okunup EN SONUNDA
/// onaylanır; hepsi onaylanmadan kutular işaretlenmez ve "Okudum, kabul
/// ediyorum" açılmaz. Onay `yasal_onay_kaydet` RPC'sine
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
  /// Kutu düzeni kayıt ekranıyla aynı karar; ekran açılışında bir kez.
  late final bool _tekKutu = RemoteConfigService.instance.tekOnayKutusu;

  /// Zorunlu okuma — ekran açılışında bir kez (bkz. kayıt ekranı).
  late final bool _zorunlu = RemoteConfigService.instance.zorunluOkuma;

  bool _kosulKutusu = false;
  bool _rizaKutusu = false;
  bool _kutuHatasi = false;
  bool _kayitHatasi = false;
  final Set<String> _acilanlar = {};

  /// Zorunlu okumada sonuna kadar okunup sonunda onaylanan türler.
  final Set<String> _onaylananlar = {};

  bool get _kutularTamam =>
      !widget.durum.kutuEksik || (_kosulKutusu && _rizaKutusu);

  List<ZorunluMetin> _metinler(AppLocalizations l) => ZorunluMetin.liste(l,
      yatirimUyarisiDahil: widget.yatirimUyarisiDahil);

  int _onayliSayisi(AppLocalizations l) =>
      _metinler(l).where((m) => _onaylananlar.contains(m.tur)).length;

  /// Zorunlu okuma kapalıyken her zaman `true`.
  bool get _belgelerTamam {
    if (!_zorunlu) return true;
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
      (_tekKutu
          ? context.l10n.tekOnayUlkeBilinmiyor
          : KayitKutuMetni.rizaUlkeBilinmiyor);

  /// Bayrak kapalıyken: belge yalnız okunur (`LegalDocScreen`). Ad ve ikon
  /// [ZorunluMetin.belge]'den — iki kipte aynı.
  Future<void> _belgeyiAc(YasalBelge belge) async {
    final m = ZorunluMetin.belge(context.l10n, belge);
    final bloklar = m.bloklar();
    setState(() => _acilanlar.add(belge.tur));
    await pushGuarded<void>(
      context,
      adaptiveRoute(
        builder: (_) => LegalDocScreen(
            title: m.adaylar.first, icon: m.ikon, blocks: bloklar),
      ),
    );
  }

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
            tekKutu: _tekKutu,
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
        sonunaKadarOkunanlar: _zorunlu ? {..._onaylananlar} : const {},
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

    final belgeler = _zorunlu
        ? [
            for (final m in _metinler(l))
              YasalBelgeSatiri(
                adaylar: m.adaylar,
                surum: l.yasalBelgeSurum(m.surum),
                tamam: _onaylananlar.contains(m.tur),
                tamamEtiketi: l.zorunluOkumaOnaylandi,
                onTap: () => _zorunluOku(m),
              ),
          ]
        : [
            for (final b in YasalBelge.values)
              YasalBelgeSatiri(
                adaylar: ZorunluMetin.belge(l, b).adaylar,
                surum: l.yasalBelgeSurum(b.surum),
                tamam: _acilanlar.contains(b.tur),
                tamamEtiketi: l.yasalBelgeAcildi,
                onTap: () => _belgeyiAc(b),
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
      if (_zorunlu) ...[
        Text(
          l.zorunluOkumaBelgelerAciklama,
          style: context.t.bodyMedium?.copyWith(color: context.c.text58),
        ),
        const SizedBox(height: SandikSpace.sm),
      ],
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
      // Zorunlu okumada uyarı listede bir satır (tam metin okuyucuda).
      if (widget.yatirimUyarisiDahil && !_zorunlu) ...[
        const SizedBox(height: SandikSpace.lg),
        SandikSectionHeader(title: l.yasalKapiYatirimUyarisi),
        const SizedBox(height: SandikSpace.sm),
        Container(
          padding: const EdgeInsets.all(SandikSpace.md),
          decoration: BoxDecoration(
            color: context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
          ),
          child: Text(
            disclaimerText,
            style: context.t.bodyMedium?.copyWith(
              color: context.c.text58,
              height: 1.6,
            ),
          ),
        ),
      ],
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
          // Zorunlu okumada düğme kapalıyken neyin beklendiği: önce kaç
          // metnin onaylandığı, metinler bitince kutular.
          if (_zorunlu && (!_belgelerTamam || !_kutularTamam)) ...[
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
            onPressed: !_zorunlu || (_belgelerTamam && _kutularTamam)
                ? _onayla
                : null,
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

  /// Kayıt formundaki kutuların AYNISI — metinler katalogdan, düzen
  /// `tek_onay_kutusu`'na göre. Belgeler yukarıda listelendiği için kutuda
  /// bağlantı yok; kutu cümlesi düz metin (hash'lenen metinle aynı).
  /// Zorunlu okumada metinler bitene kadar kilitli ve nedenini söyler
  /// (kayıt ekranıyla aynı karar: kutu son metnin onayıyla kendiliğinden
  /// işaretlenmez, açık rıza ayrı bir eylemdir).
  List<Widget> _kutular(BuildContext context) {
    final l = context.l10n;
    final ulke = _kutuUlkesi(context);
    final hata = _kutuHatasi && !_kutularTamam;
    final belgelerTamam = _belgelerTamam;
    final kilitNotu = _zorunlu ? l.zorunluOkumaKutuKilitli : null;
    if (_tekKutu) {
      return [
        YasalOnayKutusu(
          icon: Icons.gavel_rounded,
          title: l.tekOnayBaslik,
          versionLabel: 'v${YasalMetinKatalogu.kutuSurumu}',
          bodyText: l.tekOnayAciklama(ulke),
          checkboxLabel: YasalMetinKatalogu.tekKutuCumlesi(l),
          accepted: _kosulKutusu && _rizaKutusu,
          docConfirmed: belgelerTamam,
          kilitNotu: kilitNotu,
          error: hata,
          errorMessage: l.tekOnayGerekli,
          onToggle: () => _kutuDegistir(() {
            final yeni = !(_kosulKutusu && _rizaKutusu);
            _kosulKutusu = yeni;
            _rizaKutusu = yeni;
          }),
        ),
      ];
    }
    return [
      YasalOnayKutusu(
        icon: Icons.gavel_rounded,
        title: KayitKutuMetni.kosulBaslik,
        versionLabel: 'v${YasalMetinKatalogu.kutuSurumu}',
        bodyText: KayitKutuMetni.kosulGovde,
        checkboxLabel: KayitKutuMetni.kosulCumle,
        accepted: _kosulKutusu,
        docConfirmed: belgelerTamam,
        kilitNotu: kilitNotu,
        error: _kutuHatasi && !_kosulKutusu,
        errorMessage: l.yasalKapiKutuGerekli,
        onToggle: () => _kutuDegistir(() => _kosulKutusu = !_kosulKutusu),
      ),
      const SizedBox(height: SandikSpace.md2),
      YasalOnayKutusu(
        icon: Icons.public_rounded,
        title: KayitKutuMetni.rizaBaslik,
        bodyText: KayitKutuMetni.rizaGovde(ulke),
        checkboxLabel: KayitKutuMetni.rizaCumle,
        accepted: _rizaKutusu,
        docConfirmed: belgelerTamam,
        kilitNotu: kilitNotu,
        error: _kutuHatasi && !_rizaKutusu,
        errorMessage: l.yasalKapiKutuGerekli,
        onToggle: () => _kutuDegistir(() => _rizaKutusu = !_rizaKutusu),
      ),
    ];
  }
}
