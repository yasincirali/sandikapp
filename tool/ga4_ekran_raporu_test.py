"""python3 -m unittest tool/ga4_ekran_raporu_test.py"""
import importlib.util
import pathlib
import unittest

_yol = pathlib.Path(__file__).with_name("ga4_ekran_raporu.py")
_spec = importlib.util.spec_from_file_location("ga4_ekran_raporu", _yol)
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)


def _yanit(*rows):
    return {"rows": [{"dimensionValues": [{"value": ad}],
                      "metricValues": [{"value": str(m)} for m in ms]}
                     for ad, *ms in rows]}


class Ga4EkranRaporuTest(unittest.TestCase):
    def test_huni_hazir_suzgecle_olay_sayar(self):
        tum, girisli = g.istekler(7, "eventName", g.HUNI)
        self.assertIs(tum["dimensionFilter"], g.HUNI)
        self.assertEqual(tum["metrics"][0]["name"], "eventCount")
        self.assertEqual(girisli["dimensionFilter"]["andGroup"]["expressions"],
                         [g.HUNI, g.GIRISLI])

    def test_birlestir_girisli_payina_gore_siralar_ve_suresi_kisi_basi(self):
        tum = _yanit(("Ana sayfa", 900, 300, 6000), ("Zekat", 12, 4, 400))
        girisli = _yanit(("Ana sayfa", 200), ("Zekat", 2))
        liste = g.birlestir(tum, girisli, 200)
        self.assertEqual([s["ad"] for s in liste], ["Ana sayfa", "Zekat"])
        self.assertEqual(liste[0]["sure"], 20)
        self.assertEqual(liste[0]["pay"], 1.0)
        self.assertAlmostEqual(liste[1]["pay"], 0.01)

    def test_yalniz_bir_tarafta_olan_satir_ve_bos_ad(self):
        liste = g.birlestir(_yanit(("", 5, 1, 30)), _yanit(("Yeni", 3)), 100)
        adlar = {s["ad"]: s for s in liste}
        self.assertEqual(adlar["(not set)"]["girisli"], 0)
        self.assertEqual(adlar["Yeni"]["sayi"], 0)
        self.assertEqual(adlar["Yeni"]["sure"], 0)

    def test_payda_sifirsa_bolme_hatasi_yok(self):
        self.assertEqual(g.birlestir(_yanit(("A", 1, 1, 1)), {}, 0)[0]["pay"], 0)

    def test_tablo_esik_altini_isaretler(self):
        liste = g.birlestir(_yanit(("A", 10, 10, 650), ("B", 1, 1, 5)),
                            _yanit(("A", 50), ("B", 1)), 100)
        metin = g.tablo("Ekranlar", "görüntüleme", liste, 100)
        self.assertIn("| A | 10 | 10 | 1 dk 05 sn | 50 | %50,0 |", metin)
        self.assertIn("| B | 1 | 1 | 5 sn | 1 | %1,0 ⚠ |", metin)
        self.assertIn("1 satır: B", metin)

    def test_olay_istegi_girisli_suzgeciyle_birlikte(self):
        tum, girisli = g.istekler(7, "customEvent:ozellik", "ozellik_kullanildi")
        self.assertEqual(tum["metrics"][0]["name"], "eventCount")
        self.assertEqual(tum["dimensionFilter"]["filter"]["fieldName"], "eventName")
        alanlar = [e["filter"]["fieldName"]
                   for e in girisli["dimensionFilter"]["andGroup"]["expressions"]]
        self.assertEqual(alanlar, ["eventName", "signedInWithUserId"])

    def test_ekran_istegi_olay_suzgeci_yok(self):
        tum, girisli = g.istekler(30, "unifiedScreenName", None)
        self.assertNotIn("dimensionFilter", tum)
        self.assertEqual(girisli["dimensionFilter"], g.GIRISLI)
        self.assertEqual(tum["dateRanges"][0]["startDate"], "30daysAgo")

    def test_anahtar_yoksa_atlar(self):
        import os
        eski = {k: os.environ.pop(k, None)
                for k in ("GA4_SERVICE_ACCOUNT_JSON", "GA4_PROPERTY_ID")}
        try:
            self.assertEqual(g.main(), 0)
        finally:
            os.environ.update({k: v for k, v in eski.items() if v})


    def test_ozellik_adlari_dart_enumundan_eksiksiz_okunur(self):
        import re
        metin = g.OZELLIK_DOSYASI.read_text(encoding="utf-8")
        govde = metin[metin.index("enum Ozellik {"):metin.index("const Ozellik(")]
        sayi = len(re.findall(r"^\s*[a-z]\w*\(\s*'", govde, re.M))
        adlar = g.dart_ozellikleri(metin)
        self.assertEqual(len(adlar), sayi)
        self.assertEqual(adlar["varlik_widget"], ("Tek varlık widget'ı", False))
        self.assertTrue(adlar["portfoy_yorumu"][1])

    def test_hic_gorulmeyen_kod_sifirla_eklenir_ve_adlandirilir(self):
        adlar = {"zekat": ("Zekât hesabı", False), "fon_xray": ("Fon dağılımı", True)}
        liste = g.tamamla(g.birlestir(_yanit(("zekat", 3, 2, 10)),
                                      _yanit(("zekat", 2)), 100), adlar)
        self.assertEqual([s["ad"] for s in liste], ["zekat", "fon_xray"])
        metin = g.tablo("Özellik", "olay", liste, 100, adlar)
        self.assertIn("| Zekât hesabı `zekat` | 3 |", metin)
        self.assertIn("| Fon dağılımı ★ `fon_xray` | 0 | 0 |", metin)

    def test_adsiz_ve_bilinmeyen_kod_acikca_yazilir(self):
        self.assertEqual(g._goster("(not set)", {}), g.ADSIZ)
        self.assertEqual(g._goster("yeni_kod", {}), "yeni_kod (adsız kod)")
        self.assertEqual(g._goster("login", None), "login")


if __name__ == "__main__":
    unittest.main()
