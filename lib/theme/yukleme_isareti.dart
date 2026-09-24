/// sandık yükleme işareti — vektör, tema/çözünürlük bağımsız.
///
/// ## Neden GIF değil (kullanıcı bildirimi, 2026-09-24)
/// *"İlk giriş loading gif'i düzgün kırpılmamış gibi gözüküyor; dark modda
/// sınırlar çok belli oluyor."*
///
/// Eski `assets/images/loading.gif` 200×200 px, 1-bit alfa (0/255) ve
/// 60 kareydi. Açılış ekranı onu 140 dp × 1,33 = 187 dp'ye, 3× ekranda
/// 560 fiziksel piksele büyütüyordu — 2,8 kat. Ölçüldü: kenar pikselleri
/// kaynakta merdiven basamağı (köşe yarıçapı 27 px'te 28 basamak), yüksek
/// kalite filtre bunu 2-3 px'lik bulanık bir banda çeviriyordu. Açık zeminde
/// sarı ile bej yakın olduğundan görünmüyor; koyu yeşil zeminde o bant
/// "çerçeve" gibi okunuyor, köşelerdeki basamaklar da "kırpılmamış"
/// izlenimi veriyordu. Kaynağı büyütmek (ör. 800 px GIF) dosyayı katlar,
/// 1-bit alfa sorununu çözmez.
///
/// Şimdi işaret CustomPainter ile çiziliyor: anti-alias'lı yuvarlak kare
/// kırpması her DPR'da keskin, zemin ne olursa olsun kenar yok, 117 KB
/// asset gitti. Geometri ve renkler GIF'ten ölçüldü (kare 0, x=100 sütunu):
/// dört bant + tepede ince parlak şerit, üç sınır aynı fazda ilerleyen
/// sinüs dalgası (genlik 8/150, dalga boyu = kutu genişliği, döngü
/// 60 kare × 30 ms = 1,8 s).
///
/// Renkler marka sabitidir, iki modda da aynıdır (GIF'te de öyleydi) —
/// bu yüzden `context.c` üzerinden değil, buradaki sabitlerden okunur.
/// `design_token_leak_test` `lib/theme/` dizinini dışarıda tutar.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

/// Yükleme işaretinin sabitleri.
abstract final class YuklemeIsaretiSabitleri {
  const YuklemeIsaretiSabitleri._();

  /// Tepedeki ince parlak şerit (GIF: 251,209,88).
  static const Color tepe = Color(0xFFFBD158);

  /// Üst bant (248,201,80).
  static const Color sari = Color(0xFFF8C950);

  /// İkinci bant (225,133,30).
  static const Color turuncu = Color(0xFFE1851E);

  /// Üçüncü bant (197,99,20).
  static const Color kehribar = Color(0xFFC56314);

  /// Alt bant (153,61,10).
  static const Color kahve = Color(0xFF993D0A);

  /// Köşe yarıçapı / kenar (27/150).
  static const double koseOrani = 27 / 150;

  /// Parlak şeridin yüksekliği / kenar (11/150).
  static const double parlakSerit = 11 / 150;

  /// Üç dalga sınırının ortalama y'si / kenar (46, 69, 93 / 150).
  static const List<double> dalgaOrtalari = [46 / 150, 69 / 150, 93 / 150];

  /// Dalga genliği / kenar (8/150).
  static const double genlik = 8 / 150;

  /// Bir tam dalga döngüsü — GIF'in 60 × 30 ms'i.
  static const Duration dongu = Duration(milliseconds: 1800);

  /// Kenarı toparlayan ince çerçeve: en koyu bandın %28'i. Parlak sarının
  /// koyu zemine çarptığı yerde tek piksellik AA geçişi sert okunuyordu;
  /// yarı saydam koyu çerçeve iki zeminde de kenarı yumuşatır.
  static const Color cerceve = Color(0x47993D0A);

  /// Açık zeminde işaretin altına düşen gölge (siyah %14). Koyu zeminde
  /// gölge görünmez, çizilmez.
  static const Color golgeAcikZemin = Color(0x24000000);
}

/// İşareti verilen [faz] (0..1) için çizer. [repaint] verilirse her tick'te
/// yeniden çizilir; `Animated*` widget'ı gerekmez.
class YuklemeIsaretiPainter extends CustomPainter {
  YuklemeIsaretiPainter({required this.faz, this.golge, super.repaint});

  /// 0..1 arası; [repaint] bir [Animation] ise onun `value`'su okunur.
  final Animation<double>? faz;

  /// Verilirse işaretin altına bu renkte yumuşak gölge düşer.
  final Color? golge;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (s <= 0) return;
    // Gölge payı: dış kutu aynı, gövde biraz içeri alınır ki gölge kutudan
    // taşıp komşu widget'ın üstüne binmesin.
    final pay = golge == null ? 0.0 : s * 0.04;
    final kenar = s - 2 * pay;
    final rect = Rect.fromLTWH(
        (size.width - kenar) / 2, (size.height - kenar) / 2, kenar, kenar);
    final rrect = RRect.fromRectAndRadius(
        rect, Radius.circular(kenar * YuklemeIsaretiSabitleri.koseOrani));
    final govde = Path()..addRRect(rrect);
    final t = faz?.value ?? 0;

    // ## Neden kırpma (`clipRRect`) değil, yol kesişimi (2026-09-24)
    // Kullanıcı: "mükemmel smooth round köşeler ve kenarlar". Kırpma
    // AA'sı motora bağlı — Impeller'da kırpma kenarı Skia'daki kadar
    // yumuşak olmuyor. Her bant, gövde yuvarlak karesiyle KESİŞTİRİLMİŞ
    // bir yol olarak dolduruluyor; kenar her motorda dolgunun kendi
    // anti-alias'ından geliyor, kırpmadan değil.
    Path kes(Path p) => Path.combine(PathOperation.intersect, govde, p);
    final dolgu = Paint()..isAntiAlias = true;

    if (golge != null) {
      canvas.drawRRect(
        rrect.shift(Offset(0, s * 0.035)),
        Paint()
          ..color = golge!
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.05),
      );
    }

    canvas.drawRRect(rrect, dolgu..color = YuklemeIsaretiSabitleri.sari);
    canvas.drawPath(
      kes(Path()
        ..addRect(Rect.fromLTWH(rect.left, rect.top, kenar,
            kenar * YuklemeIsaretiSabitleri.parlakSerit))),
      dolgu..color = YuklemeIsaretiSabitleri.tepe,
    );

    const renkler = [
      YuklemeIsaretiSabitleri.turuncu,
      YuklemeIsaretiSabitleri.kehribar,
      YuklemeIsaretiSabitleri.kahve,
    ];
    // 96 parça: 187 dp × 3x'te bile sinüs kırıksız.
    const parca = 96;
    for (var k = 0; k < renkler.length; k++) {
      final orta = rect.top + kenar * YuklemeIsaretiSabitleri.dalgaOrtalari[k];
      final dalga = Path();
      for (var i = 0; i <= parca; i++) {
        final u = i / parca;
        final x = rect.left + kenar * u;
        // Dalga sola akar (GIF'teki yön): faz arttıkça tepe sola kayar.
        final y = orta +
            kenar * YuklemeIsaretiSabitleri.genlik *
                math.sin(2 * math.pi * (u + t));
        if (i == 0) {
          dalga.moveTo(x, y);
        } else {
          dalga.lineTo(x, y);
        }
      }
      dalga
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.left, rect.bottom)
        ..close();
      canvas.drawPath(kes(dalga), dolgu..color = renkler[k]);
    }

    // Kenarı toparlayan ince çerçeve — gövdenin yarım piksel içinde ki
    // dışarı taşıp zeminde ikinci bir hat çizmesin.
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = YuklemeIsaretiSabitleri.cerceve,
    );
  }

  @override
  bool shouldRepaint(YuklemeIsaretiPainter old) =>
      old.faz != faz || old.golge != golge;
}

/// Kendi kendine dönen yükleme işareti. [size] × [size] kutuyu tam doldurur.
///
/// "Hareketi azalt" açıkken dalga durur, işaret ilk karesinde sabit çizilir
/// (iOS HIG: hareket tercihi yok sayılmaz). Ayar oturum içinde değişirse
/// `didChangeDependencies` sayacı durdurur/başlatır.
class YuklemeIsareti extends StatefulWidget {
  const YuklemeIsareti({super.key, required this.size, this.golgeli = false});

  /// Açık zeminde işaretin altına yumuşak gölge düşsün mü? Açılış ekranı
  /// gibi büyük, tek başına duran işaret için; satır içi küçük göstergede
  /// gölge gürültü olur. Koyu zeminde gölge zaten çizilmez.
  final bool golgeli;

  /// Sayaç çalışsın mı? Uygulamada her zaman `true`.
  ///
  /// Widget testleri `test/flutter_test_config.dart` ile `false` yapar:
  /// sonsuz sayaç `pumpAndSettle`'ı hiç bitirmez ve 35 test dosyası ona
  /// dayanıyor. Eski GIF testte hiç çözülmediği için sessizce hareketsizdi;
  /// bu bayrak aynı davranışı AÇIK hâle getirir. Sayacın kendisini sınayan
  /// test bayrağı geçici olarak `true` yapar (`yukleme_isareti_test`).
  static bool hareketli = true;

  final double size;

  @override
  State<YuklemeIsareti> createState() => _YuklemeIsaretiState();
}

class _YuklemeIsaretiState extends State<YuklemeIsareti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sayac = AnimationController(
    vsync: this,
    duration: YuklemeIsaretiSabitleri.dongu,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!YuklemeIsareti.hareketli || MediaQuery.disableAnimationsOf(context)) {
      _sayac
        ..stop()
        ..value = 0;
    } else if (!_sayac.isAnimating) {
      _sayac.repeat();
    }
  }

  @override
  void dispose() {
    _sayac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final acikZemin = Theme.of(context).brightness == Brightness.light;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: YuklemeIsaretiPainter(
          faz: _sayac,
          repaint: _sayac,
          golge: widget.golgeli && acikZemin
              ? YuklemeIsaretiSabitleri.golgeAcikZemin
              : null,
        ),
      ),
    );
  }
}
