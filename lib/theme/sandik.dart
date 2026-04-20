import 'package:flutter/material.dart';

/// Sandık (ex-Toka) marka renk paleti ve logo painter
class Sandik {
  // ── Core palette ────────────────────────────────────────────────────────────
  static const Color dark      = Color(0xFF112E28); // Seviye 1 — Kart yüzeyi
  static const Color background = Color(0xFF0A1E15); // Seviye 0 — Ana arka plan
  static const Color surface1  = Color(0xFF112E28); // Seviye 1
  static const Color surface2  = Color(0xFF1A3D2E); // Seviye 2 — Hero kart / elevated
  static const Color brown     = Color(0xFF2D7A60); // "Orman" — yardımcı yeşil
  
  static const Color amber     = Color(0xFFF5A623); // CTA, aktif durum, logo ikon
  static const Color gold      = Color(0xFFF5C842); // Display sayılar, logo wordmark
  static const Color bronze    = Color(0xFFF5A623); // (Legacy mapping to amber)
  static const Color adacayi   = Color(0xFFE8EDE5); // Açık zemin (light mode)

  // ── Finansal anlamsal ───────────────────────────────────────────────────────
  static const Color gain      = Color(0xFF2D9E6C); // Pozitif delta (Kazanç)
  static const Color loss      = Color(0xFFE8503A); // Negatif delta (Kayıp)

  // ── Sabit opaklıklar (dark zemin üzeri metin) ──────────────────────────────
  static const Color text90    = Color(0xE1FFFFFF); // 0.88 opak (Ana başlık)
  static const Color text58    = Color(0x8CFFFFFF); // 0.55 (İkincil etiket)
  static const Color text36    = Color(0x59FFFFFF); // 0.35 (Üçüncül yardımcı)
  static const Color text20    = Color(0x33FFFFFF); // 0.20 (Devre dışı)

  static InputDecoration inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: text36, fontSize: 14),
      filled: true,
      fillColor: Colors.black.withOpacity(0.1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: amber, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

/// Sandık (ex-Toka) logosu — viewBox 80×50, geometrik kemer tokası
class SandikLogoPainter extends CustomPainter {
  final Color color;
  const SandikLogoPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // viewBox 80x50 mapping
    final sx = size.width / 80;
    final sy = size.height / 50;

    final paintStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8 * sx
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final paintFill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 1. Dış çerçeve: Yuvarlatılmış dikdörtgen (rx=10)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2 * sx, 2 * sy, 76 * sx, 46 * sy),
        Radius.circular(10 * sx),
      ),
      paintStroke,
    );

    // 2. İç slot: Daha küçük yuvarlatılmış dikdörtgen (rx=5)
    final slotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * sx;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(9 * sx, 10 * sy, 30 * sx, 30 * sy),
        Radius.circular(5 * sx),
      ),
      slotPaint,
    );

    // 3. Pin/dil: Sağ tarafta yatay çizgi
    final pinPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5 * sx
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(48 * sx, 25 * sy), Offset(72 * sx, 25 * sy), pinPaint);

    // 4. Pin başı: Sol ucu dolan küçük dolu daire
    canvas.drawCircle(Offset(48 * sx, 25 * sy), 4.5 * sx, paintFill);
  }

  @override
  bool shouldRepaint(SandikLogoPainter old) => old.color != color;
}

/// Sandık logo widget'ı
class SandikLogo extends StatelessWidget {
  final double size;
  final Color? color;
  const SandikLogo({super.key, this.size = 32, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Sandik.amber;
    return CustomPaint(
      size: Size(size * 80 / 50, size),
      painter: SandikLogoPainter(c),
    );
  }
}
