import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempo_oficial/dados/canada.dart';
import 'package:tempo_oficial/dados/municipios.dart';

void main() {
  // Resposta real do ECCC para Toronto, guardada em 14/11/2026.
  final dados = lerCanada(File('test/dados/eccc_toronto.json').readAsStringSync());

  test('Canadá: medição atual', () {
    final m = dados.medicao!;
    expect(m.temperatura, 4.9);
    expect(m.umidade, 82);
    expect(m.ventoKmh, 30);
    expect(m.rajadaKmh, 41);
    expect(m.sensacao, -4);
    expect(m.codigo, 'YYZ');
    expect(m.latitude, closeTo(43.68, 0.01));
    expect(m.longitude, closeTo(-79.63, 0.01));
  });

  test('Canadá: previsão por dia e por hora em português', () {
    expect(dados.dias.length, greaterThanOrEqualTo(6));
    expect(dados.dias.first.minima, 2);
    expect(dados.dias[1].maxima, 7);
    expect(dados.dias[1].uv, 1);
    expect(dados.dias[1].resumo, 'Nublado');
    expect(dados.horas.length, 24);
    expect(dados.horas.first.temperatura, 6);
    expect(dados.horas.first.probabilidade, 40);
  });

  test('código numérico das cidades do Canadá', () {
    expect(codigoCanada('on-143'), -9143);
    expect(codigoCanada('ab-1'), -1001);
  });

  test('Canadá: avisos oficiais em português', () {
    final a = lerCanada(File('test/dados/eccc_aviso.json').readAsStringSync()).alertas;
    expect(a.length, 2);
    expect(a.first.descricao, 'Aviso: chuva forte');
    expect(a.last.descricao, 'Aviso: ventania');
    expect(a.first.severidade, 'Perigo Potencial');
    expect(a.first.inicio.toUtc(), DateTime.utc(2026, 11, 14, 12, 27, 57));
    expect(a.first.fim.toUtc(), DateTime.utc(2026, 11, 15, 4, 27, 57));
    expect(a.first.id, isNot(a.last.id));
  });

  test('Canadá: descarta frio do vento ou humidex sem sentido', () {
    // ECCC em 18/11/2026: 13 °C com frio do vento de −4 °C (valor antigo).
    expect(sensacaoCanadaPlausivel(13, -4, null), isNull);
    expect(sensacaoCanadaPlausivel(4.9, -4, null), -4);
    expect(sensacaoCanadaPlausivel(30, null, 38), 38);
    expect(sensacaoCanadaPlausivel(15, null, 22), isNull);
    expect(sensacaoCanadaPlausivel(null, -4, null), isNull);
  });
}
