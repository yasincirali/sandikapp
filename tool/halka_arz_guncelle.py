"""Halka arz takvimini kaynağından günceller (docs/data + assets/data).

Kullanıcı (2026-10-01): "Halka arz güncel olmalı." Liste bugüne kadar
docs/README.md "Halka arz verisi" prosedürüyle ELLE güncelleniyordu; yeni arz
haftalarca eksik kalabiliyordu. Bu betik o prosedürün 1–3. adımlarını yapar:

  1. halkarz.com ana sayfasındaki "İlk Halka Arzlar" listesinin son
     [ADAY_SAYISI] şirketini okur (kaynak, mevcut kayıtların hepsinin
     `kaynak` alanıyla aynı site),
  2. her şirket sayfasından alanları ayrıştırır; BİLİNMEYEN alan `null`
     kalır (uydurma yasak — fiyat aralığıysa fiyat null, tarih
     çözülemiyorsa null),
  3. yeni kodu ekler, var olan kayıtta yalnızca `null` olan alanı doldurur
     (elle düzeltilmiş dolu bir alanın üstüne YAZMAZ),
  4. işlem görmeye başlamış yeni kodu `bist100StocksMap`'e ekler,
  5. iki JSON kopyasını birebir aynı yazar.

Doğrulamanın asıl kapısı `test/halka_arz_veri_test.dart` (şema, tarih
sırası, fiyat > 0 ya da null, iki kopyanın eşitliği, sembol listesi) —
GitHub Actions (`halka-arz.yml`) değişikliği PR olarak açar, CI testi koşar,
birleştirme insanda kalır.

Kullanım:
    python tool/halka_arz_guncelle.py            # yazar
    python tool/halka_arz_guncelle.py --dry-run  # yalnız ne değişeceğini söyler
Çıkış satırı `DEGISIKLIK_VAR` ya da `DEGISIKLIK_YOK` (iş akışı buna bakar).
Başarılı taramada (en az bir şirket sayfası ayrıştırıldı) kayıtlar aynı kalsa
da üst `guncelleme` bugüne çekilir → `DEGISIKLIK_VAR`; aynı gün tekrar koşuda
`DEGISIKLIK_YOK`. Aday yoksa ya da aday var ama hiçbiri ayrıştırılamadıysa
çıkış kodu 2 (iş akışı kırmızı).
Test: `python -m unittest tool/halka_arz_guncelle_test.py` (ağsız).
"""
from __future__ import annotations

import datetime as dt
import html
import json
import re
import sys
import urllib.request
from pathlib import Path

KOK = Path(__file__).resolve().parent.parent
JSON_YOLLARI = [KOK / 'docs/data/halka_arz.json', KOK / 'assets/data/halka_arz.json']
# Sembol listesi 2026-10-10'da asset_categories.dart'tan bu dosyaya taşındı
# (borsanın tamamı, alfabetik). Betik eski yolu gösterdiği için ilk gerçek
# değişiklikte "halka arz bloğu bulunamadı" ile düşecekti; besleme o tarihten
# beri hep DEGISIKLIK_YOK verdiğinden fark edilmedi (2026-11-08).
SEMBOL_DOSYASI = KOK / 'lib/models/bist_hisseleri.dart'
HARITA_BASI = 'const bist100StocksMap = <String, String>{\n'
ANA_SAYFA = 'https://halkarz.com/'
ADAY_SAYISI = 12
UA = 'Mozilla/5.0 (compatible; sandik-halka-arz/1.0; +https://yasincirali.github.io/sandikapp/)'

AYLAR = {
    'ocak': 1, 'şubat': 2, 'mart': 3, 'nisan': 4, 'mayıs': 5, 'haziran': 6,
    'temmuz': 7, 'ağustos': 8, 'eylül': 9, 'ekim': 10, 'kasım': 11, 'aralık': 12,
}


def getir(url: str) -> str:
    istek = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'tr-TR'})
    with urllib.request.urlopen(istek, timeout=30) as y:
        return y.read().decode('utf-8', errors='replace')


def duz_metin(s: str) -> str:
    s = re.sub(r'<script.*?</script>|<style.*?</style>', ' ', s, flags=re.S)
    s = html.unescape(re.sub(r'<[^>]+>', '|', s))
    s = re.sub(r'\s+', ' ', s)
    return re.sub(r'(\|\s*)+', '|', s)


def aday_sayfalar(ana: str) -> list[str]:
    """"İlk Halka Arzlar" bloğundaki şirket bağlantıları, sayfadaki sırayla."""
    bas = ana.find('Taslak Arzlar')
    govde = ana[bas:] if bas >= 0 else ana
    goruldu: list[str] = []
    for m in re.finditer(r'href="(https://halkarz\.com/[a-z0-9-]+/)"', govde):
        url = m.group(1)
        if url.rstrip('/').count('/') != 3:  # yalnız kök düzeyindeki şirket sayfası
            continue
        if not re.search(r'-a-s(-\d+)?/$', url):  # "… A.Ş." şirket sayfaları
            continue
        if url not in goruldu:
            goruldu.append(url)
        if len(goruldu) >= ADAY_SAYISI:
            break
    return goruldu


def alanlar(metin: str) -> dict[str, str]:
    """"Etiket : |değer|" çiftleri."""
    out: dict[str, str] = {}
    # Kapanış `|` lookahead: tüketilseydi bir sonraki çiftin açılış `|`'ı
    # gider ve her ikinci alan (Bist Kodu, Fiyat…) kaçardı.
    for m in re.finditer(r'\|([^|:]{2,60}?)\s*:\s*\|([^|]+)(?=\|)', metin):
        etiket = m.group(1).strip()
        if etiket not in out:
            out[etiket] = m.group(2).strip()
    return out


def tarih_araligi(s: str | None) -> tuple[str | None, str | None]:
    """'9-10-11 Eylül 2026' / '30 Eylül-1-2 Ekim 2026' → (ilk gün, son gün)."""
    if not s:
        return None, None
    yil_m = re.search(r'(20\d\d)', s)
    if not yil_m:
        return None, None
    yil = int(yil_m.group(1))
    parcalar = re.findall(r'(\d{1,2})\s*([A-Za-zÇĞİÖŞÜçğıöşü]+)?', s[:yil_m.start()])
    gunler: list[tuple[int, int | None]] = []
    for gun, ay in parcalar:
        gunler.append((int(gun), AYLAR.get(ay.lower()) if ay else None))
    if not gunler:
        return None, None
    # Ay adı olmayan günler, kendisinden sonraki ilk ayı alır.
    ay_sonraki: int | None = None
    cozulen: list[tuple[int, int]] = []
    for gun, ay in reversed(gunler):
        if ay is not None:
            ay_sonraki = ay
        if ay_sonraki is None:
            return None, None
        cozulen.append((gun, ay_sonraki))
    cozulen.reverse()
    try:
        ilk = dt.date(yil, cozulen[0][1], cozulen[0][0])
        son = dt.date(yil, cozulen[-1][1], cozulen[-1][0])
    except ValueError:
        return None, None
    if ilk > son:  # Aralık→Ocak gibi yıl devri: ilk gün önceki yıl
        try:
            ilk = dt.date(yil - 1, cozulen[0][1], cozulen[0][0])
        except ValueError:
            return None, None
    return ilk.isoformat(), son.isoformat()


def tek_tarih(s: str | None) -> str | None:
    _, son = tarih_araligi(s)
    return son


def fiyat(s: str | None) -> float | None:
    """'25,52 TL' → 25.52; aralık ('22,00 - 24,00 TL') ya da belirsiz → None."""
    if not s:
        return None
    sayilar = re.findall(r'\d[\d.]*,\d+|\d+', s)
    if len(sayilar) != 1:
        return None
    try:
        v = float(sayilar[0].replace('.', '').replace(',', '.'))
    except ValueError:
        return None
    return v if v > 0 else None


def dagitim(s: str | None) -> str | None:
    if not s:
        return None
    k = s.lower()
    if 'eşit' in k:
        return 'eşit'
    if 'oransal' in k:
        return 'oransal'
    return None


def kayit_kur(url: str, metin: str, bugun: str) -> dict | None:
    a = alanlar(metin)
    kod = (a.get('Bist Kodu') or '').strip().upper()
    if not re.fullmatch(r'[A-Z0-9]{3,6}', kod):
        return None  # taslak ya da kodu belli değil
    m = re.search(r'\|' + re.escape(kod) + r'\|([^|]{3,120})\|Halka Arz Bilgileri', metin)
    sirket = m.group(1).strip() if m else None
    if not sirket:
        return None
    t_bas, t_bit = tarih_araligi(a.get('Halka Arz Tarihi'))
    pazar = a.get('Pazar')
    return {
        'kod': kod,
        'sirket': sirket,
        'talep_baslangic': t_bas,
        'talep_bitis': t_bit,
        'fiyat': fiyat(a.get('Halka Arz Fiyatı/Aralığı')),
        'dagitim': dagitim(a.get('Dağıtım Yöntemi')),
        'islem_baslangic': tek_tarih(a.get('Bist İlk İşlem Tarihi')),
        'pazar': pazar if pazar and pazar != '-' else None,
        'kaynak': url,
        'guncelleme': bugun,
    }


def tutarli_mi(k: dict) -> bool:
    """Test kurallarının istemci tarafı: ters tarih yazılmaz."""
    sira = [k['talep_baslangic'], k['talep_bitis'], k['islem_baslangic']]
    dolu = [x for x in sira if x]
    return dolu == sorted(dolu)


def kisa_ad(sirket: str) -> str:
    ad = re.sub(r'\s*(A\.\s?Ş\.?|Anonim Şirketi)\s*$', '', sirket).strip()
    return ad.replace('Gayrimenkul Yatırım Ortaklığı', 'GYO')


def sembol_satiri(kod: str, ad: str) -> str:
    """`dart format` biçimi: 80 sütunu aşan girdi değeri alt satıra iner."""
    ad = ad.replace("'", "\\'")
    tek = f"  '{kod}.IS': '{ad}',\n"
    if len(tek) - 1 <= 80:
        return tek
    return f"  '{kod}.IS':\n      '{ad}',\n"


def sembol_ekle(kodlar_adlar: list[tuple[str, str]], kuru: bool) -> list[str]:
    kaynak = SEMBOL_DOSYASI.read_text(encoding='utf-8')
    eklenen = []
    bas = kaynak.find(HARITA_BASI)
    assert bas >= 0 and kaynak.count(HARITA_BASI) == 1, \
        'bist_hisseleri.dart: bist100StocksMap bulunamadı'
    govde_bas = bas + len(HARITA_BASI)
    govde_son = kaynak.index('\n};', govde_bas) + 1
    govde = kaynak[govde_bas:govde_son]
    for kod, ad in kodlar_adlar:
        if f"'{kod}.IS'" in kaynak or kod in eklenen:
            continue
        # Liste alfabetik (dosya başındaki karar): yeni kod, anahtarı kendisinden
        # büyük ilk girdinin önüne girer.
        anahtar = f'{kod}.IS'
        yer = len(govde)
        for m in re.finditer(r"^  '([A-Z0-9]+\.IS)':", govde, flags=re.M):
            if m.group(1) > anahtar:
                yer = m.start()
                break
        govde = govde[:yer] + sembol_satiri(kod, kisa_ad(ad)) + govde[yer:]
        eklenen.append(kod)
    if eklenen and not kuru:
        kaynak = kaynak[:govde_bas] + govde + kaynak[govde_son:]
        SEMBOL_DOSYASI.write_text(kaynak, encoding='utf-8', newline='\n')
    return eklenen


def main(argv: list[str] | None = None, bugun: str | None = None) -> int:
    kuru = '--dry-run' in (sys.argv[1:] if argv is None else argv)
    bugun = bugun or dt.date.today().isoformat()
    ham = JSON_YOLLARI[0].read_text(encoding='utf-8').replace('\r\n', '\n')
    veri = json.loads(ham)
    mevcut = {k['kod']: k for k in veri['kayitlar']}

    ana = getir(ANA_SAYFA)
    adaylar = aday_sayfalar(ana)
    if not adaylar:
        print('HATA: aday bulunamadı — sayfa yapısı değişmiş olabilir.', file=sys.stderr)
        return 2

    yeniler: list[dict] = []
    guncellenen: list[str] = []
    ayristirilan = 0
    for url in adaylar:
        try:
            k = kayit_kur(url, duz_metin(getir(url)), bugun)
        except Exception as e:  # tek sayfa hatası tüm koşuyu düşürmez
            print(f'uyarı: {url} okunamadı: {e}', file=sys.stderr)
            continue
        if k is None:
            continue
        ayristirilan += 1
        if not tutarli_mi(k):
            continue
        eski = mevcut.get(k['kod'])
        if eski is None:
            # Talep tarihi belli olmayan (ertelenmiş / takvimi açıklanmamış)
            # arz listeye girmez: ekran tarihsiz bir satırı "yaklaşan" diye
            # gösteremez. Tarih açıklanınca sonraki koşu ekler.
            if k['talep_baslangic'] is None:
                continue
            yeniler.append(k)
            continue
        # Yalnız boş alanı doldur; dolu (belki elle düzeltilmiş) alana dokunma.
        degisti = False
        for alan, deger in k.items():
            if alan in ('guncelleme', 'kaynak'):
                continue
            if eski.get(alan) is None and deger is not None:
                eski[alan] = deger
                degisti = True
        if degisti and tutarli_mi(eski):
            eski['guncelleme'] = bugun
            guncellenen.append(k['kod'])

    # İş akışı günlüğünde teşhis satırı: "aday var, kayıt yok" ile "kayıt var,
    # değişiklik yok" artık ayırt edilir (2026-11-08 öncesi ikisi de yalnız
    # DEGISIKLIK_YOK yazıyordu).
    print(f'aday: {len(adaylar)} · ayrıştırılan: {ayristirilan}')

    # Aday sayfa var ama hiçbirinden kayıt çıkmadı → ayrıştırıcı bugünkü sayfa
    # yapısını okuyamıyor. 2 ile çık ki iş akışı kırmızı dönsün (e-posta
    # gider). Neden (Ar-Ge 2026-11-08): eski kod burada DEGISIKLIK_YOK yazıp
    # 0 dönüyordu; besleme 2026-09-29'dan beri tazelenmedi, iş akışı her gün
    # yeşildi ve `halkaArzBayatMi` (21 gün) Profil girişini sessizce gizledi.
    # ADAY_SAYISI son 12 arzı aldığı için en az biri kodu açıklanmış arzdır;
    # hepsi taslak çıkarsa da sayfa yapısından şüphelenmek doğru.
    if ayristirilan == 0:
        print('HATA: aday sayfalar var ama hiçbirinden kayıt ayrıştırılamadı: '
              'şirket sayfası yapısı değişmiş olabilir.', file=sys.stderr)
        return 2

    # Tarama başarılı (en az bir sayfa okundu): üst `guncelleme` "kaynak bu gün
    # kontrol edildi" demektir, kayıt listesi aynı kalsa da bugüne çekilir.
    # Yoksa yeni arz olmayan haftalarda tarih eskir, `halkaArzBayatMi` çalışan
    # bir beslemeyi ölü sanıp ekranı gizler (yasin raporu 2026-11-08 madde 1).
    # Aynı gün ikinci koşu dosyaya dokunmaz → DEGISIKLIK_YOK, boş PR yok.
    yalniz_tarih = not yeniler and not guncellenen
    if yalniz_tarih and veri.get('guncelleme') == bugun:
        print('DEGISIKLIK_YOK')
        return 0

    yeniler.sort(key=lambda k: k['talep_baslangic'] or '', reverse=True)
    veri['kayitlar'] = yeniler + veri['kayitlar']
    veri['guncelleme'] = bugun
    # Tarih-yalnız koşuda da çalışır: `halka_arz_veri_test` "derleme tarihine
    # kadar işlem görmeye başlayan kod sembol listesinde" kuralını üst
    # `guncelleme`ye göre ölçer; tarih ilerleyince yeni kod listeye girmeli.
    islemde = [(k['kod'], k['sirket']) for k in veri['kayitlar'] if k['islem_baslangic']]
    eklenen_sembol = sembol_ekle(islemde, kuru)

    # `yeni:` öneki iş akışının PR başlığı/commit özeti için grep'lediği satır.
    if yalniz_tarih and not eklenen_sembol:
        print(f'yeni: yok · kaynak kontrol edildi, tarih {bugun} '
              f'({ayristirilan} sayfa okundu)')
    else:
        print(f"yeni: {[k['kod'] for k in yeniler]} · güncellenen: {guncellenen} · "
              f"sembol eklenen: {eklenen_sembol}")
    if not kuru:
        cikti = json.dumps(veri, ensure_ascii=False, indent=2) + '\n'
        for yol in JSON_YOLLARI:
            yol.write_text(cikti, encoding='utf-8', newline='\n')
    print('DEGISIKLIK_VAR')
    return 0


if __name__ == '__main__':
    sys.exit(main())
