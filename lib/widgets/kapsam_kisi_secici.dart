import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/user_model.dart';
import '../theme/sandik.dart';

/// "Kimin portföyü?" seçici — kontrol yığınının İLK satırı.
///
/// Birlikte ve Ben tek dokunuşluk segment; ortaklar üçüncü segmentte: tek
/// ortak varsa doğrudan adı (tek dokunuş), birden çoksa açılır liste.
///
/// ## Nasıl buraya geldi (2026-09-15, dört tur kullanıcı geri bildirimi)
///   1. Kapsam panelinin arkasında, çipte "Ben · Tümü" — "görülebilir olmalı".
///   2. Başlık çubuğunda avatar+ad çipi, açılır menü — "hızlı hızlı geçiş
///      yapıp grafik karşılaştıracak var": menü her geçişi iki dokunuşa
///      çıkarıyor.
///   3. Başlıkta avatar şeridi, tek dokunuş — "o kadar yukarıda olması
///      doğru olmadı, aşağıya gelmeli; Birlikte ve Ben hızlı tıklanabilir,
///      ortaklar dropdown olabilir".
///   4. Bu: kontrollerin ilk satırında segmentli seçici. Sık geçilen iki
///      hedef (Birlikte/Ben) tek dokunuş, seyrek olan ortak listesi menüde.
///      Yüzey (Grafik/Özet) ve dönem seçicileriyle aynı kabuk (36pt,
///      surface1, radius md) — kullanıcı üçünü aynı sınıf denetim okur.
///
/// ## Sözleşme `ModernTabSelector` ile AYNI
/// `null` = Birlikte, `''` = Ben, uuid = o ortak. Ortak yoksa çağıran satırı
/// hiç çizmez — tek seçenekli seçici gürültü.
class KapsamKisiSecici extends StatelessWidget {
  const KapsamKisiSecici({
    super.key,
    required this.partners,
    required this.selectedId,
    required this.onChanged,
  });

  final List<AppUser> partners;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  static String _ilkAd(String ad) {
    final t = ad.trim();
    return t.isEmpty ? '?' : t.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final tekOrtak = partners.length == 1;
    AppUser? seciliOrtak;
    for (final p in partners) {
      if (p.id == selectedId) seciliOrtak = p;
    }
    // Tek ortak: adı yazılır, dokununca seçilir. Çok ortak: seçili olanın
    // adı ya da "Ortaklar", dokununca liste açılır.
    final ortakEtiket = tekOrtak
        ? _ilkAd(partners.first.displayName)
        : (seciliOrtak != null
            ? _ilkAd(seciliOrtak.displayName)
            : l.scopePartners);

    return Container(
      height: 36,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _Segment(
            etiket: l.scopeTogether,
            secili: selectedId == null,
            onek: l.scopeWho,
            onTap: () => onChanged(null),
          ),
          _Segment(
            etiket: l.scopeMe,
            secili: selectedId == '',
            onek: l.scopeWho,
            onTap: () => onChanged(''),
          ),
          if (tekOrtak)
            _Segment(
              etiket: ortakEtiket,
              secili: seciliOrtak != null,
              onek: l.scopeWho,
              onTap: () => onChanged(partners.first.id),
            )
          else
            _OrtakMenusu(
              etiket: ortakEtiket,
              secili: seciliOrtak != null,
              onek: l.scopeWho,
              partners: partners,
              seciliId: seciliOrtak?.id,
              onChanged: onChanged,
              ilkAd: _ilkAd,
            ),
        ],
      ),
    );
  }
}

/// Seçili kabuk: surface2 + amber metin — dönem ve yüzey seçicileriyle aynı.
BoxDecoration _kabuk(BuildContext context, bool secili) => BoxDecoration(
      color: secili ? context.c.surface2 : Colors.transparent,
      borderRadius: BorderRadius.circular(SandikRadius.sm),
    );

TextStyle? _metin(BuildContext context, bool secili) =>
    context.t.bodyMedium?.copyWith(
      fontWeight: secili ? FontWeight.w600 : FontWeight.w500,
      color: secili ? context.c.amberText : context.c.text36,
    );

class _Segment extends StatelessWidget {
  const _Segment({
    required this.etiket,
    required this.secili,
    required this.onek,
    required this.onTap,
  });

  final String etiket;
  final bool secili;
  final String onek;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: secili,
        label: '$onek: $etiket',
        child: ExcludeSemantics(
          child: CupertinoButton(
            minimumSize: SandikTouch.minSize,
            padding: EdgeInsets.zero,
            onPressed: onTap,
            child: Container(
              height: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xs2),
              decoration: _kabuk(context, secili),
              child: Text(
                etiket,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _metin(context, secili),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ortak listesi — birden çok ortakta üçüncü segment.
///
/// `Material` sarmalayıcısı ZORUNLU ve popup'ın DIŞINDA: bu ekran
/// `CupertinoPageScaffold` altında ve `PopupMenuButton`'ın kendi `InkWell`'i
/// Material ata arıyor (bkz. `GrafikTipiSecici`, aynı tuzak).
class _OrtakMenusu extends StatelessWidget {
  const _OrtakMenusu({
    required this.etiket,
    required this.secili,
    required this.onek,
    required this.partners,
    required this.seciliId,
    required this.onChanged,
    required this.ilkAd,
  });

  final String etiket;
  final bool secili;
  final String onek;
  final List<AppUser> partners;
  final String? seciliId;
  final ValueChanged<String?> onChanged;
  final String Function(String) ilkAd;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: secili,
        label: '$onek: $etiket',
        child: ExcludeSemantics(
          child: Material(
            type: MaterialType.transparency,
            child: PopupMenuButton<String>(
              tooltip: context.l10n.scopePartners,
              position: PopupMenuPosition.under,
              color: context.c.surface2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SandikRadius.md),
                side: BorderSide(color: context.c.hairline),
              ),
              onSelected: onChanged,
              itemBuilder: (_) => [
                for (final p in partners)
                  PopupMenuItem<String>(
                    value: p.id,
                    height: 48,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            ilkAd(p.displayName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.bodyMedium?.copyWith(
                              color: context.c.text90,
                              fontWeight: p.id == seciliId
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        // Tik YALNIZCA seçilide; yer hep ayrılır ki satırlar
                        // kaymasın.
                        SizedBox(
                          width: 20,
                          child: p.id == seciliId
                              ? Icon(Icons.check_rounded,
                                  size: 16, color: context.c.amberText)
                              : null,
                        ),
                      ],
                    ),
                  ),
              ],
              child: Container(
                height: double.infinity,
                alignment: Alignment.center,
                padding:
                    const EdgeInsets.symmetric(horizontal: SandikSpace.xs2),
                decoration: _kabuk(context, secili),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        etiket,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _metin(context, secili),
                      ),
                    ),
                    Icon(Icons.expand_more_rounded,
                        size: 16,
                        color: secili ? context.c.amberText : context.c.text36),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
