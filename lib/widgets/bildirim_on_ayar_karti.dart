import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/bildirim_on_ayar_provider.dart';
import '../providers/preferences_provider.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'sandik_async_button.dart';
import 'sandik_segment.dart';

/// Ayarlar › Bildirimler'in başındaki tek soru: "Bildirimler ne sıklıkta
/// gelsin?" — Az · Dengeli · Çok.
///
/// Sinyal Ayarları'ndaki ön ayar kartının (`_OnAyarKarti`) bütün push'lara
/// genişlemiş hâli; davranış aynı: seçim kayıtlı değerlerden türetilir
/// ([bildirimOnAyarProvider]), hiçbir ön ayara uymayan kullanıcı "Özel"
/// etiketini görür ve hiçbir şey değişmez. Özel bir segment değildir —
/// dokununca neye döneceği belirsiz kalırdı.
///
/// Yazma sürerken ikinci dokunuş yok sayılır (çift yazma, iki ön ayarın
/// karışmasıyla "Özel" bırakırdı). Ayrı bir yükleniyor göstergesi yok:
/// segment iyimser kayar, yazma arka planda biter
/// (`yukleniyor_tek_davranis_test` — elle çizilmiş meşgul hâl yasak).
///
/// Kilitli seçenek (Ar-Ge 26 Kas 02:03 #2): ücretsiz kullanıcının kilitli
/// "Çok"a ilk dokunuşu seçimi değiştirmez, paywall da açmaz; açıklama satırı
/// Çok'un ne getirdiğini + "Premium'la açılır." der ve altında "Premium'la
/// aç" düğmesi çıkar. Eskiden dokunuş doğrudan paywall'a gidiyordu; kişi
/// ne alacağını görmeden karar veriyordu. Değer önce, ödeme sonra; baskı ve
/// geri sayım yok. Aynı seçeneğe ikinci dokunuş da düğme gibi paywall'a
/// gider. Premium kullanıcıda kilit olmadığı için davranış aynen.
class BildirimOnAyarKarti extends ConsumerStatefulWidget {
  const BildirimOnAyarKarti({super.key, required this.onPaywall});

  /// Seçilen ön ayarın sinyal sıklığı ücretsiz günlük sınırı aşıyorsa
  /// çağrılır; `true` (satın alma tamamlandı) dönerse seçilen ön ayar
  /// uygulanır, aksi hâlde hiçbir şey yazılmaz (Ar-Ge 23 Kas 22:03 #2:
  /// eskiden "Çok"a basıp Premium alan kişi dönüşte hâlâ "Az" görüyordu).
  final Future<bool> Function() onPaywall;

  @override
  ConsumerState<BildirimOnAyarKarti> createState() =>
      _BildirimOnAyarKartiState();
}

class _BildirimOnAyarKartiState extends ConsumerState<BildirimOnAyarKarti> {
  bool _yaziliyor = false;

  /// Yazma sürerken segmentin göstereceği seçim (iyimser).
  BildirimOnAyar? _hedef;

  /// Açıklaması gösterilen kilitli seçenek (henüz seçilmedi, ödenmedi).
  BildirimOnAyar? _onizleme;

  Future<void> _sec(BildirimOnAyar a) async {
    if (_yaziliyor) return;
    if (bildirimOnAyariPremiumIster(a, ref.read(sinyalSlotSiniriProvider))) {
      if (_onizleme != a) {
        setState(() => _onizleme = a);
        return;
      }
      return _premiumlaAc(a);
    }
    if (_onizleme != null) setState(() => _onizleme = null);
    await _uygula(a);
  }

  Future<void> _premiumlaAc(BildirimOnAyar a) async {
    if (_yaziliyor) return;
    // Slot sağlayıcısı satın almadan sonra geç güncellenebilir: yeniden
    // sorulmaz, satın alma sonucuna güvenilir.
    if (!await widget.onPaywall() || !mounted || _yaziliyor) return;
    setState(() => _onizleme = null);
    await _uygula(a);
  }

  Future<void> _uygula(BildirimOnAyar a) async {
    setState(() {
      _yaziliyor = true;
      _hedef = a;
    });
    try {
      await bildirimOnAyariUygula(ref, a);
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _yaziliyor = false;
          _hedef = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final durum = ref.watch(bildirimOnAyarProvider);
    final slot = ref.watch(sinyalSlotSiniriProvider);
    final yuklendi = durum.hasValue;
    final secili = _hedef ?? durum.valueOrNull;
    final etiketler = [l10n.s5OnAyarAz, l10n.s5OnAyarDengeli, l10n.s5OnAyarCok];
    // Başka yoldan Premium alınınca kilit kalkar; eski önizleme yalan söylemesin.
    final onizleme = _onizleme != null &&
            bildirimOnAyariPremiumIster(_onizleme!, slot)
        ? _onizleme
        : null;
    final aciklama = !yuklendi
        ? ''
        : onizleme != null
            ? '${_aciklamaMetni(l10n, onizleme)} '
                '${l10n.bildirimOnAyarPremiumlaAcilir}'
            : _aciklamaMetni(l10n, secili);
    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.bildirimOnAyarSoru,
                  style: context.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600, color: context.c.text90),
                ),
              ),
              if (yuklendi && secili == null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                    border: Border.all(
                        color: context.c.amberFill.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    l10n.s5OnAyarOzel,
                    style: context.t.labelMedium?.copyWith(
                      // w600 tavanı (unslop, yasin 5 Kas; Ar-Ge 26 Kas #6).
                      fontWeight: FontWeight.w600,
                      color: context.c.amberText,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: SandikSpace.smd),
          SandikSegment(
            adet: etiketler.length,
            // Yüklenirken ve Özel'de aralık dışı → zemin çizilmez.
            secili: yuklendi ? (secili?.index ?? -1) : -1,
            onSec: (i) {
              if (!yuklendi) return;
              _sec(BildirimOnAyar.values[i]);
            },
            oge: (context, i, _) => sandikKilitliSegmentEtiketi(
              context,
              etiketler[i],
              kilitli: bildirimOnAyariPremiumIster(
                  BildirimOnAyar.values[i], slot),
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(
            aciklama,
            style: context.t.bodySmall
                ?.copyWith(color: context.c.text58, height: 1.4),
          ),
          if (onizleme != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SandikAsyncTap(
                key: const ValueKey('bildirimOnAyarPremiumlaAc'),
                onTap: () => _premiumlaAc(onizleme),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      minHeight: SandikTouch.min, minWidth: SandikTouch.min),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 1,
                    child: Text(
                      l10n.bildirimOnAyarPremiumlaAc,
                      style: context.t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.c.amberText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _aciklamaMetni(AppLocalizations l10n, BildirimOnAyar? a) =>
      switch (a) {
        BildirimOnAyar.az => l10n.bildirimOnAyarAzAciklama,
        BildirimOnAyar.dengeli => l10n.bildirimOnAyarDengeliAciklama,
        BildirimOnAyar.cok => l10n.bildirimOnAyarCokAciklama,
        null => l10n.bildirimOnAyarOzelAciklama,
      };
}
