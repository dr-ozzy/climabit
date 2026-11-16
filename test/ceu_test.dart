import 'package:flutter_test/flutter_test.dart';
import 'package:tempo_oficial/dados/fontes.dart';
import 'package:tempo_oficial/dados/widget_tela.dart';
import 'package:tempo_oficial/telas/ceu.dart';
import 'package:tempo_oficial/util/formatos.dart';

void main() {
  test('céu: chuva medida manda no fundo; nuvens vêm da previsão', () {
    expect(estadoCeu(resumoPeriodo: 'Muitas nuvens com chuva', chuvaUltimaHora: 0),
        EstadoCeu.nublado);
    expect(estadoCeu(resumoPeriodo: 'Céu claro', chuvaUltimaHora: 1.2), EstadoCeu.chuva);
    expect(estadoCeu(resumoPeriodo: 'Pancadas de chuva e trovoadas', chuvaUltimaHora: 3),
        EstadoCeu.trovoada);
    expect(estadoCeu(resumoPeriodo: 'Céu claro', chuvaUltimaHora: null), EstadoCeu.limpo);
    expect(estadoCeu(resumoPeriodo: 'Poucas nuvens', chuvaUltimaHora: 0), EstadoCeu.parcial);
    expect(estadoCeu(resumoPeriodo: 'Parcialmente nublado', chuvaUltimaHora: 0),
        EstadoCeu.parcial);
    expect(nomeCeu(EstadoCeu.limpo, true), 'Céu limpo');
    expect(nomeCeu(EstadoCeu.limpo, false), 'Ensolarado');
  });

  test('avaliações', () {
    expect(avaliarUmidade(80).$1, 'Úmido');
    expect(avaliarUmidade(85).$1, 'Muito úmido');
    expect(avaliarUmidade(45).$1, 'Confortável');
    expect(avaliarSensacao(28).$1, 'Quente');
    expect(avaliarVento(9).$1, 'Fraco');
    expect(avaliarChuva(0).$1, 'Sem chuva');
    expect(avaliarUv(2).$1, 'Baixo');
  });

  test('visibilidade, pressão e ponto de orvalho', () {
    expect(avaliarVisibilidade(10).$1, 'Boa');
    expect(avaliarVisibilidade(6).$1, 'Moderada');
    expect(avaliarVisibilidade(0.5).$1, 'Nevoeiro');
    expect(avaliarPressao(1000).$1, 'Baixa pressão');
    expect(avaliarPressao(1013).$1, 'Normal');
    expect(avaliarOrvalho(23).$1, 'Muito abafado');
    expect(orvalhoCalculado(25, 100)!.round(), 25);
    expect(orvalhoCalculado(30, 50)!.round(), 18);
    expect(visibilidadeMetarKm('10+')!.round(), 16);
    expect(visibilidadeMetarKm(6)!.round(), 10);
  });

  test('barra 4 x 1: 3 horas de 3 em 3, depois de agora', () {
    final agora = DateTime(2026, 11, 16, 13, 40);
    final horas = [
      for (var i = 0; i < 24; i++)
        HoraChuva(hora: DateTime(2026, 11, 16, 13).add(Duration(hours: i)), temperatura: 20.0 + i),
    ];
    expect(horasDoDia(horas, agora).map((h) => h.hora.hour).toList(), [15, 18, 21]);
  });

  test('trenó só de 23 a 25 de dezembro', () {
    expect(ehNatal(DateTime(2026, 12, 22)), isFalse);
    expect(ehNatal(DateTime(2026, 12, 23)), isTrue);
    expect(ehNatal(DateTime(2026, 12, 25, 23, 59)), isTrue);
    expect(ehNatal(DateTime(2026, 12, 26)), isFalse);
    expect(ehNatal(DateTime(2026, 11, 24)), isFalse);
  });

  test('cenário do tipo de dia', () {
    Paisagem p({EstadoCeu e = EstadoCeu.parcial, double t = 25, double? s, double chuva = 0,
            String r = ''}) =>
        escolherPaisagem(
            estado: e, temperatura: t, sensacao: s, chuvaUltimaHora: chuva, resumo: r);
    // Neve só quando está nevando de fato.
    expect(p(t: -5, e: EstadoCeu.limpo), Paisagem.campo);
    expect(p(t: 8), isNot(Paisagem.neve));
    expect(p(r: 'Possibilidade de geada'), isNot(Paisagem.neve));
    expect(p(r: 'Chance de neve'), isNot(Paisagem.neve));
    expect(p(t: -2, r: 'Neve fraca'), Paisagem.neve);
    expect(p(t: 1, e: EstadoCeu.chuva, r: 'Chuva e neve'), Paisagem.neve);
    expect(p(t: 33, s: 38), Paisagem.vulcao);
    expect(p(e: EstadoCeu.chuva, chuva: 12), Paisagem.cachoeiras);
    expect(p(e: EstadoCeu.trovoada, chuva: 1), Paisagem.cachoeiras);
    expect(p(e: EstadoCeu.chuva, chuva: 1), Paisagem.morros);
    expect(p(e: EstadoCeu.limpo), Paisagem.campo);
    expect(p(e: EstadoCeu.nublado), Paisagem.morros);
  });
}
