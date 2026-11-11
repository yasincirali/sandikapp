import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../services/acilis_olcumu.dart';

/// Sekmeleri ağaçta tutan [IndexedStack] — geçiş ANLIK.
///
/// `main_navigation_screen.dart`'tan buraya taşındı (Ar-Ge 11 Kas 18:04 #3):
/// boşta önceden kurulum widget testiyle kilitlensin diye. Kabuk
/// (`MainNavigationScreen`) testte kurulamıyor (Supabase, portföy, ağ).
///
/// Neden düz `AnimatedSwitcher` değil: AnimatedSwitcher eski çocuğu ağaçtan
/// söker, bu da her sekme dönüşünde ekranların baştan kurulmasına (scroll
/// pozisyonu sıfırlanması, provider'ların yeniden tetiklenmesi) yol açardı.
/// Burada tüm ekranlar `IndexedStack` gibi ağaçta kalır. State koruması
/// aynen sürer.
///
/// ## Neden çapraz sönüm KALDIRILDI (hareket denetimi, 2026-09-29)
/// Eskiden giden sekme 260 ms'de sönerken gelen belirirdi. Sekme çubuğu
/// uygulamanın en sık dokunulan öğesi (günde onlarca kez) ve geçişin
/// ortasında iki TAM EKRAN yarı saydam üst üste görünüyordu; tam ekran
/// opaklık animasyonu da her karede iki ekranı ara katmana boyuyordu.
/// iOS'ta sekme geçişi anlıktır (HIG, Tab bars). Sık tekrarlanan eylem
/// hareket istemez; "hangi sekmedeyim" bilgisini sekme çubuğu verir.
/// Pasif sekme `Offstage`: ağaçta kalır, çizilmez, dokunuş almaz.
/// Ekran okuyucu ağacı için `ExcludeSemantics` ayrıca korunur.
///
/// ## Boşta önceden kurulum (Ar-Ge 11 Kas 18:04 #3)
/// Görülmemiş sekme hâlâ kurulmaz — bir istisna: [onKurulacak]. Portföy en
/// sık ikinci dokunulan sekme ve ilk açılışı halka + listeyi O ANDA
/// kuruyordu; ilk geçiş takılıyordu. Ana sayfanın ilk karesi çizildikten,
/// açılış ölçümü bittikten ([AcilisOlcumu.bekle]) ve zamanlayıcı boşa
/// düştükten (koşan animasyon yok) sonra o sekme `Offstage` kurulur:
/// çizilmez, TickerMode kapalı, dokunuş ve ekran okuyucu almaz.
///
/// Önceden kurulan sekme kullanıcı onu görene kadar [SekmeOnKurulumu]
/// altında "bekliyor" işaretiyle durur; ekran bu sürede YENİ ağ isteği
/// başlatmaz (bkz. `PortfolioScreen` — takip sayacı, alarm rozeti, sparkline
/// ön yüklemesi, portföy listesi). Kullanıcı sekmeye geçince işaret düşer,
/// yalnız o küçük parçalar kurulur.
///
/// Performans sekmesi önceden KURULMAZ: seri hesabı ve ağ isteği tetikler.
/// Zamanlayıcı hiç boşa düşmezse (sürekli animasyon) eski davranış kalır.
class SekmeYigini extends StatefulWidget {
  const SekmeYigini({
    super.key,
    required this.index,
    required this.children,
    this.onKurulacak,
  });

  final int index;
  final List<Widget> children;

  /// Boşta `Offstage` kurulacak sekmenin indeksi; `null` → hiçbiri.
  final int? onKurulacak;

  @override
  State<SekmeYigini> createState() => _SekmeYiginiState();
}

class _SekmeYiginiState extends State<SekmeYigini> {
  /// Henüz hiç görüntülenmemiş sekmeler inşa edilmez — ilk açılışta beş
  /// ekranın birden kurulması gecikme yaratırdı. IndexedStack'in kendi
  /// davranışı da budur (lazy değil ama görünmeyen çocuk layout almaz),
  /// burada açıkça yönetiyoruz.
  late final Set<int> _visited = {widget.index};

  /// Önceden kurulmuş ama henüz görülmemiş sekmeler → "bekliyor" işareti.
  final Map<int, ValueNotifier<bool>> _bekleyen = {};

  @override
  void initState() {
    super.initState();
    if (widget.onKurulacak != null) {
      // İlk kare ÖNCE çizilsin: ana sayfanın ilk karesiyle yarışmasın.
      SchedulerBinding.instance.addPostFrameCallback((_) => _olcumuBekle());
    }
  }

  Future<void> _olcumuBekle() async {
    await AcilisOlcumu.instance.bekle();
    if (!mounted) return;
    _bostaKur();
  }

  /// Koşan animasyon varken (`transientCallbackCount > 0`) bir sonraki
  /// karenin sonunu bekler; animasyon kare ister, yani bu döngü yalnız
  /// kare çizilirken döner. Boşa düşünce kurulum zamanlayıcının görev
  /// sırasına girer (`scheduleTask`): önce bekleyen dokunuşlar ve olaylar
  /// işlenir, görev koşarken boşluk YENİDEN denetlenir.
  ///
  /// Neden `Priority.idle` değil: boşta görev animasyon sürerken
  /// reddedilir ve zamanlayıcı her olay döngüsünde yeniden dener (sıfır
  /// süreli Timer zinciri). Görev sıraya girdikten sonra bir kaydırma ya da
  /// tur başlarsa bu hem boşa CPU hem testte sonsuz döngü olurdu. Boşluğu
  /// kendimiz denetleyip görevi `Priority.animation` ile sıraya koyuyoruz;
  /// görev o an animasyon görürse kare sonunu beklemeye döner.
  void _bostaKur() {
    final hedef = widget.onKurulacak;
    if (!mounted || hedef == null || _visited.contains(hedef)) return;
    final zamanlayici = SchedulerBinding.instance;
    if (zamanlayici.transientCallbackCount > 0) {
      zamanlayici.addPostFrameCallback((_) => _bostaKur());
      return;
    }
    zamanlayici.scheduleTask<void>(() {
      if (!mounted || _visited.contains(hedef)) return;
      if (zamanlayici.transientCallbackCount > 0) {
        zamanlayici.addPostFrameCallback((_) => _bostaKur());
        return;
      }
      setState(() {
        _visited.add(hedef);
        _bekleyen[hedef] = ValueNotifier<bool>(true);
      });
    }, Priority.animation, debugLabel: 'SekmeYigini.onKurulum');
  }

  @override
  void didUpdateWidget(covariant SekmeYigini oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_visited.contains(widget.index)) {
      _visited.add(widget.index);
    }
    // Önceden kurulan sekme ilk kez görüldü: işaret düşer, ekran ertelediği
    // parçaları (takip sayacı, alarm rozeti…) şimdi kurar.
    _bekleyen[widget.index]?.value = false;
  }

  @override
  void dispose() {
    for (final n in _bekleyen.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: List.generate(widget.children.length, (i) {
        final isActive = i == widget.index;

        // Hiç ziyaret edilmemiş sekmeyi inşa etme.
        if (!_visited.contains(i)) {
          return const SizedBox.shrink();
        }

        Widget cocuk = widget.children[i];
        final bekliyor = _bekleyen[i];
        if (bekliyor != null) {
          cocuk = SekmeOnKurulumu(bekliyor: bekliyor, child: cocuk);
        }

        return Offstage(
          offstage: !isActive,
          child: IgnorePointer(
            ignoring: !isActive,
            // Pasif sekmeler ağaçta kalır (state korunur) ama ne çizim
            // maliyeti üretir ne de erişilebilirlik ağacını kirletir.
            child: TickerMode(
              enabled: isActive,
              child: ExcludeSemantics(
                excluding: !isActive,
                child: cocuk,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Önceden kurulan sekmenin "henüz görülmedi" işareti ([SekmeYigini]).
///
/// Ekran `SekmeOnKurulumu.bekliyor(context)` okur; `true` iken yeni ağ
/// isteği başlatan parçaları kurmaz. İşaret düşünce yalnız bu bağımlılığı
/// kuran parçalar yeniden kurulur. Sarmalayıcı yoksa `false` (sekme
/// doğrudan açıldı ya da önceden kurulum hiç olmadı) — davranış birebir eski.
class SekmeOnKurulumu extends InheritedNotifier<ValueNotifier<bool>> {
  const SekmeOnKurulumu({
    super.key,
    required ValueNotifier<bool> bekliyor,
    required super.child,
  }) : super(notifier: bekliyor);

  static bool bekliyor(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SekmeOnKurulumu>()
          ?.notifier
          ?.value ??
      false;
}

