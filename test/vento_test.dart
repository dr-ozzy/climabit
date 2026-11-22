import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempo_oficial/dados/vento.dart';

void main() {
  test('direção do Open-Meteo vira componentes leste/norte', () {
    // Vento do norte (0°) sopra para o sul.
    var (u, v) = componentesVento(10, 0);
    expect(u, closeTo(0, 1e-9));
    expect(v, closeTo(-10, 1e-9));
    // Vento do leste (90°) sopra para o oeste.
    (u, v) = componentesVento(10, 90);
    expect(u, closeTo(-10, 1e-9));
    expect(v, closeTo(0, 1e-9));
    // Vento do sudoeste (225°) sopra para o nordeste.
    (u, v) = componentesVento(10, 225);
    expect(u, greaterThan(0));
    expect(v, greaterThan(0));
  });

  test('virada de vento não passa por calmaria', () {
    final (ua, va) = componentesVento(30, 0);
    final (ub, vb) = componentesVento(30, 180);
    final (u, v) = interpolarVento(ua, va, ub, vb, 0.5);
    expect(u * u + v * v, closeTo(900, 1e-6));
    // De 350° para 10°: passa por 0°, não por 180°.
    final (a1, b1) = componentesVento(20, 350);
    final (a2, b2) = componentesVento(20, 10);
    final (x, y) = interpolarVento(a1, b1, a2, b2, 0.5);
    expect(x, closeTo(0, 1e-6));
    expect(y, closeTo(-20, 1e-6));
  });

  test('área em km não achata em latitude alta', () {
    final rio = areaAoRedor(-22.9, -43.1);
    final toronto = areaAoRedor(43.7, -79.4);
    expect(rio.proporcao, closeTo(1, 0.05));
    expect(toronto.proporcao, closeTo(1, 0.05));
  });

  test('lê a grade e interpola', () {
    final area = areaAoRedor(-22.9, -43.1);
    const n = 3;
    final pontos = [
      for (var p = 0; p < n * n; p++)
        {
          'hourly': {
            'time': ['2026-11-22T15:00', '2026-11-22T16:00'],
            'wind_speed_10m': [10, 20],
            'wind_direction_10m': [270, 270],
            'precipitation': [p.toDouble(), 0],
            'cloud_cover': [50, 100],
          },
        },
    ];
    final g = lerGradeVento(jsonEncode(pontos), area,
        n: n, obtidoEm: DateTime(2026, 11, 22))!;
    expect(g.horas.length, 2);
    expect(g.horas.first, DateTime.utc(2026, 11, 22, 15).toLocal());
    final (u, v) = g.ventoEm(0.5, 0.5, 0);
    expect(u, closeTo(10, 1e-4)); // vento de oeste sopra para leste
    expect(v, closeTo(0, 1e-4));
    final (u2, _) = g.ventoEm(0.5, 0.5, 0.5);
    expect(u2, closeTo(15, 1e-4));
    // Chuva no centro da grade 3×3 = ponto 4.
    expect(g.valorEm(g.chuva, 0.5, 0.5, 0), closeTo(4, 1e-4));
    expect(lerGradeVento(jsonEncode(pontos.sublist(1)), area,
        n: n, obtidoEm: DateTime(2026)), isNull);
  });
}
