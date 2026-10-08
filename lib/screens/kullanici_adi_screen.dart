import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/analytics_service.dart';
import '../services/crash_reporter.dart';
import '../services/kullanici_adi_denetimi.dart';

import '../l10n/l10n.dart';
import '../models/kullanici_adi.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_async_button.dart';

/// Kullanıcı adı seçme / değiştirme (2026-09-28, 0079).
///
/// İki kullanım:
/// - [zorunlu] — giriş kapısı (`main.dart` `_resolveScreen`). Adı olmayan
///   her hesap (Apple/Google ile yeni kayıt ve güncelleme öncesinden kalan
///   mevcut kullanıcılar) buradan geçmeden uygulamaya giremez. Geri yok;
///   tek çıkış "Çıkış yap" — başka hesapla girmek isteyen kilitli kalmasın.
///   Kayıt başarılı olunca `authProvider` yeni adı taşır ve kapı kendiliğinden
///   kapanır; bu ekran kendini kapatmaz.
/// - Ayarlar > Hesap — aynı ekran, geri oku ile; kayıtta kapanır.
///
/// Karar sunucuda (`kullanici_adi_denetle`): burada biçim anında, uygunluk
/// ve benzersizlik kısa bir beklemeyle sorulur ki kullanıcı "Kaydet"e
/// basmadan "alınmış"ı görsün. Kayıtta sunucu yine son sözü söyler
/// (iki kişi aynı anda aynı adı seçerse indeks birini reddeder).
class KullaniciAdiScreen extends ConsumerStatefulWidget {
  const KullaniciAdiScreen({super.key, this.zorunlu = false});

  final bool zorunlu;

  @override
  ConsumerState<KullaniciAdiScreen> createState() => _KullaniciAdiScreenState();
}

class _KullaniciAdiScreenState extends ConsumerState<KullaniciAdiScreen> {
  final _ctrl = TextEditingController();

  /// Gecikme, eskime ve "kaydedilebilir mi" mantığı kayıt formuyla ortak
  /// (`KullaniciAdiDenetimi`, 2026-09-28); bu ekran yalnız okur.
  late final KullaniciAdiDenetimi _denetim;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).valueOrNull;
    _denetim = KullaniciAdiDenetimi(
      sor: SupabaseService.instance.kullaniciAdiUygunMu,
      mevcutAd: user?.username,
    )..addListener(_yenile);
    // Değiştirmede mevcut ad; zorunlu ekranda görünen addan öneri
    // ("Yasin Dirali" → "Yasin.Dirali"). Öneri de denetimden geçer —
    // gecikmesiz, çünkü kullanıcı henüz yazmadı.
    final baslangic = user?.username ?? KullaniciAdi.oneri(user?.displayName ?? '');
    _ctrl.text = baslangic;
    _ctrl.addListener(() => _denetim.metinDegisti(_ctrl.text));
    _denetim.metinDegisti(baslangic,
        hemen: baslangic.isNotEmpty && baslangic != user?.username);
  }

  void _yenile() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _denetim.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String get _metin => _ctrl.text.trim();

  String _hataMetni(KullaniciAdiSonuc s) => switch (s) {
        KullaniciAdiSonuc.bicim => context.l10n.kullaniciAdiHataBicim,
        KullaniciAdiSonuc.uygunsuz => context.l10n.kullaniciAdiHataUygunsuz,
        KullaniciAdiSonuc.ayrilmis => context.l10n.kullaniciAdiHataAyrilmis,
        KullaniciAdiSonuc.alinmis => context.l10n.kullaniciAdiHataAlinmis,
        KullaniciAdiSonuc.bilinmiyor ||
        KullaniciAdiSonuc.uygun =>
          context.l10n.kullaniciAdiHataBilinmiyor,
      };

  Future<void> _kaydet() async {
    final m = _metin;
    // `await`'ten ÖNCE okunur: zorunlu ekranda kayıt başarılı olunca kapı
    // bu ekranı ağaçtan söker; olay `mounted` denetiminden önce gitmeli.
    final zorunlu = widget.zorunlu;
    FocusScope.of(context).unfocus();
    try {
      final s = await ref.read(authProvider.notifier).kullaniciAdiKaydet(m);
      // Kayıt hunisi (F11) — yalnız giriş kapısındaki ad adımı; Ayarlar'dan
      // ad değiştirmek huninin parçası değil.
      if (zorunlu && s == KullaniciAdiSonuc.uygun) {
        unawaited(AnalyticsService.instance.logSignupStep('username_set'));
      }
      if (!mounted) return;
      if (s == KullaniciAdiSonuc.uygun) {
        if (!widget.zorunlu) {
          sandikSnack(context, context.l10n.kullaniciAdiKaydedildi,
              kind: SandikSnackKind.success);
          // Sayfa kapanışı beklenmez; `arkaPlan` lint'i susturmakla kalmaz,
          // olası hatayı non-fatal kaydeder (`arka_plan_hata_yutma_test`).
          CrashReporter.arkaPlan(Navigator.of(context).maybePop(),
              reason: 'KullaniciAdiScreen.maybePop');
        }
        return;
      }
      _denetim.sonucYaz(m, s);
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final durum = _denetim.durum;
    final zorunlu = widget.zorunlu;

    // Alan: metin ortalı ve büyük — ekranın tek işi bu ad. "@" alanın
    // içinde değil, üstteki amblemde: prefix ortalamayı kaydırıyordu.
    final alan = TextField(
      controller: _ctrl,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
      maxLength: KullaniciAdi.enUzun,
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.newUsername],
      onSubmitted: (_) {
        if (_denetim.kaydedilebilir) _kaydet();
      },
      style: context.t.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: context.c.text90,
      ),
      decoration: context
          .inputDecoration(
            context.l10n.kullaniciAdiEtiket,
            suffixIcon: _denetim.soruluyor
                ? const Padding(
                    padding: EdgeInsets.all(SandikSpace.md2),
                    child: CustomLoadingIndicator(size: 16),
                  )
                : null,
          )
          .copyWith(
            counterText: '',
            // Sağdaki yükleniyor göstergesi ortalamayı bozmasın: aynı
            // genişlikte görünmez bir sol boşluk.
            prefixIcon:
                _denetim.soruluyor ? const SizedBox(width: SandikTouch.min) : null,
          ),
    );

    // Durum satırı: kural → biçim hatası → sunucu yanıtı. "Uygun" yanıtı
    // zorunlu ekranda "devam edebilirsin" der — kullanıcı kapının o an
    // açıldığını buradan ve aktifleşen düğmeden anlar (kullanıcı isteği
    // 2026-09-28: "belirleyince hemen geçebileceğini bilmeli").
    final String durumMetni;
    final Color durumRengi;
    IconData? durumIkon;
    if (durum == null) {
      durumMetni = context.l10n.kullaniciAdiKurallar;
      durumRengi = context.c.text36;
    } else if (durum != KullaniciAdiSonuc.uygun) {
      durumMetni = durum == KullaniciAdiSonuc.bicim
          ? context.l10n.kullaniciAdiHataBicim
          : _hataMetni(durum);
      durumRengi = context.c.loss;
      durumIkon = Icons.error_outline_rounded;
    } else {
      durumMetni = zorunlu
          ? context.l10n.kullaniciAdiUygunDevam
          : context.l10n.kullaniciAdiUygun;
      durumRengi = context.c.gain;
      durumIkon = Icons.check_circle_rounded;
    }

    final icerik = ConstrainedBox(
      // Tablet/masaüstünde alan ekran boyu uzamasın; 420pt bir form
      // sütunu için rahat okunur genişlik.
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Amblem: ekranın odağı. Marka amberi dolgu değil, saydam halka;
          // amberText ikon (zemin olarak amberText yasağı — ratchet).
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.c.amberFill.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.alternate_email_rounded,
                  size: 34, color: context.c.amberText),
            ),
          ),
          const SizedBox(height: SandikSpace.lg),
          if (zorunlu) ...[
            Text(
              context.l10n.kullaniciAdiBaslik,
              textAlign: TextAlign.center,
              style: context.t.headlineMedium?.copyWith(color: context.c.text90),
            ),
            const SizedBox(height: SandikSpace.sm),
          ],
          Text(
            context.l10n.kullaniciAdiAciklama,
            textAlign: TextAlign.center,
            style: context.t.bodyMedium?.copyWith(color: context.c.text58),
          ),
          if (zorunlu) ...[
            const SizedBox(height: SandikSpace.sm),
            // Kapı kuralı açık yazılır: adsız geçiş yok, ad seçilince
            // bekleme yok.
            Text(
              context.l10n.kullaniciAdiZorunluNot,
              textAlign: TextAlign.center,
              style: context.t.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.c.text90,
              ),
            ),
          ],
          const SizedBox(height: SandikSpace.xl),
          alan,
          const SizedBox(height: SandikSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (durumIkon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: SandikSpace.xxs),
                  child: Icon(durumIkon, size: 14, color: durumRengi),
                ),
                const SizedBox(width: SandikSpace.xs),
              ],
              Flexible(
                child: Text(
                  durumMetni,
                  textAlign: TextAlign.center,
                  style: context.t.bodySmall?.copyWith(color: durumRengi),
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.lg),
          SandikAsyncButton(
            onPressed: _denetim.kaydedilebilir ? _kaydet : null,
            child: Text(zorunlu
                ? context.l10n.kullaniciAdiDevam
                : context.l10n.kullaniciAdiKaydet),
          ),
        ],
      ),
    );

    // Dikeyde ortalı; klavye açılınca görünür alan küçülür, blok yine
    // ortada kalır ve sığmazsa kayar (minHeight = görünür yükseklik).
    // "Çıkış yap" ortalanan bloğa DAHİL DEĞİL: alt kenara sabit, ikincil.
    final hp = SandikSpace.screenH(context);
    final govde = Column(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            return SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(
                  horizontal: hp, vertical: SandikSpace.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight: c.maxHeight - 2 * SandikSpace.lg),
                child: Center(child: icerik),
              ),
            );
          }),
        ),
        if (zorunlu)
          Padding(
            padding: EdgeInsets.fromLTRB(hp, 0, hp, SandikSpace.sm),
            // Çıkış istek atar: tek yükleniyor davranışı (2026-10-08).
            child: SandikAsyncButton.kompakt(
              tur: SandikAsyncTur.metin,
              onPressed: () => ref.read(authProvider.notifier).logout(),
              child: Text(
                context.l10n.kullaniciAdiCikis,
                style: context.t.bodyMedium?.copyWith(color: context.c.text36),
              ),
            ),
          ),
      ],
    );

    return PopScope(
      canPop: !zorunlu,
      child: Scaffold(
        backgroundColor: context.c.background,
        appBar: zorunlu
            ? null
            : SandikAppBar(title: context.l10n.kullaniciAdiEtiket),
        body: zorunlu ? SafeArea(child: govde) : govde,
      ),
    );
  }
}
