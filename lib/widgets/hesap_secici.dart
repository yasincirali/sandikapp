import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/hesap_provider.dart';
import '../services/hesap_gecisi.dart';
import '../services/hesap_kasasi.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/tr_format.dart' show dayKey;
import 'sandik_cam.dart';
import 'uygulama_kabugu.dart' show HesapAvatari;

/// Çoklu hesap arayüzü (bayrak `coklu_hesap`, 2026-10-10).
///
/// Giriş noktası Profil'in kimlik kartındaki "ad ⌄" (7 Kas; 5 Kas'ta ayrı
/// "Hesap ⌄" düğmesi, daha önce üst çubukta aktif hesabın adıydı). Dokununca
/// yüzen cam menü ([hesapMenusunuAc]); Profil sekmesine uzun basma ve
/// "Hesapları düzenle" bugünkü alt sayfayı açar. Alt gezinme çubuğu
/// değişmez (kullanıcı kuralı). Çıkış düğmesi yerinde kalır; birden fazla
/// hesap varken iki seçenek sorar ([cokluCikisSor]).
///
/// HIG: her satır ≥ 44 pt, ad ve durum metni Dynamic Type ile büyür
/// (sabit yükseklik yok), seçili hesap yalnız renkle değil onay işaretiyle
/// ve ekran okuyucuda "seçili" ile ayrılır, yıkıcı eylem (kaldır) onay ister.

// ── Profil başlığı ───────────────────────────────────────────────────────────

/// Kimlik kartındaki ad: "ad ⌄" (Profil yeniden tasarımı, yasin 7 Kas).
///
/// ## Neden adın kendisi (önce ayrı "Hesap ⌄" düğmesi)
/// Kartın sağında yüzen küçük "Hesap ⌄" ne olduğunu da nerede bittiğini de
/// söylemiyordu. Instagram, Gmail ve iOS hesabı adın yanındaki okla
/// değiştirir: neyi değiştirdiğin zaten dokunduğun yazıdır.
///
/// ## Ok yalnız iki ve daha fazla hesapta
/// Tek hesapta ad düz metindir, dokunulmaz: değiştirilecek bir şey yokken
/// ok boş bir vaat olurdu. İkinci hesabı eklemenin yolu Profil › Ayarlar'daki
/// "Hesap ekle" satırı (Ar-Ge 7 Kas); Profil sekmesine uzun basmak da
/// eskisi gibi listeyi açar ([profilSekmesiUzunBasildi]).
///
/// Dokunma alanı adın ve okun tamamı (≥ 44 pt); ekran okuyucu "Hesap
/// değiştir, şu an …" der (önceki düğmenin etiketi korunur).
class HesapBasligi extends ConsumerWidget {
  const HesapBasligi({super.key, required this.ad, this.stil});

  /// Kartta yazan ad (bugünkü `displayName`; değişmedi).
  final String ad;
  final TextStyle? stil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aktif = ref.watch(authProvider).valueOrNull;
    final kayitli = ref.watch(kayitliHesaplarProvider);
    final cokHesap = kayitli.any((h) => h.uid != aktif?.id);
    final yazi = Text(
      ad,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: stil,
    );
    if (!cokHesap) return yazi;
    return Semantics(
      container: true,
      button: true,
      label: ad.isEmpty ? 'Hesap değiştir' : 'Hesap değiştir, şu an $ad',
      excludeSemantics: true,
      child: SandikTappable(
        onTap: () => hesapMenusunuAc(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              minHeight: SandikTouch.min, minWidth: SandikTouch.min),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: yazi),
              const SizedBox(width: SandikSpace.xs),
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: context.c.text58, size: SandikSpace.lg),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hesap menüsü (yüzen, cam) ────────────────────────────────────────────────

/// Adın altından açılan yüzen hesap menüsü (Ar-Ge 7 Kas; önce alt sayfa).
///
/// ## Cam yalnız burada
/// Cam bir malzemedir: arkasından içerik görünen yüzen katmanda anlam
/// taşır (`docs/TASARIM_DILI.md` cam kuralı). Menü Profil'in üstünde
/// yüzer, arkasında kart ve yazı durur; iOS 26'nın açılır menü kalıbı.
/// Uygulamada başka yeni cam yok (yasin: "Liquid Glass yalnız hesap
/// menüsünde"). Yüzey [SandikCamYuzey]: iOS'ta buzlu cam; Android, yüksek
/// kontrast, iOS "Saydamlığı azalt" ve "Hareketi azalt" açıkken katı
/// zemin (`surface2`).
///
/// ## Hareket
/// Menü düğmeden doğar (sol üstten ölçek + solma), aynı yoldan kapanır.
/// Hareketi azalt açıkken süre sıfır: ilk karede yerinde.
///
/// Satırlar ve geçiş mantığı alt sayfayla ortak ([hesabaGec],
/// [hesapEklemeyiBaslat]); kaldırma için "Hesapları düzenle" bugünkü
/// sayfayı açar.
Future<void> hesapMenusunuAc(BuildContext context) {
  final kutu = context.findRenderObject();
  final kaynak = kutu is RenderBox && kutu.hasSize
      ? kutu.localToGlobal(Offset.zero) & kutu.size
      : Rect.zero;
  final azalt = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Hesap menüsünü kapat',
    barrierColor: context.c.golge
        .withValues(alpha: context.isLight ? 0.18 : 0.32),
    transitionDuration: SandikMotion.surfaceOf(context),
    pageBuilder: (_, __, ___) =>
        HesapMenusu(kaynak: kaynak, ustContext: context),
    transitionBuilder: (ctx, anim, _, child) {
      final egri = CurvedAnimation(
          parent: anim,
          curve: SandikMotion.enter,
          reverseCurve: SandikMotion.exit);
      if (azalt) return FadeTransition(opacity: egri, child: child);
      return FadeTransition(
        opacity: egri,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(egri),
          alignment: Alignment(
            // Ölçeğin çıkış noktası düğmenin kendisi.
            (kaynak.center.dx / MediaQuery.sizeOf(ctx).width) * 2 - 1,
            (kaynak.bottom / MediaQuery.sizeOf(ctx).height) * 2 - 1,
          ),
          child: child,
        ),
      );
    },
  );
}

/// Menünün gövdesi; [kaynak] düğmenin ekran dikdörtgeni. Test ve görsel
/// önizleme doğrudan kurar.
class HesapMenusu extends ConsumerWidget {
  const HesapMenusu(
      {super.key, required this.kaynak, required this.ustContext});

  final Rect kaynak;

  /// Menü kapandıktan sonra hata/bilgi diyaloğu bu bağlamda açılır.
  final BuildContext ustContext;

  /// Menü genişliği; dar ekranda kenar payları içinde kalır.
  static const double _genislik = 300;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final aktif = ref.watch(authProvider).valueOrNull;
    final kayitli = ref.watch(kayitliHesaplarProvider);
    final digerleri = [
      for (final h in kayitli)
        if (h.uid != aktif?.id) h,
    ];
    final dolu = digerleri.length + 1 >= HesapKasasi.enCok;
    // Hareketi azalt da camı kapatır (Ar-Ge 7 Kas: "hareketi/şeffaflığı
    // azalt açıkken katı"); Saydamlığı azalt ve yüksek kontrast
    // `SandikCam.bulanik` içinde.
    final kati = MediaQuery.disableAnimationsOf(context);

    final liste = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (aktif != null)
          _HesapSatiri(
            ton: 0,
            harf: KayitliHesap(
                    uid: aktif.id,
                    eposta: aktif.email,
                    ad: hesapAdi(aktif),
                    sonKullanim: DateTime.now())
                .basHarf,
            ad: hesapAdi(aktif),
            alt: 'Bu cihazda açık',
            secili: true,
          ),
        for (final (i, h) in digerleri.indexed)
          _HesapSatiri(
            ton: i + 1,
            harf: h.basHarf,
            ad: h.ad,
            alt: h.oturumDustu
                ? 'Tekrar giriş gerekli'
                : 'Son açılış ${goreliZaman(h.sonKullanim, DateTime.now())}',
            uyari: h.oturumDustu,
            onTap: (yer) {
              Navigator.of(context).pop();
              hesabaGec(ustContext, h, aktif: aktif, ton: i + 1, kaynak: yer);
            },
          ),
        Divider(color: c.hairline, height: SandikSpace.md),
        _EylemSatiri(
          ikon: Icons.add_rounded,
          etiket: 'Hesap ekle',
          alt: dolu
              ? 'En fazla ${HesapKasasi.enCok} hesap'
              : 'Mevcut hesabın açık kalır',
          onTap: dolu
              ? null
              : () {
                  Navigator.of(context).pop();
                  hesapEklemeyiBaslat(ustContext, aktif);
                },
        ),
        if (digerleri.isNotEmpty)
          _EylemSatiri(
            ikon: Icons.edit_outlined,
            etiket: 'Hesapları düzenle',
            alt: 'Bu cihazdan kaldır',
            onTap: () {
              Navigator.of(context).pop();
              if (ustContext.mounted) hesapSeciciniAc(ustContext);
            },
          ),
      ],
    );

    return SafeArea(
      child: CustomSingleChildLayout(
        delegate: _MenuYerlesimi(
          kaynak: kaynak,
          kenar: SandikSpace.screenH(context),
          ustBosluk: MediaQuery.paddingOf(context).top,
        ),
        child: SizedBox(
          width: _genislik,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: SandikRadius.lgAll,
              boxShadow: [
                // Yüzen katmanın tek derinlik ipucu; cam katıyken de menüyü
                // kartlardan ayırır.
                BoxShadow(
                  color: c.golge.withValues(alpha: context.isLight ? 0.12 : 0.3),
                  blurRadius: SandikSpace.lg,
                  offset: const Offset(0, SandikSpace.sm),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: SandikCamYuzey(
                borderRadius: SandikRadius.lgAll,
                renk: kati
                    ? c.surface2
                    : c.surface2.withValues(alpha: SandikCam.ortu),
                opakRenk: c.surface2,
                bulaniklikAcik: !kati,
                kenar: Border.all(color: c.hairline),
                child: Semantics(
                  scopesRoute: true,
                  namesRoute: true,
                  explicitChildNodes: true,
                  label: 'Hesaplar',
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: SandikSpace.md, vertical: SandikSpace.xs),
                    child: liste,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Menüyü düğmenin altına (yer yoksa üstüne) koyar; yatayda kenar
/// paylarında tutar, dikeyde ekrana sığmazsa içerik kayar.
class _MenuYerlesimi extends SingleChildLayoutDelegate {
  _MenuYerlesimi(
      {required this.kaynak, required this.kenar, required this.ustBosluk});

  final Rect kaynak;
  final double kenar;
  final double ustBosluk;

  static const double _ara = SandikSpace.xs;

  // `SafeArea` içinde: global dikdörtgen üst güvenli alan kadar kayar.
  Rect get _yerel => kaynak.shift(Offset(0, -ustBosluk));

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final r = _yerel;
    final alt = constraints.maxHeight - r.bottom - _ara - kenar;
    final ust = r.top - _ara - kenar;
    final yukseklik = (alt >= ust ? alt : ust)
        .clamp(SandikTouch.min * 2, constraints.maxHeight);
    return BoxConstraints(
      maxWidth: (constraints.maxWidth - 2 * kenar)
          .clamp(0.0, HesapMenusu._genislik),
      maxHeight: yukseklik,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size cocuk) {
    final r = _yerel;
    final x = r.left.clamp(kenar, size.width - cocuk.width - kenar);
    final asagi = r.bottom + _ara;
    final y = asagi + cocuk.height <= size.height - kenar
        ? asagi
        : (r.top - _ara - cocuk.height).clamp(0.0, size.height);
    return Offset(x.toDouble(), y.toDouble());
  }

  @override
  bool shouldRelayout(_MenuYerlesimi eski) =>
      eski.kaynak != kaynak || eski.kenar != kenar || eski.ustBosluk != ustBosluk;
}

String hesapAdi(AppUser u) =>
    (u.username?.isNotEmpty ?? false) ? u.username! : u.displayName;

// ── Hesap listesi ────────────────────────────────────────────────────────────

Future<void> hesapSeciciniAc(BuildContext context) {
  return showSandikSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
    builder: (_) => HesapSeciciSayfasi(ustContext: context),
  );
}

/// Alt sayfanın gövdesi. Görsel önizleme ve test doğrudan kurar.
class HesapSeciciSayfasi extends ConsumerStatefulWidget {
  const HesapSeciciSayfasi({super.key, required this.ustContext});

  /// Sayfa kapandıktan sonra hata/bilgi diyaloğu bu bağlamda açılır.
  final BuildContext ustContext;

  @override
  ConsumerState<HesapSeciciSayfasi> createState() => _HesapSeciciSayfasiState();
}

class _HesapSeciciSayfasiState extends ConsumerState<HesapSeciciSayfasi> {
  bool _duzenle = false;

  @override
  Widget build(BuildContext context) {
    final aktif = ref.watch(authProvider).valueOrNull;
    final kayitli = ref.watch(kayitliHesaplarProvider);
    final digerleri = [
      for (final h in kayitli)
        if (h.uid != aktif?.id) h,
    ];
    final dolu = digerleri.length + 1 >= HesapKasasi.enCok;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.lg, SandikSpace.sm, SandikSpace.lg, SandikSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Hesaplar',
                        style: context.t.titleMedium?.copyWith(
                            color: context.c.text90,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                if (digerleri.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _duzenle = !_duzenle),
                    child: Text(_duzenle ? 'Bitti' : 'Düzenle'),
                  ),
              ],
            ),
            const SizedBox(height: SandikSpace.xs),
            if (aktif != null)
              _HesapSatiri(
                ton: 0,
                harf: KayitliHesap(
                        uid: aktif.id,
                        eposta: aktif.email,
                        ad: hesapAdi(aktif),
                        sonKullanim: DateTime.now())
                    .basHarf,
                ad: hesapAdi(aktif),
                alt: 'Bu cihazda açık',
                secili: true,
              ),
            for (final (i, h) in digerleri.indexed)
              _HesapSatiri(
                ton: i + 1,
                harf: h.basHarf,
                ad: h.ad,
                alt: h.oturumDustu
                    ? 'Tekrar giriş gerekli'
                    : 'Son açılış ${goreliZaman(h.sonKullanim, DateTime.now())}',
                uyari: h.oturumDustu,
                onTap: _duzenle ? null : (kaynak) => _gec(h, i + 1, kaynak),
                kaldir: _duzenle ? () => _kaldir(h) : null,
              ),
            Divider(color: context.c.hairline, height: SandikSpace.lg),
            if (!_duzenle)
              _EylemSatiri(
                ikon: Icons.add_rounded,
                etiket: 'Hesap ekle',
                alt: dolu
                    ? 'En fazla ${HesapKasasi.enCok} hesap'
                    : 'Mevcut hesabın açık kalır',
                onTap: dolu ? null : _ekle,
              ),
          ],
        ),
      ),
    );
  }

  void _gec(KayitliHesap h, int ton, Rect? kaynak) {
    final aktif = ref.read(authProvider).valueOrNull;
    Navigator.of(context).pop();
    hesabaGec(widget.ustContext, h, aktif: aktif, ton: ton, kaynak: kaynak);
  }

  void _ekle() {
    final aktif = ref.read(authProvider).valueOrNull;
    Navigator.of(context).pop();
    hesapEklemeyiBaslat(widget.ustContext, aktif);
  }

  Future<void> _kaldir(KayitliHesap h) async {
    final aktif = ref.read(authProvider).valueOrNull;
    await showSandikConfirm(
      context: context,
      title: '${h.ad} kaldırılsın mı?',
      message: 'Hesap bu cihazdan çıkış yapar ve listeden kalkar. '
          'Verilerin silinmez; istediğinde tekrar giriş yapabilirsin.',
      confirmLabel: 'Kaldır',
      destructive: true,
      islem: () => HesapGecisi.instance.kaldir(h.uid, aktif: aktif),
    );
  }
}

// ── Ortak geçiş ve ekleme (sayfa, menü, Ayarlar satırı) ──────────────────────

/// Kayıtlı hesaba geç. Menü/sayfa kapandıktan SONRA çağrılır; [ust] açık
/// kalan ekranın bağlamı. Mantık 7 Kas'a kadar sayfanın içindeydi; menü
/// ve sayfa aynısını kullansın diye buraya taşındı, davranış değişmedi.
Future<void> hesabaGec(BuildContext ust, KayitliHesap h,
    {required AppUser? aktif, required int ton, Rect? kaynak}) async {
  if (h.oturumDustu) {
    await _tekrarGiris(ust, h, aktif);
    return;
  }
  try {
    await HesapGecisi.instance
        .gec(h.uid, aktif: aktif, kaynak: kaynak, ton: ton);
  } on HesapOturumuDustu catch (e) {
    if (!ust.mounted) return;
    final tekrar = await showSandikConfirm(
      context: ust,
      title: 'Oturum kapanmış',
      message: '${e.hesap.ad} hesabı başka bir cihazda açıldığı ya da '
          'şifresi değiştiği için bu cihazdaki oturumu kapandı. Tekrar '
          'giriş yapınca bu hesaba geçersin.',
      confirmLabel: 'Tekrar giriş yap',
    );
    if (tekrar && ust.mounted) await _tekrarGiris(ust, e.hesap, aktif);
  } catch (e) {
    if (ust.mounted) showAppError(ust, e);
  }
}

Future<void> _tekrarGiris(
    BuildContext ust, KayitliHesap h, AppUser? aktif) async {
  if (aktif == null) return;
  HesapGecisi.instance.onerilenEposta = h.eposta;
  try {
    await HesapGecisi.instance.eklemeyiBaslat(aktif);
  } catch (e) {
    HesapGecisi.instance.onerilenEposta = null;
    if (ust.mounted) showAppError(ust, e);
  }
}

/// Hesap ekleme akışını başlat (menü, sayfa ve Ayarlar'daki "Hesap ekle").
///
/// Ekleme ücretsiz (yasin 2026-10-10 akşam: "session switch özelliği de
/// premium olmamalı"); #152'deki paywall dalı kalktı.
Future<void> hesapEklemeyiBaslat(BuildContext ust, AppUser? aktif) async {
  if (aktif == null) return;
  try {
    await HesapGecisi.instance.eklemeyiBaslat(aktif);
  } on HesapSiniriDolu {
    if (ust.mounted) {
      await showAppInfo(ust,
          title: 'Hesap sınırı',
          message:
              'Bu cihazda en fazla ${HesapKasasi.enCok} hesap açık tutulabilir. '
              'Yeni hesap eklemek için önce birini listeden kaldır.');
    }
  } catch (e) {
    if (ust.mounted) showAppError(ust, e);
  }
}

class _HesapSatiri extends StatelessWidget {
  const _HesapSatiri({
    required this.ton,
    required this.harf,
    required this.ad,
    required this.alt,
    this.secili = false,
    this.uyari = false,
    this.onTap,
    this.kaldir,
  });

  final int ton;
  final String harf;
  final String ad;
  final String alt;
  final bool secili;
  final bool uyari;

  /// Dokunulan satırın avatar dikdörtgeniyle (geçiş perdesi oradan başlar).
  final void Function(Rect? kaynak)? onTap;
  final VoidCallback? kaldir;

  static Rect? _yer(BuildContext? ctx) {
    final kutu = ctx?.findRenderObject();
    if (kutu is! RenderBox || !kutu.hasSize || !kutu.attached) return null;
    return kutu.localToGlobal(Offset.zero) & kutu.size;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    BuildContext? avatarBaglami;
    final satir = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
        child: Row(
          children: [
            Builder(builder: (ctx) {
              avatarBaglami = ctx;
              return HesapAvatari(harf: harf, ton: ton, soluk: uyari);
            }),
            const SizedBox(width: SandikSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodyLarge?.copyWith(
                          color: c.text90, fontWeight: FontWeight.w600)),
                  Text(alt,
                      style: context.t.bodySmall
                          ?.copyWith(color: uyari ? c.loss : c.text58)),
                ],
              ),
            ),
            if (secili)
              Icon(Icons.check_circle_rounded, color: c.amberText, size: 24)
            else if (kaldir != null)
              TextButton(
                onPressed: kaldir,
                style: TextButton.styleFrom(
                    foregroundColor: c.loss, minimumSize: SandikTouch.minSize),
                child: const Text('Kaldır'),
              )
            else
              Icon(Icons.chevron_right_rounded, color: c.text36, size: 22),
          ],
        ),
      ),
    );
    return Semantics(
      selected: secili,
      button: onTap != null,
      label: '$ad, $alt',
      excludeSemantics: kaldir == null,
      child: onTap == null
          ? satir
          : SandikTappable(
              onTap: () => onTap!(_yer(avatarBaglami)), child: satir),
    );
  }
}

class _EylemSatiri extends StatelessWidget {
  const _EylemSatiri({
    required this.ikon,
    required this.etiket,
    required this.alt,
    required this.onTap,
  });

  final IconData ikon;
  final String etiket;
  final String alt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pasif = onTap == null;
    return Semantics(
      button: true,
      enabled: !pasif,
      label: '$etiket, $alt',
      excludeSemantics: true,
      child: SandikTappable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.text36, width: 1.5),
                ),
                child: Icon(ikon, color: pasif ? c.text36 : c.text90, size: 22),
              ),
              const SizedBox(width: SandikSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(etiket,
                        style: context.t.bodyLarge?.copyWith(
                            color: pasif ? c.text36 : c.text90,
                            fontWeight: FontWeight.w600)),
                    Text(alt,
                        style: context.t.bodySmall?.copyWith(color: c.text58)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "dün", "3 gün önce", "az önce" — seçicideki son açılış. Saf.
String goreliZaman(DateTime t, DateTime simdi) {
  final fark = simdi.difference(t);
  if (fark.inMinutes < 1) return 'az önce';
  if (fark.inHours < 1) return '${fark.inMinutes} dk önce';
  final gunFarki = dayKey(simdi).difference(dayKey(t)).inDays;
  if (gunFarki == 0) return 'bugün';
  if (gunFarki == 1) return 'dün';
  if (gunFarki < 7) return '$gunFarki gün önce';
  if (gunFarki < 30) return '${gunFarki ~/ 7} hafta önce';
  return '${gunFarki ~/ 30} ay önce';
}

// ── Çıkış ────────────────────────────────────────────────────────────────────

enum CokluCikis { buHesap, tumu }

/// Birden fazla hesap varken çıkış sorusu. `null` = vazgeçildi.
Future<CokluCikis?> cokluCikisSor(
    BuildContext context, String ad, int hesapSayisi) {
  return showSandikSheet<CokluCikis>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
    builder: (ctx) => CokluCikisSayfasi(ad: ad, hesapSayisi: hesapSayisi),
  );
}

class CokluCikisSayfasi extends StatelessWidget {
  const CokluCikisSayfasi(
      {super.key, required this.ad, required this.hesapSayisi});

  final String ad;
  final int hesapSayisi;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.lg, SandikSpace.sm, SandikSpace.lg, SandikSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Çıkış yap',
                  textAlign: TextAlign.center,
                  style: context.t.titleMedium
                      ?.copyWith(color: c.text90, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: SandikSpace.xs),
            Text('Bu cihazda $hesapSayisi hesap açık.',
                textAlign: TextAlign.center,
                style: context.t.bodyMedium?.copyWith(color: c.text58)),
            const SizedBox(height: SandikSpace.lg),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(CokluCikis.buHesap),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.loss,
                side: BorderSide(color: c.loss.withValues(alpha: 0.5)),
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text('$ad hesabından çık'),
            ),
            const SizedBox(height: SandikSpace.sm),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(CokluCikis.tumu),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: const Text('Tüm hesaplardan çık'),
            ),
            const SizedBox(height: SandikSpace.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                  foregroundColor: c.text58,
                  minimumSize: const Size.fromHeight(SandikTouch.min)),
              child: const Text('Vazgeç'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Çıkış düğmesinin çoklu hesap yolu. `false` = bu yol uygulanmadı
/// (tek hesap ya da bayrak kapalı) — çağıran bugünkü onay sorusunu sorar.
Future<bool> cokluHesapCikisi(BuildContext context, WidgetRef ref) async {
  if (!ref.read(cokluHesapGorunurProvider)) return false;
  final aktif = ref.read(authProvider).valueOrNull;
  if (aktif == null) return false;
  final digerleri =
      ref.read(kayitliHesaplarProvider).where((h) => h.uid != aktif.id).length;
  if (digerleri == 0) return false;
  final secim = await cokluCikisSor(context, hesapAdi(aktif), digerleri + 1);
  if (secim == null) return true;
  final gecis = HesapGecisi.instance;
  gecis.perde.value = const HesapGecisPerdesi(
      basHarf: '·', ad: 'Çıkış yapılıyor', alt: 'birkaç saniye sürebilir');
  try {
    if (secim == CokluCikis.tumu) {
      await gecis.digerlerindenCik(aktif.id);
      await ref.read(authProvider.notifier).logout();
      gecis.perde.value = null;
      return true;
    }
    await ref.read(authProvider.notifier).logout();
    final gecti = await gecis.cikistanSonraSiradakine(aktif.id);
    if (!gecti) gecis.perde.value = null;
  } catch (e) {
    gecis.perde.value = null;
    rethrow;
  }
  return true;
}

// ── Giriş ekranı ─────────────────────────────────────────────────────────────

/// Giriş ekranında "Bu cihazdaki hesaplar". Hesap eklerken en üstte
/// "Vazgeç, X hesabına dön" durur; çıkıştan sonra kalan hesaplar tek
/// dokunuşla açılır. Bayrak kapalıyken ya da kasa boşken hiçbir şey çizmez.
class CihazdakiHesaplar extends ConsumerWidget {
  const CihazdakiHesaplar({super.key, required this.epostaSec});

  /// Oturumu düşmüş hesaba dokunulunca e-posta forma yazılır.
  final ValueChanged<String> epostaSec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!HesapGecisi.instance.acik) return const SizedBox.shrink();
    final hesaplar = ref.watch(kayitliHesaplarProvider);
    return ValueListenableBuilder<KayitliHesap?>(
      valueListenable: HesapGecisi.instance.eklemedenDonulecek,
      builder: (context, donulecek, _) {
        if (hesaplar.isEmpty && donulecek == null) {
          return const SizedBox.shrink();
        }
        final c = context.c;
        return Padding(
          padding: const EdgeInsets.only(bottom: SandikSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (donulecek != null) ...[
                Container(
                  padding: const EdgeInsets.all(SandikSpace.md),
                  decoration: BoxDecoration(
                    color: c.amberFill.withValues(alpha: 0.14),
                    borderRadius: SandikRadius.mdAll,
                  ),
                  child: Text(
                    context.l10n.cihazHesapAcikKalir(donulecek.ad),
                    style: context.t.bodySmall?.copyWith(color: c.amberText),
                  ),
                ),
                const SizedBox(height: SandikSpace.sm),
              ],
              Semantics(
                header: true,
                child: Text(context.l10n.cihazHesaplari,
                    style: context.t.labelLarge?.copyWith(color: c.text58)),
              ),
              const SizedBox(height: SandikSpace.xs),
              for (final (i, h) in hesaplar.indexed)
                _HesapSatiri(
                  ton: i,
                  harf: h.basHarf,
                  ad: h.ad,
                  alt: h.oturumDustu
                      ? context.l10n.cihazHesapTekrarGiris(h.eposta)
                      : h.uid == donulecek?.uid
                          ? context.l10n.cihazHesapGeriDon
                          : context.l10n.cihazHesapDevamEt,
                  uyari: h.oturumDustu,
                  onTap: (kaynak) async {
                    if (h.oturumDustu) {
                      epostaSec(h.eposta);
                      return;
                    }
                    try {
                      await HesapGecisi.instance
                          .gec(h.uid, kaynak: kaynak, ton: i);
                    } on HesapOturumuDustu {
                      epostaSec(h.eposta);
                    } catch (e) {
                      if (context.mounted) showAppError(context, e);
                    }
                  },
                ),
              Divider(color: c.hairline, height: SandikSpace.lg),
              Text(context.l10n.cihazHesapBaskaHesapla,
                  textAlign: TextAlign.center,
                  style: context.t.bodySmall?.copyWith(color: c.text36)),
            ],
          ),
        );
      },
    );
  }
}

/// Profil sekmesine uzun basma — aynı listeyi açar (navbar görünüşü
/// değişmez). Görünür değilse no-op.
void profilSekmesiUzunBasildi(BuildContext context, WidgetRef ref) {
  if (!ref.read(cokluHesapGorunurProvider)) return;
  SandikHaptic.medium.perform();
  hesapSeciciniAc(context);
}
