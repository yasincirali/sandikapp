import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';

/// Mevduat ve BES formlarının ortak parçaları.
///
/// ## Neden ayrı formlar (2026-09-30)
/// Kullanıcı kuralı: *"Varlık ekle kısmından da eklenebilir olmalı, o
/// yüzden orayı da bozmamalı."* Genel form miktar × fiyat üzerine kurulu
/// (3000 satır, kimlik/önizleme/komisyon akışı); sözleşmeli türlerin
/// girdisi başkadır (faiz, vade, katkı planı). Genel formun durum makinesine
/// yeni dallar eklemek yerine tür çipi seçilince gövde bu formlarla yer
/// değiştirir; genel formun hiçbir alanı ve doğrulaması değişmez.
/// Kaydet çubuğu ekranın kendi çubuğudur (görünüm aynı kalsın); ekran
/// [SozlesmeFormu.kaydet]'i çağırır.
abstract class SozlesmeFormu {
  /// Doğrular ve kaydeder; başarılıysa `true`. Hata mesajını form gösterir.
  Future<bool> kaydet();
}

/// Alan etiketi — genel formun `_fieldLabel`'ıyla aynı stil.
class SozlesmeEtiketi extends StatelessWidget {
  const SozlesmeEtiketi(this.metin, {super.key, this.ek});

  final String metin;

  /// Etiketin yanında soluk not ("İsteğe bağlı").
  final String? ek;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: SandikSpace.sm),
        child: Row(
          children: [
            Flexible(
              child: Text(
                metin,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.c.text90,
                ),
              ),
            ),
            if (ek != null) ...[
              const SizedBox(width: SandikSpace.xs2),
              Flexible(
                child: Text(
                  ek!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodySmall?.copyWith(color: context.c.text36),
                ),
              ),
            ],
          ],
        ),
      );
}

/// Açıklama satırı — alanın altındaki soluk not.
class SozlesmeNotu extends StatelessWidget {
  const SozlesmeNotu(this.metin, {super.key});
  final String metin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: SandikSpace.xs2),
        child: Text(
          metin,
          style: context.t.bodySmall?.copyWith(color: context.c.text36),
        ),
      );
}

/// Ondalık girdi süzgeci: rakam, nokta, virgül.
final sozlesmeSayiSuzgeci = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];

/// İşaretli ondalık süzgeç: BES getirisi zarar olabilir (`-1.250,40`).
final sozlesmeIsaretliSuzgeci = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
];

/// Metin/sayı alanı — dolgu ve çerçeve temadan (`context.inputDecoration`).
class SozlesmeAlani extends StatelessWidget {
  const SozlesmeAlani({
    super.key,
    required this.controller,
    required this.ipucu,
    this.sonek,
    this.sayi = false,
    this.dogrula,
    this.degisti,
    this.buyukHarf = false,
    this.isaretli = false,
    this.dokununca,
    this.onek,
    this.enFazlaSatir = 1,
    this.enFazlaKarakter,
  });

  final TextEditingController controller;
  final String ipucu;
  final String? sonek;
  final bool sayi;
  final bool buyukHarf;

  /// Sayı eksi olabilir mi (yalnız [sayi] ile anlamlı).
  final bool isaretli;
  final String? Function(String?)? dogrula;
  final void Function(String)? degisti;

  /// Verilirse alan yazılmaz, dokununca seçici açılır (mevduat banka
  /// seçicisi). Doğrulama ve görünüş yazılan alanla aynı kalır.
  final VoidCallback? dokununca;

  /// Alanın başındaki küçük öğe (seçilen bankanın harf rozeti).
  final Widget? onek;

  /// Çok satırlı serbest metin (not) için.
  final int enFazlaSatir;
  final int? enFazlaKarakter;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        readOnly: dokununca != null,
        onTap: dokununca,
        maxLines: enFazlaSatir,
        minLines: 1,
        maxLength: enFazlaKarakter,
        style: context.t.bodyLarge
            ?.copyWith(color: context.c.text90, fontWeight: FontWeight.w500),
        decoration: context.inputDecoration(ipucu).copyWith(
              suffixText: sonek,
              suffixStyle: context.t.titleSmall?.copyWith(
                  color: context.c.text58, fontWeight: FontWeight.w700),
              suffixIcon: dokununca == null
                  ? null
                  : Icon(Icons.expand_more_rounded, color: context.c.text58),
              prefixIcon: onek,
              // Sayaç yalnız sınıra yaklaşınca anlamlı; her an "0/300"
              // yazmak not alanını kalabalıklaştırırdı.
              counterText: '',
            ),
        keyboardType: sayi
            ? TextInputType.numberWithOptions(decimal: true, signed: isaretli)
            : TextInputType.text,
        inputFormatters: sayi
            ? (isaretli ? sozlesmeIsaretliSuzgeci : sozlesmeSayiSuzgeci)
            : null,
        textCapitalization: buyukHarf
            ? TextCapitalization.words
            : (enFazlaSatir > 1
                ? TextCapitalization.sentences
                : TextCapitalization.none),
        validator: dogrula,
        onChanged: degisti,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      );
}

/// Tarih satırı — genel formun tarih çipiyle aynı görünüm.
class SozlesmeTarihi extends StatelessWidget {
  const SozlesmeTarihi({
    super.key,
    required this.etiket,
    required this.tarih,
    required this.degisti,
    this.ilk,
  });

  final String etiket;
  final DateTime tarih;
  final ValueChanged<DateTime> degisti;
  final DateTime? ilk;

  @override
  Widget build(BuildContext context) {
    final metin = DateFormat.yMMMd(context.l10n.localeName).format(tarih);
    return InkWell(
      borderRadius: SandikRadius.mdAll,
      onTap: () async {
        final secim = await pickSandikDate(
          context,
          initialDate: tarih,
          firstDate: ilk,
          helpText: etiket,
        );
        if (secim != null) degisti(secim);
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.md2, vertical: SandikSpace.smd),
        decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: SandikRadius.mdAll,
          border: Border.all(color: context.c.overlay),
        ),
        child: Row(
          children: [
            Icon(Icons.event_rounded, size: 16, color: context.c.text58),
            const SizedBox(width: SandikSpace.sm2),
            Flexible(
              child: Text(etiket,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600, color: context.c.text90)),
            ),
            const Spacer(),
            Flexible(
              child: Text(metin,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: context.c.amberText)),
            ),
            const SizedBox(width: SandikSpace.xs),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: context.c.amberText),
          ],
        ),
      ),
    );
  }
}

/// Seçim çipi — tek seçimli çip grupları (vade, hesap türü).
class SozlesmeCipi extends StatelessWidget {
  const SozlesmeCipi({
    super.key,
    required this.metin,
    required this.secili,
    required this.secildi,
    required this.renk,
    this.icerigeGore = false,
  });

  final String metin;
  final bool secili;
  final VoidCallback secildi;
  final Color renk;

  /// `Wrap` içinde çip metni kadar geniş olsun mu?
  ///
  /// Metni ortalayan `alignment`, `Wrap`'ın verdiği sınırsız genişlikte
  /// çipi tüm satıra yayıyordu: dört vade seçeneği alt alta tam genişlik
  /// satırlar olarak diziliyordu (2026-10-02 müşteri testi). `Expanded`
  /// içindeki kullanım (Vadeli / Günlük faizli) yayılmak İSTER; o yüzden
  /// varsayılan kapalı.
  final bool icerigeGore;

  @override
  Widget build(BuildContext context) {
    final cip = _cip(context);
    return icerigeGore ? IntrinsicWidth(child: cip) : cip;
  }

  Widget _cip(BuildContext context) => Semantics(
        button: true,
        selected: secili,
        child: InkWell(
          borderRadius: SandikRadius.mdAll,
          onTap: secildi,
          child: AnimatedContainer(
            duration: SandikMotion.stateOf(context),
            curve: SandikMotion.enter,
            constraints: const BoxConstraints(minHeight: SandikTouch.min),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md2),
            decoration: BoxDecoration(
              color: secili ? renk.withValues(alpha: 0.18) : context.c.surface1,
              borderRadius: SandikRadius.mdAll,
              border: Border.all(
                color: secili ? renk : context.c.overlay,
                width: secili ? 1.4 : 1,
              ),
            ),
            child: Text(
              metin,
              style: context.t.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: secili ? context.c.text90 : context.c.text58,
              ),
            ),
          ),
        ),
      );
}

/// Özet satırı: etiket solda, değer sağda.
class SozlesmeOzetSatiri extends StatelessWidget {
  const SozlesmeOzetSatiri({
    super.key,
    required this.etiket,
    required this.deger,
    this.renk,
    this.vurgulu = false,
  });

  final String etiket;
  final String deger;
  final Color? renk;
  final bool vurgulu;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // İkisi de esnek: büyük metin ölçeğinde uzun değer ("%35 · 3 yıl
            // sonra %60") satırı taşırmasın, alt satıra sarsın.
            Expanded(
              flex: 5,
              child: Text(etiket,
                  style:
                      context.t.bodyMedium?.copyWith(color: context.c.text58)),
            ),
            const SizedBox(width: SandikSpace.sm),
            Flexible(
              flex: 5,
              child: Text(
                deger,
                textAlign: TextAlign.end,
                style: (vurgulu ? context.t.numMedium : context.t.numSmall)
                    .copyWith(
                  color: renk ?? context.c.text90,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}
