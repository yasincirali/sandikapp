"""Tokyo ve Frankfurt'a bağlı iki emülatörde AYNI hesapla aynı ekranları gezip metinleri karşılaştırır.

K3 provasının ekran ayağı: `veri_tasima.py` satır sayısını doğrular, bu betik
kullanıcının GÖRDÜĞÜ rakamları. Her iki emülatöre aynı hesapla giriş yapılmış
olmalı (5554 = `.env.local` Tokyo build'i, 5556 = `.env.frankfurt` build'i).

    PYTHONIOENCODING=utf-8 python tool/tasima/ekran_karsilastir.py

İlk koşu (2026-09-27, vasin_dirali@hotmail.com pilotu): 8 ekranda HİÇBİR
rakam farkı yok. Görülen farklar veri değil yerleşimdi: Tokyo'da ortak
seçici satırı içeriği aşağı itiyor (ortaklıklar pilota kopyalanmadı) ve
"Yarış" düğmesi yalnız aktif ortak varken çiziliyor.
"""
import html, os, re, subprocess, sys, time, io
from concurrent.futures import ThreadPoolExecutor

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
ADB = r"C:/Users/vasin/Android/sdk/platform-tools/adb.exe"
ENV = dict(os.environ, MSYS_NO_PATHCONV="1")
CIHAZ = {"TOKYO": "emulator-5554", "FRANKFURT": "emulator-5556"}


def adb(dev, *a):
    return subprocess.run([ADB, "-s", dev, *a], capture_output=True, env=ENV).stdout.decode("utf-8", "replace")


def dugumler(dev):
    adb(dev, "shell", "uiautomator", "dump", "/sdcard/ui.xml")
    x = adb(dev, "exec-out", "cat", "/sdcard/ui.xml")
    out = []
    for m in re.finditer(r"<node ([^>]*)>", x):
        n = m.group(1)
        t = re.search(r'text="([^"]*)"', n).group(1) or re.search(r'content-desc="([^"]*)"', n).group(1)
        b = [int(v) for v in re.findall(r"\d+", re.search(r'bounds="([^"]*)"', n).group(1))]
        if t:
            out.append((html.unescape(t).replace("\n", " | "), (b[0] + b[2]) // 2, (b[1] + b[3]) // 2))
    return out


def dokun(dev, metin):
    for t, x, y in dugumler(dev):
        if t == metin or t.split(" | ")[0] == metin:
            adb(dev, "shell", "input", "tap", str(x), str(y))
            return True
    return False


def ekran(dev):
    # Alt gezinme ve üst çubuk gürültüsünü at; içerik metinleri kalsın.
    gurultu = {"Ana | Ana", "Portföy | Portföy", "Varlık ekle", "Performans | Performans", "Profil | Profil",
               "Çıkış yap", "Fiyatları yenile", "Bakiyeyi gizle", "Bildirimler", "sandık", "Geri"}
    return [t for t, _, _ in dugumler(dev) if t not in gurultu and not t.startswith("Kimin portföyü")]


ADIMLAR = [
    ("Ana ekran", [("tap", "Ana")], 6),
    ("Portföy", [("tap", "Portföy")], 6),
    ("Performans/Grafik GÜNLÜK", [("tap", "Performans"), ("tap", "Grafik"), ("tap", "GÜNLÜK")], 12),
    ("Performans/Grafik 1H", [("tap", "1H")], 10),
    ("Performans/Grafik 1A", [("tap", "1A")], 10),
    ("Performans/Grafik 1Y", [("tap", "1Y")], 12),
    ("Performans/Özet 1A", [("tap", "Özet"), ("tap", "1A")], 10),
    ("Performans/Özet 1Y", [("tap", "1Y")], 10),
]


def calistir(ad_dev):
    ad, dev = ad_dev
    adb(dev, "shell", "am", "force-stop", "com.sandik.app")
    adb(dev, "shell", "monkey", "-p", "com.sandik.app", "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(35)  # açılış fiyat turu (8–27 sn ölçülmüştü)
    sonuc = {}
    for baslik, eylemler, bekle in ADIMLAR:
        for tur, hedef in eylemler:
            dokun(dev, hedef)
            time.sleep(1.5)
        time.sleep(bekle)
        sonuc[baslik] = ekran(dev)
    return ad, sonuc


with ThreadPoolExecutor(2) as ex:
    sonuclar = dict(ex.map(calistir, CIHAZ.items()))

fark_sayisi = 0
for baslik, _, _ in ADIMLAR:
    t, f = sonuclar["TOKYO"][baslik], sonuclar["FRANKFURT"][baslik]
    yalniz_t = [x for x in t if x not in f]
    yalniz_f = [x for x in f if x not in t]
    durum = "✓ AYNI" if not yalniz_t and not yalniz_f else "✗ FARK"
    fark_sayisi += durum.startswith("✗")
    print(f"\n=== {baslik}: {durum}  ({len(t)} / {len(f)} metin)")
    for x in yalniz_t:
        print(f"   T  {x[:230]}")
    for x in yalniz_f:
        print(f"   F  {x[:230]}")
    if durum.startswith("✓"):
        for x in t[:4]:
            print(f"      {x[:160]}")
print(f"\nFARKLI EKRAN: {fark_sayisi}/{len(ADIMLAR)}")
