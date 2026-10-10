"""Türkçe anlatımı EMA Lightning ile yerelde üretir (mağaza/tanıtım videoları).

Neden EMA Lightning (2026-10-10, yasin: "bununla store videosu seslendireceğiz"):
- Kokoro'da (brag/Hyperframes'in TTS'i) Türkçe ses yok; şimdiye kadarki yedek
  edge-tts resmi bir API değil, ticari kullanımı belirsiz (`SES_LISANS.md`).
- EMA Lightning Apache 2.0 (ağırlıklar dahil, ticari serbest), tamamen yerel:
  metin makineden çıkmaz. Sayı/tarih/tutar okumayı normalizer-tr yapar
  ("31,49" → "otuz bir virgül kırk dokuz").
- Tek ses, duygu kontrolü yok — tonu cümle yazımıyla ayarlarsın.

Kurulum (bir kez; paket Python >= 3.11 ister, sistemdeki 3.10 yetmez):
  python -m pip install uv
  python -m uv venv --python 3.12 store_listing/preview_video/.venv-ema
  python -m uv pip install --python store_listing/preview_video/.venv-ema/Scripts/python.exe \
      torch --index-url https://download.pytorch.org/whl/cu128      # RTX 50xx; GPU yoksa düz `torch`
  python -m uv pip install --python store_listing/preview_video/.venv-ema/Scripts/python.exe ema-lightning==1.0.4
İlk koşuda ağırlıklar (~34 MB) HF önbelleğine iner. Paket onları
`torch.load(weights_only=True)` ile açar — pickle'dan kod çalışmaz (1.0.4'te denetlendi).

Kullanım (venv'in python'u ile):
  .venv-ema/Scripts/python.exe scripts/seslendir_ema.py anlatim.json
  .venv-ema/Scripts/python.exe scripts/seslendir_ema.py --id 01_rozet --metin "Paran enflasyonu geçti mi?"

anlatim.json: [{"id": "01_rozet", "metin": "..."}, ...]  ("text" anahtarı da olur)
Çıktı: <cikti>/m_<id>.wav — 48 kHz mono 16 bit, baş/son sessizlik
`prep_media.py` ile aynı kuralla kırpılmış (-45 dBFS, 30 ms pencere, 60 ms
pay); edge-tts sesleriyle (a_/e_) yan yana değiştirilebilir. Basılan süreler
index.html SCENES tablosundaki `voLen` alanına elle girilir.

Yazım kuralları: ../ANLATIM_KURALLARI.md (kullanıcı kuralı 2026-10-10: doğal,
basit, açıklayıcı). Her satır üretimden önce denetlenir; `--denetle` yalnız
denetler, ses üretmez (sistem Python'u da yeter).

Seviye: tepe -1 dBFS'e çekilir (`--ham` kapatır); gerekçe `tepeye_cek`.

Tohum sabit (varsayılan 0): aynı metin + tohum = aynı ses; bir satırı
beğenmezsen yalnız onun tohumunu değiştir (`"tohum": 3`).
"""
import argparse
import json
import os
import re
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
VARSAYILAN_CIKTI = os.path.normpath(
    os.path.join(HERE, "..", "brag-output", "composition", "assets", "vo"))
SR = 48000


# Jargon → günlük karşılık (ANLATIM_KURALLARI.md §2). Küçük harfle, sözcük başı.
JARGON = {
    "reel": "enflasyondan sonra kalan kazanç",
    "nominal": "söyleme ya da 'görünen kâr'",
    "tüfe": "enflasyon",
    "xu100": "borsa",
    "bist": "Borsa İstanbul / borsa",
    "endeks": "borsa",
    "tefas": "fon",
    "xirr": "kazancın",
    "twr": "kazancın",
    "getiri oranı": "yüzde kaç kazandığın",
    "volatilite": "ne kadar oynadığı",
    "enstrüman": "varlık",
    "benchmark": "karşılaştırma",
    "deneyimleyin": "sen hitabı, düz fiil",
    "sunuyoruz": "sen hitabı, düz fiil",
    "kapsamlı": "somut söyle",
}
EN_COK_KELIME = 12


def denetle(metin: str) -> list[str]:
    """ANLATIM_KURALLARI.md'nin makineyle bakılabilen kısmı. Uyarır, durdurmaz:
    son karar kulağın (kontrol listesi §8)."""
    uyari = []
    kucuk = metin.lower()
    for cumle in re.split(r"(?<=[.?!…])\s+", metin.strip()):
        n = len(cumle.split())
        if n > EN_COK_KELIME:
            uyari.append(f"{n} kelimelik cümle (en çok {EN_COK_KELIME}): böl")
    for terim, yerine in JARGON.items():
        if re.search(rf"(?<!\w){re.escape(terim)}", kucuk):
            uyari.append(f"jargon '{terim}' → {yerine}")
    if re.search(r"\d|%", metin):
        uyari.append("rakam/% var: sözcükle yaz ve yuvarla (\"otuz puandan fazla\")")
    if "!" in metin:
        uyari.append("ünlem reklam tonu verir, sese bir şey katmaz")
    if re.search(r"(?<!\w)[A-ZÇĞİÖŞÜ]{2,}(?!\w)", metin):
        uyari.append("kısaltma/BÜYÜK HARF: harf harf ya da yanlış okunur, açık yaz")
    if metin.count(",") >= 2:
        uyari.append("virgül duraklatmaz (ölçüldü): duraklama için noktaya böl")
    return uyari


def kirp(ses: np.ndarray) -> np.ndarray:
    """Baş/son sessizliği kırpar — `prep_media.py`'deki kuralın aynısı."""
    esik = 10 ** (-45 / 20)
    pencere = SR * 30 // 1000
    yuksek = lambda i: np.abs(ses[i:i + pencere]).max(initial=0) > esik
    s = 0
    while s + pencere < len(ses) and not yuksek(s):
        s += pencere
    e = len(ses)
    while e - pencere > s and not yuksek(e - pencere):
        e -= pencere
    pay = SR * 60 // 1000
    return ses[max(0, s - pay):min(len(ses), e + pay)]


def tepeye_cek(ses: np.ndarray, tepe_db: float = -1.0) -> np.ndarray:
    """Tepeyi [tepe_db]'ye çeker. EMA çıktısı edge-tts'ten ~8 dB kısık
    (RMS -25/-26 dBFS'e karşı -17); tepe/RMS farkı da büyük (~20 dB), bu
    yüzden RMS'e göre büyütmek tepeyi kırpardı. Tepe -1 dBFS'te RMS ~-21'e
    çıkar; kalan ~3-4 dB miksajda (hyperframes-audio kompresör/limiter ya da
    `data-volume`) kapatılır."""
    tepe = float(np.abs(ses).max(initial=0))
    return ses if tepe == 0 else ses * (10 ** (tepe_db / 20) / tepe)


def dbfs(ses: np.ndarray) -> float:
    return 20 * np.log10(max(float(np.sqrt(np.mean(ses ** 2))), 1e-9))


def yaz(yol: str, ses: np.ndarray) -> None:
    pcm = (np.clip(ses, -1, 1) * 32767).astype("<i2")
    with wave.open(yol, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dosya", nargs="?", help="anlatim.json")
    ap.add_argument("--id")
    ap.add_argument("--metin")
    ap.add_argument("--cikti", default=VARSAYILAN_CIKTI)
    ap.add_argument("--onek", default="m_",
                    help="dosya öneki (a_ Ahmet, e_ Emel, m_ EMA)")
    ap.add_argument("--hiz", type=float, default=1.0, help="0.25–4")
    ap.add_argument("--tohum", type=int, default=0)
    ap.add_argument("--ham", action="store_true",
                    help="tepe normalizasyonu yapma (modelin kendi seviyesi)")
    ap.add_argument("--denetle", action="store_true",
                    help="yalnız metni ANLATIM_KURALLARI'na göre denetle, ses üretme")
    a = ap.parse_args()

    if a.dosya:
        with open(a.dosya, encoding="utf-8") as f:
            satirlar = json.load(f)
    elif a.id and a.metin:
        satirlar = [{"id": a.id, "metin": a.metin}]
    else:
        ap.error("anlatim.json ya da --id + --metin ver")

    toplam_uyari = 0
    for s in satirlar:
        for u in denetle(s.get("metin") or s["text"]):
            print(f"uyarı {s['id']}: {u}")
            toplam_uyari += 1
    if a.denetle:
        kelime = sum(len((s.get("metin") or s["text"]).split()) for s in satirlar)
        print(f"{len(satirlar)} satır, {kelime} kelime ≈ {kelime / 2:.0f} sn "
              f"(2 kelime/sn), {toplam_uyari} uyarı")
        return

    from ema_lightning import EMA  # ağır içe aktarma: argümanlar doğruysa

    os.makedirs(a.cikti, exist_ok=True)
    tts = EMA()
    for s in satirlar:
        metin = s.get("metin") or s["text"]
        konusma = tts.say(metin, speed=float(s.get("hiz", a.hiz)),
                          seed=int(s.get("tohum", a.tohum)))
        ses = kirp(np.asarray(konusma.audio, dtype=np.float32))
        if not a.ham:
            ses = tepeye_cek(ses)
        yol = os.path.join(a.cikti, f"{a.onek}{s['id']}.wav")
        yaz(yol, ses)
        hiz = len(metin.split()) / max(len(ses) / SR, 1e-9)
        print(f"vo   {os.path.basename(yol):22s} {len(ses) / SR:5.2f}s "
              f"{hiz:3.1f} kel/sn "
              f"(ham {konusma.duration:.2f}, RMS {dbfs(ses):5.1f} dBFS, "
              f"tohum {konusma.seed})  {metin}")


if __name__ == "__main__":
    sys.exit(main())
