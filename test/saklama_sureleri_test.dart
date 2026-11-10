import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Saklama süresi kilidi: sunucudaki temizlik işleri ile yasal metindeki
/// "saklama süresi" aynı şeyi söylesin (Ar-Ge 22 Eki #3, "önce yalnız test").
///
/// Neden: süre iki yerde yaşıyor — `supabase/migrations/` (silen cron ve
/// çağırdığı fonksiyon) ve `legal/tr/*.md` (kullanıcıya verilen söz). Biri
/// değişip öteki unutulursa hiçbir test kırılmıyordu; 0114 `cleanup_db_logs`'u
/// yeniden yazarken 0097'nin eklediği kayıt hunisi silmesini düşürdü ve bu
/// ancak bu tablo yazılırken görüldü (aşağıda `_bilinenAykirilar`).
///
/// Kilit dört yönlüdür:
///  1. Migration'daki GÜNCEL süre (son tanım kazanır) tablodakiyle aynı mı.
///  2. Tablodaki yasal ifade md'de hâlâ birebir duruyor mu.
///  3. Migration süresi ≤ yasal süre mi (söylediğimizden uzun tutmuyoruz).
///  4. Tabloda olmayan yeni bir temizlik işi var mı (ratchet).
/// Herhangi biri kırılırsa: tabloyu güncelle VE yasal metni yeniden oku;
/// süre uzuyorsa yasal metin değişikliği (Sürüm + Onay sürümü) gerekir.
///
/// Kapsam: yalnız migration'larda `cron.schedule` ile kurulan SQL temizliği.
/// Edge function içinde silenler (ekstre-esle 40 gün, akis-gozlem, x-paylas…)
/// burada değil; onlar kendi fonksiyonlarında.

/// Bir temizlik işinin bir tablodaki silmesi.
class _Saklama {
  const _Saklama({
    required this.isAdi,
    required this.tablo,
    required this.migrasyon,
    required this.sure,
    this.yasalSure,
    this.ifadeler = const [],
    this.gerekce,
  });

  /// `cron.schedule` adı.
  final String isAdi;

  /// Silinen tablo (`public.` öneksiz; başka şemada şemasıyla).
  final String tablo;

  /// Silmenin son tanımlandığı migration numarası (fonksiyon yeniden
  /// yazıldıysa o dosya; silme cron komutundaysa cron'un dosyası).
  final String? migrasyon;

  /// Migration'daki süre, Postgres interval yazımıyla (`'90 days'`);
  /// `::date - N` biçimi `'N days'` sayılır. `null` = silme yok.
  final String? sure;

  /// Yasal metnin söylediği üst sınır, aynı yazımla. `null` = metinde bu veri
  /// için süre yok; o zaman [gerekce] zorunlu.
  final String? yasalSure;

  /// (md dosyası, birebir ifade) çiftleri. İfade kategori ADI ile SÜRESİNİ
  /// birlikte taşır ki yalnız biri değişse de kırılsın.
  final List<(String, String)> ifadeler;

  final String? gerekce;
}

const _gp = 'PRIVACY_POLICY.md';
const _kvkk = 'KVKK_AYDINLATMA_METNI.md';

const _bildirimGunlugu = (
  _gp,
  'tekrar gönderilmemesi için) | Türüne göre 30 gün ile 18 ay arası',
);
const _bildirimKaydi = [
  (_gp, 'Bildirim kayıtları (uygulama içi bildirimler, fiyat alarmı bildirimleri) | 90 gün'),
  (_kvkk, 'Bildirim kayıtları (uygulama içi, fiyat alarmı) | 90 gün'),
];
const _zirve = [
  (_gp, 'Zirve havuzu ölçümleri (getiri %, tür payı %) | Son 365 gün rolling'),
  (_kvkk, 'Zirve havuzu ölçümleri | Son 365 gün rolling'),
];
const _yaris = [
  (_gp, 'Yarış ölçümleri (getiri %, tür payı %) | Son 365 gün rolling'),
  (_kvkk, 'Yarış ölçümleri | Son 365 gün rolling'),
];
const _snapshot = [
  (_gp, 'Portföy anlık görüntüleri | Son 2 yıl (730 gün) rolling'),
  (_kvkk, 'Portföy anlık görüntüleri | Son 2 yıl (730 gün) rolling'),
];
const _piyasa = 'Piyasa verisi önbelleği/gözlemi; kişisel veri değil, yasal '
    'metin piyasa verisini saymaz (kullanıcı kararı 2026-10-08).';

const _tablo = <_Saklama>[
  // ── Güvenlik ve teknik kayıtlar ──────────────────────────────────────────
  _Saklama(
    isAdi: 'purge-rate-limit-attempts', tablo: 'rate_limit_attempts',
    migrasyon: '0028', sure: '24 hours',
    gerekce: 'Kötüye kullanım sayacı; metinde ayrı satırı yok. 24 saat, '
        'metindeki en kısa güvenlik süresinin (90 gün) çok altında.',
  ),
  _Saklama(
    isAdi: 'live-activity-cleanup', tablo: 'live_activity_sessions',
    migrasyon: '0032', sure: '1 hour',
    gerekce: 'Kilit ekranı oturumu, süresi (expires_at) dolduktan 1 saat '
        'sonra silinir; metin §3.3 veriyi sayar, ayrı süre vermez.',
  ),
  _Saklama(
    isAdi: 'cron-gecmisi-saklama', tablo: 'cron.job_run_details',
    migrasyon: '0112', sure: '7 days',
    gerekce: 'pg_cron çalışma geçmişi; kullanıcıya bağlı veri yok.',
  ),
  _Saklama(
    isAdi: 'db-logs-retention', tablo: 'db_logs',
    // Hatalar 30 gün, başarılı satırlar 1 gün (0114); üst sınır 30 gün.
    migrasyon: '0114', sure: '30 days', yasalSure: '30 days',
    ifadeler: [
      (_gp, 'Yapısal hata kayıtları (db_logs, yalnızca hatalar) | 30 gün'),
      (_kvkk, 'Hata kayıtları (db_logs, yalnızca hatalar) | 30 gün'),
    ],
  ),
  _Saklama(
    isAdi: 'db-logs-retention', tablo: 'huni_olaylari',
    // 0097 bu silmeyi cleanup_db_logs'a ekledi; 0114 fonksiyonu yeniden
    // yazarken düşürdü. Bugün kayıt hunisi hiç silinmiyor → _bilinenAykirilar.
    migrasyon: null, sure: null, yasalSure: '400 days',
    ifadeler: [
      (_gp, 'Kayıt hunisi adımları | 400 gün'),
      (_kvkk, 'Kayıt hunisi adımları | 400 gün'),
    ],
  ),
  _Saklama(
    isAdi: 'auth-guvenlik-kaydi-saklama', tablo: 'auth.audit_log_entries',
    migrasyon: '0105', sure: '90 days', yasalSure: '90 days',
    ifadeler: [
      (_gp, 'Supabase Auth güvenlik kaydı) | 90 gün'),
      (_kvkk, 'Supabase Auth güvenlik kaydı) | 90 gün'),
    ],
  ),
  // ── Hesap silindikten sonra kalan kanıt kayıtları ────────────────────────
  _Saklama(
    isAdi: 'yasal-onay-saklama', tablo: 'yasal_onaylar',
    // Süre hesap_silindi_at'ten sayılır; metin de "silindikten sonra" der.
    migrasyon: '0102', sure: '3 years', yasalSure: '3 years',
    ifadeler: [
      (_gp, 'yatırım uyarısı) | Hesap silindikten sonra **3 yıl**'),
      (_kvkk, 'yatırım uyarısı) | Hesap silinmesinden sonra **3 yıl**'),
    ],
  ),
  _Saklama(
    isAdi: 'hesap-silme-kaydi-saklama', tablo: 'account_deletion_log',
    migrasyon: '0105', sure: '3 years', yasalSure: '3 years',
    ifadeler: [
      (_gp, 'silme zamanı ve nedeni) | Silmeden sonra **3 yıl**'),
      (_kvkk, 'silme zamanı ve nedeni) | Hesap silinmesinden sonra **3 yıl**'),
    ],
  ),
  // ── Bildirim kayıtları ve gönderim günlükleri ────────────────────────────
  _Saklama(
    isAdi: 'price-alert-notifications-cleanup',
    tablo: 'price_alert_notifications',
    migrasyon: '0065', sure: '90 days', yasalSure: '90 days',
    ifadeler: _bildirimKaydi,
  ),
  _Saklama(
    isAdi: 'app-notifications-cleanup', tablo: 'app_notifications',
    migrasyon: '0066', sure: '90 days', yasalSure: '90 days',
    ifadeler: _bildirimKaydi,
  ),
  // Gönderim günlükleri: metin "türüne göre 30 gün ile 18 ay" der; üst sınır
  // 18 ay. Bu satır yalnız Gizlilik Politikası'nda var (KVKK tablosunda yok).
  _Saklama(
    isAdi: 'daily-brief-cleanup', tablo: 'daily_brief_log',
    migrasyon: '0044', sure: '30 days', yasalSure: '18 months',
    ifadeler: [_bildirimGunlugu],
  ),
  _Saklama(
    isAdi: 'weekly-summary-cleanup', tablo: 'weekly_summary_log',
    migrasyon: '0052', sure: '90 days', yasalSure: '18 months',
    ifadeler: [_bildirimGunlugu],
  ),
  _Saklama(
    isAdi: 'calendar-nudge-log-cleanup', tablo: 'calendar_nudge_log',
    migrasyon: '0053', sure: '18 months', yasalSure: '18 months',
    ifadeler: [_bildirimGunlugu],
  ),
  _Saklama(
    isAdi: 'watchlist-moves-cleanup', tablo: 'watchlist_move_log',
    migrasyon: '0068', sure: '30 days', yasalSure: '18 months',
    ifadeler: [_bildirimGunlugu],
  ),
  // ── Portföy, yarış ve zirve ölçümleri ────────────────────────────────────
  _Saklama(
    isAdi: 'snapshots-retention', tablo: 'snapshots',
    migrasyon: '0077', sure: '730 days', yasalSure: '730 days',
    ifadeler: _snapshot,
  ),
  _Saklama(
    isAdi: 'snapshots-gunluk', tablo: 'snapshots',
    // Silme değil seyreltme: 35 günden eski saatlik noktalar günde bire
    // iner (0159). Veri 730 güne kadar yine durur; kategori aynı.
    migrasyon: '0159', sure: '35 days', yasalSure: '730 days',
    ifadeler: _snapshot,
  ),
  _Saklama(
    isAdi: 'leaderboard-snapshot-retention', tablo: 'user_roi_snapshots',
    migrasyon: '0167', sure: '365 days', yasalSure: '365 days',
    ifadeler: _yaris,
  ),
  _Saklama(
    isAdi: 'leaderboard-snapshot-retention',
    tablo: 'user_allocation_snapshots',
    migrasyon: '0167', sure: '365 days', yasalSure: '365 days',
    ifadeler: _yaris,
  ),
  _Saklama(
    isAdi: 'leaderboard-snapshot-retention', tablo: 'zirve_roi_snapshots',
    migrasyon: '0167', sure: '365 days', yasalSure: '365 days',
    ifadeler: _zirve,
  ),
  _Saklama(
    isAdi: 'leaderboard-snapshot-retention',
    tablo: 'zirve_allocation_snapshots',
    // 0167: metin 365 gün der, sunucu 7 günde siler (daha kısa, uygun).
    migrasyon: '0167', sure: '7 days', yasalSure: '365 days',
    ifadeler: _zirve,
  ),
  // ── Piyasa verisi (kişisel veri değil) ───────────────────────────────────
  _Saklama(
    isAdi: 'tefas-nav-gozlem-cleanup', tablo: 'tefas_nav_gozlem',
    migrasyon: '0063', sure: '60 days', gerekce: _piyasa,
  ),
  _Saklama(
    isAdi: 'kripto-seri-onbellek-cleanup', tablo: 'kripto_seri_onbellek',
    migrasyon: '0074', sure: '1 day', gerekce: _piyasa,
  ),
  _Saklama(
    isAdi: 'eurobond-seri-onbellek-cleanup', tablo: 'eurobond_seri_onbellek',
    migrasyon: '0124', sure: '1 day', gerekce: _piyasa,
  ),
];

/// Bugün bilinen aykırılıklar (iş adı/tablo). Kod ve yasal metin bu testte
/// DÜZELTİLMEDİ (görev "önce yalnız test"); düzeltme ayrı PR'da. Düzeltilince
/// tablo satırı kırılır ve buradan da silinir (aşağıdaki test bunu ister).
const _bilinenAykirilar = <String>{
  // Yasal metin "Kayıt hunisi adımları | 400 gün" diyor; 0114'ten beri
  // huni_olaylari'ni silen bir iş yok, satırlar süresiz kalıyor.
  'db-logs-retention/huni_olaylari',
};

void main() {
  final dosyalar = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final sema = _Sema.oku(dosyalar);

  String anahtar(_Saklama s) => '${s.isAdi}/${s.tablo}';

  test('ayrıştırıcı iki süre yazımını ve son tanımı tanır', () {
    final s = _Sema.oku([], ek: {
      '0001_a.sql': r"create function public.f() returns void as $$ "
          r"delete from public.t where ts < now() - interval '9 days'; $$; "
          r"select cron.schedule('j', '0 1 * * *', $$select public.f()$$);",
      '0002_b.sql': r"create or replace function public.f() returns void "
          r"as $x$ delete from public.t where d < current_date - 3; $x$;",
    });
    final sil = s.silmeler('j');
    expect(sil.keys, ['t']);
    expect(sil['t']!.sure, '3 days');
    expect(sil['t']!.migrasyon, '0002');
    expect(_saat('18 months'), greaterThan(_saat('90 days')));
  });

  test('tablodaki süre migration\'daki güncel süreyle aynı', () {
    final farklar = <String>[];
    for (final s in _tablo) {
      final sil = sema.silmeler(s.isAdi)[s.tablo];
      if (sil?.sure != s.sure || sil?.migrasyon != s.migrasyon) {
        farklar.add('${anahtar(s)}: tabloda ${s.sure ?? "silme yok"} '
            '(${s.migrasyon ?? "-"}), migration\'da '
            '${sil?.sure ?? "silme yok"} (${sil?.migrasyon ?? "-"})');
      }
    }
    expect(farklar, isEmpty,
        reason: 'Saklama süresi değişti. Tabloyu güncelle ve legal/tr '
            'Gizlilik Politikası ile KVKK Aydınlatma Metni §saklama '
            'satırını yeniden oku; süre uzuyorsa metin de değişmeli '
            '(Sürüm + Onay sürümü, CLAUDE.md "Yasal metin tek kaynak"):\n'
            '${farklar.join('\n')}');
  });

  test('yasal ifadeler md\'de hâlâ birebir duruyor', () {
    final md = <String, String>{};
    final eksik = <String>[];
    for (final s in _tablo) {
      for (final (dosya, ifade) in s.ifadeler) {
        final metin = md[dosya] ??= File('legal/tr/$dosya')
            .readAsStringSync()
            .replaceAll('\r\n', '\n');
        if (!metin.contains(ifade)) eksik.add('$dosya: "$ifade"');
      }
    }
    expect(eksik, isEmpty,
        reason: 'Yasal metindeki saklama satırı değişti. Yeni süreyi '
            'migration\'la karşılaştır, sonra bu testteki ifadeyi güncelle:\n'
            '${eksik.join('\n')}');
  });

  test('veri yasal metnin söylediğinden uzun tutulmuyor', () {
    final asan = <String>[];
    for (final s in _tablo) {
      if (s.yasalSure == null) {
        expect(s.gerekce, isNotNull,
            reason: '${anahtar(s)}: yasal süre yoksa gerekçe yazılır');
        continue;
      }
      expect(s.ifadeler, isNotEmpty,
          reason: '${anahtar(s)}: yasal süre md\'den alıntıyla gelir');
      final uygun = s.sure != null && _saat(s.sure!) <= _saat(s.yasalSure!);
      if (!uygun && !_bilinenAykirilar.contains(anahtar(s))) {
        asan.add('${anahtar(s)}: sunucu ${s.sure ?? "hiç silmiyor"}, '
            'metin ${s.yasalSure}');
      }
    }
    expect(asan, isEmpty,
        reason: 'Sunucu veriyi yasal metindeki süreden uzun tutuyor:\n'
            '${asan.join('\n')}');
  });

  test('bilinen aykırılık listesi güncel (düzelen buradan silinir)', () {
    for (final a in _bilinenAykirilar) {
      final s = _tablo.where((s) => anahtar(s) == a).single;
      final uygun = s.sure != null && _saat(s.sure!) <= _saat(s.yasalSure!);
      expect(uygun, isFalse,
          reason: '$a artık uygun; _bilinenAykirilar\'dan çıkar.');
    }
  });

  test('tabloda olmayan temizlik işi yok', () {
    final bilinen = {for (final s in _tablo) anahtar(s)};
    final yeni = <String>[];
    for (final is_ in sema.isler) {
      for (final t in sema.silmeler(is_).keys) {
        if (!bilinen.contains('$is_/$t')) yeni.add('$is_/$t');
      }
    }
    expect(yeni, isEmpty,
        reason: 'Yeni bir saklama/temizlik işi var. _tablo\'ya ekle ve '
            'yasal metinde o verinin süresini bul (yoksa gerekçe yaz):\n'
            '${yeni.join('\n')}');
  });
}

/// Bir silmenin güncel süresi ve son tanımlandığı migration.
class _Silme {
  const _Silme(this.sure, this.migrasyon);
  final String? sure;
  final String migrasyon;
}

/// Migration'ları sırayla "uygular": son `cron.schedule` ve son
/// `create [or replace] function` kazanır — Postgres'te olan da budur.
class _Sema {
  final Map<String, (String, String)> _cron = {}; // ad → (komut, no)
  final Map<String, (String, String)> _fn = {}; // ad → (gövde, no)

  Iterable<String> get isler => _cron.keys;

  static _Sema oku(List<File> dosyalar, {Map<String, String> ek = const {}}) {
    final s = _Sema();
    final kaynak = <String, String>{
      for (final f in dosyalar) f.uri.pathSegments.last: f.readAsStringSync(),
      ...ek,
    };
    for (final ad in kaynak.keys.toList()..sort()) {
      s._uygula(ad.substring(0, 4), _govde(kaynak[ad]!));
    }
    return s;
  }

  // Yorumlar atılmış, boşluk tekleştirilmiş, küçük harf (tablo_izinleri_test).
  static String _govde(String sql) => sql
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((s) => s.replaceFirst(RegExp(r'--.*$'), ''))
      .join('\n')
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  void _uygula(String no, String g) {
    final olaylar = <(int, void Function())>[];
    final fn = RegExp(r'create (?:or replace )?function (?:public\.)?(\w+)\s*\(');
    for (final m in fn.allMatches(g)) {
      final as = RegExp(r'\bas (\$\w*\$)').firstMatch(g.substring(m.end));
      if (as == null) continue;
      final bas = m.end + as.end;
      final son = g.indexOf(as.group(1)!, bas);
      if (son < 0) continue;
      final govde = g.substring(bas, son);
      olaylar.add((m.start, () => _fn[m.group(1)!] = (govde, no)));
    }
    final cron = RegExp(
        r"cron\.schedule\(\s*'([^']+)'\s*,\s*'[^']*'\s*,\s*"
        r"(?:(\$\w*\$)(.*?)\2|'((?:[^']|'')*)')");
    for (final m in cron.allMatches(g)) {
      final komut = m.group(3) ?? m.group(4)!.replaceAll("''", "'");
      olaylar.add((m.start, () => _cron[m.group(1)!] = (komut, no)));
    }
    // Kaldırma: `cron.unschedule('ad')` ya da `... where jobname = / in (...)`.
    final kaldir = RegExp(
        r"cron\.unschedule\(\s*(?:'([^']+)'|jobid\s*\)\s*from cron\.job "
        r"where jobname (?:= '([^']+)'|in \(([^)]*)\)))");
    for (final m in kaldir.allMatches(g)) {
      final adlar = [
        if (m.group(1) != null) m.group(1)!,
        if (m.group(2) != null) m.group(2)!,
        if (m.group(3) != null)
          ...RegExp(r"'([^']+)'").allMatches(m.group(3)!).map((x) => x[1]!),
      ];
      olaylar.add((m.start, () => adlar.forEach(_cron.remove)));
    }
    olaylar.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, uygula) in olaylar) {
      uygula();
    }
  }

  /// Bir işin sildiği tablolar: komuttaki `delete` + komutun çağırdığı
  /// fonksiyonların GÜNCEL gövdesindeki `delete`. Bir silmede birden çok
  /// süre varsa (db_logs: hata 30 gün, diğer 1 gün) üst sınır alınır.
  Map<String, _Silme> silmeler(String isAdi) {
    final c = _cron[isAdi];
    if (c == null) return {};
    final kaynaklar = <(String, String)>[c];
    for (final m in RegExp(r'(?:public\.)?(\w+)\s*\(').allMatches(c.$1)) {
      final f = _fn[m.group(1)!];
      if (f != null) kaynaklar.add(f);
    }
    final sonuc = <String, _Silme>{};
    for (final (metin, no) in kaynaklar) {
      for (final d in RegExp(r'delete from ([\w.]+)([^;]*)').allMatches(metin)) {
        final tablo = d.group(1)!.replaceFirst('public.', '');
        final sureler = [
          for (final m in RegExp(r"interval '([^']+)'").allMatches(d.group(2)!))
            m.group(1)!,
          for (final m in RegExp(r'::date - (\d+)\b|current_date - (\d+)\b')
              .allMatches(d.group(2)!))
            '${m.group(1) ?? m.group(2)} days',
        ]..sort((a, b) => _saat(b).compareTo(_saat(a)));
        if (sureler.isEmpty) continue; // süresiz silme saklama değildir
        sonuc[tablo] = _Silme(sureler.first, no);
      }
    }
    return sonuc;
  }
}

/// Interval → yaklaşık saat (ay 30, yıl 365 gün). Karşılaştırma aynı birimde
/// eşit çıkar ('18 months' = '18 months'), karışık birimde yeterince doğru.
int _saat(String interval) {
  final m = RegExp(r'^(\d+) (hour|day|week|month|year)s?$').firstMatch(interval);
  if (m == null) throw ArgumentError('Tanınmayan süre: $interval');
  const birim = {'hour': 1, 'day': 24, 'week': 168, 'month': 720, 'year': 8760};
  return int.parse(m.group(1)!) * birim[m.group(2)!]!;
}
