import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/cevrimdisi_provider.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart' show dayKey;

/// "İnternet yok · fiyatlar 14:32'deki hâli" — Ana sayfa ve Portföy'ün
/// üstünde tek ince satır (Ar-Ge 7 Kas 08:03 #3).
///
/// Neden kutu değil satır: bağlantı yokluğu hata değil durum; son fiyatlar
/// ekranda doğru duruyor, yalnız eski. Piyasa kapalı satırı gibi sakin
/// bir bilgi (ikincil metin rengi, uyarı kutusu yok). Anlam yalnız renkle
/// verilmez: ikon + cümle. Ana sayfa toplam kartının İÇİNE ya da ÜSTÜNE
/// binmez; kartın üstünde ayrı satır (kullanıcı kuralı).
///
/// Hareket yok: belirip kaybolması bilerek animasyonsuz — hareketi azalt
/// açık/kapalı fark etmez, satır anında gelir ve gider. Durum
/// `cevrimdisiProvider`'da; ilk başarılı turda kendiliğinden kalkar.
class CevrimdisiSeridi extends ConsumerWidget {
  const CevrimdisiSeridi({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durum = ref.watch(cevrimdisiProvider);
    if (durum == null) return const SizedBox.shrink();
    final c = context.c;
    final metin = cevrimdisiMetni(context.l10n, durum.sonFiyat, DateTime.now());
    return Padding(
      padding: padding,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: metin,
        excludeSemantics: true,
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: SandikSpace.md, color: c.text58),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: Text(
                metin,
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Şerit metni. Saat bugünse "14:32", değilse "06.11 14:32" (dünün saati
/// bugünün saati sanılmasın). Saat bilinmiyorsa saatsiz cümle.
String cevrimdisiMetni(AppLocalizations l, DateTime? son, DateTime simdi) {
  if (son == null) return l.offlinePricesUnknown;
  final yerel = son.toLocal();
  final saat = DateFormat('HH:mm').format(yerel);
  final metin = dayKey(yerel) == dayKey(simdi.toLocal())
      ? saat
      : '${DateFormat('dd.MM').format(yerel)} $saat';
  return l.offlinePricesAt(metin, trSaatBulunmaEki(yerel.hour, yerel.minute));
}

/// Saatin Türkçe okunuşuna göre "-deki" eki: 14:32 → "deki" (otuz iki),
/// 14:30 → "daki" (otuz), 14:00 → "teki" (on dört), 09:05 → "teki" (beş).
///
/// Neden: "14:30'deki" Türkçe okura yanlış gelir; ek son okunan sayının son
/// ünlüsüne (kalın a/ı/o/u → a, ince → e) ve son sesine (sert ç/f/h/k/p/s/ş/t
/// → t) uyar. Dakika 00 ise saat okunur ("on dört"), 0 saat "sıfır".
String trSaatBulunmaEki(int saat, int dakika) {
  final kelime = _sayiSonKelimesi(dakika != 0 ? dakika : saat);
  final sonHarf = kelime[kelime.length - 1];
  var kalin = false;
  for (var i = kelime.length - 1; i >= 0; i--) {
    final h = kelime[i];
    if ('aıou'.contains(h)) {
      kalin = true;
      break;
    }
    if ('eiöü'.contains(h)) break;
  }
  final sert = 'çfhkpsşt'.contains(sonHarf);
  return '${sert ? 't' : 'd'}${kalin ? 'aki' : 'eki'}';
}

String _sayiSonKelimesi(int n) {
  const birler = ['', 'bir', 'iki', 'üç', 'dört', 'beş', 'altı', 'yedi',
      'sekiz', 'dokuz'];
  const onlar = ['', 'on', 'yirmi', 'otuz', 'kırk', 'elli'];
  if (n % 10 != 0) return birler[n % 10];
  if (n >= 10) return onlar[n ~/ 10];
  return 'sıfır';
}
