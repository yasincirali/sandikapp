import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../models/sozlesme.dart';
import '../providers/portfolio_provider.dart';
import '../providers/sozlesme_provider.dart';
import 'bes_dagilim_editoru.dart';
import 'sozlesme_formu_ortak.dart';
import '../services/bes_hesabi.dart';
import '../services/crash_reporter.dart';
import '../services/mevduat_hesabi.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';

/// Varlık sayfasındaki sözleşme kartı — mevduat ve BES.
///
/// Sayılar lot defterinden ve sözleşmeden gelir; kart hesap YAPMAZ, hazır
/// saf fonksiyonları çağırır (`MevduatHesabi`, `BesHesabi`). Eylemler
/// (yenile, çektim, katkı ekle) yalnız KENDİ sözleşmende görünür: ortağın
/// sözleşmesine yazma izni yok (RLS: ortak yalnız okur).
class SozlesmeKarti extends ConsumerWidget {
  const SozlesmeKarti({
    super.key,
    required this.varlik,
    this.dis = const EdgeInsets.only(top: SandikSpace.lg),
  });

  final Asset varlik;
  final EdgeInsets dis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = varlik.sozlesmeId;
    if (id == null || !varlik.type.sozlesmeli) return const SizedBox.shrink();
    final sd = ref.watch(sozlesmeProvider).valueOrNull;
    final s = sd?.sozlesme(id);
    if (s == null) return const SizedBox.shrink();
    final lotlar = [
      for (final a in ref.watch(portfolioProvider).valueOrNull?.assets ??
          const <Asset>[])
        if (sozlesmeLotuMu(a, s) && a.isActive) a,
    ];
    final govde = s.tur == SozlesmeTuru.mevduat
        ? _MevduatGovdesi(s: s, donemler: sd!.donemleri(id), lotlar: lotlar)
        : _BesGovdesi(s: s, lotlar: lotlar);
    return Padding(padding: dis, child: govde);
  }
}

/// Kart başlığı: tür adı · kurum, sağda ek bilgi.
class _Baslik extends StatelessWidget {
  const _Baslik({required this.tur, required this.kurum, this.sag});
  final AssetType tur;
  final String kurum;
  final String? sag;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(tur.icon, size: 18, color: tur.onSurface(context)),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Text(
              '${tur.labelOf(context.l10n)} · $kurum',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700, color: context.c.text90),
            ),
          ),
          if (sag != null)
            Flexible(
              child: Text(sag!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600, color: context.c.text58)),
            ),
        ],
      );
}

/// Kart içi eylem düğmesi.
class _Eylem extends StatelessWidget {
  const _Eylem({required this.metin, required this.bas, this.birincil = false});
  final String metin;
  final VoidCallback bas;
  final bool birincil;

  @override
  // En az 44pt, üstü serbest: büyük metin ölçeğinde etiket iki satıra
  // sarabilsin (sabit yükseklik metni kırpardı).
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        child: birincil
            ? FilledButton(
                onPressed: bas,
                style: FilledButton.styleFrom(
                  backgroundColor: context.c.amberFill,
                  foregroundColor: context.c.onAmber,
                  shape: RoundedRectangleBorder(
                      borderRadius: SandikRadius.mdAll),
                ),
                child: Text(metin,
                    textAlign: TextAlign.center,
                    style: context.t.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              )
            : OutlinedButton(
                onPressed: bas,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.c.text90,
                  side: BorderSide(color: context.c.hairline),
                  shape: RoundedRectangleBorder(
                      borderRadius: SandikRadius.mdAll),
                ),
                child: Text(metin,
                    textAlign: TextAlign.center,
                    style: context.t.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
      );
}

// ── Mevduat ──────────────────────────────────────────────────────────────

class _MevduatGovdesi extends ConsumerWidget {
  const _MevduatGovdesi(
      {required this.s, required this.donemler, required this.lotlar});
  final Sozlesme s;
  final List<MevduatDonemi> donemler;
  final List<Asset> lotlar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final son = MevduatHesabi.sonDonem(donemler);
    if (son == null) return const SizedBox.shrink();
    final simdi = DateTime.now();
    final pozisyon = aggregatePositions(lotlar);
    final pay = pozisyon.fold<double>(0, (t, p) => t + p.totalQuantity);
    final bugun = MevduatHesabi.birimDeger(donemler, simdi) ?? 0;
    final buDonem = MevduatHesabi.donemKazanci(
      donemler,
      [
        for (final a in lotlar)
          if (a.isBuy || a.isSell)
            (a.addedDate, a.isSell ? -a.quantity : a.quantity),
      ],
      simdi,
    );
    final doldu = MevduatHesabi.vadesiDoldu(donemler, simdi);
    final kalan = MevduatHesabi.vadeyeKalanGun(donemler, simdi);
    final ilerleme = MevduatHesabi.donemIlerlemesi(donemler, simdi);
    final vade = son.vadeSonu;
    final vadeDegeri = vade == null
        ? null
        : pay * (MevduatHesabi.birimDeger(donemler, vade) ?? 0);
    final tarih = DateFormat.yMMMd(l10n.localeName);
    final acik = s.acik && pay > 1e-9;
    // Vadeli dönem, vadesi dolmamış: değer anaparada düz, faiz vade sonunda
    // eklenecek (kullanıcı kararı 2026-10-02). Kazanç "beklenen" olarak
    // gösterilir; "Bu dönem net" ₺0 yazıp kullanıcıyı korkutmaz.
    final vadeIci = !son.vadesiz && !doldu;
    final beklenen =
        vadeIci ? MevduatHesabi.vadeSonuNetFaizi(donemler, pay) : null;

    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Baslik(
            tur: AssetType.mevduat,
            kurum: s.kurum,
            sag: son.vadesiz
                ? l10n.depositKindDaily
                : l10n.depositPeriodN(MevduatHesabi.donemSayisi(donemler)),
          ),
          const SizedBox(height: SandikSpace.smd),
          // Formun alan etiketleri ("Yıllık faiz (brüt, %)", "Stopaj (%)")
          // kartta "42 · Stopaj (%) 12" diye okunuyordu (2026-10-01
          // emülatör testi); kartın kendi etiketi ve değer kalıbı var.
          SozlesmeOzetSatiri(
            etiket: l10n.depositCardRate,
            deger: l10n.depositCardRateValue(
                fmtNumFlex(son.yillikFaiz, maxDigits: 2),
                fmtNumFlex(son.stopaj, maxDigits: 2)),
          ),
          if (vade != null)
            SozlesmeOzetSatiri(
                etiket: l10n.depositMaturity, deger: tarih.format(vade)),
          if (acik) ...[
            if (beklenen != null)
              SozlesmeOzetSatiri(
                etiket: l10n.depositInterestAtMaturity,
                deger: '+${fmtTRY(beklenen, digits: 2)}',
                renk: context.c.gain,
              )
            else
              SozlesmeOzetSatiri(
                etiket: l10n.depositThisPeriod,
                deger: '+${fmtTRY(buDonem, digits: 2)}',
                renk: context.c.gain,
              ),
            if (vadeDegeri != null && !doldu)
              SozlesmeOzetSatiri(
                etiket: l10n.depositAtMaturity,
                deger: fmtTRY(vadeDegeri, digits: 2),
                vurgulu: true,
              ),
          ],
          if (ilerleme != null && !doldu && acik) ...[
            const SizedBox(height: SandikSpace.sm),
            ClipRRect(
              borderRadius: SandikRadius.smAll,
              child: LinearProgressIndicator(
                value: ilerleme,
                minHeight: 5,
                backgroundColor: context.c.overlay,
                color: AssetType.mevduat.color,
              ),
            ),
            if (kalan != null)
              Padding(
                padding: const EdgeInsets.only(top: SandikSpace.xs2),
                child: Text(l10n.depositDaysLeft(kalan),
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58)),
              ),
          ],
          if (vadeIci && acik) SozlesmeNotu(l10n.depositPaidAtMaturityNote),
          if (doldu && acik) ...[
            const SizedBox(height: SandikSpace.smd),
            Container(
              padding: const EdgeInsets.all(SandikSpace.smd),
              decoration: BoxDecoration(
                color: context.c.amberFill.withValues(alpha: 0.12),
                borderRadius: SandikRadius.mdAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.depositMatured,
                      style: context.t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: context.c.amberText)),
                  const SizedBox(height: SandikSpace.xs),
                  Text(l10n.depositMaturedBody,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58)),
                ],
              ),
            ),
          ],
          if (acik) ...[
            const SizedBox(height: SandikSpace.smd),
            Row(
              children: [
                Expanded(
                  // Vade içinde "Yenile" yerine "Oranı güncelle": banka vade
                  // içinde faizi değiştirdiyse dönem aynı kalır, vade
                  // sonundaki kazanç yeni orana göre çıkar (2026-10-02).
                  child: _Eylem(
                    metin: son.vadesiz || vadeIci
                        ? l10n.depositRateUpdate
                        : l10n.depositRenew,
                    birincil: doldu,
                    bas: () => vadeIci
                        ? _faizGuncelle(context, ref, son)
                        : _yenile(context, ref, son),
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Expanded(
                  child: _Eylem(
                    metin: l10n.depositWithdraw,
                    bas: () => _cek(context, ref, pay * bugun),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _yenile(
      BuildContext context, WidgetRef ref, MevduatDonemi son) async {
    if (DemoModu.yazmaKapisi('mevduat')) return;
    final l10n = context.l10n;
    final sonuc = await showModalBottomSheet<_YeniDonem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => _YenilemeSayfasi(onceki: son),
    );
    if (sonuc == null || !context.mounted) return;
    final n = ref.read(sozlesmeProvider.notifier);
    try {
      if (son.vadesiz) {
        await n.mevduatOranGuncelle(
            sozlesmeId: s.id, yillikFaiz: sonuc.faiz, stopaj: sonuc.stopaj);
      } else {
        await n.mevduatYenile(
            sozlesmeId: s.id,
            yillikFaiz: sonuc.faiz,
            stopaj: sonuc.stopaj,
            vadeGun: sonuc.gun,
            baslangic: sonuc.bas);
      }
      if (context.mounted) {
        sandikSnack(context,
            son.vadesiz ? l10n.depositRateSaved : l10n.depositRenewSaved,
            kind: SandikSnackKind.success);
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SozlesmeKarti.yenile');
      if (context.mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
    }
  }

  /// Vade içinde faiz değişikliği — dönem yerinde güncellenir.
  Future<void> _faizGuncelle(
      BuildContext context, WidgetRef ref, MevduatDonemi son) async {
    if (DemoModu.yazmaKapisi('mevduat')) return;
    final l10n = context.l10n;
    final sonuc = await showModalBottomSheet<_YeniDonem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => _YenilemeSayfasi(onceki: son, vadeIci: true),
    );
    if (sonuc == null || !context.mounted) return;
    try {
      await ref.read(sozlesmeProvider.notifier).mevduatFaizGuncelle(
          sozlesmeId: s.id, yillikFaiz: sonuc.faiz, stopaj: sonuc.stopaj);
      if (context.mounted) {
        sandikSnack(
            context,
            l10n.depositRateSavedMidTerm(
                fmtNumFlex(sonuc.faiz, maxDigits: 2)),
            kind: SandikSnackKind.success);
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SozlesmeKarti.faizGuncelle');
      if (context.mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
    }
  }

  Future<void> _cek(BuildContext context, WidgetRef ref, double deger) async {
    if (DemoModu.yazmaKapisi('mevduat')) return;
    final l10n = context.l10n;
    final onay = await showSandikConfirm(
      context: context,
      title: l10n.depositWithdrawTitle,
      message: l10n.depositWithdrawBody(fmtTRY(deger, digits: 2)),
      confirmLabel: l10n.depositWithdrawConfirm,
      cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
    );
    if (!onay || !context.mounted) return;
    try {
      await ref.read(sozlesmeProvider.notifier).mevduatCek(s.id);
      if (context.mounted) {
        sandikSnack(context, l10n.depositWithdrawn,
            kind: SandikSnackKind.success);
        // Çekilen mevduatın sayfasında kalmanın anlamı yok: sayfa açık
        // pozisyonu (bugünkü değer ₺100.086) göstermeye devam ediyordu
        // (2026-10-01 emülatör testi). Portföye dönülür; satır kalkmıştır.
        await Navigator.of(context).maybePop();
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SozlesmeKarti.cek');
      if (context.mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
    }
  }
}

typedef _YeniDonem = ({double faiz, double stopaj, int? gun, DateTime bas});

/// Yenileme / oran güncelleme sayfası.
class _YenilemeSayfasi extends StatefulWidget {
  const _YenilemeSayfasi({required this.onceki, this.vadeIci = false});
  final MevduatDonemi onceki;

  /// Vadeli dönemde VADE İÇİ oran değişikliği: yalnız faiz ve stopaj
  /// sorulur; vade ve başlangıç dönemin kendisidir.
  final bool vadeIci;

  @override
  State<_YenilemeSayfasi> createState() => _YenilemeSayfasiState();
}

class _YenilemeSayfasiState extends State<_YenilemeSayfasi> {
  final _form = GlobalKey<FormState>();
  late final _faiz = TextEditingController(
      text: fmtNumFlex(widget.onceki.yillikFaiz, maxDigits: 2));
  late int? _gun = widget.onceki.gun;

  // Yeni dönemin stopajı YENİ dönemin açılış gününde yürürlükteki orandır
  // (stopaj incelemesi, 2026-10-01). Eskiden alan önceki dönemin oranıyla
  // açılıyor, öneri yalnızca vade çipine dokununca geliyordu: 2025 Şubat'ta
  // %15'le açılıp Temmuz'dan sonra aynı vadeyle yenilenen mevduat %17,5
  // yerine %15'le kaydediliyordu.
  // Vade içi değişiklikte stopaj dönemin kendi stopajıdır (açılış günü ve
  // vadeye bağlı; ikisi de değişmiyor).
  late final _stopaj = TextEditingController(
      text: fmtNumFlex(
          widget.vadeIci
              ? widget.onceki.stopaj
              : onerilenStopaj(_yeniBaslangic, _gun),
          maxDigits: 2));

  /// Yeni dönemin başı. Varsayılan `mevduatYenile` ile aynı kural (banka
  /// vadeli hesabı vade gününde yeniler); kullanıcı değiştirebilir.
  ///
  /// Neden seçilebilir (2026-10-01 emülatör testi): 7 ay önce vadesi dolup
  /// kendisi bugün yenileyen kullanıcı, 32 günlük dönemleri tek tek girmek
  /// zorunda kalıyordu — her biri yine geçmişte kalıp "vadesi doldu"
  /// diyordu. Seçilen gün ile eski vade arasındaki günler faizsiz, düz.
  /// Vadesizde (oran değişikliği) yeni oran bugünden işler, seçim yok.
  late DateTime _yeniBaslangic = widget.onceki.vadesiz
      ? dayKey(DateTime.now())
      : dayKey(widget.onceki.vadeSonu ?? DateTime.now());

  /// Kullanıcı stopajı elle değiştirdiyse vade/tarih değişikliği öneriyi
  /// üstüne yazmaz (formdaki kural).
  bool _stopajElle = false;

  @override
  void dispose() {
    _faiz.dispose();
    _stopaj.dispose();
    super.dispose();
  }

  void _gunSec(int g) {
    setState(() => _gun = g);
    _stopajOner();
  }

  void _stopajOner() {
    if (_stopajElle) return;
    _stopaj.text =
        fmtNumFlex(onerilenStopaj(_yeniBaslangic, _gun), maxDigits: 2);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final vadesiz = widget.onceki.vadesiz;
    final vadeIci = widget.vadeIci;
    final renk = AssetType.mevduat.color;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SandikSpace.lgs),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  vadesiz || vadeIci
                      ? l10n.depositRateUpdate
                      : l10n.depositRenewTitle,
                  style: context.t.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700, color: context.c.text90)),
              const SizedBox(height: SandikSpace.md),
              SozlesmeEtiketi(l10n.depositRate),
              SozlesmeAlani(
                controller: _faiz,
                ipucu: '0',
                sonek: '%',
                sayi: true,
                dogrula: (v) {
                  final x = parseTrNumber(v ?? '');
                  return x == null || x <= 0 || x >= 500
                      ? l10n.depositErrorRate
                      : null;
                },
              ),
              if (vadeIci) SozlesmeNotu(l10n.depositRateMidTermHint),
              if (!vadesiz && !vadeIci) ...[
                const SizedBox(height: SandikSpace.md),
                SozlesmeEtiketi(l10n.depositTerm),
                Wrap(
                  spacing: SandikSpace.sm,
                  runSpacing: SandikSpace.sm,
                  children: [
                    for (final g in {
                      ...MevduatHesabi.hizliVadeler,
                      if (widget.onceki.gun case final x?) x,
                    }.toList()
                      ..sort())
                      SozlesmeCipi(
                        icerigeGore: true,
                        metin: l10n.depositDays(g),
                        secili: _gun == g,
                        renk: renk,
                        secildi: () => _gunSec(g),
                      ),
                  ],
                ),
              ],
              if (!vadesiz && !vadeIci) ...[
                const SizedBox(height: SandikSpace.md),
                SozlesmeTarihi(
                  etiket: l10n.depositStart,
                  tarih: _yeniBaslangic,
                  ilk: dayKey(widget.onceki.baslangic)
                      .add(const Duration(days: 1)),
                  degisti: (d) => setState(() {
                    _yeniBaslangic = dayKey(d);
                    _stopajOner();
                  }),
                ),
                SozlesmeNotu(l10n.depositRenewStartHint),
              ],
              const SizedBox(height: SandikSpace.md),
              SozlesmeEtiketi(l10n.depositWithholding),
              SozlesmeAlani(
                controller: _stopaj,
                ipucu: '0',
                sonek: '%',
                sayi: true,
                degisti: (_) => _stopajElle = true,
                dogrula: (v) {
                  final x = parseTrNumber(v ?? '');
                  return x == null || x < 0 || x > 100
                      ? l10n.depositErrorWithholding
                      : null;
                },
              ),
              const SizedBox(height: SandikSpace.lg),
              _Eylem(
                metin: l10n.save,
                birincil: true,
                bas: () {
                  if (!(_form.currentState?.validate() ?? false)) return;
                  Navigator.of(context).pop<_YeniDonem>((
                    faiz: parseTrNumber(_faiz.text)!,
                    stopaj: parseTrNumber(_stopaj.text)!,
                    gun: vadesiz ? null : _gun,
                    bas: _yeniBaslangic,
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── BES ──────────────────────────────────────────────────────────────────

/// BES sözleşmesinin bugünkü dökümü — kartın ve testin ortak hesabı.
///
/// `katki` ve `devlet` ANAPARADIR (maliyet): "senin yatırdığın" ve
/// "devletin yatırdığı". İkisinin getirisi `getiri`de toplanır — üçü
/// toplamı verir (Σ parça == bütün).
({
  double toplam,
  double katki,
  double devlet,
  double getiri,
  double eldeKalan,
  double hakEdis,
}) besDokumu(Sozlesme s, List<Asset> lotlar, DateTime simdi) {
  var toplam = 0.0, katki = 0.0, devlet = 0.0, dkMaliyet = 0.0, kendi = 0.0;
  for (final p in aggregatePositions(lotlar)) {
    final dk = p.representative.subCategory == BesAltKategori.devletKatkisi;
    toplam += p.totalValue;
    if (dk) {
      devlet += p.totalValue;
      dkMaliyet += p.totalCost;
    } else {
      kendi += p.totalValue;
      katki += p.totalCost;
    }
  }
  final hak = BesHesabi.hakEdisOrani(s.baslangic, simdi);
  return (
    toplam: toplam,
    katki: katki,
    devlet: dkMaliyet,
    getiri: toplam - katki - dkMaliyet,
    // Çıkışta: kendi birikimin (katkı + getirisi) + devlet birikiminin hak
    // edilen payı. Vergi (stopaj) öncesi — oran sistemde kalınan süreye ve
    // yaşa bağlı; ekran "vergi öncesi" der.
    eldeKalan: kendi + devlet * hak / 100,
    hakEdis: hak,
  );
}

class _BesGovdesi extends ConsumerWidget {
  const _BesGovdesi({required this.s, required this.lotlar});
  final Sozlesme s;
  final List<Asset> lotlar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final simdi = DateTime.now();
    final d = besDokumu(s, lotlar, simdi);
    final yil = BesHesabi.tamYil(s.baslangic, simdi) + 1;
    final sonraki = BesHesabi.sonrakiBasamakSuresi(s.baslangic, simdi);
    final n = ref.read(sozlesmeProvider.notifier);
    final katkiTarihleri = n.katkiTarihleri(s.id);
    final katkiBekliyor = BesHesabi.katkiBekleniyor(
      s: s,
      simdi: simdi,
      katkiTarihleri: katkiTarihleri,
    );
    final buAyEklendi = BesHesabi.buAyKatkiVar(katkiTarihleri, simdi);
    // Otomatik yazılan, henüz onaylanmamış katkı (0096). Lotu silindiyse
    // soru da gösterilmez: düzeltilecek bir şey kalmadı.
    final bekleyen = s.acik ? n.otomatikKatkiLotlari(s.id) : null;
    final planTam = s.aylikKatki != null && s.katkiGunu != null;
    final parca = d.toplam <= 0
        ? null
        : (
            katki: (d.katki / d.toplam).clamp(0.0, 1.0),
            devlet: (d.devlet / d.toplam).clamp(0.0, 1.0),
          );

    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Baslik(
              tur: AssetType.bes, kurum: s.kurum, sag: l10n.pensionYear(yil)),
          const SizedBox(height: SandikSpace.smd),
          SozlesmeOzetSatiri(
            etiket: l10n.pensionTotal,
            deger: fmtTRY(d.toplam),
            vurgulu: true,
          ),
          if (parca != null) ...[
            const SizedBox(height: SandikSpace.sm),
            ClipRRect(
              borderRadius: SandikRadius.smAll,
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    Expanded(
                      flex: (parca.katki * 1000).round(),
                      child: ColoredBox(color: AssetType.bes.color),
                    ),
                    Expanded(
                      flex: (parca.devlet * 1000).round(),
                      child: ColoredBox(color: context.c.info),
                    ),
                    Expanded(
                      flex: ((1 - parca.katki - parca.devlet)
                                  .clamp(0.0, 1.0) *
                              1000)
                          .round(),
                      child: ColoredBox(color: context.c.gain),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: SandikSpace.sm),
          ],
          SozlesmeOzetSatiri(
              etiket: l10n.pensionOwn, deger: fmtTRY(d.katki)),
          SozlesmeOzetSatiri(
              etiket: l10n.pensionGovShort, deger: fmtTRY(d.devlet)),
          SozlesmeOzetSatiri(
            etiket: l10n.pensionReturn,
            deger: '${d.getiri >= 0 ? '+' : '−'}${fmtTRY(d.getiri.abs())}',
            renk: d.getiri >= 0 ? context.c.gain : context.c.loss,
          ),
          Divider(height: SandikSpace.lg, color: context.c.hairline),
          SozlesmeOzetSatiri(
              etiket: l10n.pensionIfLeave, deger: fmtTRY(d.eldeKalan)),
          SozlesmeOzetSatiri(
            etiket: l10n.pensionVesting,
            deger: sonraki == null
                ? fmtPct(d.hakEdis, digits: 0)
                : sonraki.yil == 0 && sonraki.ay == 0
                    ? l10n.pensionVestingSoon(fmtPct(d.hakEdis, digits: 0),
                        fmtPct(sonraki.oran, digits: 0))
                    : l10n.pensionVestingNextIn(
                        fmtPct(d.hakEdis, digits: 0),
                        sonraki.ay == 0
                            ? l10n.pensionYears(sonraki.yil)
                            : sonraki.yil == 0
                                ? l10n.pensionMonths(sonraki.ay)
                                : l10n.pensionYearsMonths(
                                    sonraki.yil, sonraki.ay),
                        fmtPct(sonraki.oran, digits: 0)),
          ),
          if (s.dkFonKodu == null) SozlesmeNotu(l10n.pensionNoGovFund),
          if (s.acik) ...[
            if (bekleyen != null) ...[
              const SizedBox(height: SandikSpace.smd),
              _OtomatikKatkiSorusu(
                gun: s.otomatikKatkiBekleyen!,
                tutar: bekleyen.tutar,
                dogru: () => _otomatikOnayla(context, ref),
                guncelle: () => _otomatikGuncelle(context, ref, bekleyen.tutar),
              ),
            ] else if (katkiBekliyor) ...[
              // Otomatik açıkken de gösterilir: bu ayın katkısı yazılamadıysa
              // (fiyat yok, ağ yok) kullanıcı elle ekleyebilsin.
              const SizedBox(height: SandikSpace.smd),
              Text(l10n.pensionContributionDue,
                  style: context.t.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.c.amberText)),
            ],
            if (planTam) ...[
              const SizedBox(height: SandikSpace.sm),
              MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.pensionAuto,
                        style: context.t.bodyMedium?.copyWith(
                            color: context.c.text90,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    Switch.adaptive(
                      value: s.otomatikKatki,
                      activeTrackColor: context.c.amberText,
                      onChanged: (v) => _otomatikAyarla(context, ref, v),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: SandikSpace.smd),
            _Eylem(
              // Düğme kalır (ara katkı yapılabilir) ama ay dolduysa adı
              // değişir.
              metin: buAyEklendi
                  ? l10n.pensionAddExtraContribution
                  : l10n.pensionAddContribution,
              birincil: katkiBekliyor,
              bas: () => _katkiEkle(context, ref),
            ),
            const SizedBox(height: SandikSpace.sm),
            _Eylem(
              metin: l10n.pensionSwitchFunds,
              bas: () => _fonDegistir(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _katkiEkle(BuildContext context, WidgetRef ref) async {
    if (DemoModu.yazmaKapisi('bes')) return;
    final l10n = context.l10n;
    final n = ref.read(sozlesmeProvider.notifier);
    final simdi = DateTime.now();
    final sonuc = await showModalBottomSheet<({double tutar, double dk})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => _KatkiSayfasi(
        s: s,
        buYilDevlet: n.buYilDevletKatkisi(s.id, simdi.year),
      ),
    );
    if (sonuc == null || !context.mounted) return;
    final kurum = s.kurum;
    final devletEtiketi = l10n.pensionGovShort;
    try {
      await n.besKatkiEkle(
        sozlesmeId: s.id,
        tutar: sonuc.tutar,
        devletKatkisi: sonuc.dk,
        adUret: (kod, {required devlet}) =>
            devlet ? '$kurum · $kod · $devletEtiketi' : '$kurum · $kod',
      );
      if (context.mounted) {
        sandikSnack(context, l10n.pensionContributionSaved,
            kind: SandikSnackKind.success);
      }
    } on BesFiyatYokException catch (e) {
      if (context.mounted) {
        sandikSnack(context, l10n.pensionPriceMissing(e.kod),
            kind: SandikSnackKind.error);
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SozlesmeKarti.katki');
      if (context.mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
    }
  }
}

/// Kendi birikiminin bugünkü dağılımı (değer oranı, %) — "Fon değiştir"
/// sayfası bununla açılır. Devlet katkısı hariç.
List<FonPayi> besBugunkuDagilim(List<Asset> lotlar) {
  final p = [
    for (final x in aggregatePositions(lotlar))
      if (x.representative.subCategory != BesAltKategori.devletKatkisi) x,
  ];
  final toplam = p.fold<double>(0, (t, x) => t + x.totalValue);
  if (toplam <= 0) return const [];
  return [
    for (final x in p)
      FonPayi(
        kod: x.representative.ticker.replaceFirst(tefasOneki, ''),
        // Tam sayıya yuvarlanır (talimatlar tam yüzdeyle verilir); son fon
        // kalanı alır ki toplam %100 olsun.
        oran: (x.totalValue / toplam * 100).roundToDouble(),
      ),
  ]..sort((a, b) => b.oran.compareTo(a.oran));
}

/// "Katkın otomatik eklendi, tutarı güncellemek ister misin?" (0096).
class _OtomatikKatkiSorusu extends StatelessWidget {
  const _OtomatikKatkiSorusu({
    required this.gun,
    required this.tutar,
    required this.dogru,
    required this.guncelle,
  });
  final DateTime gun;
  final double tutar;
  final VoidCallback dogru;
  final VoidCallback guncelle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(SandikSpace.smd),
      decoration: BoxDecoration(
        color: context.c.amberFill.withValues(alpha: 0.12),
        borderRadius: SandikRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.pensionAutoAdded(
                DateFormat.MMMMd(l10n.localeName).format(gun), fmtTRY(tutar)),
            style: context.t.bodySmall?.copyWith(
                color: context.c.text90, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: SandikSpace.smd),
          Row(
            children: [
              Expanded(child: _Eylem(metin: l10n.pensionAutoConfirm, bas: dogru)),
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                child: _Eylem(
                    metin: l10n.pensionAutoUpdate,
                    birincil: true,
                    bas: guncelle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Otomatik katkı eylemleri — sayılar `SozlesmeNotifier`'da.
extension on _BesGovdesi {
  Future<void> _otomatikAyarla(
      BuildContext context, WidgetRef ref, bool acik) async {
    if (DemoModu.yazmaKapisi('bes')) return;
    try {
      await ref.read(sozlesmeProvider.notifier).otomatikKatkiAyarla(s.id, acik);
      if (!acik || !context.mounted) return;
      // Açıldığı an bu ayın günü geçmişse hemen yazılsın; beklemesin.
      final l10n = context.l10n;
      final devletEtiketi = l10n.pensionGovShort;
      await ref.read(sozlesmeProvider.notifier).otomatikKatkilariIsle(
            adUret: (x, kod, {required devlet}) => devlet
                ? '${x.kurum} · $kod · $devletEtiketi'
                : '${x.kurum} · $kod',
            not: l10n.pensionAutoLotNote,
          );
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SozlesmeKarti.otomatikAyarla');
      if (context.mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
    }
  }

  Future<void> _otomatikOnayla(BuildContext context, WidgetRef ref) async {
    if (DemoModu.yazmaKapisi('bes')) return;
    try {
      await ref.read(sozlesmeProvider.notifier).otomatikKatkiOnayla(s.id);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SozlesmeKarti.otomatikOnayla');
      if (context.mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
    }
  }

  Future<void> _otomatikGuncelle(
      BuildContext context, WidgetRef ref, double tutar) async {
    if (DemoModu.yazmaKapisi('bes')) return;
    final l10n = context.l10n;
    final sonuc = await showModalBottomSheet<({double tutar, bool plan})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => _OtomatikGuncelleSayfasi(tutar: tutar),
    );
    if (sonuc == null || !context.mounted) return;
    try {
      await ref.read(sozlesmeProvider.notifier).otomatikKatkiGuncelle(
            sozlesmeId: s.id,
            yeniTutar: sonuc.tutar,
            planiDa: sonuc.plan,
          );
      if (context.mounted) {
        sandikSnack(context, l10n.pensionAutoUpdated,
            kind: SandikSnackKind.success);
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SozlesmeKarti.otomatikGuncelle');
      if (context.mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
    }
  }
}

/// Otomatik yazılan katkının tutarı: yeni tutar + "sonraki aylar da".
class _OtomatikGuncelleSayfasi extends StatefulWidget {
  const _OtomatikGuncelleSayfasi({required this.tutar});
  final double tutar;

  @override
  State<_OtomatikGuncelleSayfasi> createState() =>
      _OtomatikGuncelleSayfasiState();
}

class _OtomatikGuncelleSayfasiState extends State<_OtomatikGuncelleSayfasi> {
  final _form = GlobalKey<FormState>();
  late final _tutar =
      TextEditingController(text: fmtNumFlex(widget.tutar, maxDigits: 2));
  // Varsayılan açık: tutar değiştiyse çoğunlukla talimat değişmiştir.
  bool _plan = true;

  @override
  void dispose() {
    _tutar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SandikSpace.lgs),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.pensionAutoUpdateTitle,
                  style: context.t.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700, color: context.c.text90)),
              const SizedBox(height: SandikSpace.md),
              SozlesmeEtiketi(l10n.pensionContributionAmount),
              SozlesmeAlani(
                controller: _tutar,
                ipucu: '0',
                sonek: '₺',
                sayi: true,
                dogrula: (v) {
                  final x = parseTrNumber(v ?? '');
                  return x == null || x <= 0 ? l10n.depositErrorPrincipal : null;
                },
              ),
              const SizedBox(height: SandikSpace.smd),
              MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.pensionAutoUpdatePlan,
                        style: context.t.bodyMedium
                            ?.copyWith(color: context.c.text90),
                      ),
                    ),
                    Switch.adaptive(
                      value: _plan,
                      activeTrackColor: context.c.amberText,
                      onChanged: (v) => setState(() => _plan = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SandikSpace.lg),
              _Eylem(
                metin: l10n.save,
                birincil: true,
                bas: () {
                  if (!(_form.currentState?.validate() ?? false)) return;
                  Navigator.of(context)
                      .pop((tutar: parseTrNumber(_tutar.text)!, plan: _plan));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _BesGovdesi {
  Future<void> _fonDegistir(BuildContext context, WidgetRef ref) async {
    if (DemoModu.yazmaKapisi('bes')) return;
    final l10n = context.l10n;
    final n = ref.read(sozlesmeProvider.notifier);
    var bugunku = besBugunkuDagilim(lotlar);
    if (bugunku.isNotEmpty) {
      final digerleri = bugunku
          .skip(1)
          .fold<double>(0, (t, f) => t + f.oran);
      bugunku = [
        FonPayi(kod: bugunku.first.kod, oran: 100 - digerleri),
        ...bugunku.skip(1),
      ];
    }
    final sonuc =
        await showModalBottomSheet<({List<FonPayi> dagilim, bool katki})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => _FonDegisimSayfasi(
        bugunku: bugunku,
        buYil: n.buYilFonDegisikligi(s.id, DateTime.now().year),
      ),
    );
    if (sonuc == null || !context.mounted) return;
    final kurum = s.kurum;
    final devletEtiketi = l10n.pensionGovShort;
    try {
      final yazilan = await n.besFonDegistir(
        sozlesmeId: s.id,
        yeniDagilim: sonuc.dagilim,
        katkiTalimatiDa: sonuc.katki,
        adUret: (kod, {required devlet}) =>
            devlet ? '$kurum · $kod · $devletEtiketi' : '$kurum · $kod',
        not: l10n.pensionSwitchNote,
      );
      if (context.mounted) {
        sandikSnack(
            context,
            yazilan == 0 && !sonuc.katki
                ? l10n.pensionSwitchSame
                : l10n.pensionSwitchSaved,
            kind: SandikSnackKind.success);
      }
    } on BesFiyatYokException catch (e) {
      if (context.mounted) {
        sandikSnack(context, l10n.pensionPriceMissing(e.kod),
            kind: SandikSnackKind.error);
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SozlesmeKarti.fonDegistir');
      if (context.mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
    }
  }
}

class _FonDegisimSayfasi extends StatefulWidget {
  const _FonDegisimSayfasi({required this.bugunku, required this.buYil});
  final List<FonPayi> bugunku;
  final int buYil;

  @override
  State<_FonDegisimSayfasi> createState() => _FonDegisimSayfasiState();
}

class _FonDegisimSayfasiState extends State<_FonDegisimSayfasi> {
  final _editor = GlobalKey<BesDagilimEditoruState>();
  bool _katkiDa = true;
  String? _hata;

  void _kaydet() {
    final l10n = context.l10n;
    final d = _editor.currentState?.dagilim ?? const <FonPayi>[];
    final hata = d.isEmpty
        ? l10n.pensionFundError
        : !BesHesabi.dagilimGecerli(d)
            ? l10n.pensionShareError
            : null;
    if (hata != null) {
      setState(() => _hata = hata);
      return;
    }
    Navigator.of(context).pop((dagilim: d, katki: _katkiDa));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SandikSpace.lgs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.pensionSwitchTitle,
                style: context.t.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700, color: context.c.text90)),
            SozlesmeNotu(l10n.pensionSwitchHint),
            const SizedBox(height: SandikSpace.md),
            BesDagilimEditoru(
              key: _editor,
              baslangic: widget.bugunku,
              hata: _hata,
              degisti: () {
                if (_hata != null) setState(() => _hata = null);
              },
            ),
            CheckboxListTile(
              value: _katkiDa,
              onChanged: (v) => setState(() => _katkiDa = v ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.pensionSwitchContributions,
                  style: context.t.bodyMedium
                      ?.copyWith(color: context.c.text90)),
            ),
            SozlesmeNotu(l10n.pensionSwitchCount(widget.buYil)),
            const SizedBox(height: SandikSpace.lg),
            _Eylem(metin: l10n.save, birincil: true, bas: _kaydet),
          ],
        ),
      ),
    );
  }
}

class _KatkiSayfasi extends StatefulWidget {
  const _KatkiSayfasi({required this.s, required this.buYilDevlet});
  final Sozlesme s;
  final double buYilDevlet;

  @override
  State<_KatkiSayfasi> createState() => _KatkiSayfasiState();
}

class _KatkiSayfasiState extends State<_KatkiSayfasi> {
  final _form = GlobalKey<FormState>();
  late final _tutar = TextEditingController(
      text: widget.s.aylikKatki == null
          ? ''
          : fmtNumFlex(widget.s.aylikKatki!, maxDigits: 2));
  final _dk = TextEditingController();
  bool _dkElle = false;
  bool _sinirDoldu = false;

  @override
  void initState() {
    super.initState();
    _dkHesapla();
    _tutar.addListener(_dkHesapla);
  }

  @override
  void dispose() {
    _tutar.dispose();
    _dk.dispose();
    super.dispose();
  }

  void _dkHesapla() {
    if (_dkElle || widget.s.dkFonKodu == null) return;
    final t = parseTrNumber(_tutar.text) ?? 0;
    final r = BesHesabi.devletKatkisi(
        katki: t, tarih: DateTime.now(), buYilAlinan: widget.buYilDevlet);
    _dk.text = r.tutar > 0 ? fmtNumFlex(r.tutar, maxDigits: 2) : '0';
    if (_sinirDoldu != r.sinirDoldu) setState(() => _sinirDoldu = r.sinirDoldu);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dkVar = widget.s.dkFonKodu != null;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SandikSpace.lgs),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.pensionContributionTitle,
                  style: context.t.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700, color: context.c.text90)),
              const SizedBox(height: SandikSpace.md),
              SozlesmeEtiketi(l10n.pensionContributionAmount),
              SozlesmeAlani(
                controller: _tutar,
                ipucu: '0',
                sonek: '₺',
                sayi: true,
                dogrula: (v) {
                  final x = parseTrNumber(v ?? '');
                  return x == null || x <= 0 ? l10n.depositErrorPrincipal : null;
                },
              ),
              const SizedBox(height: SandikSpace.md),
              if (dkVar) ...[
                SozlesmeEtiketi(l10n.pensionGov),
                SozlesmeAlani(
                  controller: _dk,
                  ipucu: '0',
                  sonek: '₺',
                  sayi: true,
                  degisti: (_) => _dkElle = true,
                ),
                if (_sinirDoldu)
                  SozlesmeNotu(l10n.pensionContributionGovCapped),
              ] else
                SozlesmeNotu(l10n.pensionNoGovFund),
              const SizedBox(height: SandikSpace.lg),
              _Eylem(
                metin: l10n.save,
                birincil: true,
                bas: () {
                  if (!(_form.currentState?.validate() ?? false)) return;
                  Navigator.of(context).pop((
                    tutar: parseTrNumber(_tutar.text)!,
                    dk: dkVar ? (parseTrNumber(_dk.text) ?? 0) : 0.0,
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
