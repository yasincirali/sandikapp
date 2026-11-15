import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart' show leaderboardOptInProvider;
import '../services/analytics_service.dart';
import '../services/leaderboard_service.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../l10n/l10n.dart';
import '../utils/tr_iyelik.dart';
import 'sandik_skeleton.dart';

/// Ana ekranda anonim yüzdelik dilim şeridi.
///
/// **Neden ana ekranda?** Karşılaştırma zaten Yarış ekranında var
/// (`_GlobalPercentileTeaser`) ama oraya kullanıcı bilerek gider — yani
/// zaten gelmiş olanı görür. Tutundurmaya katkı, uygulamayı açan HERKESİN
/// görmesiyle olur; şeridin varlık sebebi budur.
///
/// **Neden tutar değil dilim?** Para üstünden karşılaştırma hem mahremiyeti
/// hem motivasyonu bozar (alttakini demotive eder, üsttekini teşhir eder).
/// Dilim, sosyal karşılaştırmanın motive eden yarısını verir.
///
/// Üç kapı: Remote Config bayrağı, kullanıcının yarış opt-in'i ve sunucudaki
/// k-anonimlik eşiği. Üçünden biri kapalıysa şerit HİÇ çizilmez —
/// "yakında" plaseholderi ana ekranda yer işgal etmeye değmez.
class PercentileStrip extends ConsumerStatefulWidget {
  /// Kullanıcının kendi ham lot'ları (ortak varlıkları DEĞİL).
  final List<Asset> myAssets;

  /// Tutarı TRY'ye çeviren dönüştürücü — `PortfolioState.toTRY`.
  final double Function(double value, String currency) toTRY;

  /// Görünürken uygulanacak dolgu.
  ///
  /// Dolgu ÇAĞIRANDA değil burada durur: şerit çoğu zaman hiç çizilmez
  /// (bayrak kapalı, opt-in yok ya da k-anonimlik eşiği dolmamış) ve dışarıda
  /// bir `Padding` olsaydı o durumlarda ana ekranda sebepsiz bir boşluk
  /// kalırdı.
  final EdgeInsets padding;

  const PercentileStrip({
    super.key,
    required this.myAssets,
    required this.toTRY,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
  });

  /// Karşılaştırma penceresi. Plan "son 30 gün" diyor: 7 gün gürültülü,
  /// 365 gün yeni kullanıcıyı dışarıda bırakır.
  static const periodDays = 30;

  @override
  ConsumerState<PercentileStrip> createState() => _PercentileStripState();
}

/// Son 30 günün yüzdelik dilimi; null = şerit çizilmez (kapılardan biri
/// kapalı ya da sunucuda kendi satırı yok).
///
/// Widget'ın `initState`'inden provider'a taşındı (yasin 2026-11-15:
/// "Profil açıldığında kademeli açılıp sonradan çizilen komponentler var,
/// hepsi aynı anda tekte çizilmeli"). İstek eskiden şerit kurulunca
/// başlıyordu, yani Profil HER açılışta şerit sonradan beliriyordu. Artık
/// açılışta ısıtılır (`_AuthGate._warmUpData`), Profil hazır veriyle kurulur
/// ve Profil kapısı (`profilHazirProvider`) bunu bekler. Kullanıcı başına
/// bir kez: ROI'yi her yeniden kurulumda hesaplatmayız.
final yuzdelikDilimProvider = FutureProvider<PercentileBucket?>((ref) async {
  final optIn = ref.watch(leaderboardOptInProvider);
  final me = ref.watch(authProvider.select((a) => a.valueOrNull?.id));
  if (me == null || !optIn) return null;
  if (!RemoteConfigService.instance.percentileStripEnabled) return null;
  // Anlık görüntüyü cihaz YAZMAZ (0095): `leaderboard-snapshot` cron'u
  // yarışa katılan herkes için günde iki kez TWR yazar. Eskiden şerit
  // kendi simülasyon değerini yüklüyordu — iki ölçü aynı havuzda
  // karışırdı. Kendi satırı yoksa (yeni hesap, 30 gün dolmadı) RPC boş
  // döner ve şerit gizli kalır; uydurma dilim yok.
  return LeaderboardService.instance
      .fetchPercentile(PercentileStrip.periodDays);
});

class _PercentileStripState extends ConsumerState<PercentileStrip> {
  /// Görüntülenme olayı ekran başına bir kez (eskiden `_yukle` tek atıştı).
  bool _loglandi = false;

  PercentileBucket? get _data {
    final data = ref.watch(yuzdelikDilimProvider).valueOrNull;
    if (data != null && !_loglandi) {
      _loglandi = true;
      unawaited(AnalyticsService.instance.logPercentileViewed(
        bucket: data.percentile,
        periodDays: PercentileStrip.periodDays,
      ));
    }
    return data;
  }

  // Veri gelince yükseklik akarak belirir
  // (2026-10-14; bkz. [SandikBelirme]).
  @override
  Widget build(BuildContext context) =>
      SandikBelirme(child: _belirenGovde(context));

  Widget _belirenGovde(BuildContext context) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();

    // RPC'de 1 = en üst, 100 = en alt. Kullanıcıya "kaçından iyisin"
    // demek "ilk %X'tesin"den daha anlaşılır ve daha az yarışmacı bir dil.
    final ustundeOlduklari = 100 - data.percentile;
    final iyiTaraf = data.percentile <= 50;

    // Metriğin ADI ve medyan farkı (TECHNICAL_DEBT "medyan farkı ve metrik
    // etiketi"). Sıralama GETİRİ bazlı; portföy büyüklüğü sıralaması yok ve
    // olmayacak — ama ekran bunu yazmayınca kullanıcı "%X" ifadesinin
    // büyüklük mü getiri mi olduğunu bilmiyordu. Medyan farkı 0061'den
    // gelir; eski sunucuda `null` → yalnızca etiket.
    final medyan = data.medianDiffPts;
    final medyanMetni = medyan == null
        ? null
        : (medyan >= 0
            ? context.l10n.medianAhead(fmtNum(medyan.abs(), digits: 1))
            : context.l10n.medianBehind(fmtNum(medyan.abs(), digits: 1)));
    final altSatir = medyanMetni == null
        ? context.l10n.returnRanking
        : context.l10n.returnRankingWith(medyanMetni);

    return Padding(
      padding: widget.padding,
      child: Semantics(
        label: context.l10n.percentileSemantics(ustundeOlduklari, altSatir),
        // `SandikCard` (2. tur, 2026-10-08). Köşe 12 → `SandikRadius.md`
        // (14), kenar `text20 %25` → saç teli: şerit Profil'deki komşu
        // kartlarla aynı kabuğu taşısın, tek başına farklı köşe olmasın.
        child: SandikCard(
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.md2, vertical: 11),
          child: Row(
            children: [
              Icon(
                Icons.groups_rounded,
                size: 18,
                color: iyiTaraf ? context.c.gain : context.c.text58,
              ),
              const SizedBox(width: 10),
              Expanded(
                // Stiller `context.t`'den türer: sistem "Kalın Metin"
                // erişilebilirlik ayarı orada tek noktada çözülür; elle
                // yazılmış bir `TextStyle` o yolu atlardı
                // (bkz. bold_text_support_test).
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: context.t.bodyMedium?.copyWith(
                          height: 1.35,
                          color: context.c.text58,
                        ),
                        children: [
                          TextSpan(text: context.l10n.last30DaysLike),
                          TextSpan(
                            text: "yatırımcıların %$ustundeOlduklari'"
                                "${trSayiAyrilmaEki(ustundeOlduklari)}",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color:
                                  iyiTaraf ? context.c.gain : context.c.text90,
                            ),
                          ),
                          const TextSpan(text: ' iyi getirdin'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      altSatir,
                      style: context.t.bodySmall?.copyWith(
                        color: context.c.text36,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Katılımcı sayısı: karşılaştırmanın kaç kişilik havuzdan
              // geldiğini söylemek hem güveni artırır hem k-anonimliği
              // görünür kılar.
              Text(
                context.l10n.nPeople(data.total),
                style: context.t.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: context.c.text36,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
