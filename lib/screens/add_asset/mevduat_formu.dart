import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../demo/demo_modu.dart';
import '../../l10n/l10n.dart';
import '../../models/asset_type.dart';
import '../../models/mevduat_bankasi.dart';
import '../../providers/mevduat_banka_provider.dart';
import '../../providers/sozlesme_provider.dart';
import '../../services/crash_reporter.dart';
import '../../services/mevduat_hesabi.dart';
import '../../services/remote_config_service.dart';
import '../../theme/sandik.dart';
import '../../utils/friendly_error.dart';
import '../../utils/sandik_snack.dart';
import '../../utils/tr_format.dart';
import '../../widgets/sozlesme_formu_ortak.dart';
import 'mevduat_banka_secici.dart';

/// Vadeli / günlük faizli mevduat girişi (seçenek M2 + M3).
///
/// Girdi kullanıcının banka ekranında gördüğü sayılardır: banka, tutar,
/// yıllık brüt faiz, vade. Stopaj vadeye göre ÖNERİLİR
/// (`onerilenStopaj`), kullanıcı elle değiştirirse öneri bir daha üstüne
/// yazmaz. Özet satırları (vade sonu, net getiri) aynı hesap motorundan
/// gelir; kaydedilen lotun değeri de o motorla hesaplanır — formda
/// gösterilen ile portföyde görünen aynı sayıdır.
///
/// Bayrak `mevduat_banka_secici` (2026-10-09) açıkken: banka listeden
/// seçilir; yıllık brüt faiz vadeye göre TCMB haftalık ortalamasıyla
/// ÖNERİLİR (stopaj önerisiyle aynı kural: elle yazılınca bir daha üstüne
/// yazılmaz), yanında aylık brüt (= yıllık / 12, iki yönlü); mevduata not
/// yazılır. Kapalıyken form birebir eski.
class MevduatFormu extends ConsumerStatefulWidget {
  const MevduatFormu({super.key});

  @override
  ConsumerState<MevduatFormu> createState() => MevduatFormuState();
}

class MevduatFormuState extends ConsumerState<MevduatFormu>
    implements SozlesmeFormu {
  final _form = GlobalKey<FormState>();
  final _banka = TextEditingController();
  final _anapara = TextEditingController();
  final _faiz = TextEditingController();
  final _ozelGun = TextEditingController();
  final _stopaj = TextEditingController();
  final _aylik = TextEditingController();
  final _not = TextEditingController();

  /// Bayrak form açılışında bir kez okunur: form açıkken Remote Config
  /// yenilenirse alanlar yer değiştirmesin.
  late final bool _secici = RemoteConfigService.instance.mevduatBankaSecici;

  /// Listeden seçilen banka; elle yazılan adda `null`.
  MevduatBankasi? _secilenBanka;

  /// Kullanıcı faizi (yıllık ya da aylık) kendisi yazdı: ortalama bir daha
  /// üstüne yazılmaz — "müşteriye özel oran verildiyse değiştirebilsin".
  bool _faizElle = false;

  /// Faiz alanında şu an TCMB ortalaması duruyorsa o verinin haftası
  /// (notta gösterilir); elle yazılmış ya da boşsa `null`.
  DateTime? _ortalamaHaftasi;

  bool _vadesiz = false;
  int? _vade = 32; // null = özel
  DateTime _baslangic = _bugun();
  bool _stopajElle = false;

  /// İlk başarısız "Ekle"den sonra alanlar yazdıkça doğrulanır: hata metni
  /// alan düzeltilince kalkar. Eskiden bir sonraki "Ekle"ye kadar kırmızı
  /// kalıyordu (2026-10-01 emülatör testi). İlk açılışta form kızarmaz.
  bool _denendi = false;

  static DateTime _bugun() {
    final n = DateTime.now();
    return dayKey(n);
  }

  @override
  void initState() {
    super.initState();
    _stopajOner();
    for (final c in [_anapara, _faiz, _ozelGun, _stopaj]) {
      c.addListener(_yenile);
    }
    if (_secici) {
      // Liste ve ortalamalar form açılınca bir kez okunur (oturumda
      // önbellekli); gelince boş faiz alanı önerilir.
      ref.listenManual(mevduatKaynaklariProvider, (_, __) {
        if (mounted) setState(_faizOner);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _banka,
      _anapara,
      _faiz,
      _ozelGun,
      _stopaj,
      _aylik,
      _not
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _yenile() {
    if (mounted) setState(() {});
  }

  int? get _gun {
    if (_vadesiz) return null;
    return _vade ?? int.tryParse(_ozelGun.text.trim());
  }

  void _stopajOner() {
    if (_stopajElle) return;
    final oneri = onerilenStopaj(_baslangic, _gun);
    _stopaj.text = fmtNumFlex(oneri, maxDigits: 2);
    _faizOner();
  }

  /// Faiz önerisi: seçilen banka + vade → TCMB ortalaması (basit yıllığa
  /// çevrilmiş). Öneri artık geçerli değilse (katılım bankası, vadesiz,
  /// dilimin verisi yok) daha önce YAZDIĞIMIZ öneri silinir — eski vadenin
  /// ortalaması yeni vadede yanlış bilgi olurdu. Elle yazılana dokunulmaz.
  void _faizOner() {
    if (!_secici || _faizElle) return;
    final k = ref.read(mevduatKaynaklariProvider).valueOrNull;
    final v = mevduatVarsayilanFaiz(
      banka: _secilenBanka,
      gun: _vadesiz ? null : _gun,
      ortalamalar: k?.ortalamalar ?? const {},
    );
    if (v == null) {
      if (_ortalamaHaftasi != null) {
        _faiz.clear();
        _aylik.clear();
        _ortalamaHaftasi = null;
      }
      return;
    }
    _faiz.text = fmtNumFlex(v.oran, maxDigits: 2);
    _aylik.text = fmtNumFlex(v.oran / 12, maxDigits: 2);
    _ortalamaHaftasi = v.hafta;
  }

  /// Yıllık ↔ aylık brüt: biri yazılınca öteki hesaplanır (aylık = yıllık
  /// / 12, bankaların ekranındaki basit oran). İkisi de "elle" sayılır.
  void _yillikYazildi(String v) {
    final x = parseTrNumber(v);
    setState(() {
      _faizElle = true;
      _ortalamaHaftasi = null;
      _aylik.text = x == null ? '' : fmtNumFlex(x / 12, maxDigits: 2);
    });
  }

  void _aylikYazildi(String v) {
    final x = parseTrNumber(v);
    setState(() {
      _faizElle = true;
      _ortalamaHaftasi = null;
      _faiz.text = x == null ? '' : fmtNumFlex(x * 12, maxDigits: 2);
    });
  }

  Future<void> _bankaSec() async {
    final r = await mevduatBankasiSec(context, seciliKod: _secilenBanka?.kod);
    if (r == null || !mounted) return;
    setState(() {
      _secilenBanka = r.banka;
      _banka.text = r.ad;
      _faizOner();
    });
  }

  @override
  Future<bool> kaydet() async {
    if (DemoModu.yazmaKapisi('mevduat')) return false;
    if (!(_form.currentState?.validate() ?? false)) {
      setState(() => _denendi = true);
      return false;
    }
    final l10n = context.l10n;
    final kurum = _banka.text.trim();
    final tur = _vadesiz ? l10n.depositKindDaily : l10n.depositKindTerm;
    try {
      await ref.read(sozlesmeProvider.notifier).mevduatAc(
            kurum: kurum,
            ad: '$kurum · $tur',
            anapara: parseTrNumber(_anapara.text)!,
            yillikFaiz: parseTrNumber(_faiz.text)!,
            stopaj: parseTrNumber(_stopaj.text)!,
            baslangic: _baslangic,
            vadeGun: _gun,
            not: _secici ? _not.text : '',
          );
      return true;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'MevduatFormu.kaydet');
      if (mounted) {
        sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      }
      return false;
    }
  }

  String? _faizHatasi(String? v, AppLocalizations l10n) {
    final x = parseTrNumber(v ?? '');
    return x == null || x <= 0 || x >= 500 ? l10n.depositErrorRate : null;
  }

  /// Faiz alanlarının altındaki not: önerinin kaynağı ve "bankaya özel
  /// değil" uyarısı, elle oran, katılım bankası. Söylenecek bir şey yoksa
  /// (banka seçilmemiş, vadesiz) `null` — boş not yazılmaz.
  String? _faizNotu(AppLocalizations l10n) {
    if (_faizElle) return l10n.depositRateOwn;
    if (_secilenBanka?.katilim ?? false) return l10n.depositRateParticipation;
    final h = _ortalamaHaftasi;
    if (h != null) {
      return l10n.depositRateMarketAverage(
          DateFormat.yMMMd(l10n.localeName).format(h));
    }
    return null;
  }

  String? _pozitif(String? v, String hata) {
    final x = parseTrNumber(v ?? '');
    return x == null || x <= 0 ? hata : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final renk = AssetType.mevduat.color;
    final gun = _gun;
    final vadeSonu =
        _vadesiz || gun == null ? null : _baslangic.add(Duration(days: gun));
    final vadeGecmiste =
        vadeSonu != null && !vadeSonu.isAfter(dayKey(DateTime.now()));
    return Form(
      key: _form,
      autovalidateMode: _denendi
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SozlesmeEtiketi(l10n.depositBank),
          if (_secici)
            SozlesmeAlani(
              controller: _banka,
              ipucu: l10n.depositBankPick,
              dokununca: _bankaSec,
              onek: _secilenBanka == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: SandikSpace.smd),
                      child: MevduatBankaRozeti(_secilenBanka!.rozet),
                    ),
              dogrula: (v) =>
                  (v ?? '').trim().isEmpty ? l10n.depositErrorBank : null,
            )
          else
            SozlesmeAlani(
              controller: _banka,
              ipucu: l10n.depositBankHint,
              buyukHarf: true,
              dogrula: (v) =>
                  (v ?? '').trim().isEmpty ? l10n.depositErrorBank : null,
            ),
          const SizedBox(height: SandikSpace.lgs),
          Row(
            children: [
              Expanded(
                child: SozlesmeCipi(
                  metin: l10n.depositKindTerm,
                  secili: !_vadesiz,
                  renk: renk,
                  secildi: () => setState(() {
                    _vadesiz = false;
                    _stopajOner();
                  }),
                ),
              ),
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                child: SozlesmeCipi(
                  metin: l10n.depositKindDaily,
                  secili: _vadesiz,
                  renk: renk,
                  secildi: () => setState(() {
                    _vadesiz = true;
                    _stopajOner();
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.lgs),
          if (_secici) ...[
            SozlesmeEtiketi(l10n.depositPrincipal),
            SozlesmeAlani(
              controller: _anapara,
              ipucu: '0',
              sonek: '₺',
              sayi: true,
              dogrula: (v) => _pozitif(v, l10n.depositErrorPrincipal),
            ),
            const SizedBox(height: SandikSpace.lgs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SozlesmeEtiketi(l10n.depositRateAnnualGross),
                      SozlesmeAlani(
                        controller: _faiz,
                        ipucu: '0',
                        sonek: '%',
                        sayi: true,
                        degisti: _yillikYazildi,
                        dogrula: (v) => _faizHatasi(v, l10n),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SandikSpace.smd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SozlesmeEtiketi(l10n.depositRateMonthlyGross),
                      SozlesmeAlani(
                        controller: _aylik,
                        ipucu: '0',
                        sonek: '%',
                        sayi: true,
                        degisti: _aylikYazildi,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_faizNotu(l10n) case final not?) SozlesmeNotu(not),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SozlesmeEtiketi(l10n.depositPrincipal),
                      SozlesmeAlani(
                        controller: _anapara,
                        ipucu: '0',
                        sonek: '₺',
                        sayi: true,
                        dogrula: (v) => _pozitif(v, l10n.depositErrorPrincipal),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SandikSpace.smd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SozlesmeEtiketi(l10n.depositRate),
                      SozlesmeAlani(
                        controller: _faiz,
                        ipucu: '0',
                        sonek: '%',
                        sayi: true,
                        dogrula: (v) => _faizHatasi(v, l10n),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          if (!_vadesiz) ...[
            const SizedBox(height: SandikSpace.lgs),
            SozlesmeEtiketi(l10n.depositTerm),
            Wrap(
              spacing: SandikSpace.sm,
              runSpacing: SandikSpace.sm,
              children: [
                for (final g in MevduatHesabi.hizliVadeler)
                  SozlesmeCipi(
                    icerigeGore: true,
                    metin: l10n.depositDays(g),
                    secili: _vade == g,
                    renk: renk,
                    secildi: () => setState(() {
                      _vade = g;
                      _stopajOner();
                    }),
                  ),
                SozlesmeCipi(
                  icerigeGore: true,
                  metin: l10n.depositCustomDays,
                  secili: _vade == null,
                  renk: renk,
                  secildi: () => setState(() {
                    _vade = null;
                    _stopajOner();
                  }),
                ),
              ],
            ),
            if (_vade == null) ...[
              const SizedBox(height: SandikSpace.sm),
              SozlesmeAlani(
                controller: _ozelGun,
                ipucu: l10n.depositCustomDaysHint,
                sayi: true,
                degisti: (_) => setState(_stopajOner),
                dogrula: (v) {
                  final g = int.tryParse((v ?? '').trim());
                  return g == null || g <= 0 || g > 3660
                      ? l10n.depositErrorDays
                      : null;
                },
              ),
            ],
          ],
          const SizedBox(height: SandikSpace.lgs),
          SozlesmeTarihi(
            etiket: l10n.depositStart,
            tarih: _baslangic,
            degisti: (d) => setState(() {
              _baslangic = dayKey(d);
              _stopajOner();
            }),
          ),
          const SizedBox(height: SandikSpace.lgs),
          SozlesmeEtiketi(l10n.depositWithholding),
          SozlesmeAlani(
            controller: _stopaj,
            ipucu: '0',
            sonek: '%',
            sayi: true,
            degisti: (_) {
              if (!_stopajElle) setState(() => _stopajElle = true);
            },
            dogrula: (v) {
              final x = parseTrNumber(v ?? '');
              return x == null || x < 0 || x > 100
                  ? l10n.depositErrorWithholding
                  : null;
            },
          ),
          // Elle girilen oranın altında "vadeye göre önerildi" yazmak yanlış
          // bilgiydi; öneri artık üstüne yazmıyor, not da bunu söyler.
          SozlesmeNotu(_stopajElle
              ? l10n.depositWithholdingManual
              : l10n.depositWithholdingHint),
          if (_secici) ...[
            const SizedBox(height: SandikSpace.lgs),
            SozlesmeEtiketi(l10n.depositNote),
            SozlesmeAlani(
              controller: _not,
              ipucu: l10n.depositNoteHint,
              enFazlaSatir: 3,
              enFazlaKarakter: 300,
            ),
          ],
          const SizedBox(height: SandikSpace.lgs),
          _Ozet(
            anapara: parseTrNumber(_anapara.text),
            faiz: parseTrNumber(_faiz.text),
            stopaj: parseTrNumber(_stopaj.text),
            gun: _gun,
            vadesiz: _vadesiz,
            baslangic: _baslangic,
          ),
          if (vadeGecmiste)
            SozlesmeNotu(l10n.depositAlreadyMatured(
                DateFormat.yMMMd(l10n.localeName).format(vadeSonu))),
          // Vadesiz hesabın bozulacak vadesi yok; "vadeyi erken bozarsan"
          // notu orada yanlıştı.
          SozlesmeNotu(_vadesiz
              ? l10n.depositAccrualNoteDaily
              : l10n.depositAccrualNote),
        ],
      ),
    );
  }
}

class _Ozet extends StatelessWidget {
  const _Ozet({
    required this.anapara,
    required this.faiz,
    required this.stopaj,
    required this.gun,
    required this.vadesiz,
    required this.baslangic,
  });

  final double? anapara;
  final double? faiz;
  final double? stopaj;
  final int? gun;
  final bool vadesiz;
  final DateTime baslangic;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final a = anapara, f = faiz, s = stopaj;
    if (a == null || a <= 0 || f == null || f <= 0 || s == null) {
      return const SizedBox.shrink();
    }
    final satirlar = <Widget>[];
    if (vadesiz) {
      final gunluk =
          MevduatHesabi.gunlukNetFaiz(anapara: a, yillikFaiz: f, stopaj: s);
      satirlar.add(SozlesmeOzetSatiri(
        etiket: l10n.depositDailyNet,
        deger: '+${fmtTRY(gunluk, digits: 2)}',
        renk: context.c.gain,
        vurgulu: true,
      ));
    } else {
      final g = gun;
      if (g == null || g <= 0) return const SizedBox.shrink();
      final net = MevduatHesabi.donemNetFaizi(
          anapara: a, yillikFaiz: f, stopaj: s, gun: g);
      final vade = baslangic.add(Duration(days: g));
      satirlar.addAll([
        SozlesmeOzetSatiri(
          etiket: l10n.depositMaturity,
          deger: DateFormat.yMMMd(l10n.localeName).format(vade),
        ),
        SozlesmeOzetSatiri(
          etiket: l10n.depositNetReturn,
          deger: '+${fmtTRY(net, digits: 2)}',
          renk: context.c.gain,
        ),
        SozlesmeOzetSatiri(
          etiket: l10n.depositAtMaturity,
          deger: fmtTRY(a + net, digits: 2),
          vurgulu: true,
        ),
      ]);
    }
    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: satirlar,
      ),
    );
  }
}
