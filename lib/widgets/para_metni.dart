import 'package:flutter/material.dart';

import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Büyük para/fiyat metni: hane hane akan rakam + simge/kuruş hiyerarşisi
/// (bayrak `akan_rakam`; çağıran bayrağa bakar, kapalıyken düz `Text`).
///
/// ## Neden (göz alıcılık paketi A, yasin 2026-10-09)
/// Fiyat yenilenince yeni değere sessizce atlıyordu; ₺, tam kısım ve kuruş
/// aynı boy ve ağırlıktaydı. Robinhood (açık kaynak "Ticker") ve Apple
/// (`numericText` geçişi) yalnız DEĞİŞEN haneyi döndürür, yönü değerden
/// alır; Apple Card/Revolut büyük tutarda birimi geri çeker. Göz önce
/// büyüklüğü, sonra birimi okur.
///
/// ## Kurallar
/// - Biçim çağırandan gelir (`fmtTRY`, `BazPara.fmt`…); burada yeniden
///   biçimlenmez, yalnız parçalanır. Rakamsız metin ("—", gizli bakiye)
///   düz yazılır.
/// - İlk çizimde dönmez: sayı hazır gelir. Yalnız değişen hane döner;
///   artışta aşağıdan yukarı, düşüşte yukarıdan aşağı. Haneler soldan sağa
///   hafif gecikmeli (göz büyük haneden okur).
/// - Süre `SandikMotion.flowOf` (gözün izlemesi istenen akış); "hareketi
///   azalt" açıkken sıfır, rakam anında yerine oturur.
/// - Ekran okuyucu tek metin okur ([metin]); haneler tek tek okunmaz.
/// - Yer oynamaz: rakamlar tablo genişliğinde (`numLarge`/`numMedium`
///   tabular), dönen hane kendi kutusunda kırpılır.
class ParaMetni extends StatefulWidget {
  const ParaMetni(
    this.metin, {
    super.key,
    required this.stil,
    this.kimlik,
  });

  final String metin;

  /// Rakamların stili (rengi dahil). Simge ve kuruş bundan türetilir.
  final TextStyle stil;

  /// Değerin "kime ait" olduğu; değişirse (başka varlık, başka dilim)
  /// haneler dönmez, yeni metin doğrudan yazılır.
  final Object? kimlik;

  @override
  State<ParaMetni> createState() => _ParaMetniState();
}

/// Simge ve kuruşun rakama göre boyu ve opaklığı. Kuruş fiyatta anlamlı
/// (206,10) — simgeden az küçülür.
const double _simgeOrani = 0.6;
const double _kurusOrani = 0.72;
const double _ikincilOpaklik = 0.7;

class _ParaMetniState extends State<ParaMetni> {
  bool _yukari = true;
  // Kimlik değişince haneler sıfırdan kurulsun (dönmesin) diye anahtar
  // nesli.
  int _nesil = 0;

  @override
  void didUpdateWidget(covariant ParaMetni old) {
    super.didUpdateWidget(old);
    if (old.kimlik != widget.kimlik) {
      _nesil++;
      return;
    }
    if (old.metin == widget.metin) return;
    final a = parseTrNumber(old.metin);
    final b = parseTrNumber(widget.metin);
    if (a != null && b != null && a != b) _yukari = b > a;
  }

  @override
  Widget build(BuildContext context) {
    final p = _Parcalar.ayir(widget.metin);
    if (p == null) {
      return Text(widget.metin, maxLines: 1, style: widget.stil);
    }
    // Boyut oranı için yazı boyu gerekir; stil boyut taşımıyorsa ortam
    // stilinden tamamlanır.
    final stil = DefaultTextStyle.of(context).style.merge(widget.stil);
    final ikincil = stil.copyWith(
      color: stil.color?.withValues(
          alpha: (stil.color!.a * _ikincilOpaklik).clamp(0.0, 1.0)),
    );
    final simgeStili = ikincil.apply(fontSizeFactor: _simgeOrani);
    final kurusStili = ikincil.apply(fontSizeFactor: _kurusOrani);

    final cocuklar = <Widget>[];
    if (p.isaret.isNotEmpty) {
      cocuklar.add(Text(p.isaret, style: stil));
    }
    if (p.onEk.isNotEmpty) {
      cocuklar.add(Text(p.onEk, style: simgeStili));
    }
    // Haneler SAĞDAN konumlanır: 99 → 100'de birler hanesi birler hanesi
    // kalsın, öndeki yeni hane dönmeden belirsin.
    final govde = p.tam;
    for (var i = 0; i < govde.length; i++) {
      final ch = govde[i];
      final sagdan = govde.length - i;
      if (_rakam(ch)) {
        cocuklar.add(_Hane(
          key: ValueKey('t$_nesil-$sagdan'),
          rakam: ch,
          yukari: _yukari,
          gecikme: (i * 0.05).clamp(0.0, 0.3),
          stil: stil,
        ));
      } else {
        cocuklar.add(Text(ch, style: stil));
      }
    }
    if (p.kurus.isNotEmpty) {
      for (var i = 0; i < p.kurus.length; i++) {
        final ch = p.kurus[i];
        if (_rakam(ch)) {
          cocuklar.add(_Hane(
            key: ValueKey('k$_nesil-$i'),
            rakam: ch,
            yukari: _yukari,
            gecikme: 0.3,
            stil: kurusStili,
          ));
        } else {
          cocuklar.add(Text(ch, style: kurusStili));
        }
      }
    }
    if (p.sonEk.isNotEmpty) {
      cocuklar.add(Text(p.sonEk, style: simgeStili));
    }

    return Semantics(
      label: widget.metin,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: cocuklar,
        ),
      ),
    );
  }
}

bool _rakam(String ch) {
  final c = ch.codeUnitAt(0);
  return c >= 0x30 && c <= 0x39;
}

/// Biçimlenmiş metnin parçaları: `-₺1.234,56 USD` → işaret `-`, ön ek `₺`,
/// tam `1.234`, kuruş `,56`, son ek ` USD`.
class _Parcalar {
  const _Parcalar(this.isaret, this.onEk, this.tam, this.kurus, this.sonEk);

  final String isaret;
  final String onEk;
  final String tam;
  final String kurus;
  final String sonEk;

  static _Parcalar? ayir(String s) {
    var ilk = -1;
    var son = -1;
    for (var i = 0; i < s.length; i++) {
      if (_rakam(s[i])) {
        if (ilk < 0) ilk = i;
        son = i;
      }
    }
    if (ilk < 0) return null;
    final once = s.substring(0, ilk);
    final govde = s.substring(ilk, son + 1);
    final sonEk = s.substring(son + 1);

    // İşaret ön ekte rakam boyunda kalır (eksi kaybolmasın); simge küçülür.
    final isaret = once.replaceAll(RegExp(r'[^\-+−]'), '');
    final onEk = once.replaceAll(RegExp(r'[\-+−]'), '');

    // Türkçe biçimde ondalık ayırıcı virgül; yalnız sondaki virgül kuruştur.
    final v = govde.lastIndexOf(',');
    if (v < 0) return _Parcalar(isaret, onEk, govde, '', sonEk);
    return _Parcalar(
        isaret, onEk, govde.substring(0, v), govde.substring(v), sonEk);
  }
}

/// Tek hane. Değişince eski rakam bir yana kayıp çıkar, yenisi öbür yandan
/// girer; kutu kırpılır, genişlik değişmez.
class _Hane extends StatefulWidget {
  const _Hane({
    super.key,
    required this.rakam,
    required this.yukari,
    required this.gecikme,
    required this.stil,
  });

  final String rakam;
  final bool yukari;

  /// Akışın 0–1 aralığında başlama payı (soldan sağa kademelenme).
  final double gecikme;
  final TextStyle stil;

  @override
  State<_Hane> createState() => _HaneState();
}

class _HaneState extends State<_Hane> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: SandikMotion.flow, value: 1);
  String? _onceki;

  @override
  void didUpdateWidget(covariant _Hane old) {
    super.didUpdateWidget(old);
    if (old.rakam == widget.rakam) return;
    _onceki = old.rakam;
    _c.duration = SandikMotion.flowOf(context);
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yeni = Text(widget.rakam, style: widget.stil);
    return AnimatedBuilder(
      animation: _c,
      child: yeni,
      builder: (context, child) {
        final onceki = _onceki;
        if (_c.isCompleted || onceki == null) return child!;
        final t = Interval(widget.gecikme, 1, curve: SandikMotion.glide)
            .transform(_c.value);
        // Artış: yeni aşağıdan gelir, eski yukarı çıkar. Düşüş tersi.
        final yon = widget.yukari ? 1.0 : -1.0;
        return ClipRect(
          child: Stack(
            children: [
              FractionalTranslation(
                translation: Offset(0, yon * (1 - t)),
                child: child,
              ),
              Positioned.fill(
                child: FractionalTranslation(
                  translation: Offset(0, -yon * t),
                  child: Text(onceki, style: widget.stil),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
