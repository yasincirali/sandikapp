"""python3 -m unittest tool/play_istatistik_test.py"""
import datetime as dt
import importlib.util
import pathlib
import unittest

_yol = pathlib.Path(__file__).with_name("play_istatistik.py")
_spec = importlib.util.spec_from_file_location("play_istatistik", _yol)
pi = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pi)

CSV = (
    "Date,Package Name,Daily Device Installs,Daily Device Uninstalls,"
    "Daily User Installs,Daily User Uninstalls,Active Device Installs\n"
    "2026-11-03,com.sandik.app,9,1,9,1,40\n"
    "2026-11-04,com.sandik.app,5,0,4,0,44\n"
    "2026-11-05,com.sandik.app,3,2,3,2,45\n"
)


class PlayIstatistikTest(unittest.TestCase):
    def test_kurulum_pencere_disini_saymaz(self):
        k = pi.kurulum_ozeti(CSV, dt.date(2026, 11, 4), dt.date(2026, 11, 10))
        self.assertEqual(k, {"kurulum": 7, "kaldırma": 2, "gün": 2, "aktif cihaz": 45})

    def test_kurulum_bos_csv(self):
        k = pi.kurulum_ozeti("", dt.date(2026, 11, 4), dt.date(2026, 11, 10))
        self.assertEqual(k["kurulum"], 0)
        self.assertIsNone(k["aktif cihaz"])

    def test_vitals_ortalama_yuzde(self):
        yanit = {"rows": [
            {"metrics": [{"metric": "crashRate", "decimalValue": {"value": "0.01"}}]},
            {"metrics": [{"metric": "crashRate", "decimalValue": {"value": "0.03"}},
                         {"metric": "userPerceivedCrashRate"}]},
        ]}
        o = pi.vitals_ozeti(yanit, ["crashRate", "userPerceivedCrashRate"])
        self.assertAlmostEqual(o["crashRate"], 2.0)
        self.assertIsNone(o["userPerceivedCrashRate"])


if __name__ == "__main__":
    unittest.main()
