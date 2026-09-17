"""App Store (TR) arama sıralaması ölçümü — docs/KURULUM_BUYUME_PLANI_2026_09.md §2.

Neden ayrı betik: App Store Connect sıralama vermez; iTunes Search API açık ve
anahtarsızdır. Aynı sorguyu her hafta aynı biçimde koşmak, "değişti mi" sorusunu
tahminden ölçüme çevirir. Sonuç Apple'ın cihazda gösterdiğiyle birebir değil
(kişiselleştirme, reklam kartı yok) ama göreli hareketi güvenilir yansıtır.

Kullanım:
    python tool/aso_siralama.py            # varsayılan sorgular
    python tool/aso_siralama.py enflasyon "temettü takip"

Not: Windows konsolu cp1254 açar; çıktı utf-8'e zorlanır, JSON utf-8 okunur.
Heredoc'lu inline Python Bash aracında takıldığı için dosya olarak duruyor.
"""

import json
import sys
import urllib.parse
import urllib.request
from datetime import date

APP_ID = 6786837699  # Sandık: Portföy Takibi — com.sandik.app
COUNTRY = "tr"
LIMIT = 200

# Planın izlediği sorgular. Marka sorgularının ikisi de bilinçli: "sandık"
# (noktasız ı) Apple tarafında kırık, "sandik" çalışıyor — ikisinin ayrışması
# sorunun sürüp sürmediğini gösterir.
VARSAYILAN = [
    "sandık", "sandik", "sandık portföy",
    "portföy takibi", "portföy", "hisse takip", "fon takip",
    "enflasyon", "reel getiri", "temettü", "altın takip", "kâr zarar",
]


def sorgula(term: str):
    q = urllib.parse.urlencode(
        {"term": term, "country": COUNTRY, "entity": "software", "limit": LIMIT}
    )
    with urllib.request.urlopen(
        "https://itunes.apple.com/search?" + q, timeout=30
    ) as r:
        d = json.loads(r.read().decode("utf-8"))
    ids = [x["trackId"] for x in d["results"]]
    sira = ids.index(APP_ID) + 1 if APP_ID in ids else None
    ilk3 = [x["trackName"][:22] for x in d["results"][:3]]
    return d["resultCount"], sira, ilk3


def main(argv):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    terimler = argv or VARSAYILAN
    print(f"# {date.today().isoformat()}  App Store {COUNTRY.upper()}  id={APP_ID}")
    print(f"{'sorgu':<18}{'toplam':>7}{'sıra':>6}  ilk 3")
    for t in terimler:
        try:
            toplam, sira, ilk3 = sorgula(t)
        except Exception as e:  # ağ hatası ölçümü kesmesin, satırı işaretle
            print(f"{t:<18}{'?':>7}{'?':>6}  hata: {type(e).__name__}")
            continue
        print(f"{t:<18}{toplam:>7}{(sira if sira else '—'):>6}  {' | '.join(ilk3)}")


if __name__ == "__main__":
    main(sys.argv[1:])
