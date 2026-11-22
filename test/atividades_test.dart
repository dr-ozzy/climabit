import 'package:flutter_test/flutter_test.dart';
import 'package:tempo_oficial/dados/atividades.dart';
import 'package:tempo_oficial/dados/fontes.dart';

HoraChuva h(DateTime t,
        {int p = 0, double mm = 0, double s = 22, double v = 10, double uv = 2, bool dia = true,
        int codigo = 1}) =>
    HoraChuva(
        hora: t,
        probabilidade: p,
        milimetros: mm,
        sensacao: s,
        temperatura: s,
        ventoKmh: v,
        uv: uv,
        dia: dia,
        codigo: codigo);

void main() {
  final t = DateTime(2026, 11, 23, 6);

  test('regras de cada atividade', () {
    expect(avaliarHora(Atividade.caminhar, h(t)).nota, Nota.boa);
    expect(avaliarHora(Atividade.caminhar, h(t, p: 60)).nota, Nota.ruim);
    expect(avaliarHora(Atividade.caminhar, h(t, p: 30)).nota, Nota.regular);
    expect(avaliarHora(Atividade.caminhar, h(t, s: 35)).nota, Nota.ruim);
    expect(avaliarHora(Atividade.caminhar, h(t, uv: 10)).motivos, ['UV 10']);
    expect(avaliarHora(Atividade.praia, h(t, s: 28, dia: false)).nota, Nota.ruim);
    expect(avaliarHora(Atividade.praia, h(t, s: 28)).nota, Nota.boa);
    expect(avaliarHora(Atividade.secarRoupa, h(t, p: 25)).nota, Nota.ruim);
    expect(avaliarHora(Atividade.pedalar, h(t, v: 35)).nota, Nota.ruim);
    expect(avaliarHora(Atividade.caminhar, h(t, codigo: 95)).motivos, contains('trovoada'));
  });

  test('trechos bons seguidos', () {
    final l = [
      for (var i = 0; i < 6; i++)
        avaliarHora(Atividade.caminhar, h(t.add(Duration(hours: i)), p: i == 2 ? 70 : 0)),
    ];
    final r = trechosBons(l);
    expect(r.length, 2);
    expect(r[0], (DateTime(2026, 11, 23, 6), DateTime(2026, 11, 23, 8)));
    expect(r[1], (DateTime(2026, 11, 23, 9), DateTime(2026, 11, 23, 12)));
  });

  test('rotina: próxima sessão, avaliação e previsão que não alcança', () {
    // 23/11/2026 é segunda-feira.
    const r = Rotina(atividade: Atividade.caminhar, dias: {1, 3, 5}, inicio: 6, fim: 8);
    expect(r.proxima(DateTime(2026, 11, 23, 5)), DateTime(2026, 11, 23, 6));
    expect(r.proxima(DateTime(2026, 11, 23, 7)), DateTime(2026, 11, 23, 6)); // em andamento
    expect(r.proxima(DateTime(2026, 11, 23, 9)), DateTime(2026, 11, 25, 6));
    final horas = [
      for (var i = 0; i < 30; i++) h(DateTime(2026, 11, 23, 5).add(Duration(hours: i)), p: 40),
    ];
    final (nota, motivos) = avaliarRotina(r, horas, DateTime(2026, 11, 23, 5))!;
    expect(nota, Nota.regular);
    expect(motivos, ['chuva (até 40 %)']);
    expect(avaliarRotina(r, horas, DateTime(2026, 11, 23, 9)), isNull);
    final copia = Rotina.lerLista(Rotina.gravarLista([r])).single;
    expect(copia.dias, {1, 3, 5});
    expect(copia.atividade, Atividade.caminhar);
  });
}
