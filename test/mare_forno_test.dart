import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempo_oficial/dados/mare.dart';

void main() {
  test('Porto do Forno: extremos de 1º/1/2025 perto da tábua oficial', () {
    final e = EstacaoMare.deJson(File('assets/mare/porto_do_forno.json').readAsStringSync());
    expect(e.raioKm, 35);
    final x = e.extremos(DateTime(2025, 1, 1), DateTime(2025, 1, 2));
    // Tábua oficial (hora de Brasília): 04:21 1,10; 10:16 0,47; 15:47 0,90; 22:10 0,10.
    final oficiais = [
      (DateTime(2025, 1, 1, 4, 21), 1.10),
      (DateTime(2025, 1, 1, 10, 16), 0.47),
      (DateTime(2025, 1, 1, 15, 47), 0.90),
      (DateTime(2025, 1, 1, 22, 10), 0.10),
    ];
    for (final (hora, altura) in oficiais) {
      final p = x.reduce((a, b) =>
          (a.hora.difference(hora).abs() < b.hora.difference(hora).abs()) ? a : b);
      expect(p.hora.difference(hora).inMinutes.abs(), lessThanOrEqualTo(75), reason: '$hora');
      expect((p.altura - altura).abs(), lessThanOrEqualTo(0.10), reason: '$hora');
    }
  });

  test('cidade escolhe a estação certa', () {
    // Sem carregar do app: só a regra de distância de cada estação.
    final f = EstacaoMare.deJson(File('assets/mare/porto_do_forno.json').readAsStringSync());
    expect(f.distanciaKm(-22.8794, -42.0187) < f.raioKm, isTrue); // Cabo Frio
    expect(f.distanciaKm(-22.7469, -41.8817) < f.raioKm, isTrue); // Búzios
  });

  test('sem marés de mentira (diferença menor que 5 cm) num ano inteiro', () {
    final e = EstacaoMare.deJson(File('assets/mare/porto_do_forno.json').readAsStringSync());
    final x = e.extremos(DateTime(2026, 1, 1), DateTime(2027, 1, 1));
    for (var i = 1; i + 2 < x.length; i++) {
      expect((x[i].altura - x[i + 1].altura).abs(), greaterThanOrEqualTo(0.05), reason: '${x[i].hora}');
      expect(x[i].alta, isNot(x[i + 1].alta));
    }
  });
}
