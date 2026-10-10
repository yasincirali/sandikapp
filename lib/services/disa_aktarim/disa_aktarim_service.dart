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

  Future<void> paylas(
    RaporBelgesi belge, {
    required DisaAktarimBicimi bicim,
    required String tur,
    Rect? kaynak,
  }) async {
    final Uint8List baytlar;
    final String uzanti;
    final String mime;
    switch (bicim) {
      case DisaAktarimBicimi.excel:
        baytlar = xlsxYaz(belge);
        uzanti = 'xlsx';
        mime =
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case DisaAktarimBicimi.pdf:
        _duz ??= await rootBundle.load('assets/fonts/DMSans-Regular.ttf');
        _kalin ??= await rootBundle.load('assets/fonts/DMSans-Bold.ttf');
        baytlar = await pdfYaz(belge, duz: _duz!, kalin: _kalin!);
        uzanti = 'pdf';
        mime = 'application/pdf';
    }
    final dir = await getTemporaryDirectory();
    final dosya = File('${dir.path}/${belge.dosyaAdi}.$uzanti');
    await dosya.writeAsBytes(baytlar, flush: true);
    unawaited(AnalyticsService.instance.logDisaAktarim(tur: tur, bicim: uzanti));
    try {
      await ShareCardService.shareFile(
        dosya.path,
        mimeType: mime,
        subject: belge.baslik,
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
