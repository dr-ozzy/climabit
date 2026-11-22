import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempo_oficial/dados/alertas_omm.dart';

void main() {
  // Trecho do resumo da OMM de 2026-11-22 (acentos perdidos pela própria OMM).
  final corpo = jsonEncode({
    'itemCount': 3,
    'items': [
      {
        'id': 'urn:oid:2.49.0.0.76.0.2026.28747.1',
        'event': 'Tempestade',
        'headline': 'Aviso de Tempestade. Severidade Grau: Moderate',
        'sent': '2026-11-22 14:35:31',
        'expires': '2026-11-25 02:59:00',
        'areaDesc': 'Aviso para as �reas: Tri�ngulo Mineiro/Alto Parana�ba, '
            'Norte Central Paranaense, Metropolitana do Rio de Janeiro',
        'url': 'br-inmet-pt/2026/11/22/11/38/a.xml',
      },
      {
        'id': 'urn:oid:2.49.0.0.76.0.2026.28744.1',
        'event': 'Decl�nio de Temperatura',
        'headline': 'Aviso. Severidade Grau: Severe',
        'sent': '2026-11-22 11:20:00',
        'expires': '2026-11-23 02:59:00',
        'areaDesc': 'Aviso para as �reas: Tri�ngulo Mineiro/Alto Parana�ba',
        'url': 'br-inmet-pt/2026/11/22/08/20/b.xml',
      },
      {
        'id': 'urn:oid:2.49.0.0.124.0.1',
        'event': 'Snow',
        'headline': 'Snowfall warning',
        'sent': '2026-11-22 10:00:00',
        'expires': '2026-11-23 10:00:00',
        'areaDesc': 'Metropolitana do Rio de Janeiro',
        'url': 'ca-msc-xx/a.xml',
      },
    ],
  });

  test('aviso do INMET pela mesorregião, com número, nível e horários', () {
    final r = lerAlertasOmm(corpo, 'Metropolitana do Rio de Janeiro');
    expect(r.length, 1); // o aviso do Canadá não conta
    final a = r.single;
    expect(a.id, '28747');
    expect(a.descricao, 'Tempestade');
    expect(a.severidade, 'Perigo Potencial');
    expect(a.cor, '#FFFE00');
    expect(a.fim, DateTime.utc(2026, 11, 25, 2, 59).toLocal());
    // Termina no dia 24 (hora local): começa à meia-noite do dia 24, não na publicação.
    final fimLocal = a.fim;
    expect(a.inicio, DateTime(fimLocal.year, fimLocal.month, fimLocal.day));
  });

  test('nome com acento perdido ainda casa, e o evento volta com acento', () {
    final r = lerAlertasOmm(corpo, 'Triângulo Mineiro/Alto Paranaíba');
    expect(r.length, 2);
    final declinio = r.firstWhere((a) => a.id == '28744');
    expect(declinio.descricao, 'Declínio de Temperatura');
    expect(declinio.severidade, 'Perigo');
    expect(declinio.cor, '#F96602');
  });

  test('mesorregião sem aviso', () {
    expect(lerAlertasOmm(corpo, 'Sul Fluminense'), isEmpty);
  });
}
