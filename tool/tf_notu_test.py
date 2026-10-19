"""python3 -m unittest tool/tf_notu_test.py"""
import importlib.util
import pathlib
import unittest

_yol = pathlib.Path(__file__).with_name("tf_notu.py")
_spec = importlib.util.spec_from_file_location("tf_notu", _yol)
tf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tf)


class TfNotuTest(unittest.TestCase):
    def test_bolum_sonraki_basliga_kadar(self):
        g = "x\n## TestFlight'ta test et\n- A yap\n- [ ] B yap\n<!-- not -->\n## HIG kontrolü\n- C"
        self.assertEqual(tf.test_bolumu(g), ["• A yap", "• B yap"])

    def test_bolumsuz_uygulama_disi_sessiz(self):
        self.assertIsNone(tf.pr_metni(1, "Doküman", "", ["docs/a.md"]))
        self.assertIn("görünen bir değişiklik yok",
                      tf.notu_kur([{"no": 1, "baslik": "x", "govde": "", "dosyalar": ["docs/a"]}]))

    def test_numara_yazilmaz(self):
        g = "## TestFlight'ta test et\n- Bir hisse sat"
        m = tf.notu_kur([{"no": 212, "baslik": "fix(0156): uuid", "govde": g, "dosyalar": []}])
        self.assertNotIn("212", m)
        self.assertNotIn("uuid", m)
        self.assertIn("• Bir hisse sat", m)

    def test_sinir(self):
        uzun = [{"no": i, "baslik": "x" * 400, "govde": "", "dosyalar": ["lib/a"]} for i in range(20)]
        self.assertLessEqual(len(tf.notu_kur(uzun)), tf.LIMIT)

    def test_bos(self):
        self.assertEqual(tf.notu_kur([]), "")


if __name__ == "__main__":
    unittest.main()
