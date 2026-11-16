import 'package:flutter_test/flutter_test.dart';
import 'package:tempo_oficial/dados/atualizacao.dart';

void main() {
  test('compara versões', () {
    expect(versaoMaisNova('1.18.0', '1.17.0'), isTrue);
    expect(versaoMaisNova('v1.18.1', '1.18.0'), isTrue);
    expect(versaoMaisNova('1.10.0', '1.9.9'), isTrue);
    expect(versaoMaisNova('2.0.0', '1.99.99'), isTrue);
    expect(versaoMaisNova('1.18.0', '1.18.0'), isFalse);
    expect(versaoMaisNova('1.17.5', '1.18.0'), isFalse);
  });

  test('lê a release do GitHub e só aceita APK do próprio repositório', () {
    final release = {
      'tag_name': 'v1.19.0',
      'body': 'Novidades',
      'assets': [
        {'name': 'notas.txt', 'browser_download_url': 'https://github.com/$repositorioApp/x.txt'},
        {
          'name': 'climabit-1.19.0.apk',
          'size': 58000000,
          'browser_download_url':
              'https://github.com/$repositorioApp/releases/download/v1.19.0/climabit-1.19.0.apk',
        },
      ],
    };
    final v = lerRelease(release, '1.18.0');
    expect(v?.versao, '1.19.0');
    expect(v?.urlApk, endsWith('climabit-1.19.0.apk'));
    expect(v?.tamanhoMb, '55 MB');

    expect(lerRelease(release, '1.19.0'), isNull, reason: 'mesma versão');
    final deFora = {
      'tag_name': 'v1.19.0',
      'assets': [
        {'name': 'a.apk', 'browser_download_url': 'https://exemplo.com/a.apk'},
      ],
    };
    expect(lerRelease(deFora, '1.18.0'), isNull, reason: 'APK de outro site');
  });
}
