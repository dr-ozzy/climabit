import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tempo_oficial/dados/fontes.dart';
import 'package:tempo_oficial/dados/notificacoes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));
  final agora = DateTime(2026, 11, 16, 14, 5);
  List<Faixa15> faixas(List<double> mm, {int codigo = 61, double neve = 0}) => [
        for (var i = 0; i < mm.length; i++)
          Faixa15(
              inicio: DateTime(2026, 11, 16, 14).add(Duration(minutes: 15 * i)),
              milimetros: mm[i],
              codigo: codigo,
              neve: neve),
      ];

  test('avisa a primeira faixa com chuva nas próximas 2 horas', () {
    final a = avisoDeChuva(faixas([0, 0, 0.1, 0.6, 1]), agora)!;
    expect(a.inicio, DateTime(2026, 11, 16, 14, 45));
    expect(a.agora, isFalse);
    expect(a.titulo('Niterói'), 'Deve começar a chover por volta das 14:45');
    expect(a.descricao, 'chuva fraca');
  });

  test('sem chuva, ou só depois de 2 horas, não avisa', () {
    expect(avisoDeChuva(faixas([0, 0, 0.1, 0]), agora), isNull);
    final tarde = [
      for (var i = 0; i < 12; i++)
        Faixa15(inicio: DateTime(2026, 11, 16, 14).add(Duration(minutes: 15 * i)),
            milimetros: i >= 9 ? 2.0 : 0.0, codigo: 61),
    ];
    expect(avisoDeChuva(tarde, agora), isNull);
  });

  test('tipo pelo código: garoa, neve, trovoada; chuva já começando', () {
    expect(avisoDeChuva(faixas([0, 0.3], codigo: 53), agora)!.verbo, 'garoar');
    expect(avisoDeChuva(faixas([0, 0.5], codigo: 73), agora)!.verbo, 'nevar');
    final t = avisoDeChuva(faixas([3, 3], codigo: 95), agora)!;
    expect(t.agora, isTrue);
    expect(t.titulo('Niterói'), 'Começou a chover com trovoada em Niterói');
    expect(t.descricao, 'chuva forte com trovoada');
  });

  test('não repete o aviso do mesmo episódio', () {
    final a = avisoDeChuva(faixas([0, 0, 0.5]), agora)!;
    final guardado = '3303302|${a.inicio.millisecondsSinceEpoch}';
    expect(mesmoEpisodioDeChuva(a, null, 3303302, agora), isFalse);
    expect(mesmoEpisodioDeChuva(a, guardado, 3303302, agora), isTrue);
    expect(mesmoEpisodioDeChuva(a, guardado, 3304557, agora), isFalse, reason: 'outra cidade');
    // Chuva continuando 3 horas depois do aviso: ainda o mesmo episódio.
    final depois = agora.add(const Duration(hours: 3));
    final continua = AvisoChuva(inicio: depois, verbo: 'chover', descricao: 'chuva fraca', agora: true);
    expect(mesmoEpisodioDeChuva(continua, guardado, 3303302, depois), isTrue);
  });
}
