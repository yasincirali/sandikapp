// Bedelli sermaye artırımı sayfası ve varlık ekranının "⋯" menüsü
// (Ar-Ge 2026-11-07 16:06#1, müşteri raporu 16:30 YAP 1).
//
// Hesap saf fonksiyonda (`BedelliArtirim.hesapla`); bu dosya yalnız girdiyi
// toplar, önizlemeyi yazar ve kaydı mevcut alış yoluna (`addAsset`) verir.
// Sunucu değişmez: kayıt fiyatı 1 ₺ olan sıradan bir alış lotudur, notu
// "Bedelli artırım". Ücretsiz: doğruluk düzeltmesidir, kota kapısı aynı
// pozisyona eklenen lotu yeni varlık saymaz.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../models/bedelli_artirim.dart';
import '../providers/portfolio_provider.dart';
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import 'sandik_async_button.dart';
import 'sandik_baglam_menusu.dart';
import 'sozlesme_formu_ortak.dart';

/// Varlık ekranının "⋯" menüsü. Bugün tek satır (bedelli artırım);
/// bedelsiz/bölünme düzeltmesi geldiğinde aynı menüye satır olarak girer
/// (fikir 6 Kas 20:04#1).
///
/// Menü düğmeye bağlı açılır menüdür (`showSandikAcilirMenu`, müşteri
/// raporu 2026-11-10 #4): eskiden tek satırlık "Diğer işlemler" alt sayfası
/// açıyor, satır onun üstüne bedelli sayfasını açıyordu (iki modal üst
/// üste). Ekranda `PopupMenuButton` yine yok (`varlik_islem_cubugu_test`
/// madde 11: oradaki karar hiç çizilmeyen Sil menüsüydü); satırlar 44 pt.
/// [dugme] "⋯" düğmesinin kendi bağlamı, menü onun altında açılır.
Future<void> showVarlikDigerIslemler(
  BuildContext dugme,
  WidgetRef ref, {
  required Asset varlik,
  required List<Asset> lotlar,
}) {
  final l10n = dugme.l10n;
  return showSandikAcilirMenu(dugme, eylemler: [
    SandikBaglamEylemi(
      anahtar: const ValueKey('menu-bedelli-artirim'),
      ikon: Icons.add_card_rounded,
      etiket: l10n.bedelliBaslik,
      altMetin: l10n.bedelliSatirAlt,
      // Menü kapandıktan sonra çağrılır; düğme o an ağaçta.
      onSec: () {
        if (!dugme.mounted) return;
        CrashReporter.arkaPlan(
            showBedelliArtirimSheet(dugme, ref, varlik: varlik, lotlar: lotlar),
            reason: 'bedelli.menu');
      },
    ),
  ]);
}

/// Bedelli artırım sayfasını açar; kullanıcı kaydederse lotu yazar.
Future<void> showBedelliArtirimSheet(
  BuildContext context,
  WidgetRef ref, {
  required Asset varlik,
  required List<Asset> lotlar,
}) async {
  if (DemoModu.yazmaKapisi('bedelli')) return; // Demo: kayıt hesap ister.
  final l10n = context.l10n;
  // Notifier ŞİMDİ alınır: kayıt sürerken ekran kapanabilir.
  final notifier = ref.read(portfolioProvider.notifier);
  final eklenen = await showSandikSheet<int>(
    context: context,
    isScrollControlled: true,
    baslik: l10n.bedelliBaslik,
    altMetin: l10n.bedelliAciklama(fmtTRY(BedelliArtirim.nominal)),
    builder: (_) => BedelliArtirimSheet(
      lotlar: lotlar,
      kaydet: (hesap, tarih) => notifier.addAsset(
        name: varlik.name,
        ticker: varlik.ticker,
        type: varlik.type,
        quantity: hesap.yeniLot.toDouble(),
        purchasePrice: BedelliArtirim.nominal,
        currency: 'TRY',
        // Not etiketi: hareket listesinde bu lotun neden 1 ₺ olduğunu
        // söyler (kullanıcı notu gibi düzenlenebilir).
        notes: l10n.bedelliBaslik,
        isManualPrice: varlik.isManualPrice,
        subCategory: varlik.subCategory,
        unitType: varlik.unitType,
        addedDate: tarih,
        portfoyId: varlik.portfoyId,
        yol: 'bedelli',
      ),
    ),
  );
  if (eklenen == null || !context.mounted) return;
  sandikSnack(context, l10n.bedelliKaydedildi(fmtNumFlex(eklenen.toDouble())),
      kind: SandikSnackKind.success);
}

/// Sayfanın gövdesi. Açık sınıf: widget testi doğrudan pump edebilsin.
class BedelliArtirimSheet extends StatefulWidget {
  const BedelliArtirimSheet({
    super.key,
    required this.lotlar,
    required this.kaydet,
    this.ilkTarih,
  });

  /// Pozisyonun defter satırları; eldeki lot seçilen tarihe göre sayılır.
  final List<Asset> lotlar;

  /// Kaydı yazar. Başarıda sayfa eklenen lot sayısıyla kapanır; hata
  /// olursa açık kalır (girilen oran kaybolmaz).
  final Future<void> Function(BedelliArtirim hesap, DateTime tarih) kaydet;

  /// Testte "bugün" yerine verilen başlangıç tarihi.
  final DateTime? ilkTarih;

  @override
  State<BedelliArtirimSheet> createState() => _BedelliArtirimSheetState();
}

class _BedelliArtirimSheetState extends State<BedelliArtirimSheet> {
  final _oran = TextEditingController();
  late DateTime _tarih = widget.ilkTarih ?? DateTime.now();

  @override
  void dispose() {
    _oran.dispose();
    super.dispose();
  }

  BedelliArtirim get _hesap => BedelliArtirim.hesapla(
        lotlar: widget.lotlar,
        oranYuzde: parseTrNumber(_oran.text),
        tarih: _tarih,
        // Yeni ortalama, lotu kaydın gerçekten yazılacağı ana koyar.
        kayitAni: _kayitTarihi,
      );

  /// Tarih seçici gece yarısını döner. Geçmiş günde lot öğlene yazılır:
  /// kayıt UTC'ye çevrilir (`added_date`), gece yarısı saat dilimi farkıyla
  /// önceki güne kayabilirdi. Bugünse şimdiki an (sıradan alışla aynı).
  DateTime get _kayitTarihi {
    final s = DateTime.now();
    final t = _tarih;
    final bugun = t.year == s.year && t.month == s.month && t.day == s.day;
    return bugun ? s : DateTime(t.year, t.month, t.day, 12);
  }

  Future<void> _kaydet(BedelliArtirim hesap) async {
    try {
      await widget.kaydet(hesap, _kayitTarihi);
    } catch (e) {
      if (!mounted) return;
      // Snackbar sayfanın altında kalırdı; hata sayfanın üstünde.
      CrashReporter.arkaPlan(
          showSandikDialog(
            context: context,
            kind: SandikDialogKind.error,
            title: context.l10n.bedelliBaslik,
            message: context.l10n.transactionFailed(friendlyError(e)),
          ),
          reason: 'bedelli.hataDiyalogu');
      return;
    }
    if (mounted) Navigator.pop(context, hesap.yeniLot);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hesap = _hesap;
    final oranVar = (parseTrNumber(_oran.text) ?? 0) > 0;

    // Önizleme yalnız oran yazılınca; tarihte lot yoksa onu söyler.
    String? onizleme;
    String? yuvarlama;
    String? yeniOrtalama;
    if (hesap.eldekiLot <= 0) {
      onizleme = l10n.bedelliLotYok;
    } else if (oranVar) {
      onizleme = l10n.bedelliOnizleme(
        fmtNumFlex(hesap.eldekiLot),
        fmtNumFlex(hesap.yeniLot.toDouble()),
        fmtTRY(BedelliArtirim.nominal),
        fmtTRY(hesap.toplamTutar),
      );
      if (hesap.yeniOrtalama case final o?) {
        yeniOrtalama = fmtTRYFiyat(o);
      }
      if (hesap.yuvarlandi) {
        yuvarlama = l10n.bedelliYuvarlama(
          fmtNumFlex(hesap.hakSayisi),
          fmtNumFlex(hesap.yeniLot.toDouble()),
        );
      }
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        SandikSpace.screenH(context),
        SandikSpace.md,
        SandikSpace.screenH(context),
        SandikSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SozlesmeEtiketi(l10n.bedelliOran),
          SozlesmeAlani(
            key: const ValueKey('bedelli-oran'),
            controller: _oran,
            ipucu: l10n.bedelliOranIpucu,
            sonek: '%',
            sayi: true,
            degisti: (_) => setState(() {}),
          ),
          const SizedBox(height: SandikSpace.md),
          SozlesmeTarihi(
            etiket: l10n.bedelliTarih,
            tarih: _tarih,
            degisti: (t) => setState(() => _tarih = t),
          ),
          if (onizleme != null) ...[
            const SizedBox(height: SandikSpace.md),
            // Tam cümle: ekran okuyucu tek parça okur, anlam renkte değil.
            Text(
              onizleme,
              key: const ValueKey('bedelli-onizleme'),
              style: context.t.bodyLarge?.copyWith(color: context.c.text90),
            ),
          ],
          if (yuvarlama != null) SozlesmeNotu(yuvarlama),
          if (yeniOrtalama != null) ...[
            const SizedBox(height: SandikSpace.sm),
            _YeniOrtalamaSatiri(yeniOrtalama),
          ],
          const SizedBox(height: SandikSpace.lg),
          SandikAsyncButton.kompakt(
            key: const ValueKey('bedelli-kaydet'),
            style: FilledButton.styleFrom(
              backgroundColor: context.c.amberFill,
              foregroundColor: context.c.onAmber,
              minimumSize: const Size.fromHeight(SandikTouch.min),
            ),
            // Oran yazılmadan ya da lot çıkmıyorsa kapalı.
            onPressed: hesap.kaydedilebilir ? () => _kaydet(hesap) : null,
            child: Text(l10n.bedelliKaydet),
          ),
        ],
      ),
    );
  }
}

/// "Yeni ortalama maliyetin ₺115,60 olur." — tutar w600 (müşteri raporu
/// 2026-11-10 #1). Cümle tek parça: ekran okuyucu bütün okur; vurgu ağırlıkla,
/// renkle değil. Tutar .arb cümlesinde arandığı için dil sırası serbest.
class _YeniOrtalamaSatiri extends StatelessWidget {
  const _YeniOrtalamaSatiri(this.tutar);

  final String tutar;

  @override
  Widget build(BuildContext context) {
    final cumle = context.l10n.bedelliYeniOrtalama(tutar);
    final i = cumle.indexOf(tutar);
    final stil = context.t.bodyLarge?.copyWith(color: context.c.text90);
    return Text.rich(
      key: const ValueKey('bedelli-yeni-ortalama'),
      i < 0
          ? TextSpan(text: cumle)
          : TextSpan(children: [
              TextSpan(text: cumle.substring(0, i)),
              TextSpan(
                text: tutar,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: cumle.substring(i + tutar.length)),
            ]),
      style: stil,
    );
  }
}
