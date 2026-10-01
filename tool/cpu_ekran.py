"""Emülatörde sekme başına boşta CPU ve kare sayısı — "boşta sürekli çizim" kapısı.

Neden (2026-10-01, docs/CPU_GPU_VE_BOYUT_RAPORU_2026_10.md): Ana ekrandaki
piyasa şeridi boşta 58 fps çiziyordu; hiçbir widget testi bunu göremez,
yalnızca cihazda kare sayarak görünür. Betik her sekmeye geçip 8 sn boşta
bekler, iş parçacığı bazında CPU (/proc/<pid>/task/*/stat farkı) ve
SurfaceFlinger'ın uygulama katmanında saydığı kareyi yazar.

Kullanım:
  python tool/cpu_ekran.py [emulator-5556] [--kapi]
  --kapi: Ana sekmesinde şeridin boşta durması beklenir (bostaSuresi + sönme),
          sonra 8 sn'de ortalama kare/sn eşiğin üstündeyse 1 ile çıkar.
          Eşik 5 fps: 30 sn'lik fiyat nabzı bir iki kare üretebilir, sürekli
          akış 58 üretir; arada geniş boşluk var.

Sınır: emülatör x86, yüzdeler telefondan yüksek; oranlar ve kare sayısı
anlamlı. toybox `top -n1` boşta hep 0 gösterir, `dumpsys gfxinfo` Flutter
karelerini saymaz — bu yüzden /proc ve SurfaceFlinger.
"""
import re
import subprocess
import sys
import time

# Windows konsolu cp1254: ✓/✗ yazdırırken UnicodeEncodeError veriyordu.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ADB = r"C:\Users\vasin\Android\sdk\platform-tools\adb.exe"
PKG = "com.sandik.app"
CLK = 100
# Alt sekme merkezleri (1080x2400 pixel7): Ana, Portföy, Performans, Profil.
TAB = {"Ana": (108, 2258), "Portföy": (324, 2258), "Performans": (756, 2258), "Profil": (972, 2258)}
BOSTA_BEKLEME = 35 + 5   # PiyasaSeridi.bostaSuresi + sönme payı (sn)
KAPI_ESIK_FPS = 5.0

args = [a for a in sys.argv[1:] if not a.startswith("--")]
DEV = args[0] if args else "emulator-5556"
KAPI = "--kapi" in sys.argv


def sh(c, timeout=30):
    return subprocess.run([ADB, "-s", DEV, "shell", c], capture_output=True, text=True, timeout=timeout).stdout


def snap(p):
    out = sh(
        f"for t in /proc/{p}/task/*; do awk '{{print $1\" \"$2\" \"$14\" \"$15}}' $t/stat 2>/dev/null; done; "
        f"echo PROC $(awk '{{print $14\" \"$15}}' /proc/{p}/stat); echo UP $(cut -d' ' -f1 /proc/uptime)"
    )
    th = {}
    proc = up = None
    for line in out.splitlines():
        s = line.split()
        if not s:
            continue
        if s[0] == "PROC":
            proc = int(s[1]) + int(s[2])
        elif s[0] == "UP":
            up = float(s[1])
        elif s[0].isdigit() and len(s) >= 4:
            th[s[0]] = (" ".join(s[1:-2]).strip("()"), int(s[-2]) + int(s[-1]))
    return th, proc, up


def kareler():
    ts = sh("dumpsys SurfaceFlinger --timestats -dump")
    for blok in ts.split("layerName = ")[1:]:
        if PKG in blok[:200]:
            m = re.search(r"totalFrames = (\d+)", blok)
            return int(m.group(1)) if m else -1
    return 0


def olc(p, sure=8):
    sh("dumpsys SurfaceFlinger --timestats -enable -clear")
    a, ap, au = snap(p)
    time.sleep(sure)
    b, bp, bu = snap(p)
    f = kareler()
    sh("dumpsys SurfaceFlinger --timestats -disable")
    dt = bu - au

    def th(name):
        return sum((b[t][1] - a[t][1]) for t in b if t in a and b[t][0] == name) / CLK / dt * 100

    return dt, (bp - ap) / CLK / dt * 100, th(PKG), th("1.raster"), f


def main():
    pid = sh(f"pidof {PKG}").split()
    if not pid:
        print("uygulama çalışmıyor")
        sys.exit(2)
    p = int(pid[0])
    print(f"cihaz {DEV} pid {p}")
    for ad, xy in TAB.items():
        sh(f"input tap {xy[0]} {xy[1]}")
        time.sleep(3.0)
        dt, toplam, ui, raster, f = olc(p)
        print(f"{ad:<11} boşta {dt:.1f}s  toplam %{toplam:5.1f}  ui %{ui:5.1f}  raster %{raster:5.1f}  kare {f} ({f/dt:.0f} fps)")
    if not KAPI:
        return
    sh(f"input tap {TAB['Ana'][0]} {TAB['Ana'][1]}")
    print(f"kapı: Ana'da {BOSTA_BEKLEME} sn dokunmadan bekleniyor (şerit durmalı)…")
    time.sleep(BOSTA_BEKLEME)
    dt, toplam, ui, raster, f = olc(p)
    fps = f / dt
    print(f"Ana (boşta durma sonrası) toplam %{toplam:.1f}  ui %{ui:.1f}  raster %{raster:.1f}  kare {f} ({fps:.1f} fps)")
    if fps > KAPI_ESIK_FPS:
        print(f"✗ KAPI: Ana ekran boşta {fps:.1f} fps çiziyor (eşik {KAPI_ESIK_FPS}). Sürekli animasyon var.")
        sys.exit(1)
    print("✓ KAPI: Ana ekran boşta uyuyor.")


main()
