// Portföy hedefi giriş sayfası.
//
// Hedef yalnızca gösterimdir: hiçbir hesabı değiştirmez, "Bugün" kartında
// ilerleme çubuğu olur. Hazır tutarlar portföye göre (Ar-Ge 2 Kas 08:45 #2,
// müşteri YAP): bugünkü toplamın üstündeki ilk dört basamak. Sabit
// 250K–2,5M listesi 484 binlik portföye geçilmiş bir hedef, 20 milyonluğa
// dört anlamsız tutar öneriyordu. İlk hedefi yazmak yerine dokunmak daha
// kolay; istenirse elle girilir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart';
import '../services/analytics_service.dart';
import '../services/bugun_service.dart' show HedefSatiri;
import '../services/review_prompt_service.dart';
import '../theme/sandik.dart';
import 'review_prompt_sheet.dart';
import 'tur_filtre_cipleri.dart' show SandikFiltreCipi;
import '../utils/tr_format.dart';
import '../utils/tr_iyelik.dart';

/// Hazır hedef merdiveni (TRY). Basamaklar yukarı doğru genişler: 100
/// binlik portföye 250 bin anlamlı bir hedef, 10 milyonluğa 25 milyon.
const hedefMerdiveni = <int>[
  100000,
  250000,
  500000,
  750000,
  1000000,
  1500000,
  2500000,
  5000000,
  10000000,
  25000000,
  50000000,
];

/// Bugünkü değer bilinmiyorken ya da bakiye gizliyken: eski sabit dört.
/// Gizliyken portföyden türetilmiş çip toplamı ele verirdi.
const _sabitHedefler = <int>[250000, 500000, 1000000, 2500000];

/// Hazır tutarlar: [deger]'in ÜSTÜNDEKİ ilk dört basamak. Geçilmiş tutar
/// önerilmez; merdiven bittiyse kalan basamaklar (en büyük portföyde hiç).
List<int> hazirHedefler(double? deger, {bool gizli = false}) {
  if (gizli || deger == null || deger <= 0) return _sabitHedefler;
  return hedefMerdiveni.where((h) => h > deger).take(4).toList();
}

/// [kapsam]: `kapsamHedefiProvider` anahtarı (`''` Ben). [etiket] kartın
/// kapsam etiketi ("Birlikte", "Ayşe'nin bugünü") — başka bir defterin
/// hedefi yazılırken sheet kimin için olduğunu söyler.
///
/// [deger]: kapsamın bugünkü toplamı (Bugün kartıyla aynı sayı). Verilirse
/// çipler ona göre gelir ve yazılan hedefin önizlemesi görünür; [gizli]
/// (bakiye gizli) ise önizlemede yalnız oran kalır.
Future<void> showHedefSheet(BuildContext context, WidgetRef ref,
    {String kapsam = '',
    String? etiket,
    double? deger,
    bool gizli = false}) async {
  // Demo: hedef bir tercih yazımı (F1).
  if (DemoModu.yazmaKapisi('hedef')) return;
  final saglayici = kapsamHedefiProvider(kapsam);
  final mevcut = ref.read(saglayici);
  final sonuc = await showSandikSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.c.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
    ),
    builder: (ctx) =>
        _HedefSheet(mevcut: mevcut, etiket: etiket, deger: deger, gizli: gizli),
  );
  if (sonuc == null) return;
  await ref.read(saglayici.notifier).set(sonuc);
  // Kaç kişinin hedef kullandığı, kartın bu satırı hak edip etmediğini söyler.
  unawaited(AnalyticsService.instance.logGoalSet(amountTRY: sonuc));
  // Hedef KONDUYSA (0 = hedef kaldırıldı, mutlu an değil) değerlendirme
  // istemi; sheet kapandı, kullanıcı kartına döndü. Karar serviste.
  if (sonuc > 0 && context.mounted) {
    await ReviewPromptSheet.belkiGoster(context, ReviewAni.hedefKondu);
  }
}

class _HedefSheet extends StatefulWidget {
  const _HedefSheet(
      {required this.mevcut, this.etiket, this.deger, this.gizli = false});
  final int mevcut;
  final String? etiket;
  final double? deger;
  final bool gizli;

  @override
  State<_HedefSheet> createState() => _HedefSheetState();
}

class _HedefSheetState extends State<_HedefSheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.mevcut > 0 ? fmtNum(widget.mevcut.toDouble(), digits: 0) : '',
  );
  String? _hata;

  @override
  void initState() {
    super.initState();
    // Önizleme ve çip seçimi yazılan tutarı izler.
    _ctrl.addListener(_yenile);
  }

  void _yenile() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_yenile);
    _ctrl.dispose();
    super.dispose();
  }

  void _kaydet() {
    final v = parseTrNumber(_ctrl.text);
    if (v == null || v <= 0) {
      setState(() => _hata = context.l10n.goalInvalid);
      return;
    }
    Navigator.pop(context, v.round());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final yazilan = parseTrNumber(_ctrl.text);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SandikSpace.screenH(context),
        SandikSpace.sm2,
        SandikSpace.screenH(context),
        MediaQuery.of(context).viewInsets.bottom + SandikSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tutamaç (HIG denetimi 2026-10-10): aşağı kaydırarak kapandığı görünsün.
          const Center(child: SandikTutamac()),
          const SizedBox(height: SandikSpace.md),
          if (widget.etiket != null)
            Padding(
              padding: const EdgeInsets.only(bottom: SandikSpace.xs),
              child: Text(
                trBuyukHarf(widget.etiket!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelSmall?.copyWith(
                  color: context.c.text58,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          Text(
            l10n.goalTitle,
            style: context.t.headlineSmall?.copyWith(
              color: context.c.text90,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            l10n.goalHint,
            style: context.t.bodyMedium?.copyWith(color: context.c.text58),
          ),
          const SizedBox(height: SandikSpace.md),
          Wrap(
            spacing: SandikSpace.sm,
            runSpacing: SandikSpace.sm,
            children: [
              for (final h in hazirHedefler(widget.deger, gizli: widget.gizli))
                // Alandaki tutara eşit çip SEÇİLİ görünür: ortak süzme
                // çipi (amber dolgu + onay işareti; yalnız renkle değil).
                SandikFiltreCipi(
                  ad: fmtTRYCompactSade(h.toDouble()),
                  secili: yazilan?.round() == h,
                  onTap: () => setState(() {
                    _ctrl.text = fmtNum(h.toDouble(), digits: 0);
                    _hata = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: SandikSpace.md),
          TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            style: TextStyle(color: context.c.text90),
            onSubmitted: (_) => _kaydet(),
            decoration: InputDecoration(
              prefixText: '₺ ',
              hintText: '1.000.000',
              errorText: _hata,
              // Dolgu/çerçeve temadan (`inputDecorationTheme` = `inputFill` kuralı).
            ),
          ),
          if (widget.deger != null && yazilan != null && yazilan > 0)
            _Onizleme(
                deger: widget.deger!, hedef: yazilan, gizli: widget.gizli),
          const SizedBox(height: SandikSpace.md),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.c.amberFill,
              foregroundColor: context.c.onAmber,
            ),
            onPressed: _kaydet,
            child: Text(l10n.save,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (widget.mevcut > 0)
            TextButton(
              onPressed: () => Navigator.pop(context, 0),
              child: Text(l10n.goalRemove,
                  style: TextStyle(color: context.c.text58)),
            ),
        ],
      ),
    );
  }
}

/// Yazılan hedefin önizlemesi (Ar-Ge 2 Kas 08:45 #2): Bugün kartının
/// hedef satırıyla AYNI oran ([HedefSatiri]); ikinci hesap yok. Bakiye
/// gizliyken tutarlar yazılmaz, yalnız oran kalır.
class _Onizleme extends StatelessWidget {
  const _Onizleme(
      {required this.deger, required this.hedef, required this.gizli});
  final double deger;
  final double hedef;
  final bool gizli;

  @override
  Widget build(BuildContext context) {
    final s = HedefSatiri(hedefTRY: hedef.round(), deger: deger);
    final l10n = context.l10n;
    final yuzde = fmtPct(s.oran * 100, digits: 0);
    final metin = s.ulasildi
        ? (gizli
            ? l10n.goalPreviewDoneHidden
            : l10n.goalPreviewDone(fmtTRY(deger)))
        : gizli
            ? l10n.goalPreviewHidden(yuzde)
            : l10n.goalPreview(fmtTRY(deger), yuzde, fmtTRY(s.kalan));
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: SandikRadius.smAll,
            child: LinearProgressIndicator(
              value: s.oran,
              minHeight: SandikSpace.xs,
              backgroundColor: context.c.hairline,
              valueColor: AlwaysStoppedAnimation(context.c.amberText),
            ),
          ),
          const SizedBox(height: SandikSpace.xs2),
          Text(
            metin,
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
        ],
      ),
    );
  }
}
