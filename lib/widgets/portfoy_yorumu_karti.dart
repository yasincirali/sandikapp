import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/portfoy_yorumu_provider.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../services/portfoy_yorumu_service.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart' show showSandikConfirm;
import 'para_akisi_karti.dart' show KilitSatiri;
import 'sandik_async_button.dart';
import 'sandik_segment.dart';
import 'sandik_skeleton.dart';

/// Performans › Özet: kişiye özel AI portföy yorumu (0145, 2026-10-13).
///
/// Tasarım: https://claude.ai/artifact/DMeJXyFCGt2Ff4vjUgRb6z (yasin 12 Eki:
/// "seyrek periyotlar halinde özet sayfasında yapalım", "yatırım tavsiyesi
/// değildiri belirtelim").
///
/// - Yalnız GEÇEN HAFTA ve GEÇEN AY (kapanmış takvim dönemi). Günlük ve kayan
///   aralıklar yorumlanmaz.
/// - Yorum kaydedilir; kart açıldıkça tablodan okunur, model çağrılmaz.
///   Yalnız kullanıcı "Bu dönemi yorumla"ya basınca istek gider.
/// - "Yatırım tavsiyesi değildir" uyarısı kartın altında SABİT; modele
///   yazdırılmaz (`_shared/portfoy_yorum.ts`).
/// - İlk kullanımda açık rıza sayfası (Zirve'deki gibi, isteğe bağlı).
///
/// Bayrak `portfoy_ai_yorumu` kapalıyken [gorunur] false: kart ağaca hiç
/// girmez, istek atılmaz.
class PortfoyYorumuKarti extends ConsumerStatefulWidget {
  const PortfoyYorumuKarti({super.key});

  static bool get gorunur => RemoteConfigService.instance.portfoyAiYorumu;

  @override
  ConsumerState<PortfoyYorumuKarti> createState() => _PortfoyYorumuKartiState();
}

class _PortfoyYorumuKartiState extends ConsumerState<PortfoyYorumuKarti> {
  YorumTuru _tur = YorumTuru.haftalik;
  String? _hata;

  String _hataMetni(YorumHataTuru t) {
    final l = context.l10n;
    return switch (t) {
      YorumHataTuru.kota => l.pyzHataKota,
      YorumHataTuru.reddedildi => l.pyzHataRed,
      YorumHataTuru.kapali => l.pyzHataKapali,
      YorumHataTuru.premium => l.pyzKilit,
      _ => l.pyzHataGenel,
    };
  }

  Future<void> _yorumla(PortfoyYorumPaketi paket) async {
    setState(() => _hata = null);
    final riza = await ref.read(portfoyYorumRizaProvider.future);
    if (riza != true) {
      if (!mounted) return;
      final kabul = await _rizaSor();
      if (kabul != true) return;
      try {
        await PortfoyYorumuService.instance.rizaAyarla(true);
      } catch (_) {
        if (mounted) setState(() => _hata = context.l10n.pyzHataGenel);
        return;
      }
      ref.invalidate(portfoyYorumRizaProvider);
    }
    try {
      await PortfoyYorumuService.instance.yorumla(paket);
      ref.invalidate(portfoyYorumuProvider(_tur));
    } on PortfoyYorumHatasi catch (e) {
      if (mounted) setState(() => _hata = _hataMetni(e.tur));
    } catch (_) {
      if (mounted) setState(() => _hata = context.l10n.pyzHataGenel);
    }
  }

  Future<bool?> _rizaSor() => showSandikSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => const _RizaSayfasi(),
      );

  Future<void> _kapat() async {
    final l = context.l10n;
    final ok = await showSandikConfirm(
      context: context,
      title: l.pyzKapat,
      message: l.pyzKapatOnay,
      confirmLabel: l.pyzKapat,
      cancelLabel: l.pyzSimdiDegil,
      destructive: true,
      islem: () => PortfoyYorumuService.instance.rizaAyarla(false),
    );
    if (!ok) return;
    ref.invalidate(portfoyYorumRizaProvider);
    ref.invalidate(portfoyYorumuProvider(YorumTuru.haftalik));
    ref.invalidate(portfoyYorumuProvider(YorumTuru.aylik));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    final kilitli = ref.watch(premiumKilitliProvider);
    final durum = ref.watch(portfoyYorumuProvider(_tur));
    final riza = ref.watch(portfoyYorumRizaProvider).valueOrNull;
    final yer = Localizations.localeOf(context).toString();
    final gunAy = DateFormat('d MMM', yer);

    Widget govde;
    if (kilitli) {
      govde = KilitSatiri(metin: l.pyzKilit, kaynak: 'portfoy_yorumu');
    } else {
      govde = durum.when(
        loading: () => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SandikSkeleton(height: 16),
            SizedBox(height: SandikSpace.sm),
            SandikSkeleton(width: 220),
          ],
        ),
        error: (_, __) =>
            Text(l.pyzHataGenel, style: t.bodySmall?.copyWith(color: c.text58)),
        data: (d) {
          if (d == null || !d.paket.yeterli) {
            return Text(l.pyzVeriYok,
                style: t.bodySmall?.copyWith(color: c.text58));
          }
          final donemAdi =
              _tur == YorumTuru.haftalik ? l.pyzGecenHafta : l.pyzGecenAy;
          final aralik = l.flowRange(
              gunAy.format(d.paket.baslangic), gunAy.format(d.paket.bitis));
          final kayit = d.kayit;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (kayit == null) ...[
                Text(l.pyzAciklama('$donemAdi ($aralik)'),
                    style: t.bodyMedium?.copyWith(color: c.text58)),
                const SizedBox(height: SandikSpace.md),
                SandikAsyncButton.kompakt(
                  onPressed: () => _yorumla(d.paket),
                  child: Text(l.pyzYorumla),
                ),
              ] else ...[
                _Yorum(yorum: kayit, gunAy: gunAy),
                const SizedBox(height: SandikSpace.sm),
                Text(
                  l.pyzMeta(gunAy.format(kayit.olusturuldu),
                      gunAy.format(_siradaki(_tur, d.paket.bitis))),
                  style: t.bodySmall?.copyWith(color: c.text36),
                ),
                if (!d.guncel) ...[
                  const SizedBox(height: SandikSpace.md),
                  Text(l.pyzEskidi,
                      style: t.bodySmall?.copyWith(color: c.text58)),
                  const SizedBox(height: SandikSpace.sm),
                  SandikAsyncButton.kompakt(
                    tur: SandikAsyncTur.cerceve,
                    onPressed: () => _yorumla(d.paket),
                    child: Text(l.pyzYeniden),
                  ),
                ],
              ],
            ],
          );
        },
      );
    }

    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: SandikSpace.md, color: c.amberText),
              const SizedBox(width: SandikSpace.xs),
              Expanded(
                child: Text(l.pyzBaslik,
                    style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: c.text90)),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.sm),
          Semantics(
            container: true,
            label: l.pyzDonemSecici,
            child: SandikSegment(
              adet: 2,
              secili: _tur.index,
              yukseklik: SandikTouch.min,
              onSec: (i) => setState(() {
                _tur = YorumTuru.values[i];
                _hata = null;
              }),
              oge: (_, i, __) => Text(
                i == 0 ? l.pyzGecenHafta : l.pyzGecenAy,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.md),
          AnimatedSwitcher(
            duration: SandikMotion.stateOf(context),
            child: KeyedSubtree(key: ValueKey(_tur), child: govde),
          ),
          if (_hata != null) ...[
            const SizedBox(height: SandikSpace.sm),
            Text(_hata!, style: t.bodySmall?.copyWith(color: c.danger)),
          ],
          const SizedBox(height: SandikSpace.md),
          _Uyari(metin: l.pyzUyari),
          if (riza == true && !kilitli)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
                onPressed: _kapat,
                child: Text(l.pyzKapat),
              ),
            ),
        ],
      ),
    );
  }

  /// Bir sonraki yorumun yazılabileceği gün: haftalıkta bu Pazartesi + 7,
  /// aylıkta gelecek ayın 1'i (anlatılan dönemin bitişinden türetilir).
  static DateTime _siradaki(YorumTuru tur, DateTime bitis) =>
      tur == YorumTuru.haftalik
          ? DateTime(bitis.year, bitis.month, bitis.day + 8)
          : DateTime(bitis.year, bitis.month + 2, 1);
}

class _Yorum extends StatelessWidget {
  const _Yorum({required this.yorum, required this.gunAy});

  final PortfoyYorumu yorum;
  final DateFormat gunAy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(yorum.baslik,
            style: t.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
        for (final m in yorum.maddeler) ...[
          const SizedBox(height: SandikSpace.md),
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: SandikSpace.xs2),
                  child: Container(
                    width: SandikSpace.xs2,
                    height: SandikSpace.xs2,
                    decoration:
                        BoxDecoration(color: c.text58, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.metin,
                          style: t.bodyMedium?.copyWith(color: c.text90)),
                      if (yorum.kanitlar(m.kanit).isNotEmpty) ...[
                        const SizedBox(height: SandikSpace.xs),
                        Wrap(
                          spacing: SandikSpace.xs,
                          runSpacing: SandikSpace.xs,
                          children: [
                            for (final k in yorum.kanitlar(m.kanit))
                              _KanitCipi(olcum: k),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "Dönem getirisi · +%4,2". Gösterim telefonun yazdığıyla AYNI.
class _KanitCipi extends StatelessWidget {
  const _KanitCipi({required this.olcum});

  final YorumOlcumu olcum;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    return SandikCard(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
      elevated: true,
      radius: SandikRadius.sm,
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${olcum.ad} · ', style: TextStyle(color: c.text58)),
          TextSpan(
              text: olcum.gosterim,
              style: TextStyle(color: c.text90, fontWeight: FontWeight.w700)),
        ]),
        style: t.labelSmall,
      ),
    );
  }
}

/// Sabit uyarı kutusu. Kapatılamaz, kaydırınca kaybolmaz (kartın parçası).
class _Uyari extends StatelessWidget {
  const _Uyari({required this.metin});

  final String metin;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    return SandikCard(
      elevated: true,
      bordered: false,
      radius: SandikRadius.sm,
      padding: const EdgeInsets.all(SandikSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.info_outline_rounded,
                size: SandikSpace.md, color: c.text58),
          ),
          const SizedBox(width: SandikSpace.xs),
          Expanded(
            child: Text(metin, style: t.bodySmall?.copyWith(color: c.text58)),
          ),
        ],
      ),
    );
  }
}

/// İlk kullanımda açık rıza (0145 `portfoy_yorum_rizalari`). Zirve rızası
/// deseni: isteğe bağlı, "Şimdi değil" hiçbir şeyi değiştirmez; aşağı çekip
/// kapatmak da aynı sonucu verir.
class _RizaSayfasi extends StatelessWidget {
  const _RizaSayfasi();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    final yatay = SandikSpace.screenH(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(yatay, 0, yatay, SandikSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.pyzRizaBaslik,
                style: t.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
            const SizedBox(height: SandikSpace.sm),
            Text(l.pyzRizaMetin,
                style: t.bodyMedium?.copyWith(color: c.text58)),
            const SizedBox(height: SandikSpace.md),
            _Uyari(metin: l.pyzRizaUyari),
            const SizedBox(height: SandikSpace.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.pyzKatiliyorum),
            ),
            const SizedBox(height: SandikSpace.sm),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: SandikTouch.minSize),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.pyzSimdiDegil),
            ),
          ],
        ),
      ),
    );
  }
}
