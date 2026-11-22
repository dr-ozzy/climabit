import 'package:flutter_test/flutter_test.dart';
import 'package:tempo_oficial/dados/fontes.dart';
import 'package:tempo_oficial/telas/ceu.dart';
import 'package:tempo_oficial/telas/resumo.dart';

void main() {
  final agora = DateTime(2026, 11, 22, 12, 10);
  List<HoraChuva> horas(List<int> chances, {double temp = 30, int codigo = 80}) => [
        for (var i = 0; i < chances.length; i++)
          HoraChuva(
              hora: DateTime(2026, 11, 22, 12 + i),
              probabilidade: chances[i],
              temperatura: temp,
              codigo: codigo),
      ];

  test('frase do resumo', () {
    expect(fraseResumo(EstadoCeu.parcial, false, horas([5, 10, 10, 10, 10, 40, 60]), agora),
        'Parcialmente nublado até as 16h; pancadas de chuva a partir das 17h (40 %).');
    expect(fraseResumo(EstadoCeu.limpo, false, horas([5, 5, 5]), agora),
        'Ensolarado, sem chuva prevista nas próximas 12 horas.');
    expect(fraseResumo(EstadoCeu.chuva, false, horas([80, 70, 20]), agora),
        'Chovendo agora; deve melhorar por volta das 14h.');
    expect(fraseResumo(EstadoCeu.limpo, false, horas([5, 5], temp: 36), agora),
        'Ensolarado, sem chuva prevista nas próximas 12 horas. Calor forte: até 36° às 12h.');
  });

  test('chance na próxima hora e comparação com ontem', () {
    expect(chanceProximaHora(horas([7, 20]), agora), 'Chance de chuva na próxima hora: 20 %');
    final ontem = [HoraChuva(hora: DateTime(2026, 11, 21, 12), temperatura: 27)];
    expect(comparacaoOntem(horas([0], temp: 31), ontem, agora),
        '4° mais quente que ontem a esta hora.');
    expect(comparacaoOntem(horas([0], temp: 27.5), ontem, agora),
        'Temperatura parecida com a de ontem a esta hora.');
    expect(comparacaoOntem(horas([0]), const [], agora), isNull);
  });

  test('aviso de tempo marcante nos próximos dias', () {
    DiaPrevisao d(int dia, String resumo, {int? max, int? min}) => DiaPrevisao(
        dia: DateTime(2026, 11, dia), fonte: 'INMET', resumo: resumo, maxima: max, minima: min);
    final agora = DateTime(2026, 11, 22, 10); // domingo
    expect(avisoProximosDias([d(22, 'Tempestade'), d(23, 'Sol', max: 30)], agora), isNull);
    expect(avisoProximosDias([d(23, 'Pancadas de chuva e trovoadas isoladas')], agora), isNull);
    expect(avisoProximosDias([d(23, 'Sol'), d(26, 'Chuva forte')], agora),
        'Quinta-feira: chuva forte prevista.');
    expect(avisoProximosDias([d(23, 'Sol', max: 36)], agora), 'Amanhã: calor forte (máx. 36°).');
    expect(avisoProximosDias([d(24, 'Sol', min: 8)], agora), 'Terça-feira: frio (mín. 8°).');
    expect(avisoProximosDias([d(24, 'Sun', min: 8)], agora, canada: true), isNull);
  });
}
