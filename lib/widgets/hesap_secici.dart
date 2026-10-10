import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/hesap_provider.dart';
import '../screens/paywall_screen.dart';
import '../services/hesap_gecisi.dart';
import '../services/hesap_kasasi.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/tr_format.dart' show dayKey;
import 'uygulama_kabugu.dart' show HesapAvatari;

/// Çoklu hesap arayüzü (bayrak `coklu_hesap`, 2026-10-10).
///
/// Giriş noktası Profil'in üst çubuğu: "Profil" başlığının yerinde aktif
/// hesabın adı ve küçük bir ok (Instagram'ın yerleşimi). Alt gezinme çubuğu
/// değişmez (kullanıcı kuralı). Çıkış düğmesi yerinde kalır; birden fazla
/// hesap varken iki seçenek sorar ([cokluCikisSor]).
///
/// HIG: her satır ≥ 44 pt, ad ve durum metni Dynamic Type ile büyür
/// (sabit yükseklik yok), seçili hesap yalnız renkle değil onay işaretiyle
/// ve ekran okuyucuda "seçili" ile ayrılır, yıkıcı eylem (kaldır) onay ister.

// ── Profil başlığı ───────────────────────────────────────────────────────────

/// Profil üst çubuğundaki başlık: aktif hesabın adı + ok. Dokununca hesap
/// listesi açılır.
class HesapBasligi extends ConsumerWidget {
  const HesapBasligi({super.key, required this.stil});

  final TextStyle? stil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final ad = user == null ? 'Profil' : hesapAdi(user);
    return Semantics(
      button: true,
      label: '$ad, hesap değiştir',
      excludeSemantics: true,
      child: SandikTappable(
        onTap: () => hesapSeciciniAc(context, ref),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  ad,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: stil,
                ),
              ),
              const SizedBox(width: SandikSpace.xs),
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: context.c.text58, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

String hesapAdi(AppUser u) =>
    (u.username?.isNotEmpty ?? false) ? u.username! : u.displayName;

// ── Hesap listesi ────────────────────────────────────────────────────────────

Future<void> hesapSeciciniAc(BuildContext context, WidgetRef ref) {
  return showSandikSheet<void>(
    context: context,
    backgroundColor: context.c.surface2,
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
  ConsumerState<HesapSeciciSayfasi> createState() =>
      _HesapSeciciSayfasiState();
}

class _HesapSeciciSayfasiState extends ConsumerState<HesapSeciciSayfasi> {
  bool _duzenle = false;

  @override
  Widget build(BuildContext context) {
    final aktif = ref.watch(authProvider).valueOrNull;
    final kayitli = ref.watch(kayitliHesaplarProvider);
    final kilitli = ref.watch(hesapEklemeKilitliProvider);
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
            const Center(child: SandikTutamac()),
            const SizedBox(height: SandikSpace.sm),
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
                onTap: _duzenle ? null : () => _gec(h),
                kaldir: _duzenle ? () => _kaldir(h) : null,
              ),
            Divider(color: context.c.hairline, height: SandikSpace.lg),
            if (!_duzenle)
              _EylemSatiri(
                ikon: kilitli ? Icons.lock_outline_rounded : Icons.add_rounded,
                etiket: 'Hesap ekle',
                alt: dolu
                    ? 'En fazla ${HesapKasasi.enCok} hesap'
                    : kilitli
                        ? 'Premium ile'
                        : 'Mevcut hesabın açık kalır',
                onTap: dolu ? null : () => _ekle(kilitli),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _gec(KayitliHesap h) async {
    final aktif = ref.read(authProvider).valueOrNull;
    final ust = widget.ustContext;
    Navigator.of(context).pop();
    if (h.oturumDustu) {
      await _tekrarGiris(ust, h, aktif);
      return;
    }
    try {
      await HesapGecisi.instance.gec(h.uid, aktif: aktif);
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

  Future<void> _ekle(bool kilitli) async {
    final aktif = ref.read(authProvider).valueOrNull;
    final ust = widget.ustContext;
    Navigator.of(context).pop();
    if (kilitli) {
      await PaywallScreen.show(ust, source: 'coklu_hesap');
      return;
    }
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
  final VoidCallback? onTap;
  final VoidCallback? kaldir;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final satir = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
        child: Row(
          children: [
            HesapAvatari(harf: harf, ton: ton, soluk: uyari),
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
                    foregroundColor: c.loss,
                    minimumSize: SandikTouch.minSize),
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
      child: onTap == null ? satir : SandikTappable(onTap: onTap, child: satir),
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
                child: Icon(ikon,
                    color: pasif ? c.text36 : c.text90, size: 22),
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
                        style:
                            context.t.bodySmall?.copyWith(color: c.text58)),
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
    backgroundColor: context.c.surface2,
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
            const Center(child: SandikTutamac()),
            const SizedBox(height: SandikSpace.md),
            Semantics(
              header: true,
              child: Text('Çıkış yap',
                  textAlign: TextAlign.center,
                  style: context.t.titleMedium?.copyWith(
                      color: c.text90, fontWeight: FontWeight.w700)),
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
  final digerleri = ref
      .read(kayitliHesaplarProvider)
      .where((h) => h.uid != aktif.id)
      .length;
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
                    style:
                        context.t.bodySmall?.copyWith(color: c.amberText),
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
                  onTap: () async {
                    if (h.oturumDustu) {
                      epostaSec(h.eposta);
                      return;
                    }
                    try {
                      await HesapGecisi.instance.gec(h.uid);
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
  hesapSeciciniAc(context, ref);
}
