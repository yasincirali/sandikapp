import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/user_model.dart';
import '../theme/sandik.dart';
import 'sandik_segment.dart';

/// "Kimin portföyü?" — uygulamanın TEK ortak seçicisi.
///
/// ## Neden tek bileşen (sadeleştirme madde 8, 2026-10-04)
/// Aynı soruyu (Birlikte / Ben / ortak) soran iki ayrı kabuk vardı:
/// `ModernTabSelector` (48pt kayan amber hap) ve `KapsamKisiSecici` (36pt
/// sade segment). İkisinin sözleşmesi, segment sırası, tek ortak / çok ortak
/// davranışı ve menüsü birebir aynıydı; yalnız görünüşleri ayrışıyordu, bu
/// da kullanıcıya iki farklı denetim gibi görünüyordu.
///
/// Kabuk olarak uygulamanın ortak segment kontrolü [SandikSegment] seçildi:
/// 2026-10-01 animasyon denetiminde yedi segment kontrolü zaten ona
/// indirilmişti ve dönem seçici ([DonemSecici]) üç grafik ekranında bu
/// seçicinin hemen altında aynı kabukla duruyor. Kullanıcı Performans'ta
/// dört tur geri bildirimle "kişi, dönem ve yüzey aynı sınıf denetim"
/// kararına varmıştı (aşağıda); tek görünüş o kararı öteki ekranlara taşır.
///
/// ## Neden Birlikte · Ben · ortak (2026-09-15, dört tur kullanıcı geri
/// bildirimi; silinen `KapsamKisiSecici`'nin gerekçesi)
///   1. Kapsam panelinin arkasında, çipte "Ben · Tümü" — "görülebilir olmalı".
///   2. Başlık çubuğunda avatar+ad çipi, açılır menü — "hızlı hızlı geçiş
///      yapıp grafik karşılaştıracak var": menü her geçişi iki dokunuşa
///      çıkarıyor.
///   3. Başlıkta avatar şeridi, tek dokunuş — "o kadar yukarıda olması
///      doğru olmadı, aşağıya gelmeli; Birlikte ve Ben hızlı tıklanabilir,
///      ortaklar dropdown olabilir".
///   4. Kontrollerin ilk satırında segmentli seçici: sık geçilen iki hedef
///      (Birlikte/Ben) tek dokunuş, seyrek olan ortak listesi menüde.
///
/// ## Sabit ÜÇ segment — ortak sayısı kaç olursa olsun
/// Silinen `ModernTabSelector`'ın ilk hâli genişliği ortak sayısına
/// bölüyordu: 4 ortakta segment ~58px'e iniyor, "Birlikte" sığmıyor, dokunma
/// hedefi `SandikTouch.minSize` altına düşüyordu. Genişlik N'den bağımsız.
///
/// ## Ana ekrandaki `GorunumCipi` neden ayrı kalır
/// Aynı kavram, farklı biçim: toplam kartının başlığında çip + alt sayfa
/// (her görünümün toplamı, arama, son kullanılanlar) + kartı kaydırarak
/// geçiş. Üç segment 320pt'de başlıkla yan yana sığmaz ve o yüzeyin
/// özellikleri (toplamlar, kaydırma) segmentte yok. Birleştirmek özellik
/// kaybı olurdu.
///
/// ## Sözleşme (değişmedi)
/// `null` = Birlikte, `''` = Ben, uuid = o ortak. Sıra Birlikte · Ben ·
/// ortak. Tek ortakta üçüncü segment doğrudan onun adı (tek dokunuş); çok
/// ortakta "Ortaklar" ya da seçili ortağın adı, dokununca liste açılır —
/// ortak seçiliyken yeniden dokunuş da listeyi açar (başka ortağa geçmek
/// için). Ortak yoksa çağıran satırı hiç çizmez.
///
/// Bayrak `tek_ortak_secici` 2026-10-05'te kalktı: eski iki kabuk
/// (`ModernTabSelector`, `KapsamKisiSecici`) ve onları seçen `eski`
/// parametresi silindi; tek görünüş kalıcı.
class OrtakSecici extends StatefulWidget {
  const OrtakSecici({
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
  State<OrtakSecici> createState() => _OrtakSeciciState();
}

class _OrtakSeciciState extends State<OrtakSecici> {
  final _menu = GlobalKey<PopupMenuButtonState<String>>();

  void _menuyuAc() => _menu.currentState?.showButtonMenu();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final partners = widget.partners;
    final tekOrtak = partners.length == 1;
    AppUser? seciliOrtak;
    for (final p in partners) {
      if (p.id == widget.selectedId) seciliOrtak = p;
    }
    final ortakEtiket = tekOrtak
        ? OrtakSecici._ilkAd(partners.first.displayName)
        : (seciliOrtak != null
            ? OrtakSecici._ilkAd(seciliOrtak.displayName)
            : l.scopePartners);
    final etiketler = [l.scopeTogether, l.scopeMe, ortakEtiket];
    // Listede olmayan id (gizlenmiş ortak) → zemin çizilmez; ekranlar zaten
    // `GorunumCipi.gecerli` ile Ben'e düşürüyor.
    final secili = widget.selectedId == null
        ? 0
        : widget.selectedId == ''
            ? 1
            : (seciliOrtak != null ? 2 : -1);

    // `Material` ZORUNLU: menü segmentindeki `PopupMenuButton` Material ata
    // arar ve bu seçici `CupertinoPageScaffold` altında da kullanılıyor
    // (aynı tuzak `GrafikTipiSecici`'de kayıtlı). Segmentin metin stili
    // içeride yeniden verildiği için Material'ın varsayılan metni ezmez.
    return Material(
      type: MaterialType.transparency,
      child: SandikSegment(
        adet: 3,
        secili: secili,
        semantik: (i) => '${l.scopeWho}: ${etiketler[i]}',
        onSec: (i) {
          switch (i) {
            case 0:
              widget.onChanged(null);
            case 1:
              widget.onChanged('');
            default:
              if (tekOrtak) {
                widget.onChanged(partners.first.id);
              } else {
                _menuyuAc();
              }
          }
        },
        onSeciliDokunus: (i) {
          if (i == 2 && !tekOrtak) _menuyuAc();
        },
        oge: (ctx, i, _) {
          if (i < 2 || tekOrtak) {
            return Text(etiketler[i],
                maxLines: 1, overflow: TextOverflow.ellipsis);
          }
          return _OrtakMenusu(
            menu: _menu,
            etiket: ortakEtiket,
            partners: partners,
            seciliId: seciliOrtak?.id,
            onChanged: widget.onChanged,
          );
        },
      ),
    );
  }
}

/// Çok ortakta üçüncü segmentin içi: etiket + ok ve listenin kendisi.
///
/// Düğme KAPALI (`enabled: false`): dokunuşu segmentin kendi düğmesi alır
/// (seçim zemini, titreşim, ekran okuyucu eylemi tek yerde) ve menüyü
/// `showButtonMenu` ile açar; menü yine bu kutunun altına konumlanır.
class _OrtakMenusu extends StatelessWidget {
  const _OrtakMenusu({
    required this.menu,
    required this.etiket,
    required this.partners,
    required this.seciliId,
    required this.onChanged,
  });

  final GlobalKey<PopupMenuButtonState<String>> menu;
  final String etiket;
  final List<AppUser> partners;
  final String? seciliId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: menu,
      enabled: false,
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
                    OrtakSecici._ilkAd(p.displayName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodyMedium?.copyWith(
                      color: context.c.text90,
                      fontWeight:
                          p.id == seciliId ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                // Tik YALNIZCA seçilide; yer hep ayrılır ki satırlar kaymasın.
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(etiket, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          // Ok, metinle aynı renkte ve aynı geçişte (segmentin
          // `AnimatedDefaultTextStyle`'ından okunur).
          Icon(Icons.expand_more_rounded,
              size: 16, color: DefaultTextStyle.of(context).style.color),
        ],
      ),
    );
  }
}
