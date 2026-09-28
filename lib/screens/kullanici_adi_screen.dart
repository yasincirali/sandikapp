import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  Timer? _bekleme;

  /// Son sunucu yanıtı ve hangi metin için alındığı — eski yanıt yeni
  /// metnin üstüne yazılmasın.
  KullaniciAdiSonuc? _sonuc;
  String? _sonucMetni;
  bool _soruluyor = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).valueOrNull;
    // Değiştirmede mevcut ad; zorunlu ekranda görünen addan öneri
    // ("Yasin Dirali" → "Yasin.Dirali"). Öneri de denetimden geçer.
    final baslangic = user?.username ?? KullaniciAdi.oneri(user?.displayName ?? '');
    _ctrl.text = baslangic;
    _ctrl.addListener(_degisti);
    if (baslangic.isNotEmpty && baslangic != user?.username) _sor(baslangic);
  }

  @override
  void dispose() {
    _bekleme?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  String get _metin => _ctrl.text.trim();

  bool get _mevcutAd {
    final u = ref.read(authProvider).valueOrNull?.username;
    return u != null && u == _metin;
  }

  void _degisti() {
    _bekleme?.cancel();
    setState(() {});
    final m = _metin;
    if (m.isEmpty || KullaniciAdi.bicimDenetle(m) != null || _mevcutAd) return;
    _bekleme = Timer(const Duration(milliseconds: 450),
        () => _sor(m));
  }

  Future<void> _sor(String m) async {
    setState(() => _soruluyor = true);
    try {
      final s = await SupabaseService.instance.kullaniciAdiUygunMu(m);
      if (!mounted || m != _metin) return;
      setState(() {
        _sonuc = s;
        _sonucMetni = m;
      });
    } catch (_) {
      // Anlık kontrol ağda kaldıysa sessiz: kayıt yine sunucuya sorar.
    } finally {
      if (mounted) setState(() => _soruluyor = false);
    }
  }

  String _hataMetni(KullaniciAdiSonuc s) => switch (s) {
        KullaniciAdiSonuc.bicim => context.l10n.kullaniciAdiHataBicim,
        KullaniciAdiSonuc.uygunsuz => context.l10n.kullaniciAdiHataUygunsuz,
        KullaniciAdiSonuc.ayrilmis => context.l10n.kullaniciAdiHataAyrilmis,
        KullaniciAdiSonuc.alinmis => context.l10n.kullaniciAdiHataAlinmis,
        KullaniciAdiSonuc.bilinmiyor ||
        KullaniciAdiSonuc.uygun =>
          context.l10n.kullaniciAdiHataBilinmiyor,
      };

  /// Alanın altındaki satır: biçim hatası anında, sunucu yanıtı yalnız
  /// o anki metne aitse.
  ({String metin, bool hata})? _durum() {
    final m = _metin;
    if (m.isEmpty) return null;
    if (KullaniciAdi.bicimDenetle(m) != null) {
      return (metin: context.l10n.kullaniciAdiHataBicim, hata: true);
    }
    if (_mevcutAd || _sonucMetni != m || _sonuc == null) return null;
    if (_sonuc == KullaniciAdiSonuc.uygun) {
      return (metin: context.l10n.kullaniciAdiUygun, hata: false);
    }
    return (metin: _hataMetni(_sonuc!), hata: true);
  }

  bool get _kaydedilebilir {
    final m = _metin;
    if (KullaniciAdi.bicimDenetle(m) != null || _mevcutAd) return false;
    // Bu metin için sunucu zaten "hayır" dediyse düğme pasif.
    return !(_sonucMetni == m &&
        _sonuc != null &&
        _sonuc != KullaniciAdiSonuc.uygun);
  }

  Future<void> _kaydet() async {
    final m = _metin;
    FocusScope.of(context).unfocus();
    try {
      final s = await ref.read(authProvider.notifier).kullaniciAdiKaydet(m);
      if (!mounted) return;
      if (s == KullaniciAdiSonuc.uygun) {
        if (!widget.zorunlu) {
          sandikSnack(context, context.l10n.kullaniciAdiKaydedildi,
              kind: SandikSnackKind.success);
          Navigator.of(context).maybePop();
        }
        return;
      }
      setState(() {
        _sonuc = s;
        _sonucMetni = m;
      });
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final durum = _durum();
    final alan = TextField(
      controller: _ctrl,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
      maxLength: KullaniciAdi.enUzun,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.newUsername],
      onSubmitted: (_) {
        if (_kaydedilebilir) _kaydet();
      },
      style: context.t.bodyLarge?.copyWith(color: context.c.text90),
      decoration: context
          .inputDecoration(
            '',
            labelText: context.l10n.kullaniciAdiEtiket,
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md2),
              child: Icon(Icons.alternate_email_rounded,
                  color: context.c.text36, size: 20),
            ),
            suffixIcon: _soruluyor
                ? const Padding(
                    padding: EdgeInsets.all(SandikSpace.md2),
                    child: CustomLoadingIndicator(size: 16),
                  )
                : null,
          )
          .copyWith(counterText: ''),
    );

    final govde = ListView(
      padding: EdgeInsets.symmetric(
        horizontal: SandikSpace.screenH(context),
        vertical: SandikSpace.lg,
      ),
      children: [
        if (widget.zorunlu) ...[
          Text(
            context.l10n.kullaniciAdiBaslik,
            style: context.t.headlineMedium?.copyWith(color: context.c.text90),
          ),
          const SizedBox(height: SandikSpace.sm),
        ],
        Text(
          context.l10n.kullaniciAdiAciklama,
          style: context.t.bodyMedium?.copyWith(color: context.c.text58),
        ),
        const SizedBox(height: SandikSpace.lg),
        alan,
        const SizedBox(height: SandikSpace.sm),
        Text(
          durum?.metin ?? context.l10n.kullaniciAdiKurallar,
          style: context.t.bodySmall?.copyWith(
            color: durum == null
                ? context.c.text36
                : (durum.hata ? context.c.loss : context.c.gain),
          ),
        ),
        const SizedBox(height: SandikSpace.lg),
        SandikAsyncButton(
          onPressed: _kaydedilebilir ? _kaydet : null,
          child: Text(widget.zorunlu
              ? context.l10n.kullaniciAdiDevam
              : context.l10n.kullaniciAdiKaydet),
        ),
        if (widget.zorunlu) ...[
          const SizedBox(height: SandikSpace.md),
          Center(
            child: TextButton(
              onPressed: () => ref.read(authProvider.notifier).logout(),
              child: Text(
                context.l10n.kullaniciAdiCikis,
                style: context.t.bodyMedium?.copyWith(color: context.c.text36),
              ),
            ),
          ),
        ],
      ],
    );

    return PopScope(
      canPop: !widget.zorunlu,
      child: Scaffold(
        backgroundColor: context.c.background,
        appBar: widget.zorunlu
            ? null
            : SandikAppBar(title: context.l10n.kullaniciAdiEtiket),
        body: widget.zorunlu ? SafeArea(child: govde) : govde,
      ),
    );
  }
}
