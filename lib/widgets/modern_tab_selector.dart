import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/user_model.dart';
import '../theme/sandik.dart';

/// "Kimin portföyü?" seçici — kayan amber pill kabuğu.
///
/// Sözleşme `KapsamKisiSecici` ile AYNI: `null` = Birlikte, `''` = Ben,
/// uuid = o ortak. İkisi aynı soruyu soruyor, farklı kabukta: bu 48pt
/// kayan pill (ana sekmeler), o 36pt sade segment (Performans ekranının
/// denetim yığını, yanındaki dönem/yüzey seçicileriyle aynı sınıf).
///
/// ## Sabit ÜÇ segment — ortak sayısı kaç olursa olsun
///
/// Önceki hâli `totalW / count` ile genişliği ortak sayısına bölüyordu ve
/// hiç kaydırmıyordu. 4 ortakta segment ~58px'e, 8 ortakta ~38px'e
/// iniyordu: "Birlikte" oraya sığmıyor, dokunma hedefi de
/// `SandikTouch.minSize` altına düşüyordu. Yani seçici, ortak sayısı
/// arttıkça sessizce kullanılamaz hâle geliyordu.
///
/// Çözüm `KapsamKisiSecici`'nin dört tur kullanıcı geri bildirimiyle
/// vardığı yerin aynısı: sık geçilen iki hedef (Birlikte/Ben) tek
/// dokunuş, seyrek olan ortak listesi üçüncü segmentte menüde. Genişlik
/// artık N'den bağımsız — `totalW / 3`.
///
/// Tek ortak varsa üçüncü segment doğrudan o ortağın adıdır ve tek
/// dokunuşla seçilir; menü açmak tek seçenek için gereksiz dokunuş olurdu.
class ModernTabSelector extends StatelessWidget {
  final List<AppUser> partners;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const ModernTabSelector({
    super.key,
    required this.partners,
    required this.selectedId,
    required this.onChanged,
  });

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

    // Üçüncü segmentin etiketi: tek ortakta adı, çok ortakta seçili olanın
    // adı ya da (hiçbiri seçili değilse) "Ortaklar".
    final ortakEtiket = tekOrtak
        ? _ilkAd(partners.first.displayName)
        : (seciliOrtak != null
            ? _ilkAd(seciliOrtak.displayName)
            : l.scopePartners);

    // Pill'in yeri: Birlikte 0, Ben 1, ortak (hangisi olursa olsun) 2.
    // Ortak segmenti TEK yuva — seçili ortak değişince pill kaymaz,
    // yalnızca etiket değişir.
    final int seciliIndeks =
        selectedId == null ? 0 : (selectedId == '' ? 1 : 2);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final totalW = constraints.maxWidth;
        // Sabit 3 — ortak sayısından BAĞIMSIZ. Eski `count` buraya
        // girdiğinde seçici N büyüdükçe okunamaz hâle geliyordu.
        const count = 3;
        final tabW = totalW / count;
        final pillLeft = seciliIndeks * tabW;

        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: context.c.overlay,
              width: 1.0,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Sliding pill
              AnimatedPositioned(
                duration:
                    SandikMotion.of(context, const Duration(milliseconds: 220)),
                curve: Curves.easeInOutCubic,
                left: pillLeft + 4,
                top: 4,
                width: tabW - 8,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.c.amberFill,
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    boxShadow: [
                      BoxShadow(
                        color: context.c.amberFill.withValues(alpha: 0.40),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                ),
              ),
              // Tab labels
              Positioned.fill(
                child: Row(
                  children: [
                    _Sekme(
                      etiket: l.scopeTogether,
                      secili: seciliIndeks == 0,
                      onek: l.scopeWho,
                      onTap: () => onChanged(null),
                    ),
                    _Sekme(
                      etiket: l.scopeMe,
                      secili: seciliIndeks == 1,
                      onek: l.scopeWho,
                      onTap: () => onChanged(''),
                    ),
                    if (tekOrtak)
                      _Sekme(
                        etiket: ortakEtiket,
                        secili: seciliIndeks == 2,
                        onek: l.scopeWho,
                        onTap: () => onChanged(partners.first.id),
                      )
                    else
                      _OrtakSekmesi(
                        etiket: ortakEtiket,
                        secili: seciliIndeks == 2,
                        onek: l.scopeWho,
                        partners: partners,
                        seciliId: seciliOrtak?.id,
                        onChanged: onChanged,
                        ilkAd: _ilkAd,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

TextStyle? _metin(BuildContext context, bool secili) =>
    context.t.bodyMedium!.copyWith(
      fontWeight: secili ? FontWeight.w600 : FontWeight.w500,
      color: secili ? context.c.onAmber : context.c.text36,
    );

class _Sekme extends StatelessWidget {
  const _Sekme({
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
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: SandikSpace.xs2),
                child: AnimatedDefaultTextStyle(
                  duration: SandikMotion.stateOf(context),
                  curve: SandikMotion.enter,
                  style: _metin(context, secili)!,
                  child: Text(
                    etiket,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
/// `Material` sarmalayıcısı ZORUNLU ve popup'ın DIŞINDA: bu seçici
/// `CupertinoPageScaffold` altındaki ekranlarda da kullanılıyor ve
/// `PopupMenuButton`'ın kendi `InkWell`'i Material ata arıyor (aynı tuzak
/// `KapsamKisiSecici` ve `GrafikTipiSecici`'de de kayıtlı).
class _OrtakSekmesi extends StatelessWidget {
  const _OrtakSekmesi({
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
              child: Center(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: SandikSpace.xs2),
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
                          color:
                              secili ? context.c.onAmber : context.c.text36),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
