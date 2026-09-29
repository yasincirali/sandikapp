import 'package:flutter/material.dart';

import '../models/asset_type.dart';
import '../services/tefas_service.dart';
import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Fon kodu → resmi TEFAS adı. Test için değiştirilebilir.
typedef FonAdiBulucu = Future<String?> Function(String kod);

Future<String?> _tefasAdi(String kod) async =>
    (await TefasService.instance.lookupFund(kod))?.name;

/// Bir portföyün fon türü içindeki kırılımı: hangi fon, portföyün yüzde
/// kaçı (kullanıcı kararı 2026-09-29: "fonda hangi fonlar olduğu ve
/// oranları da yazmalı").
///
/// ## Ad nereden
/// Sunucu yalnız TEFAS KODUNU taşır (0084). Ad, resmi TEFAS kataloğundan
/// okunur (`TefasService.lookupFund`, 24 saat disk önbelleği) — kullanıcının
/// varlığa verdiği ad ya da not hiçbir zaman başkasına görünmez. Katalogda
/// yoksa yalnız kod yazılır.
///
/// ## Çubuk ölçeği
/// Çubuk fon TOPLAMINA göre (en büyük fon ≈ tam dolu değil, fonların
/// kendi içindeki payı); sağdaki yüzde ise TOPLAM portföyün yüzdesi —
/// tür satırındaki "Fon %28" ile aynı taban, toplamları tutar.
class ZirveFonListesi extends StatefulWidget {
  const ZirveFonListesi({
    super.key,
    required this.fonDetay,
    this.senFonDetay,
    this.adBul,
  });

  /// {TEFAS kodu: toplam portföyün %'si}; "DIGER" toplu kalem.
  final Map<String, double> fonDetay;

  /// Verilirse her satırın altında "sende %X" yazar (kıyas).
  final Map<String, double>? senFonDetay;
  final FonAdiBulucu? adBul;

  @override
  State<ZirveFonListesi> createState() => _ZirveFonListesiState();
}

class _ZirveFonListesiState extends State<ZirveFonListesi> {
  // Future'lar kod başına bir kez kurulur; her build'de yeni istek yok.
  final Map<String, Future<String?>> _adlar = {};

  Future<String?> _ad(String kod) => _adlar.putIfAbsent(
      kod, () => (widget.adBul ?? _tefasAdi)(kod).catchError((_) => null));

  @override
  Widget build(BuildContext context) {
    final satirlar = ZirveKiyas.fonSirali(widget.fonDetay);
    if (satirlar.isEmpty) return const SizedBox.shrink();
    final fonToplami = satirlar.fold<double>(0, (s, e) => s + e.pay);
    final renk = AssetType.fon.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in satirlar) ...[
          _satir(context, f.kod, f.pay, fonToplami, renk),
          const SizedBox(height: SandikSpace.sm),
        ],
      ],
    );
  }

  Widget _satir(BuildContext context, String kod, double pay,
      double fonToplami, Color renk) {
    final diger = kod == ZirveKiyas.fonDiger;
    final sen = widget.senFonDetay;
    final senPay = sen == null ? null : (sen[kod] ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: SandikSpace.xs2),
              decoration: BoxDecoration(
                color: renk.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(SandikRadius.sm),
              ),
              child: Text(
                diger ? 'DİĞER' : kod,
                style: context.t.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: context.c.text90,
                ),
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: diger
                  ? Text(
                      'Diğer fonlar (her biri %1 altı ya da kodsuz)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.labelMedium?.copyWith(
                        letterSpacing: 0,
                        color: context.c.text58,
                      ),
                    )
                  : FutureBuilder<String?>(
                      future: _ad(kod),
                      builder: (context, snap) => Text(
                        snap.data ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.labelMedium?.copyWith(
                          letterSpacing: 0,
                          color: context.c.text58,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Text(
              '%${fmtNum(pay, digits: pay < 10 ? 1 : 0)}',
              style: context.t.numSmall.copyWith(
                fontWeight: FontWeight.w700,
                color: context.c.text90,
              ),
            ),
          ],
        ),
        const SizedBox(height: SandikSpace.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(SandikRadius.sm),
          child: Container(
            height: 6,
            color: context.c.overlay,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor:
                  fonToplami <= 0 ? 0 : (pay / fonToplami).clamp(0.0, 1.0),
              child: Container(color: renk),
            ),
          ),
        ),
        if (senPay != null) ...[
          const SizedBox(height: SandikSpace.xs),
          Text(
            senPay < 0.05
                ? 'sende yok'
                : 'sende %${fmtNum(senPay, digits: senPay < 10 ? 1 : 0)}',
            style: context.t.labelSmall?.copyWith(
              letterSpacing: 0,
              color: context.c.text36,
            ),
          ),
        ],
      ],
    );
  }
}
