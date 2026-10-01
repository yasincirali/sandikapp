"""Emülatörde sandık için iş parçacığı bazlı CPU ölçümü.

/proc/<pid>/task/*/stat utime+stime farkını alır; toybox top'un
örnekleme belirsizliği yok. Fazlar: boşta, sekme gezme, Performans
grafik kaydırma, Portföy listesi kaydırma. Her faz için toplam %CPU
(tek çekirdek = %100) ve en pahalı iş parçacıkları yazılır.
Ayrıca SurfaceFlinger timestats ile kare/jank sayımı denenir.
"""
import subprocess, sys, time, re, json

ADB = r"C:\Users\vasin\Android\sdk\platform-tools\adb.exe"
DEV = sys.argv[1] if len(sys.argv) > 1 else "emulator-5556"
ETIKET = sys.argv[2] if len(sys.argv) > 2 else "debug"
PKG = "com.sandik.app"
CLK = 100

def sh(cmd, timeout=20):
    r = subprocess.run([ADB, "-s", DEV, "shell", cmd], capture_output=True, text=True, timeout=timeout)
    return r.stdout

def pid():
    p = sh(f"pidof {PKG}").strip()
    return int(p.split()[0]) if p else None

def snap(p):
    # her thread: tid comm utime stime ; proses: utime stime ; uptime
    out = sh(
        f"for t in /proc/{p}/task/*; do "
        f"awk '{{print $1\" \"$2\" \"$14\" \"$15}}' $t/stat 2>/dev/null; done; "
        f"echo PROC $(awk '{{print $14\" \"$15}}' /proc/{p}/stat); echo UP $(cut -d' ' -f1 /proc/uptime)"
    )
    th = {}
    proc = None; up = None
    for line in out.splitlines():
        parts = line.split()
        if not parts: continue
        if parts[0] == "PROC": proc = int(parts[1]) + int(parts[2])
        elif parts[0] == "UP": up = float(parts[1])
        elif len(parts) >= 4 and parts[0].isdigit():
            tid = parts[0]; comm = " ".join(parts[1:-2]).strip("()")
            th[tid] = (comm, int(parts[-2]) + int(parts[-1]))
    return th, proc, up

def faz(ad, p, eylem, sure):
    a_th, a_pr, a_up = snap(p)
    t0 = time.time()
    eylem()
    kalan = sure - (time.time() - t0)
    if kalan > 0: time.sleep(kalan)
    b_th, b_pr, b_up = snap(p)
    dt = b_up - a_up
    toplam = (b_pr - a_pr) / CLK / dt * 100
    satir = []
    for tid, (comm, t) in b_th.items():
        if tid in a_th:
            d = (t - a_th[tid][1]) / CLK / dt * 100
            if d >= 0.3: satir.append((d, comm))
    satir.sort(reverse=True)
    print(f"\n[{ETIKET}] {ad}  süre {dt:.1f}s  toplam %{toplam:.1f} (1 çekirdek=100)")
    for d, c in satir[:8]:
        print(f"   {c:<22} %{d:.1f}")
    return {"faz": ad, "sure": round(dt, 1), "toplam": round(toplam, 1),
            "thread": [(c, round(d, 1)) for d, c in satir[:8]]}

def tap(x, y): sh(f"input tap {x} {y}")
def swipe(x1, y1, x2, y2, ms=300): sh(f"input swipe {x1} {y1} {x2} {y2} {ms}")

TAB = {"Ana": (108, 2258), "Portföy": (324, 2258), "Performans": (756, 2258), "Profil": (972, 2258)}

def bos(): pass

def sekmeler():
    for _ in range(2):
        for ad in ["Portföy", "Performans", "Profil", "Ana"]:
            tap(*TAB[ad]); time.sleep(1.6)

def grafik():
    tap(*TAB["Performans"]); time.sleep(2.0)
    # grafik bölgesi ekranın orta üstü; yatay sürükleme = imleç/tooltip
    for _ in range(4):
        swipe(200, 1000, 900, 1000, 700); swipe(900, 1000, 200, 1000, 700)

def liste():
    tap(*TAB["Portföy"]); time.sleep(2.0)
    for _ in range(4):
        swipe(540, 1900, 540, 700, 250); time.sleep(0.6)
        swipe(540, 700, 540, 1900, 250); time.sleep(0.6)

def main():
    p = pid()
    if not p:
        print("uygulama çalışmıyor"); sys.exit(1)
    print(f"cihaz {DEV} pid {p} etiket {ETIKET}")
    sh("dumpsys SurfaceFlinger --timestats -enable -clear")
    tap(*TAB["Ana"]); time.sleep(2.5)
    sonuc = []
    sonuc.append(faz("boşta (Ana, dokunma yok)", p, bos, 15))
    sonuc.append(faz("sekme gezme (4 sekme x2)", p, sekmeler, 14))
    sonuc.append(faz("Performans grafik sürükleme", p, grafik, 10))
    sonuc.append(faz("Portföy listesi kaydırma", p, liste, 10))
    tap(*TAB["Ana"]); time.sleep(2)
    sonuc.append(faz("boşta tekrar (Ana)", p, bos, 10))
    ts = sh("dumpsys SurfaceFlinger --timestats -dump", timeout=30)
    m = re.search(r"totalFrames = (\d+).*?missedFrames = (\d+).*?clientCompositionFrames = (\d+)", ts, re.S)
    if m: print("\nSurfaceFlinger timestats: toplam", m.group(1), "kaçan", m.group(2), "client-comp", m.group(3))
    # katman bazlı: sandik yüzeyi
    for blok in ts.split("layerName = ")[1:]:
        if PKG in blok[:200]:
            name = blok.split("\n")[0]
            tf = re.search(r"totalFrames = (\d+)", blok); jk = re.search(r"jankyFrames = (\d+)", blok)
            p50 = re.search(r"present2present histogram is as below:\n(.*?)\n", blok)
            print("  katman", name[:70], "| kareler", tf.group(1) if tf else "?", "| janky", jk.group(1) if jk else "?")
    sh("dumpsys SurfaceFlinger --timestats -disable")
    print("\nJSON", json.dumps(sonuc, ensure_ascii=False))

main()
