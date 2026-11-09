"""python3 -m unittest tool/tufe_web_test.py"""
import datetime as dt
import importlib.util
import pathlib
import unittest

_yol = pathlib.Path(__file__).with_name("tufe_web.py")
_spec = importlib.util.spec_from_file_location("tufe_web", _yol)
tw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tw)

YENI = "TUIK-TP.TUKFIY2025.GENEL"
ESKI = "TUIK-TP.FG.J0"


class TufeWebTest(unittest.TestCase):
    def test_bos_tablo_bos_liste(self):
        v = tw.json_kur([], dt.date(2026, 10, 20))
        self.assertEqual(v["aylar"], [])
        self.assertIsNone(v["seri"])

    def test_yalniz_son_seri_ve_sirali(self):
        satir = [
            {"period": "2026-09", "endeks": "130.5", "source": YENI},
            {"period": "2025-12", "endeks": 3500.1, "source": ESKI},
            {"period": "2026-08", "endeks": 128.25, "source": YENI},
        ]
        v = tw.json_kur(satir, dt.date(2026, 10, 20))
        self.assertEqual(v["seri"], YENI)
        self.assertEqual(v["aylar"], [{"ay": "2026-08", "endeks": 128.25},
                                      {"ay": "2026-09", "endeks": 130.5}])

    def test_bu_ay_ve_bozuk_satir_yazilmaz(self):
        satir = [
            {"period": "2026-09", "endeks": 130.5, "source": YENI},
            {"period": "2026-10", "endeks": 132.0, "source": YENI},
            {"period": "2026-07", "endeks": None, "source": YENI},
            {"period": "2026-06", "endeks": 0, "source": YENI},
        ]
        v = tw.json_kur(satir, dt.date(2026, 10, 3))
        self.assertEqual([a["ay"] for a in v["aylar"]], ["2026-09"])

    def test_zaman_damgasi_yok(self):
        # Veri aynıyken JSON da birebir aynı kalmalı (gereksiz PR açılmaz).
        satir = [{"period": "2026-09", "endeks": 130.5, "source": YENI}]
        a = tw.yazi(tw.json_kur(satir, dt.date(2026, 10, 20)))
        b = tw.yazi(tw.json_kur(satir, dt.date(2026, 10, 31)))
        self.assertEqual(a, b)


if __name__ == "__main__":
    unittest.main()
