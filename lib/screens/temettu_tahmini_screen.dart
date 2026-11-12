import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../providers/temettu_tahmini_provider.dart';
import '../services/seni_ilgilendiren_gunler.dart' show temettuGunleri;
import '../services/takvim_ics.dart';
import '../services/temettu_tahmini.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/premium_kilit_karti.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_bos_durum.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/sandik_skeleton.dart';
import '../widgets/takvime_ekle_dugmesi.dart';

/// Önümüzdeki 12 ayın temettü tahmini (Premium, 2026-10-10).
///
/// Kural `temettu_tahmini.dart`'ta ve ekranda cümleyle yazılı: son 12 ayın
/// gerçekleşmiş temettüsü bugünkü lotunla tekrarlanırsa. Sayılar "tahmini"
/// diye anılır; şirket kararı ya da yeni yıl beklentisi tahmin edilmez.
class TemettuTahminiScreen extends ConsumerWidget {
  const TemettuTahminiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (ref.watch(premiumKilitliProvider)) {
      return Scaffold(
        appBar: SandikAppBar(title: l.ttBaslik),
        body: PremiumKilitGovdesi(
          kart: PremiumKilitKarti(
            ikon: Icons.event_repeat_rounded,
            baslik: l.ttBaslik,
            govde: l.ttKilitGovde,
            kilitMetni: l.ttKilitSatir,
            kaynak: 'temettu_tahmini',
          ),
        ),
      );
    }
    final tahmin = ref.watch(temettuTahminiProvider);
    return Scaffold(
      appBar: SandikAppBar(title: l.ttBaslik),
      body: SandikIcerikGecisi(
        // Yükleme → içerik çapraz solar (2026-10-14).
        tamEkran: true,
        anahtar: SandikIcerikGecisi.hal([tahmin]),
        child: tahmin.when(
        loading: () => const SandikSkeletonList(rows: 4),
        error: (e, _) => SandikErrorView(
            error: e, onRetry: () => ref.invalidate(temettuTahminiProvider)),
        data: (t) => t.bos
            ? SandikBosDurum(metin: l.ttBos, alt: l.ttBosAlt)
            : _Govde(t: t),
      ),
      ),
    );
  }
}

class _Govde extends StatefulWidget {
  const _Govde({required this.t});

  final TemettuTahmini t;

  @override
  State<_Govde> createState() => _GovdeState();
}

/// Aya dokun → süz (2026-11-12). Seçim yalnız bu ekranın anlık durumu;
/// kalıcı değil (ekrana yeniden girişte tümü görünür).
class _GovdeState extends State<_Govde> {
  /// Seçili ay (1-12); `null` = tümü.
  int? _ay;

  void _sec(int ay) {
    // Aynı çubuğa ikinci dokunuş seçimi kaldırır — ayrı bir "tümü"
    // düğmesi yerine dokunulan yerin kendisi geri alır.
    setState(() => _ay = _ay == ay ? null : ay);
    SandikHaptic.selection.perform();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final h = SandikSpace.screenH(context);
    final t = widget.t;
    final net = t.netTry;
    final ay = _ay;
    final dil = Localizations.localeOf(context).toString();
    // Süzme ayın beklenen ödeme aylarına göre (`TahminSatiri.aylar`).
    final satirlar = ay == null
        ? t.satirlar
        : t.satirlar.where((s) => s.aylar.contains(ay)).toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(h, SandikSpace.sm, h, SandikSpace.xl),
      children: [
        SandikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Seçili ay yalnız çubuğun renginden değil, buradaki ay adı
              // ve tutardan da okunur (renk körlüğü, HIG).
              Text(
                  ay == null
                      ? l.ttToplamEtiket
                      : l.ttAyEtiket(
                          DateFormat.MMMM(dil).format(DateTime(2000, ay))),
                  style: context.t.bodyMedium?.copyWith(color: c.text58)),
              const SizedBox(height: SandikSpace.xs),
              Text(
                  fmtTRY(ay == null ? (net ?? t.brutTry) : t.aylik[ay - 1]),
                  style: context.t.numLarge
                      .copyWith(fontWeight: FontWeight.w600, color: c.gold)),
              const SizedBox(height: SandikSpace.xxs),
              Text(
                // Aylık dağılım brüt tutulur (`TemettuTahmini.aylik`); ay
                // seçiliyken net iddia edilmez.
                ay != null
                    ? l.ttAyNot
                    : net == null
                        ? l.ttBrutNot
                        : l.ttNetNot(fmtTRY(t.brutTry)),
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
              const SizedBox(height: SandikSpace.md),
              _AyCubuklari(aylik: t.aylik, secili: ay, onSec: _sec),
            ],
          ),
        ),
        const SizedBox(height: SandikSpace.lg),
        SandikSectionHeader(title: l.ttVarliklarUpper),
        const SizedBox(height: SandikSpace.sm),
        SandikCard(
          child: Column(
            children: [
              for (var i = 0; i < satirlar.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.hairline),
                _Satir(key: ValueKey(satirlar[i].sembol), s: satirlar[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: SandikSpace.lg),
        Text(l.ttKural, style: context.t.bodySmall?.copyWith(color: c.text58)),
      ],
    );
  }
}

/// 12 ay, yan yana çubuk. Ölçek en büyük aya göre; boş ay ince taban
/// çizgisi kalır (sıfır yüksekliğinde çubuk "veri yok" ile karışmasın diye
/// taban her ayda çizilir). Ay adı cihaz dilinde, tek harfe kısalmaz.
///
/// Dokunma (2026-11-12): her sütun (çubuk + ay adı) tek dokunma hedefi;
/// yükseklik en az [SandikTouch.min], genişlik sütunun tamamı — ince
/// çubuğa isabet aranmaz. Boş ay seçilemez: süzecek satırı yoktur.
///
/// Giriş hareketi: çubuklar ilk açılışta tabandan BİR KEZ yükselir
/// ([SandikMotion.flow] + [SandikMotion.enter]); süzmede yeniden oynamaz
/// (`TweenAnimationBuilder` uç değeri değişmediği için yeniden başlamaz),
/// hareketi azalt açıkken süre sıfır, son kare anında.
class _AyCubuklari extends StatelessWidget {
  const _AyCubuklari(
      {required this.aylik, required this.secili, required this.onSec});

  final List<double> aylik;
  final int? secili;
  final ValueChanged<int> onSec;

  static const _yukseklik = 72.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l10n;
    final dil = Localizations.localeOf(context).toString();
    final enBuyuk = aylik.fold(0.0, (m, v) => v > m ? v : m);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: SandikMotion.flowOf(context),
      curve: SandikMotion.enter,
      builder: (context, oran, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 12; i++)
            Expanded(
              child: Semantics(
                label: l.ttAySemantik(
                    DateFormat.MMMM(dil).format(DateTime(2000, i + 1)),
                    fmtTRY(aylik[i])),
                button: aylik[i] > 0,
                selected: secili == i + 1,
                onTap: aylik[i] > 0 ? () => onSec(i + 1) : null,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: aylik[i] > 0 ? () => onSec(i + 1) : null,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minHeight: SandikTouch.min),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: SandikSpace.xxs),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: enBuyuk <= 0
                                ? 2
                                : 2 +
                                    (_yukseklik - 2) *
                                        aylik[i] /
                                        enBuyuk *
                                        oran,
                            decoration: BoxDecoration(
                              color: aylik[i] <= 0
                                  ? c.hairline
                                  : secili == i + 1
                                      ? c.gold
                                      : c.amberFill,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(SandikSpace.xs)),
                            ),
                          ),
                          const SizedBox(height: SandikSpace.xs),
                          FittedBox(
                            child: Text(
                              DateFormat.MMM(dil).format(DateTime(2000, i + 1)),
                              // Seçili ay adı ağırlıkla da ayrılır — renk
                              // tek ipucu olmasın.
                              style: context.t.labelSmall?.copyWith(
                                  color: secili == i + 1 ? c.text90 : c.text58,
                                  fontWeight: secili == i + 1
                                      ? FontWeight.w600
                                      : null),
                            ),
                          ),
                        ],
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
}

class _Satir extends StatelessWidget {
  const _Satir({super.key, required this.s});

  final TahminSatiri s;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final dil = Localizations.localeOf(context).toString();
    final aylar = s.aylar
        .map((m) => DateFormat.MMM(dil).format(DateTime(2000, m)))
        .join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SandikSpace.smd),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.ad,
                    style: context.t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600, color: c.text90)),
                const SizedBox(height: SandikSpace.xxs),
                Text(l.ttSatirAlt(fmtTRYFiyat(s.brutPay), aylar),
                    style: context.t.bodySmall?.copyWith(color: c.text58)),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.smd),
          Text(fmtTRY(s.netTry ?? s.brutTry),
              style: context.t.numSmall
                  .copyWith(fontWeight: FontWeight.w600, color: c.text90)),
          // Beklenen temettü günü takvime (2026-11-11). Gün, ana sayfanın
          // "Seni ilgilendiren günler" satırıyla aynı kuraldan gelir
          // (geçen yılın hak gününün yıl dönümü, [temettuGunleri]); şirket
          // kararı değil → başlıkta "tahmini", açıklamada kural. Geçen yıl
          // hak günü yoksa düğme yok (uydurma tarih yazılmaz).
          TakvimeEkleDugmesi(
            etkinlikler: [
              for (final g in temettuGunleri(
                {s.sembol: s.hakGunleri},
                bugun: _bugunUtc(),
              ))
                TakvimEtkinligi(
                  uid: 'temettu-${g.kod}-${takvimGunu(g.gun)}',
                  gun: g.gun,
                  baslik: l.calendarDividendEstimated(g.kod ?? s.ad),
                  aciklama: l.calendarDividendNote,
                ),
            ],
            dosyaAdi: 'sandik-temettu-${s.sembol}',
            konu: l.calendarDividendEstimated(s.ad),
          ),
        ],
      ),
    );
  }
}

/// TR takvim günü, saatsiz (UTC gece yarısı) — [temettuGunleri] bu biçimi
/// bekler.
DateTime _bugunUtc() {
  final n = DateTime.now();
  return DateTime.utc(n.year, n.month, n.day);
}
