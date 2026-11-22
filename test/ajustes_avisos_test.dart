import 'package:flutter_test/flutter_test.dart';
import 'package:tempo_oficial/dados/fontes.dart';
import 'package:tempo_oficial/dados/notificacoes.dart';

Alerta alerta(String severidade, String cor) => Alerta(
    id: '1',
    descricao: 'Tempestade',
    severidade: severidade,
    cor: cor,
    inicio: DateTime(2026, 11, 22),
    fim: DateTime(2026, 11, 23));

void main() {
  test('nível do alerta pela cor oficial', () {
    expect(nivelDoAlerta(alerta('Perigo Potencial', '#FFFE00')), 0);
    expect(nivelDoAlerta(alerta('Perigo', '#F96602')), 1);
    expect(nivelDoAlerta(alerta('Grande Perigo', '#FF0000')), 2);
  });

  test('horário de silêncio, inclusive virando a noite', () {
    expect(emSilencio(null, DateTime(2026, 1, 1, 23)), isFalse);
    expect(emSilencio((22, 7), DateTime(2026, 1, 1, 23)), isTrue);
    expect(emSilencio((22, 7), DateTime(2026, 1, 1, 3)), isTrue);
    expect(emSilencio((22, 7), DateTime(2026, 1, 1, 7)), isFalse);
    expect(emSilencio((13, 15), DateTime(2026, 1, 1, 14)), isTrue);
    expect(emSilencio((13, 15), DateTime(2026, 1, 1, 16)), isFalse);
  });

  test('aviso de chuva só a partir de chuva moderada', () {
    final agora = DateTime(2026, 11, 22, 10);
    final faixas = [
      Faixa15(inicio: agora.add(const Duration(minutes: 15)), milimetros: 0.3, codigo: 61),
      Faixa15(inicio: agora.add(const Duration(minutes: 30)), milimetros: 0.9, codigo: 63),
    ];
    expect(avisoDeChuva(faixas, agora)!.inicio, faixas[0].inicio);
    expect(avisoDeChuva(faixas, agora, limiar15: limiarModerada15)!.inicio, faixas[1].inicio);
  });
}
