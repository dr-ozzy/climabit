import 'package:flutter_test/flutter_test.dart';
import 'package:tempo_oficial/dados/erros.dart';

void main() {
  test('causa provável de cada erro', () {
    expect(causaDoErro("Fonte indisponível: ClientException with SocketException: Failed host lookup: 'x'"),
        startsWith('sem internet'));
    expect(causaDoErro('Fonte indisponível: HandshakeException: CERTIFICATE_VERIFY_FAILED'),
        contains('data e a hora'));
    expect(causaDoErro('Fonte indisponível: TimeoutException after 0:00:20'), 'demorou demais para responder');
    expect(causaDoErro('Fonte indisponível: código 503'), contains('fora do ar'));
    expect(causaDoErro('Fonte indisponível: código 403'), contains('recusou'));
    expect(causaDoErro('formato inesperado'), 'a fonte mudou o formato dos dados');
    expect(causaDoErro('Fonte indisponível: sem cópia guardada'), 'sem internet e sem dados guardados');
    expect(causaDoErro(null), 'sem resposta');
  });
}
