import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../analytics_service.dart';
import '../share_card_service.dart';
import 'pdf_yazici.dart';
import 'rapor_belgesi.dart';
import 'xlsx_yazici.dart';
import 'yorum_notu_pdf.dart';
import '../yorum_notu.dart';

/// Premium dışa aktarımın biçimi.
enum DisaAktarimBicimi { pdf, excel }

/// [RaporBelgesi]'ni dosyaya yazıp sistem paylaşım sayfasını açar
/// (Premium, 2026-10-10).
///
/// Kilit burada DEĞİL: çağıran ekran `premiumKilitliProvider`'a bakar ve
/// kilitliyse bu servise hiç gelmez. Servis biçim ve dosya işidir.
///
/// Dosya geçici klasöre yazılır, paylaşım bitince silinir: içinde tutar ve
/// işlem geçmişi var (veri indirmeyle aynı gerekçe, `DataExportService` E3).
class DisaAktarimService {
  DisaAktarimService._();
  static final instance = DisaAktarimService._();

  ByteData? _duz;
  ByteData? _kalin;

  static const _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// PDF yazı tipleri. "Kalın" DM Sans **SemiBold**'dur, Bold değil
  /// (müşteri raporu 6 Kas 15:15 #4): uygulamanın w600 tavanı kâğıtta da
  /// geçerli, hiyerarşi boyutla kurulur. Dosya pubspec `fonts:` altında
  /// zaten paketli.
  Future<(ByteData, ByteData)> _fontlar() async {
    _duz ??= await rootBundle.load('assets/fonts/DMSans-Regular.ttf');
    _kalin ??= await rootBundle.load('assets/fonts/DMSans-SemiBold.ttf');
    return (_duz!, _kalin!);
  }

  Future<(Uint8List, String, String)> _yaz(
      RaporBelgesi belge, DisaAktarimBicimi bicim) async {
    switch (bicim) {
      case DisaAktarimBicimi.excel:
        return (xlsxYaz(belge), 'xlsx', _xlsxMime);
      case DisaAktarimBicimi.pdf:
        final (duz, kalin) = await _fontlar();
        final b = await pdfYaz(belge,
            duz: duz, kalin: kalin, logo: await _logoYukle());
        return (b, 'pdf', 'application/pdf');
    }
  }

  Future<void> paylas(
    RaporBelgesi belge, {
    required DisaAktarimBicimi bicim,
    required String tur,
    Rect? kaynak,
  }) =>
      paylasBirlikte(belge, bicimler: [bicim], tur: tur, kaynak: kaynak);

  /// Aynı belgeyi birden çok biçimde TEK paylaşım sayfasıyla gönderir
  /// (yıllık rapor "Mali müşavirime gönder", müşteri raporu 6 Kas 15:15 #2):
  /// e-postada PDF ve Excel iki ek olarak hazır gelir. Dosyalar aynı geçici
  /// klasöre yazılır, paylaşım bitince hepsi silinir. Analytics her biçim
  /// için ayrı olay (dışa aktarım sayımı biçim başına kalsın).
  Future<void> paylasBirlikte(
    RaporBelgesi belge, {
    required List<DisaAktarimBicimi> bicimler,
    required String tur,
    Rect? kaynak,
  }) async {
    final dir = await getTemporaryDirectory();
    final dosyalar = <(String, String)>[];
    final yazilan = <File>[];
    try {
      for (final bicim in bicimler) {
        final (baytlar, uzanti, mime) = await _yaz(belge, bicim);
        final dosya = File('${dir.path}/${belge.dosyaAdi}.$uzanti');
        await dosya.writeAsBytes(baytlar, flush: true);
        yazilan.add(dosya);
        dosyalar.add((dosya.path, mime));
        unawaited(
            AnalyticsService.instance.logDisaAktarim(tur: tur, bicim: uzanti));
      }
      await ShareCardService.shareFiles(
        dosyalar,
        subject: belge.baslik,
        origin: kaynak,
      );
    } finally {
      for (final dosya in yazilan) {
        try {
          if (await dosya.exists()) await dosya.delete();
        } catch (_) {
          // Silinemezse geçici klasörü işletim sistemi temizler.
        }
      }
    }
  }

  Uint8List? _logo;

  /// Uygulama ikonu — iki PDF'in üst bandındaki logo (2026-10-30).
  Future<Uint8List> _logoYukle() async =>
      _logo ??= (await rootBundle.load('assets/images/sandik_icon.png'))
          .buffer
          .asUint8List();

  /// AI yorumunun A4 notunu (2026-10-14) PDF olarak paylaşır. Dosya
  /// [paylas] gibi geçici klasöre yazılır, paylaşım bitince silinir. Premium
  /// kilidi kartta: yorum yalnız Premium'a (ya da admin'e) yazılır.
  Future<void> yorumNotuPaylas(YorumNotu n, {Rect? kaynak}) async {
    final (duz, kalin) = await _fontlar();
    final baytlar = await yorumNotuPdf(n,
        duz: duz, kalin: kalin, logo: await _logoYukle());
    final dir = await getTemporaryDirectory();
    final dosya = File('${dir.path}/${n.dosyaAdi}.pdf');
    await dosya.writeAsBytes(baytlar, flush: true);
    unawaited(AnalyticsService.instance.logDisaAktarim(tur: 'ai_yorum', bicim: 'pdf'));
    try {
      await ShareCardService.shareFile(
        dosya.path,
        mimeType: 'application/pdf',
        subject: '${n.donemAdi} · sandık yorumu',
        origin: kaynak,
      );
    } finally {
      try {
        if (await dosya.exists()) await dosya.delete();
      } catch (_) {
        // Silinemezse geçici klasörü işletim sistemi temizler.
      }
    }
  }
}
