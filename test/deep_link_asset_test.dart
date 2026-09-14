import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/deep_link_router.dart';

/// `sandik://asset/<id>` — varlık detayına derin bağlantı (Faz 3.8).
void main() {
  test('asset host → id', () {
    expect(DeepLinkRouter.hedefVarlikId(Uri.parse('sandik://asset/abc-123')),
        'abc-123');
    expect(
        DeepLinkRouter.hedefVarlikId(Uri.parse('sandik://asset/abc-123/')),
        'abc-123');
  });

  test('başka host / şema / fazla segment → null', () {
    expect(DeepLinkRouter.hedefVarlikId(Uri.parse('sandik://widget')), isNull);
    expect(DeepLinkRouter.hedefVarlikId(Uri.parse('https://asset/x')), isNull);
    expect(DeepLinkRouter.hedefVarlikId(Uri.parse('sandik://asset')), isNull);
    expect(DeepLinkRouter.hedefVarlikId(Uri.parse('sandik://asset/a/b')), isNull);
    expect(DeepLinkRouter.hedefVarlikId(null), isNull);
  });

  test('asset bağlantısı sekme hedefi DEĞİLDİR', () {
    // Sekme eşlemesi varlık bağlantısını tanımaz; iki yol birbirine karışmaz.
    expect(DeepLinkRouter.hedefSekme(Uri.parse('sandik://asset/abc')), isNull);
  });
}
