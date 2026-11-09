"""python3 -m unittest tool/asc_tanitim_tufe_test.py"""
import datetime as dt
import importlib.util
import json
import pathlib
import unittest

_yol = pathlib.Path(__file__).with_name("asc_tanitim_tufe.py")
_spec = importlib.util.spec_from_file_location("asc_tanitim_tufe", _yol)
at = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(at)

KALIP = json.loads(at.AYAR.read_text(encoding="utf-8"))["kalip"]
AYLAR = [{"ay": "2025-10", "endeks": 100.0}, {"ay": "2026-09", "endeks": 130.0},
         {"ay": "2026-10", "endeks": 132.875}]


class TanitimTufeTest(unittest.TestCase):
    def test_gecen_ay_yillik_iki_hane(self):
        m, _ = at.metin_kur(AYLAR, dt.date(2026, 11, 3), KALIP)
        self.assertIn("Ekim ayında yıllık enflasyon %32,88 oldu.", m)
        self.assertLessEqual(len(m), at.SINIR)

    def test_gecen_ay_yoksa_yazmaz(self):
        m, neden = at.metin_kur(AYLAR[:2], dt.date(2026, 11, 3), KALIP)
        self.assertIsNone(m)
        self.assertIn("2026-10", neden)

    def test_on_iki_ay_once_yoksa_yazmaz(self):
        m, _ = at.metin_kur(AYLAR[1:], dt.date(2026, 11, 3), KALIP)
        self.assertIsNone(m)

    def test_ocakta_aralik(self):
        a = [{"ay": "2025-12", "endeks": 100.0}, {"ay": "2026-12", "endeks": 125.0}]
        m, _ = at.metin_kur(a, dt.date(2027, 1, 3), KALIP)
        self.assertTrue(m.startswith("Aralık ayında yıllık enflasyon %25,00"))

    def test_uzun_kalip_yazilmaz(self):
        m, neden = at.metin_kur(AYLAR, dt.date(2026, 11, 3), "x" * 171 + "{ay}{yillik}")
        self.assertIsNone(m)
        self.assertIn("karakter", neden)


if __name__ == "__main__":
    unittest.main()
