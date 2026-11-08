"""python3 -m unittest tool/halka_arz_guncelle_test.py

Ağsız: `getir` sahte sayfalarla değiştirilir, JSON ve sembol dosyası geçici
klasöre kopyalanır. Kilitlenen karar (Ar-Ge 2026-11-08): besleme sessizce
ölmez. Aday var ama kayıt ayrıştırılamadıysa çıkış 2 (iş akışı kırmızı);
en az bir sayfa ayrıştırıldıysa üst `guncelleme` bugüne çekilir.
"""
import importlib.util
import io
import json
import pathlib
import shutil
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

_yol = pathlib.Path(__file__).with_name("halka_arz_guncelle.py")
_spec = importlib.util.spec_from_file_location("halka_arz_guncelle", _yol)
hg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hg)

BUGUN = "2026-11-08"
URL_A = "https://halkarz.com/ornek-enerji-a-s/"
URL_B = "https://halkarz.com/taslak-sirket-a-s/"

ANA = (
    "<html><body><h2>Taslak Arzlar</h2>"
    f'<a href="{URL_A}">Örnek</a><a href="{URL_B}">Taslak</a>'
    "</body></html>"
)


def sirket_sayfasi(kod: str, ad: str) -> str:
    # Sayfa düz metne çevrilince "|KOD|Ad|Halka Arz Bilgileri|Etiket :|değer|"
    # dizisi oluşur; ayrıştırıcı buna bakar. Değerler kurgusal: yalnız test.
    return (
        f"<h1>{kod}</h1><h2>{ad}</h2><h3>Halka Arz Bilgileri</h3><table>"
        f"<tr><td>Bist Kodu :</td><td>{kod}</td></tr>"
        "<tr><td>Halka Arz Tarihi :</td><td>9-10-11 Eylül 2026</td></tr>"
        "<tr><td>Halka Arz Fiyatı/Aralığı :</td><td>10,00 TL</td></tr>"
        "<tr><td>Dağıtım Yöntemi :</td><td>Eşit Dağıtım</td></tr>"
        "<tr><td>Bist İlk İşlem Tarihi :</td><td>17 Eylül 2026</td></tr>"
        "<tr><td>Pazar :</td><td>Yıldız Pazar</td></tr>"
        "</table>"
    )


TASLAK = "<h1>Taslak</h1><table><tr><td>Bist Kodu :</td><td>-</td></tr></table>"


class HalkaArzGuncelleTest(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        kok = hg.KOK
        self.jsonlar = []
        for i, kaynak in enumerate(["docs/data/halka_arz.json", "assets/data/halka_arz.json"]):
            hedef = self.tmp / f"halka_arz_{i}.json"
            shutil.copy(kok / kaynak, hedef)
            self.jsonlar.append(hedef)
        self.sembol = self.tmp / "bist_hisseleri.dart"
        shutil.copy(hg.SEMBOL_DOSYASI, self.sembol)
        self._eski = (hg.JSON_YOLLARI, hg.SEMBOL_DOSYASI, hg.getir)
        hg.JSON_YOLLARI = self.jsonlar
        hg.SEMBOL_DOSYASI = self.sembol

        def geri():
            hg.JSON_YOLLARI, hg.SEMBOL_DOSYASI, hg.getir = self._eski

        self.addCleanup(geri)
        veri = self.oku()
        self.ilk = veri["kayitlar"][0]  # dosyada var olan, alanları dolu kayıt

    def oku(self):
        return json.loads(self.jsonlar[0].read_text(encoding="utf-8"))

    def kur(self, sayfalar: dict):
        def sahte(url):
            if url == hg.ANA_SAYFA:
                return ANA
            sayfa = sayfalar.get(url)
            if isinstance(sayfa, Exception):
                raise sayfa
            return sayfa if sayfa is not None else ""

        hg.getir = sahte

    def kos(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            kod = hg.main(list(argv), bugun=BUGUN)
        return kod, out.getvalue(), err.getvalue()

    def test_sayfa_parcasi_ayristirilir(self):
        k = hg.kayit_kur(URL_A, hg.duz_metin(sirket_sayfasi("ORNEK", "Örnek Enerji A.Ş.")), BUGUN)
        self.assertEqual(k["kod"], "ORNEK")
        self.assertEqual(k["sirket"], "Örnek Enerji A.Ş.")
        self.assertEqual((k["talep_baslangic"], k["talep_bitis"]), ("2026-09-09", "2026-09-11"))
        self.assertEqual(k["fiyat"], 10.0)
        self.assertEqual(k["islem_baslangic"], "2026-09-17")

    def test_aday_var_kayit_yok_cikis_2(self):
        once = self.jsonlar[0].read_bytes()
        self.kur({URL_A: TASLAK, URL_B: RuntimeError("zaman aşımı")})
        kod, out, err = self.kos()
        self.assertEqual(kod, 2)
        self.assertIn("ayrıştırılan: 0", out)
        self.assertNotIn("DEGISIKLIK", out)
        self.assertIn("HATA", err)
        self.assertEqual(self.jsonlar[0].read_bytes(), once)

    def test_aday_yok_cikis_2(self):
        hg.getir = lambda url: "<html>bakım</html>"
        kod, out, _ = self.kos()
        self.assertEqual(kod, 2)
        self.assertNotIn("DEGISIKLIK", out)

    def test_basarili_tarama_tarihi_yeniler(self):
        eski = self.oku()
        self.assertNotEqual(eski["guncelleme"], BUGUN)
        sayfa = sirket_sayfasi(self.ilk["kod"], self.ilk["sirket"])
        self.kur({URL_A: sayfa, URL_B: TASLAK})
        kod, out, _ = self.kos()
        self.assertEqual(kod, 0)
        self.assertIn("DEGISIKLIK_VAR", out)
        self.assertTrue(any(s.startswith("yeni: yok") for s in out.splitlines()), out)
        yeni = self.oku()
        self.assertEqual(yeni["guncelleme"], BUGUN)
        # Kayıtlar birebir aynı: dolu alanın üstüne yazılmaz, kayıt tarihi
        # yalnız alan dolduysa değişir.
        self.assertEqual(yeni["kayitlar"], eski["kayitlar"])
        self.assertEqual(self.jsonlar[0].read_bytes(), self.jsonlar[1].read_bytes())

    def test_ayni_gun_ikinci_kosu_degisiklik_yok(self):
        sayfa = sirket_sayfasi(self.ilk["kod"], self.ilk["sirket"])
        self.kur({URL_A: sayfa})
        self.assertEqual(self.kos()[0], 0)
        once = self.jsonlar[0].read_bytes()
        kod, out, _ = self.kos()
        self.assertEqual(kod, 0)
        self.assertIn("DEGISIKLIK_YOK", out)
        self.assertEqual(self.jsonlar[0].read_bytes(), once)

    def test_islemdeki_yeni_kod_alfabetik_eklenir(self):
        # Gerçek kodlarla çakışmasın diye kurgusal kod; dosyada yok.
        self.assertNotIn("'ZZQQ.IS'", self.sembol.read_text(encoding="utf-8"))
        self.assertNotIn("'AAQQ.IS'", self.sembol.read_text(encoding="utf-8"))
        eklenen = hg.sembol_ekle([("ZZQQ", "Zeta Deneme A.Ş."),
                                  ("AAQQ", "Alfa Deneme Gayrimenkul Yatırım Ortaklığı A.Ş.")],
                                 kuru=False)
        self.assertEqual(eklenen, ["ZZQQ", "AAQQ"])
        metin = self.sembol.read_text(encoding="utf-8")
        self.assertIn("  'AAQQ.IS': 'Alfa Deneme GYO',\n", metin)
        self.assertIn("  'ZZQQ.IS': 'Zeta Deneme',\n", metin)
        harita = metin[metin.index(hg.HARITA_BASI):metin.index("\n};", metin.index(hg.HARITA_BASI))]
        import re
        anahtarlar = re.findall(r"^  '([A-Z0-9]+\.IS)':", harita, re.M)
        self.assertEqual(anahtarlar, sorted(anahtarlar))

    def test_uzun_ad_dart_format_bicimi(self):
        satir = hg.sembol_satiri("UZUN", "Çok Uzun Adlı Deneme Holding Sanayi ve Ticaret Organizasyon Eğitim")
        self.assertEqual(satir, "  'UZUN.IS':\n      'Çok Uzun Adlı Deneme Holding Sanayi ve Ticaret Organizasyon Eğitim',\n")

    def test_dry_run_yazmaz(self):
        once = self.jsonlar[0].read_bytes()
        sayfa = sirket_sayfasi(self.ilk["kod"], self.ilk["sirket"])
        self.kur({URL_A: sayfa})
        kod, out, _ = self.kos("--dry-run")
        self.assertEqual(kod, 0)
        self.assertIn("DEGISIKLIK_VAR", out)
        self.assertEqual(self.jsonlar[0].read_bytes(), once)


if __name__ == "__main__":
    unittest.main()
