import 'package:flutter_test/flutter_test.dart';
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
