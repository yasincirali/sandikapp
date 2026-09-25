"""Emülatör arayüzünü METİN olarak okur ve gezdirir.

Neden: bu makinedeki emülatörler Flutter'ı render edemiyor (screencap
siyah) ama uiautomator erişilebilirlik ağacını veriyor. Bu betikle ekran
"müşteri gibi" gezilir: metinler + koordinatlar okunur, dokunulur, yazılır.
Bulgu turu 2026-09-25'te altın salınımı, öneksiz fon ve ".IS" adlarını
böyle yakaladı. Tuzaklar: Flutter TextField'a `input text` yazmaz →
`keyevent`; `tap` önce TAM eşleşme arar (uyarı metnindeki "ana" değil, "Ana"
sekmesi); yatay çip satırları ekran dışına taşar → önce `swipe`.

Kullanım: PYTHONIOENCODING=utf-8 python tool/ui_gez.py <komut> ...
Cihaz: DEV=emulator-5556 ile değiştirilebilir.

Kullanım:
  python ui.py dump [--wait N]        -> metin + merkez koordinat listesi
  python ui.py tap "metin"            -> metni içeren ilk node'un merkezine dokun
  python ui.py tapxy X Y
  python ui.py back
  python ui.py text "yazı"            -> odaklı alana yaz
  python ui.py swipe x1 y1 x2 y2 [ms]
  python ui.py wait N                 -> N saniye bekle
  python ui.py log "regex"            -> logcat'te regex eşleşen son satırlar
"""
import subprocess, sys, time, re, os, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
import xml.etree.ElementTree as ET

ADB = r"C:/Users/vasin/Android/sdk/platform-tools/adb.exe"
DEV = os.environ.get("DEV", "emulator-5554")
ENV = dict(os.environ, MSYS_NO_PATHCONV="1")


def adb(*args, out=False):
    r = subprocess.run([ADB, "-s", DEV, *args], capture_output=True, env=ENV)
    return r.stdout if out else r.stdout.decode("utf-8", "replace")


def dump():
    adb("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    xml = adb("exec-out", "cat", "/sdcard/ui.xml", out=True).decode("utf-8", "replace")
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return []
    rows = []
    for n in root.iter("node"):
        t = n.get("text") or ""
        d = n.get("content-desc") or ""
        s = (t or d).strip()
        if not s:
            continue
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds", ""))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        rows.append(((x1 + x2) // 2, (y1 + y2) // 2, y1, s.replace("\n", " | ")))
    rows.sort(key=lambda r: (r[2], r[0]))
    return rows


def show(rows):
    for x, y, _, s in rows:
        print(f"{x:4d},{y:4d}  {s}")


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__); return
    cmd = a[0]
    if cmd == "dump":
        if "--wait" in a:
            time.sleep(float(a[a.index("--wait") + 1]))
        show(dump())
    elif cmd == "tap":
        needle = a[1].lower()
        idx = int(a[2]) if len(a) > 2 else 0
        rows = dump()
        # Önce tam eşleşme (ör. "Ana" sekmesi, uyarı metnindeki "ana" değil), sonra alt dize.
        hits = [r for r in rows if r[3].lower() == needle or r[3].lower() == needle + " | " + needle]
        if not hits:
            hits = [r for r in rows if needle in r[3].lower()]
        if not hits:
            print("BULUNAMADI:", a[1]); sys.exit(1)
        x, y, _, s = hits[idx]
        adb("shell", "input", "tap", str(x), str(y))
        print(f"tap {x},{y} -> {s}")
    elif cmd == "tapxy":
        adb("shell", "input", "tap", a[1], a[2]); print("tap", a[1], a[2])
    elif cmd == "back":
        adb("shell", "input", "keyevent", "KEYCODE_BACK"); print("back")
    elif cmd == "text":
        adb("shell", "input", "text", a[1].replace(" ", "%s")); print("text", a[1])
    elif cmd == "swipe":
        ms = a[5] if len(a) > 5 else "400"
        adb("shell", "input", "swipe", a[1], a[2], a[3], a[4], ms); print("swipe")
    elif cmd == "wait":
        time.sleep(float(a[1]))
    elif cmd == "log":
        txt = adb("logcat", "-d", "-v", "time")
        pat = re.compile(a[1], re.I)
        lines = [l for l in txt.splitlines() if pat.search(l)]
        print("\n".join(lines[-int(a[2]) if len(a) > 2 else -25:]))


if __name__ == "__main__":
    main()
