// Portföy hedefi giriş sayfası.
//
// Hedef yalnızca gösterimdir: hiçbir hesabı değiştirmez, "Bugün" kartında
// ilerleme çubuğu olur. Hazır tutarlar portföye göre (Ar-Ge 2 Kas 08:45 #2,
// müşteri YAP): bugünkü toplamın üstündeki ilk dört basamak. Sabit
// 250K–2,5M listesi 484 binlik portföye geçilmiş bir hedef, 20 milyonluğa
// dört anlamsız tutar öneriyordu. İlk hedefi yazmak yerine dokunmak daha
// kolay; istenirse elle girilir.
//
// "Ne zamana kadar?" (Premium, yasin 2026-11-06): hedefin kendisi ücretsiz,
// tarihi Premium. Tarih seçilince "ayda yaklaşık ₺X" satırı (düz bölme,
// getiri hariç; hesap `models/hedef_tarihi.dart`). Ücretsizde satır kilitli
// görünür, dokununca paywall; hiçbir şey kaydedilmez.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/hedef_onerisi.dart';
import '../models/hedef_tarihi.dart';
import '../providers/preferences_provider.dart';
import '../services/analytics_service.dart';
import '../services/bugun_service.dart' show HedefSatiri;
import '../services/review_prompt_service.dart';
import '../theme/sandik.dart';
import 'para_akisi_karti.dart' show KilitSatiri;
import 'review_prompt_sheet.dart';
import 'sandik_async_button.dart';
import 'tur_filtre_cipleri.dart' show SandikFiltreCipi;
import '../utils/tr_format.dart';

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
  final tarihSaglayici = kapsamHedefTarihiProvider(kapsam);
  final mevcut = ref.read(saglayici);
  final sonuc = await showSandikSheet<_HedefSonucu>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
    ),
    builder: (ctx) => _HedefSheet(
        mevcut: mevcut,
        mevcutTarih: ref.read(tarihSaglayici),
        etiket: etiket,
        deger: deger,
        gizli: gizli),
  );
  if (sonuc == null) return;
  await ref.read(saglayici.notifier).set(sonuc.hedef);
  // Tarih yalnız Premium'da yazılır (sheet ücretsizde `tarihDegisti` false
  // döner; kayıtlı gün olduğu gibi kalır). Hedef kaldırılınca günü de gider:
  // tarihsiz hedefin günü, sonraki hedefe yanlış gün taşırdı.
  if (sonuc.hedef <= 0) {
    await ref.read(tarihSaglayici.notifier).set(null);
  } else if (sonuc.tarihDegisti) {
    await ref.read(tarihSaglayici.notifier).set(sonuc.tarih);
  }
  // Kaç kişinin hedef kullandığı, kartın bu satırı hak edip etmediğini söyler.
  unawaited(AnalyticsService.instance.logGoalSet(amountTRY: sonuc.hedef));
  // Hedef KONDUYSA (0 = hedef kaldırıldı, mutlu an değil) değerlendirme
  // istemi; sheet kapandı, kullanıcı kartına döndü. Karar serviste.
  if (sonuc.hedef > 0 && context.mounted) {
    await ReviewPromptSheet.belkiGoster(context, ReviewAni.hedefKondu);
  }
}

/// Sheet'in sonucu: hedef (0 = kaldır) ve — yalnız Premium'da değiştiyse —
/// gün.
typedef _HedefSonucu = ({int hedef, DateTime? tarih, bool tarihDegisti});

class _HedefSheet extends ConsumerStatefulWidget {
  const _HedefSheet(
      {required this.mevcut,
      this.mevcutTarih,
      this.etiket,
      this.deger,
      this.gizli = false});
  final int mevcut;
  final DateTime? mevcutTarih;
  final String? etiket;
  final double? deger;
  final bool gizli;

  @override
  ConsumerState<_HedefSheet> createState() => _HedefSheetState();
}

class _HedefSheetState extends ConsumerState<_HedefSheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.mevcut > 0 ? fmtNum(widget.mevcut.toDouble(), digits: 0) : '',
  );
  String? _hata;
  late DateTime? _tarih = widget.mevcutTarih;
  bool _tarihDegisti = false;

  void _tarihSec(DateTime? t) => setState(() {
        _tarih = t;
        _tarihDegisti = true;
      });

  Future<void> _takvimdenSec() async {
    final bugun = DateTime.now();
    final yarin = DateTime(bugun.year, bugun.month, bugun.day + 1);
    final t = await pickSandikDate(
      context,
      initialDate: _tarih ?? DateTime(bugun.year + 1, bugun.month, bugun.day),
      firstDate: yarin,
      lastDate: DateTime(bugun.year + 50, 12, 31),
      helpText: context.l10n.goalDateTitle,
    );
    if (t != null && mounted) _tarihSec(t);
  }

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

  /// Kaydet düğmesinin ✓ anı (Ar-Ge 11 Kas 19:04 #3).
  final _basari = SandikBasariSinyali();

  /// ✓ evresi sürüyor: klavyedeki "Bitti" düğmeden geçmez, kilidi o
  /// paylaşmaz — ikinci gönderim ikinci `pop` olurdu.
  bool _kapaniyor = false;

  Future<void> _kaydet() async {
    if (_kapaniyor) return;
    final v = parseTrNumber(_ctrl.text);
    if (v == null || v <= 0) {
      setState(() => _hata = context.l10n.goalInvalid);
      return;
    }
    // Ücretsizde ya da gizliyken tarih hiç değişmemiş sayılır: kilitli
    // satır bir şey kaydetmez.
    final acik = ref.read(hedefTarihiDurumuProvider) == OzellikDurumu.acik;
    // Hedef bir tercih yazımı (istek yok, anında); ✓ yine de "kaydedildi"
    // anını sayfa kapanmadan gösterir — eskiden sayfa sessizce kapanıyordu.
    _kapaniyor = true;
    await _basari.goster();
    if (!mounted) return;
    Navigator.pop<_HedefSonucu>(context, (
      hedef: v.round(),
      tarih: _tarih,
      tarihDegisti: acik && _tarihDegisti,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final yazilan = parseTrNumber(_ctrl.text);
    final tarihDurumu = ref.watch(hedefTarihiDurumuProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SandikSpace.screenH(context),
        SandikSpace.sm2,
        SandikSpace.screenH(context),
        MediaQuery.of(context).viewInsets.bottom + SandikSpace.lg,
      ),
      // Kaydırılabilir: 2× yazıda tarih bölümüyle birlikte telefon boyunu
      // aşıyordu (hedefe tarih, 2026-11-06).
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.etiket != null)
              Padding(
                padding: const EdgeInsets.only(bottom: SandikSpace.xs),
                child: Text(
                  widget.etiket!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelSmall?.copyWith(
                    color: context.c.text58,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            SandikSheetBasligi(l10n.goalTitle),
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
                for (final h
                    in hazirHedefler(widget.deger, gizli: widget.gizli))
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: false),
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
            if (tarihDurumu == OzellikDurumu.kilitli)
              Padding(
                padding: const EdgeInsets.only(top: SandikSpace.sm),
                child: KilitSatiri(
                  metin: l10n.goalDateLocked,
                  kaynak: 'hedef_tarihi',
                  ozellik: 'hedef_tarihi',
                  kilitEtiketi: l10n.goalDateLockedLabel,
                ),
              )
            else if (tarihDurumu == OzellikDurumu.acik)
              _TarihBolumu(
                tarih: _tarih,
                deger: widget.deger,
                hedef: yazilan,
                gizli: widget.gizli,
                onSec: _tarihSec,
                onTakvim: _takvimdenSec,
              ),
            const SizedBox(height: SandikSpace.md),
            // `SandikAsyncButton` (istek atmasa da): ✓ durumu ve ✓ evresinde
            // çift dokunma kilidi tek bileşenden gelir.
            SandikAsyncButton.kompakt(
              basari: _basari,
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
                onPressed: () => Navigator.pop<_HedefSonucu>(
                    context, (hedef: 0, tarih: null, tarihDegisti: true)),
                child: Text(l10n.goalRemove,
                    style: TextStyle(color: context.c.text58)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Günü geçmiş, ulaşılmamış hedefin satırı — uzundan kısaya
/// ("Ara 2026 geçti · %82'ye ulaştın · yeni gün seç", "Ara 2026 geçti ·
/// yeni gün seç"). Bugün kartı ve hedef sayfası AYNI metni yazar.
///
/// Dil nötr ve ilerleme önde (2026-11-12): gün geçti demek bir başarısızlık
/// ilanı değil; ulaşılan yüzde ve tek eylem (yeni gün) yazılır. Yüzde
/// kartın başlığıyla aynı aşağı yuvarlanmış oran ([HedefSatiri.oran]);
/// ay/yıl hedefin günüyle aynı biçim (`goalDateBy`: "Ara 2027'ye kadar").
/// Bakiye gizliyken de yazılır: oran tutar ele vermez (önizleme de öyle).
/// Ayın dili metnin dilinden (`tarihDili` kuralı): Türkçe cümlede "Oct"
/// yazmasın.
List<String> hedefGunuGectiMetinleri(
    AppLocalizations l10n, DateTime tarih, double oran) {
  final dil = l10n.localeName == 'en' ? 'en_US' : 'tr_TR';
  final ay = DateFormat.yMMM(dil).format(tarih);
  final yuzde = (oran * 100).floor();
  return [
    l10n.goalDatePassed(
        ay, fmtPct(yuzde.toDouble(), digits: 0), sayiYonelmeEki(yuzde)),
    l10n.goalDatePassedShort(ay),
  ];
}

/// "Ne zamana kadar?" çipleri ve aylık tutar satırı (Premium açık).
///
/// Aylık satır yalnız gün seçili, gün geçmemiş ve kalan > 0 iken: hedefe
/// ulaşıldıysa önizlemedeki "zaten geçtin" kazanır. Bakiye gizliyken tutar
/// `••••` (Bugün kartının hedef satırıyla aynı). Gün geçmiş ve kalan > 0
/// ise aylık satırın yerinde [hedefGunuGectiMetinleri] (2026-11-12: eskiden
/// hiçbir şey yazılmıyordu).
class _TarihBolumu extends StatelessWidget {
  const _TarihBolumu({
    required this.tarih,
    required this.deger,
    required this.hedef,
    required this.gizli,
    required this.onSec,
    required this.onTakvim,
  });
  final DateTime? tarih;
  final double? deger;
  final double? hedef;
  final bool gizli;
  final ValueChanged<DateTime?> onSec;
  final VoidCallback onTakvim;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bugun = DateTime.now();
    final secenek = hedefTarihSecenegi(tarih, bugun);
    final dil = Localizations.localeOf(context).languageCode == 'en'
        ? 'en_US'
        : 'tr_TR';
    final aylik = (tarih == null || deger == null || hedef == null)
        ? null
        : hedefAylikTutar(kalan: hedef! - deger!, tarih: tarih!, bugun: bugun);
    final gecti = (tarih != null &&
            deger != null &&
            hedef != null &&
            hedef! > deger! &&
            hedefGunuGecti(tarih!, bugun))
        ? hedefGunuGectiMetinleri(l10n, tarih!,
                HedefSatiri(hedefTRY: hedef!.round(), deger: deger!).oran)
            .first
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.goalDateTitle,
            style: context.t.labelLarge?.copyWith(
              color: context.c.text90,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          Wrap(
            spacing: SandikSpace.sm,
            runSpacing: SandikSpace.sm,
            children: [
              SandikFiltreCipi(
                ad: l10n.goalDateNone,
                secili: secenek == HedefTarihSecenegi.yok,
                onTap: () => onSec(null),
              ),
              SandikFiltreCipi(
                ad: l10n.goalDateOneYear,
                secili: secenek == HedefTarihSecenegi.birYil,
                onTap: () => onSec(
                    hedefTarihiSecenekten(HedefTarihSecenegi.birYil, bugun)),
              ),
              SandikFiltreCipi(
                ad: l10n.goalDateYearEnd,
                secili: secenek == HedefTarihSecenegi.yilSonu,
                onTap: () => onSec(
                    hedefTarihiSecenekten(HedefTarihSecenegi.yilSonu, bugun)),
              ),
              // Özel gün seçiliyken çip günü yazar; dokununca takvim yine
              // açılır (günü değiştirmek için).
              SandikFiltreCipi(
                ad: secenek == HedefTarihSecenegi.ozel
                    ? DateFormat.yMMMd(dil).format(tarih!)
                    : l10n.goalDatePick,
                ikon: Icons.calendar_today_rounded,
                secili: secenek == HedefTarihSecenegi.ozel,
                onTap: onTakvim,
              ),
            ],
          ),
          if (gecti != null) ...[
            const SizedBox(height: SandikSpace.sm),
            Text(
              gecti,
              style: context.t.bodyMedium?.copyWith(color: context.c.text90),
            ),
          ],
          if (aylik != null) ...[
            const SizedBox(height: SandikSpace.sm),
            Text(
              l10n.goalDateMonthly(gizli ? '••••' : fmtTRY(aylik.toDouble())),
              style: context.t.bodyMedium?.copyWith(color: context.c.text90),
            ),
            Text(
              l10n.goalDateNoReturn,
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
          ],
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

/// Profil'deki "Portföy hedefi" satırı — yalnız Bugün kartındaki öneri
/// sönmüşken ve hedef yokken (Ar-Ge 5 Kas 19:00 #2, müşteri YAP).
///
/// ## Neden
/// Hedef sayfasının tek girişi Bugün kartındaki öneriydi. Öneri ✕ ile
/// kapanınca ya da 30 gün sönünce hedef koymanın yolu kalmazdı. Satır o
/// zaman belirir; öneri görünürken ya da hedef varken sıfır yükseklik
/// (Profil düzeni değişmez; hedefi olanın kutusu kartta).
class HedefProfilSatiri extends ConsumerWidget {
  const HedefProfilSatiri({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hedefVar = ref.watch(portfolioGoalProvider) > 0;
    final oneri = HedefOnerisiDurumu.coz(ref.watch(hedefOnerisiProvider));
    if (hedefVar || oneri.gorunur(DateTime.now())) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    final gizli = ref.watch(balanceHiddenProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.lg),
      child: SandikCard(
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.md, vertical: SandikSpace.smd),
        onTap: () => showHedefSheet(context, ref, gizli: gizli),
        child: Semantics(
          button: true,
          child: Row(
            children: [
              Icon(Icons.flag_outlined, size: 22, color: context.c.amberText),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.goalProfileRowTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.c.text90,
                      ),
                    ),
                    Text(
                      l.goalProfileRowSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.c.text58),
            ],
          ),
        ),
      ),
    );
  }
}
