import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../services/lider_seridi.dart';
import '../utils/tr_iyelik.dart';
import 'duello_arenasi.dart';

/// Yarış ekranının sahnesi — kullanıcı kararı 2026-09-29.
///
/// Beş tasarım yönü (kürsü, pist, eğri, düello, canlı liste) prototip
/// olarak karşılaştırıldı; seçilen birleşim:
///
///   * **Temel: canlı liste.** 15 saniyelik yenileme görünür olsun diye
///     satırlar sıra değişince kayar, rakamlar sayaç gibi döner, sırası
///     değişen satırda ▲/▼ çipi belirip söner, yeni liderin üstünden bir
///     ışık geçer. Eski liste aynı bilgiyi veriyordu ama bir tablo gibi
///     duruyordu; yenilenip yenilenmediği bile anlaşılmıyordu.
///   * **Tam 2 kişide üstte düello kartı.** Yarışların çoğu iki kişilik
///     (sen ve eşin); iki satırlık liste bu durumda en zayıf biçim. Fark
///     bir halat çekişi çubuğunda okunur, taç liderin başında durur ve
///     lider değişince yay çizerek karşı tarafa zıplar.
///   * **3+ kişide üstte kürsü.** İlk üç, yüksekliği sırayı anlatan
///     basamaklarda.
///   * **Düello arenası (2026-10-04, bayrak `yaris_duello_arena`).** Tam
///     iki kişide düello kartı + liste yerine tek bir arena
///     (`duello_arenasi.dart`) ve gün gün lider şeridi; ortağın getirisi
///     yoksa da arena çizilir. Arenada taç gösterisi dönem değişiminde de
///     oynar (kullanıcının onayladığı prototip) — aşağıdaki "nadir an"
///     kuralı eski düzen içindir; arenanın kendi sıklık kuralı sınıf
///     notunda. Bayrak kapalıyken bu düzen birebir.
///
/// Neşe yalnızca nadir anlara (Emil Kowalski'nin sıklık kuralı): taç
/// zıplaması ve konfeti yalnızca CANLI yenilemede lider değişince oynar,
/// dönem sekmesi değiştirilirken değil — sekmeler arasında gidip gelmek
/// her seferinde konfeti patlatırdı.
///
/// Saf widget: veriyi parametre olarak alır, provider okumaz (bkz.
/// `TransactionRow` başındaki not) — widget testiyle pump edilebilsin.
/// Bütün süreler `SandikMotion.of(context, …)`'ten geçer; "hareketi azalt"
/// açıkken konum hareketleri anında biter.
class YarisKatilimci {
  const YarisKatilimci({
    required this.id,
    required this.ad,
    required this.ben,
    required this.roi,
    this.renkSirasi = 0,
  });

  final String id;
  final String ad;
  final bool ben;

  /// Seçili dönemin getirisi (%); hesaplanamadıysa null.
  final double? roi;

  /// Ortak listesindeki yeri (1'den başlar; "sen" 0). Rengi sıralamadan
  /// bağımsız tutar: sıra değişince kişinin rengi değişmesin.
  final int renkSirasi;

  /// İlk ad — kürsü ve düelloda dar sütuna tam ad sığmaz.
  String get kisaAd {
    final t = ad.trim();
    if (t.isEmpty) return ad;
    return t.split(RegExp(r'\s+')).first;
  }

  String get harf {
    final k = kisaAd;
    if (k.isEmpty) return '?';
    return trBuyukHarf(k.characters.first);
  }
}

/// Listenin üstünde ne duracak.
///
/// [arena]: düello arenası (bayrak `yaris_duello_arena`) — listenin
/// YERİNE çizilir, üstüne değil.
enum YarisVitrini { yok, duello, kursu, arena }

/// Vitrin kuralı — saf, test edilir.
///
/// Düello YALNIZCA tam iki kişi ve ikisinin de getirisi varken: biri
/// "veri yok"ken halat çubuğu bir şey ölçmez. Kürsü getirisi olan en az üç
/// kişiyle; boş basamak kürsüyü anlamsızlaştırır.
///
/// [arena] açıkken (bayrak) tam iki kişi HER ZAMAN arenadır — ortağın
/// getirisi henüz yoksa bile: arena o tarafta "Henüz veri yok" yazar, halat
/// ortada durur. Eski kural o durumda vitrinsiz iki satırlık liste
/// gösteriyordu; kullanıcı emülatörde bunu "animasyon kaldırılmış" sandı
/// (2026-10-04).
YarisVitrini yarisVitrini(List<YarisKatilimci> k, {bool arena = false}) {
  if (arena && k.length == 2) return YarisVitrini.arena;
  final verili = k.where((x) => x.roi != null).length;
  if (k.length == 2 && verili == 2) return YarisVitrini.duello;
  if (verili >= 3) return YarisVitrini.kursu;
  return YarisVitrini.yok;
}

/// Halat çubuğundaki düğümün yeri (0..1; 0,5 başa baş, >0,5 sen öndesin).
///
/// Ölçek iki getirinin büyüğüne göre: yüzde 1'lik fark haftalık dönemde
/// büyük, yıllıkta küçük bir farktır. Uçlara (%8) yapışmasın ki düğüm her
/// zaman iki rengin arasında görünsün.
double halatOrani(double ben, double rakip) {
  final olcek = math.max(2.0, math.max(ben.abs(), rakip.abs()));
  return 0.5 + ((ben - rakip) / (2 * olcek)).clamp(-0.42, 0.42);
}

Color yarisciRengi(BuildContext context, YarisKatilimci k) {
  if (k.ben) return context.c.amberFill;
  final r = Sandik.yarisci;
  return r[(math.max(1, k.renkSirasi) - 1) % r.length];
}

String _yuzde(double v) => fmtPctIsaretli(v, digits: 1);

class YarisSahnesi extends StatefulWidget {
  const YarisSahnesi({
    super.key,
    required this.katilimcilar,
    required this.yenileme,
    required this.sonGuncelleme,
    required this.donemGun,
    this.arena = false,
    this.liderSeridi,
  });

  /// Düello arenası açık mı (bayrak `yaris_duello_arena`). Yalnız tam iki
  /// kişide etkili; 3+ kişide kürsü + liste aynen kalır.
  final bool arena;

  /// Arenanın altındaki gün gün lider şeridi; `null` → çizilmez (veri
  /// yok ya da henüz hesaplanmadı — uydurma yok).
  final LiderSeridi? liderSeridi;

  /// Getiriye göre sıralı (null'lar sonda).
  final List<YarisKatilimci> katilimcilar;

  /// Her canlı yenilemede artar — nabız ve "lider değişti" tespiti bunu izler.
  final int yenileme;
  final DateTime? sonGuncelleme;

  /// Seçili dönem. Değiştiğinde sıra farkları "canlı olay" sayılmaz.
  final int donemGun;

  @override
  State<YarisSahnesi> createState() => _YarisSahnesiState();
}

class _YarisSahnesiState extends State<YarisSahnesi> {
  int _konfeti = 0;

  static String? _lider(List<YarisKatilimci> k) =>
      k.where((x) => x.roi != null).map((x) => x.id).firstOrNull;

  @override
  void didUpdateWidget(covariant YarisSahnesi old) {
    super.didUpdateWidget(old);
    // Liderliği CANLI yenilemede aldıysan kutla. Dönem değişimi bir olay
    // değildir (bkz. sınıf notu); ilk hesap da değil — önbellekten tazeye
    // geçiş ekran açılırken olur, orada konfeti yersiz.
    if (old.donemGun != widget.donemGun ||
        old.yenileme == widget.yenileme ||
        old.yenileme == 0) {
      return;
    }
    final eski = _lider(old.katilimcilar), yeni = _lider(widget.katilimcilar);
    if (eski == null || yeni == null || eski == yeni) return;
    final benLider = widget.katilimcilar.any((k) => k.id == yeni && k.ben);
    if (!benLider) return;
    HapticFeedback.mediumImpact();
    setState(() => _konfeti++);
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.katilimcilar;
    final vitrin = yarisVitrini(k, arena: widget.arena);
    if (vitrin == YarisVitrini.arena) return _arena(context, k);
    Widget? ust;
    switch (vitrin) {
      case YarisVitrini.duello:
        final ben = k.firstWhere((x) => x.ben, orElse: () => k.first);
        final rakip = k.firstWhere((x) => x.id != ben.id);
        ust = _Duello(ben: ben, rakip: rakip);
      case YarisVitrini.kursu:
        ust = _Kursu(ilkUc: k.where((x) => x.roi != null).take(3).toList());
      case YarisVitrini.yok:
      case YarisVitrini.arena:
        ust = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CanliBaslik(yenileme: widget.yenileme, son: widget.sonGuncelleme),
        const SizedBox(height: SandikSpace.smd),
        if (ust != null) ...[
          Stack(
            clipBehavior: Clip.none,
            children: [
              ust,
              Positioned.fill(
                child: IgnorePointer(child: _Konfeti(tetik: _konfeti)),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.lg),
        ],
        _CanliListe(katilimcilar: k, donemGun: widget.donemGun),
      ],
    );
  }

  /// Arena düzeni: canlı başlık + arena + lider şeridi. İki satırlık liste
  /// YOK — aynı iki kişiyi arena zaten gösteriyor (prototip).
  Widget _arena(BuildContext context, List<YarisKatilimci> k) {
    final ben = k.firstWhere((x) => x.ben, orElse: () => k.first);
    final rakip = k.firstWhere((x) => x.id != ben.id);
    final serit = widget.liderSeridi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CanliBaslik(yenileme: widget.yenileme, son: widget.sonGuncelleme),
        const SizedBox(height: SandikSpace.smd),
        Stack(
          clipBehavior: Clip.none,
          children: [
            DuelloArenasi(ben: ben, rakip: rakip, donemGun: widget.donemGun),
            Positioned.fill(
              child: IgnorePointer(child: _Konfeti(tetik: _konfeti)),
            ),
          ],
        ),
        // Şerit yalnız AYNI dönemin verisiyse: dönem değişirken eski
        // dönemin şeridi yeni arenanın altında kalmasın.
        if (serit != null && serit.donemGun == widget.donemGun) ...[
          const SizedBox(height: SandikSpace.md),
          LiderSeridiKarti(
            serit: serit,
            benRengi: yarisciRengi(context, ben),
            rakipRengi: yarisciRengi(context, rakip),
          ),
        ],
      ],
    );
  }
}

// ── Canlı başlık ─────────────────────────────────────────────────────────────

/// "● Canlı · 12 sn önce güncellendi". Nokta her yenilemede bir kez nabız
/// atar: 15 saniyelik yenileme artık görünür.
class _CanliBaslik extends StatefulWidget {
  const _CanliBaslik({required this.yenileme, required this.son});
  final int yenileme;
  final DateTime? son;

  @override
  State<_CanliBaslik> createState() => _CanliBaslikState();
}

class _CanliBaslikState extends State<_CanliBaslik>
    with SingleTickerProviderStateMixin {
  late final AnimationController _nabiz =
      AnimationController(vsync: this, duration: SandikMotion.flow * 1.6);
  Timer? _saat;

  @override
  void initState() {
    super.initState();
    // Yalnızca etiket için saniyelik tik; animasyon değil.
    _saat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.son != null) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _CanliBaslik old) {
    super.didUpdateWidget(old);
    if (old.yenileme != widget.yenileme &&
        !MediaQuery.disableAnimationsOf(context)) {
      _nabiz.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _saat?.cancel();
    _nabiz.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final son = widget.son;
    final String metin;
    if (son == null) {
      metin = l.raceLive;
    } else {
      final sn = DateTime.now().difference(son).inSeconds;
      metin = sn < 5
          ? l.raceLiveJustNow
          : sn < 60
              ? l.raceLiveSecondsAgo(sn)
              : l.raceLiveMinutesAgo(sn ~/ 60);
    }
    final yesil = context.c.gain;
    return Row(
      children: [
        SizedBox(
          width: SandikSpace.md,
          height: SandikSpace.md,
          child: AnimatedBuilder(
            animation: _nabiz,
            builder: (_, __) {
              final t = _nabiz.value;
              final aktif = _nabiz.isAnimating;
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (aktif)
                    Transform.scale(
                      scale: 0.6 + 1.6 * t,
                      child: Container(
                        width: SandikSpace.sm,
                        height: SandikSpace.sm,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: yesil.withValues(alpha: (1 - t) * 0.85),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  Container(
                    width: SandikSpace.sm,
                    height: SandikSpace.sm,
                    decoration:
                        BoxDecoration(color: yesil, shape: BoxShape.circle),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: SandikSpace.xs2),
        Flexible(
          child: Text(
            metin,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.bodySmall?.copyWith(
              color: context.c.text58,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Yuvarlanan rakamlar ──────────────────────────────────────────────────────

/// Sayaç gibi dönen sayı metni: her rakam kendi sütununda yeni değerine
/// yuvarlanır. İlk görünüşte 0'dan döner (giriş hareketi); sonraki
/// değişimlerde bulunduğu yerden. Rakam olmayan karakterler (%, +, −, ,)
/// sabit durur.
///
/// Anahtarlar SAĞDAN konumludur: "%+4,1" → "%+12,3" olduğunda birler
/// basamağı birler basamağı olarak kalır, yanlış sütun dönmez.
class YuvarlananMetin extends StatelessWidget {
  const YuvarlananMetin(this.metin, {super.key, required this.stil});

  final String metin;
  final TextStyle stil;

  @override
  Widget build(BuildContext context) {
    final tp = TextPainter(
      text: TextSpan(text: '0', style: stil),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final h = tp.height, w = tp.width;
    tp.dispose();
    final sure = SandikMotion.of(context, SandikMotion.flow);
    final kars = metin.characters.toList();
    return Semantics(
      label: metin,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < kars.length; i++)
            if (_rakam(kars[i]) != null)
              _Hane(
                key: ValueKey(kars.length - i),
                rakam: _rakam(kars[i])!,
                yukseklik: h,
                genislik: w,
                stil: stil,
                sure: sure,
              )
            else
              Text(kars[i], key: ValueKey('s${kars.length - i}'), style: stil),
        ],
      ),
    );
  }

  static int? _rakam(String c) {
    final k = c.codeUnitAt(0);
    return (k >= 48 && k <= 57) ? k - 48 : null;
  }
}

class _Hane extends StatelessWidget {
  const _Hane({
    super.key,
    required this.rakam,
    required this.yukseklik,
    required this.genislik,
    required this.stil,
    required this.sure,
  });

  final int rakam;
  final double yukseklik;
  final double genislik;
  final TextStyle stil;
  final Duration sure;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: genislik,
      height: yukseklik,
      child: ClipRect(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: rakam.toDouble()),
          duration: sure,
          curve: SandikMotion.glide,
          builder: (_, v, child) => Transform.translate(
            offset: Offset(0, -v * yukseklik),
            child: child,
          ),
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: yukseklik * 10,
            maxHeight: yukseklik * 10,
            child: Column(
              children: [
                for (var d = 0; d < 10; d++)
                  SizedBox(
                    height: yukseklik,
                    child: Center(child: Text('$d', style: stil)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Ortak parçalar ───────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.k, required this.cap, this.parla = false});
  final YarisKatilimci k;
  final double cap;

  /// Lider parıltısı — geçişi yumuşak (lider değişince söner/yanar).
  final bool parla;

  @override
  Widget build(BuildContext context) {
    final renk = yarisciRengi(context, k);
    return AnimatedContainer(
      duration: SandikMotion.of(context, SandikMotion.flow),
      curve: SandikMotion.enter,
      width: cap,
      height: cap,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            Color.alphaBlend(renk.withValues(alpha: 0.2), context.c.surface1),
        border: Border.all(color: renk.withValues(alpha: 0.85), width: 2),
        boxShadow: [
          BoxShadow(
            color: Sandik.medalGold.withValues(alpha: parla ? 0.45 : 0),
            blurRadius: parla ? 22 : 0,
            spreadRadius: parla ? 1 : 0,
          ),
        ],
      ),
      child: Text(
        k.harf,
        style: (cap >= 52 ? context.t.headlineSmall : context.t.titleMedium)
            ?.copyWith(fontWeight: FontWeight.w800, color: context.c.text90),
      ),
    );
  }
}

/// Taç — küçük altın işaret. İkon setinde taç yok; yolu kendimiz çiziyoruz.
///
/// Açık (public): düello arenası (`duello_arenasi.dart`) aynı tacı taşır;
/// kopya yazılmadı.
class YarisTaci extends StatelessWidget {
  const YarisTaci({super.key, this.genislik = 24});
  final double genislik;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(genislik, genislik * 0.66),
        painter: const _TacBoyaci(),
      );
}

class _TacBoyaci extends CustomPainter {
  const _TacBoyaci();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final yol = Path()
      ..moveTo(w * 0.08, h * 0.92)
      ..lineTo(w * 0.92, h * 0.92)
      ..lineTo(w * 0.98, h * 0.22)
      ..lineTo(w * 0.72, h * 0.52)
      ..lineTo(w * 0.5, h * 0.02)
      ..lineTo(w * 0.28, h * 0.52)
      ..lineTo(w * 0.02, h * 0.22)
      ..close();
    final boya = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Sandik.medalGold, Sandik.medalGoldDark],
      ).createShader(Offset.zero & s);
    canvas.drawPath(yol, boya);
  }

  @override
  bool shouldRepaint(covariant _TacBoyaci old) => false;
}

/// Sıra rozeti: 1–3 madalya, 4+ sade. Tonlar [Sandik] madalya
/// token'larından (koyu rakam her iki uçta okunur, bkz. token notu).
class _Madalya extends StatelessWidget {
  const _Madalya({required this.sira, required this.verili});
  final int sira;
  final bool verili;

  @override
  Widget build(BuildContext context) {
    const cap = SandikSpace.xl + SandikSpace.xxs;
    final metin = Text(
      '$sira',
      style: context.t.numSmall.copyWith(
        fontWeight: FontWeight.w900,
        color: sira <= 3 && verili
            ? context.c.onAmber.withValues(alpha: 0.85)
            : context.c.text58,
      ),
    );
    if (sira > 3 || !verili) {
      return Container(
        width: cap,
        height: cap,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.c.overlay,
          shape: BoxShape.circle,
          border: Border.all(color: context.c.overlay),
        ),
        child: metin,
      );
    }
    final (Color acik, Color koyu) = switch (sira) {
      1 => (Sandik.medalGold, Sandik.medalGoldDark),
      2 => (Sandik.medalSilver, Sandik.medalSilverDark),
      _ => (Sandik.medalBronze, Sandik.medalBronzeDark),
    };
    return AnimatedContainer(
      duration: SandikMotion.of(context, SandikMotion.flow),
      curve: SandikMotion.enter,
      width: cap,
      height: cap,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [acik, koyu],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: acik.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: metin,
    );
  }
}

// ── Düello (tam 2 kişi) ──────────────────────────────────────────────────────

class _Duello extends StatelessWidget {
  const _Duello({required this.ben, required this.rakip});
  final YarisKatilimci ben;
  final YarisKatilimci rakip;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final a = ben.roi!, b = rakip.roi!;
    final fark = a - b;
    final benOnde = fark >= 0;
    final farkMetni = fmtNum(fark.abs(), digits: 1);
    final String mesaj;
    final Color mesajRengi;
    if (fark.abs() < 0.05) {
      mesaj = l.duelTied;
      mesajRengi = context.c.text90;
    } else if (benOnde) {
      mesaj = l.duelAhead(rakip.kisaAd, trIyelik(rakip.kisaAd), farkMetni);
      mesajRengi = context.c.gain;
    } else {
      mesaj = l.duelBehind(rakip.kisaAd, trIyelik(rakip.kisaAd), farkMetni);
      mesajRengi = context.c.loss;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(
          SandikSpace.md, SandikSpace.sm, SandikSpace.md, SandikSpace.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [context.c.surface2, context.c.surface1],
        ),
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        border: Border.all(color: context.c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            const vsW = SandikSpace.xxl;
            final yuzW = (w - vsW) / 2;
            final solX = yuzW / 2, sagX = w - yuzW / 2;
            const tacW = SandikSpace.lg + SandikSpace.xs;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: SandikSpace.lg),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: yuzW,
                        child: _Yuz(k: ben, ad: l.raceYou, lider: benOnde),
                      ),
                      SizedBox(
                        width: vsW,
                        child: Padding(
                          padding:
                              const EdgeInsets.only(bottom: SandikSpace.xl),
                          child: Text(
                            l.raceVs,
                            textAlign: TextAlign.center,
                            style: context.t.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                              color: context.c.text36,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: yuzW,
                        child:
                            _Yuz(k: rakip, ad: rakip.kisaAd, lider: !benOnde),
                      ),
                    ],
                  ),
                ),
                // Taç lider tarafta. Değer 0 (sen) ↔ 1 (rakip) arasında
                // akar; yay (sin) ve eğilme değerden türetildiği için
                // zıplama ayrı bir animasyon değil — geri dönüş de aynı
                // yolu izler, yarıda kesilirse oradan devam eder.
                TweenAnimationBuilder<double>(
                  tween: Tween(end: benOnde ? 0 : 1),
                  duration: SandikMotion.of(context, SandikMotion.flow * 1.3),
                  curve: SandikMotion.move,
                  builder: (_, v, child) {
                    final kavis = math.sin(math.pi * v);
                    return Positioned(
                      left: lerpDouble(solX, sagX, v)! - tacW / 2,
                      top: -kavis * SandikSpace.lg,
                      child: Transform.rotate(
                        angle: kavis * 0.35 * (benOnde ? -1 : 1),
                        child: child,
                      ),
                    );
                  },
                  child: const YarisTaci(genislik: tacW),
                ),
              ],
            );
          }),
          const SizedBox(height: SandikSpace.md),
          _Halat(oran: halatOrani(a, b), sagRenk: yarisciRengi(context, rakip)),
          const SizedBox(height: SandikSpace.smd),
          AnimatedSwitcher(
            duration: SandikMotion.stateOf(context),
            switchInCurve: SandikMotion.enter,
            child: Text(
              mesaj,
              key: ValueKey(mesaj),
              textAlign: TextAlign.center,
              style: context.t.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: mesajRengi,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Yuz extends StatelessWidget {
  const _Yuz({required this.k, required this.ad, required this.lider});
  final YarisKatilimci k;
  final String ad;
  final bool lider;

  @override
  Widget build(BuildContext context) {
    final roi = k.roi!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Avatar(k: k, cap: SandikSpace.xxl + SandikSpace.sm2, parla: lider),
        const SizedBox(height: SandikSpace.xs2),
        Text(
          ad,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.t.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.c.text90,
          ),
        ),
        const SizedBox(height: SandikSpace.xxs),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: YuvarlananMetin(
            _yuzde(roi),
            stil: context.t.numMedium.copyWith(
              color: roi >= 0 ? context.c.gain : context.c.loss,
            ),
          ),
        ),
      ],
    );
  }
}

/// Halat çekişi çubuğu: solda sen (amber), sağda rakip (kendi rengi),
/// düğüm aradaki farkla orantılı yerde. Düğüm hafif taşarak oturur
/// (`SandikMotion.spring` — tek, küçük öğe).
class _Halat extends StatelessWidget {
  const _Halat({required this.oran, required this.sagRenk});
  final double oran;
  final Color sagRenk;

  @override
  Widget build(BuildContext context) {
    final amber = context.c.amberFill;
    const kalin = SandikSpace.smd;
    const dugum = SandikSpace.lgs + SandikSpace.xxs;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.5, end: oran),
        duration: SandikMotion.of(context, SandikMotion.flow * 1.4),
        curve: SandikMotion.spring,
        builder: (_, f, __) {
          final x = (f * w).clamp(dugum / 2, w - dugum / 2);
          return SizedBox(
            height: dugum,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  width: x,
                  top: (dugum - kalin) / 2,
                  height: kalin,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(kalin / 2),
                      gradient: LinearGradient(
                        colors: [amber.withValues(alpha: 0.25), amber],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: x,
                  right: 0,
                  top: (dugum - kalin) / 2,
                  height: kalin,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(kalin / 2),
                      gradient: LinearGradient(
                        colors: [sagRenk, sagRenk.withValues(alpha: 0.25)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: x - dugum / 2,
                  top: 0,
                  width: dugum,
                  height: dugum,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.c.text90,
                      border: Border.all(
                          color: context.c.surface1, width: SandikSpace.xs),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}

// ── Kürsü (3+ kişi) ──────────────────────────────────────────────────────────

class _Kursu extends StatefulWidget {
  const _Kursu({required this.ilkUc});
  final List<YarisKatilimci> ilkUc;

  @override
  State<_Kursu> createState() => _KursuState();
}

class _KursuState extends State<_Kursu> with SingleTickerProviderStateMixin {
  late final AnimationController _giris =
      AnimationController(vsync: this, duration: SandikMotion.flow * 1.8);
  bool _basladi = false;

  // Görsel sıra 2 · 1 · 3 (klasik kürsü); basamak yüksekliği sırayı anlatır.
  static const _yer = {1: 1, 2: 0, 3: 2};
  static const _basamak = {
    1: SandikSpace.xxl * 2 + SandikSpace.sm,
    2: SandikSpace.xxl + SandikSpace.lg,
    3: SandikSpace.xxl + SandikSpace.xs,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_basladi) return;
    _basladi = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _giris.value = 1;
    } else {
      _giris.forward();
    }
  }

  @override
  void dispose() {
    _giris.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.textScalerOf(context);
    // Üst blok: taç + avatar + ad + getiri. Metin ölçeğiyle büyür.
    final ustBlok = SandikSpace.md +
        SandikSpace.xs +
        SandikSpace.xxl +
        SandikSpace.xs2 +
        s.scale(20) +
        s.scale(20) +
        SandikSpace.xs2;
    final yukseklik = ustBlok + _basamak[1]!;
    return LayoutBuilder(builder: (context, c) {
      final sutun = c.maxWidth / 3;
      return SizedBox(
        height: yukseklik,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < widget.ilkUc.length; i++)
              AnimatedPositioned(
                key: ValueKey(widget.ilkUc[i].id),
                duration: SandikMotion.of(context, SandikMotion.flow),
                curve: SandikMotion.move,
                left: _yer[i + 1]! * sutun,
                width: sutun,
                top: 0,
                bottom: 0,
                child: _KursuSutunu(
                  k: widget.ilkUc[i],
                  sira: i + 1,
                  basamak: _basamak[i + 1]!,
                  // 3 → 2 → 1: en yüksek basamak en son, doruk anı.
                  giris: CurvedAnimation(
                    parent: _giris,
                    curve: Interval(
                      (3 - (i + 1)) * 0.18,
                      0.64 + (3 - (i + 1)) * 0.18,
                      curve: SandikMotion.spring,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _KursuSutunu extends StatelessWidget {
  const _KursuSutunu({
    required this.k,
    required this.sira,
    required this.basamak,
    required this.giris,
  });

  final YarisKatilimci k;
  final int sira;
  final double basamak;
  final Animation<double> giris;

  @override
  Widget build(BuildContext context) {
    final roi = k.roi!;
    final koyu = Theme.of(context).brightness == Brightness.dark;
    final (Color madalya, Color madalyaKoyu) = switch (sira) {
      1 => (Sandik.medalGold, Sandik.medalGoldDark),
      2 => (Sandik.medalSilver, Sandik.medalSilverDark),
      _ => (Sandik.medalBronze, Sandik.medalBronzeDark),
    };
    final lider = sira == 1;
    final hareket = SandikMotion.of(context, SandikMotion.flow);
    // İçerik ve kaide BİR KEZ kurulur; giriş animasyonu (~1 sn × 3 sütun,
    // ekran açılırken) her karede yalnız öteleme/saydamlık/ölçek
    // sarmalayıcılarını kurar. Eskiden `AnimatedBuilder` child'sızdı: her
    // karede avatar, ad ve `YuvarlananMetin` (build'de TextPainter.layout)
    // baştan kuruluyordu — rota geçişiyle çakışan kareler (animasyon
    // denetimi 2026-10-01). Aynı widget örneği döndüğünde Flutter alt ağacı
    // yeniden kurmaz.
    final ust = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: lider ? 1 : 0.5,
          duration: hareket,
          curve: SandikMotion.spring,
          child: AnimatedOpacity(
            opacity: lider ? 1 : 0,
            duration: SandikMotion.stateOf(context),
            curve: SandikMotion.enter,
            child: const YarisTaci(genislik: SandikSpace.lg),
          ),
        ),
        const SizedBox(height: SandikSpace.xs),
        _Avatar(k: k, cap: SandikSpace.xxl, parla: lider),
        const SizedBox(height: SandikSpace.xs2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
          child: Text(
            k.kisaAd,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.c.text90,
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: YuvarlananMetin(
            _yuzde(roi),
            stil: context.t.numSmall.copyWith(
              color: roi >= 0 ? context.c.gain : context.c.loss,
            ),
          ),
        ),
      ],
    );
    final kaide = AnimatedContainer(
      duration: hareket,
      curve: SandikMotion.move,
      height: basamak,
      margin: const EdgeInsets.symmetric(horizontal: SandikSpace.xs2),
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: SandikSpace.xs2),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SandikRadius.md),
          bottom: Radius.circular(SandikSpace.xs),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            madalya.withValues(alpha: 0.4),
            madalya.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(color: madalya.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$sira',
        style: context.t.numMedium.copyWith(
          color: koyu ? madalya : madalyaKoyu,
        ),
      ),
    );
    return AnimatedBuilder(
      animation: giris,
      builder: (context, _) {
        final e = giris.value;
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Transform.translate(
              offset: Offset(0, (1 - e) * basamak),
              child: Opacity(opacity: e.clamp(0.0, 1.0), child: ust),
            ),
            const SizedBox(height: SandikSpace.xs2),
            Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.diagonal3Values(1, math.max(0.02, e), 1),
              child: kaide,
            ),
          ],
        );
      },
    );
  }
}

// ── Canlı liste ──────────────────────────────────────────────────────────────

/// Satırlar sabit yükseklikte bir Stack'te durur; sıra değişince her satır
/// yeni yerine KAYAR (FLIP'in Flutter karşılığı: anahtarlı
/// `AnimatedPositioned`). Satır yüksekliği metin ölçeğinden hesaplanır.
class _CanliListe extends StatelessWidget {
  const _CanliListe({required this.katilimcilar, required this.donemGun});
  final List<YarisKatilimci> katilimcilar;
  final int donemGun;

  @override
  Widget build(BuildContext context) {
    final k = katilimcilar;
    // Satırlar Stack'te sabit yükseklikte durur (kayma için şart); yükseklik
    // tahmin edilmez, gerçek metin ölçülerinden hesaplanır. Tahmin 1.0
    // ölçekte bile 4pt kısa kalıyordu (ad + "Lidere …" satırı).
    final satirH = _CanliSatir.yukseklik(context);
    const ara = SandikSpace.sm2;

    final verili = k.where((x) => x.roi != null).map((x) => x.roi!).toList();
    final liderRoi = verili.isEmpty ? null : verili.first;
    final maxAbs =
        verili.isEmpty ? null : verili.map((v) => v.abs()).reduce(math.max);

    return SizedBox(
      height: k.length * satirH + math.max(0, k.length - 1) * ara,
      child: Stack(
        children: [
          for (var i = 0; i < k.length; i++)
            AnimatedPositioned(
              key: ValueKey(k[i].id),
              duration: SandikMotion.of(context, SandikMotion.flow),
              curve: SandikMotion.move,
              top: i * (satirH + ara),
              left: 0,
              right: 0,
              height: satirH,
              child: _Giris(
                sira: i,
                child: _CanliSatir(
                  k: k[i],
                  sira: i + 1,
                  donemGun: donemGun,
                  liderRoi: liderRoi,
                  maxAbs: maxAbs,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Satırın ilk görünüşü: kısa gecikmeyle aşağıdan süzülür. Yalnızca bir
/// kez (ekran açılınca); sonraki güncellemeler kaydırma ile gelir.
class _Giris extends StatefulWidget {
  const _Giris({required this.sira, required this.child});
  final int sira;
  final Widget child;

  @override
  State<_Giris> createState() => _GirisState();
}

class _GirisState extends State<_Giris> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: SandikMotion.flow);
  Timer? _gecikme;
  bool _basladi = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_basladi) return;
    _basladi = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
      return;
    }
    _gecikme = Timer(SandikMotion.press * (0.6 * widget.sira), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _gecikme?.cancel();
    _c.dispose();
    super.dispose();
  }

  // Eğri bir kez kurulur; `FadeTransition` katman opaklığını doğrudan
  // değiştirir — `AnimatedBuilder` içindeki `Opacity` her karede yeniden
  // kuruluyordu (hareket denetimi 2026-09-29). Kayma piksel cinsinden
  // (`SandikSpace.md`) kaldığı için `Transform.translate` korunur.
  late final Animation<double> _egri =
      CurvedAnimation(parent: _c, curve: SandikMotion.enter);

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _egri,
      child: AnimatedBuilder(
        animation: _egri,
        child: widget.child,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, (1 - _egri.value) * SandikSpace.md),
          child: child,
        ),
      ),
    );
  }
}

class _CanliSatir extends StatefulWidget {
  const _CanliSatir({
    required this.k,
    required this.sira,
    required this.donemGun,
    required this.liderRoi,
    required this.maxAbs,
  });

  final YarisKatilimci k;
  final int sira;
  final int donemGun;
  final double? liderRoi;
  final double? maxAbs;

  static const _madalya = SandikSpace.xl + SandikSpace.xxs;

  /// Satırın sabit yüksekliği: dolgu + kenar + üst satır (madalya, ad +
  /// fark cümlesi ya da getiri — hangisi uzunsa) + fark çubuğu.
  static double yukseklik(BuildContext context) {
    final t = context.t;
    final ad =
        _metinH(context, t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
    final teaser = _metinH(context, t.labelMedium);
    final sayi = _metinH(context, t.numMedium);
    final ust = math.max(
      _madalya,
      math.max(ad + SandikSpace.xxs + teaser, sayi),
    );
    return (SandikSpace.smd * 2 + 2) +
        ust +
        SandikSpace.sm2 +
        SandikSpace.xs +
        1;
  }

  @override
  State<_CanliSatir> createState() => _CanliSatirState();
}

double _metinH(BuildContext context, TextStyle? stil) {
  final tp = TextPainter(
    text: TextSpan(text: 'Ağ', style: stil),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final h = tp.height;
  tp.dispose();
  return h;
}

class _CanliSatirState extends State<_CanliSatir>
    with SingleTickerProviderStateMixin {
  late final AnimationController _isik =
      AnimationController(vsync: this, duration: SandikMotion.flow * 2);

  /// Son canlı sıra değişimi (+ yükseldi, − düştü); çip birkaç saniye durur.
  int? _degisim;
  Timer? _cipZamanlayici;

  @override
  void didUpdateWidget(covariant _CanliSatir old) {
    super.didUpdateWidget(old);
    // Dönem değişimi canlı bir olay değil: sıra farkı ▲/▼ çipi üretmez.
    if (old.donemGun != widget.donemGun || old.sira == widget.sira) return;
    if (widget.k.roi == null) return;
    _degisim = old.sira - widget.sira;
    _cipZamanlayici?.cancel();
    _cipZamanlayici = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _degisim = null);
    });
    if (widget.sira == 1 && !MediaQuery.disableAnimationsOf(context)) {
      _isik.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _cipZamanlayici?.cancel();
    _isik.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final k = widget.k;
    final roi = k.roi;
    final lider = widget.sira == 1 && roi != null;
    final roiRengi = roi == null
        ? context.c.text36
        : (roi >= 0 ? context.c.gain : context.c.loss);

    String? teaser;
    if (k.ben && !lider && roi != null && widget.liderRoi != null) {
      final ara = widget.liderRoi! - roi;
      if (ara > 0.05) teaser = l.raceGapToLeader(fmtNum(ara, digits: 1));
    }
    // Negatif getiriye çubuk yok (utandırmayı azaltır — yalnızca rakam).
    final oran = (roi != null && roi > 0 && (widget.maxAbs ?? 0) > 0.01)
        ? (roi / widget.maxAbs!).clamp(0.0, 1.0)
        : 0.0;

    final gold = Sandik.medalGold;
    final zemin = k.ben
        ? Color.alphaBlend(
            context.c.amberFill.withValues(alpha: 0.10), context.c.surface1)
        : context.c.surface1;
    final hareket = SandikMotion.of(context, SandikMotion.flow);

    return AnimatedContainer(
      duration: hareket,
      curve: SandikMotion.enter,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.md2, vertical: SandikSpace.smd),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: lider
              ? [
                  Color.alphaBlend(gold.withValues(alpha: 0.16), zemin),
                  Color.alphaBlend(gold.withValues(alpha: 0.04), zemin),
                ]
              : [zemin, zemin],
        ),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(
          color: k.ben
              ? context.c.amberFill.withValues(alpha: 0.55)
              : lider
                  ? gold.withValues(alpha: 0.45)
                  : context.c.overlay,
          width: lider ? 1.2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: gold.withValues(alpha: lider ? 0.16 : 0),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _Madalya(sira: widget.sira, verili: roi != null),
                  const SizedBox(width: SandikSpace.smd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              flex: 3,
                              child: Text(
                                k.ad,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.t.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: context.c.text90,
                                ),
                              ),
                            ),
                            // Etiketler + çip tek grup: dar ekranda / büyük
                            // yazıda taşmak yerine birlikte küçülür (ad
                            // zaten kendi payında kısalıyor).
                            Flexible(
                              flex: 2,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (k.ben) ...[
                                      const SizedBox(width: SandikSpace.xs2),
                                      _Etiket(
                                        metin: l.raceYouTag,
                                        zemin: context.c.overlay,
                                        renk: context.c.text58,
                                      ),
                                    ],
                                    if (lider) ...[
                                      const SizedBox(width: SandikSpace.xs2),
                                      _Etiket(
                                        metin: l.leaderUpper,
                                        zemin: gold.withValues(alpha: 0.18),
                                        renk: context.c.gold,
                                      ),
                                    ],
                                    const SizedBox(width: SandikSpace.xs),
                                    AnimatedSwitcher(
                                      duration: SandikMotion.stateOf(context),
                                      switchInCurve: SandikMotion.spring,
                                      switchOutCurve: SandikMotion.exit,
                                      // %90'dan büyür, HİÇLİKTEN değil: sıra
                                      // rozeti sıfırdan patlayıp taşıyordu
                                      // (animasyon denetimi 2026-10-01).
                                      transitionBuilder: (child, a) =>
                                          FadeTransition(
                                        opacity: a,
                                        child: ScaleTransition(
                                            scale: Tween<double>(
                                                    begin: 0.9, end: 1)
                                                .animate(a),
                                            child: child),
                                      ),
                                      child: _degisim == null
                                          ? const SizedBox.shrink(
                                              key: ValueKey('yok'))
                                          : _SiraCipi(
                                              key: ValueKey(_degisim),
                                              degisim: _degisim!,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (teaser != null) ...[
                          const SizedBox(height: SandikSpace.xxs),
                          Text(
                            teaser,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                              color: context.c.amberText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: SandikSpace.sm),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.3),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: roi == null
                          ? Text(
                              l.noData,
                              style:
                                  context.t.numSmall.copyWith(color: roiRengi),
                            )
                          : YuvarlananMetin(
                              _yuzde(roi),
                              stil:
                                  context.t.numMedium.copyWith(color: roiRengi),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SandikSpace.sm2),
              ClipRRect(
                borderRadius: BorderRadius.circular(SandikRadius.sm),
                child: Container(
                  height: SandikSpace.xs,
                  color: context.c.overlay,
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: hareket,
                    curve: SandikMotion.glide,
                    widthFactor: oran,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [roiRengi.withValues(alpha: 0.5), roiRengi],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Yeni lidere bir kez ışık süzülür.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _isik,
                builder: (_, __) {
                  final t = _isik.value;
                  if (!_isik.isAnimating) return const SizedBox.shrink();
                  return FractionalTranslation(
                    translation:
                        Offset(-1 + 2 * SandikMotion.enter.transform(t), 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          stops: const [0.3, 0.5, 0.7],
                          colors: [
                            gold.withValues(alpha: 0),
                            gold.withValues(alpha: 0.3),
                            gold.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Etiket extends StatelessWidget {
  const _Etiket({required this.metin, required this.zemin, required this.renk});
  final String metin;
  final Color zemin;
  final Color renk;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.xs2, vertical: SandikSpace.xxs),
        decoration: BoxDecoration(
          color: zemin,
          borderRadius: BorderRadius.circular(SandikRadius.sm),
        ),
        child: Text(
          metin,
          style: context.t.labelSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            color: renk,
          ),
        ),
      );
}

class _SiraCipi extends StatelessWidget {
  const _SiraCipi({super.key, required this.degisim});
  final int degisim;

  @override
  Widget build(BuildContext context) {
    final yukari = degisim > 0;
    final renk = yukari ? context.c.gain : context.c.loss;
    final n = degisim.abs();
    return Semantics(
      label: yukari ? context.l10n.raceRankUp(n) : context.l10n.raceRankDown(n),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.xs2, vertical: SandikSpace.xxs),
        decoration: BoxDecoration(
          color: renk.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(SandikRadius.sm),
        ),
        child: Text(
          '${yukari ? '▲' : '▼'}$n',
          style: context.t.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: renk,
          ),
        ),
      ),
    );
  }
}

// ── Konfeti ──────────────────────────────────────────────────────────────────

/// Liderliği canlı yenilemede aldığında vitrinin üstünden kısa bir altın
/// konfeti patlaması. Nadir an; "hareketi azalt" açıkken hiç oynamaz.
class _Konfeti extends StatefulWidget {
  const _Konfeti({required this.tetik});
  final int tetik;

  @override
  State<_Konfeti> createState() => _KonfetiState();
}

class _KonfetiState extends State<_Konfeti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: SandikMotion.flow * 2.2);
  List<_Parca> _parcalar = const [];

  @override
  void didUpdateWidget(covariant _Konfeti old) {
    super.didUpdateWidget(old);
    if (old.tetik == widget.tetik || MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final r = math.Random(widget.tetik);
    final renkler = [
      Sandik.medalGold,
      Sandik.amber,
      Sandik.medalSilver,
      context.c.gain,
      Sandik.info,
    ];
    _parcalar = [
      for (var i = 0; i < 28; i++)
        _Parca(
          aci: -math.pi * (0.1 + 0.8 * r.nextDouble()),
          hiz: 180 + 220 * r.nextDouble(),
          donus: (r.nextDouble() - 0.5) * 14,
          renk: renkler[i % renkler.length],
          boy: 4 + 4 * r.nextDouble(),
        ),
    ];
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => _c.isAnimating
          ? CustomPaint(
              painter: _KonfetiBoyaci(
                t: _c.value,
                saniye: _c.duration!.inMilliseconds / 1000,
                parcalar: _parcalar,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _Parca {
  const _Parca({
    required this.aci,
    required this.hiz,
    required this.donus,
    required this.renk,
    required this.boy,
  });
  final double aci;
  final double hiz;
  final double donus;
  final Color renk;
  final double boy;
}

class _KonfetiBoyaci extends CustomPainter {
  _KonfetiBoyaci(
      {required this.t, required this.saniye, required this.parcalar});
  final double t;
  final double saniye;
  final List<_Parca> parcalar;

  @override
  void paint(Canvas canvas, Size size) {
    final kaynak = Offset(size.width / 2, size.height * 0.2);
    final zaman = t * saniye;
    const yercekimi = 620.0;
    final boya = Paint();
    for (final p in parcalar) {
      final konum = kaynak +
          Offset(
            math.cos(p.aci) * p.hiz * zaman,
            math.sin(p.aci) * p.hiz * zaman + 0.5 * yercekimi * zaman * zaman,
          );
      boya.color = p.renk.withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(konum.dx, konum.dy);
      canvas.rotate(p.donus * zaman);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero, width: p.boy, height: p.boy * 0.5),
          const Radius.circular(1),
        ),
        boya,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _KonfetiBoyaci old) => old.t != t;
}
