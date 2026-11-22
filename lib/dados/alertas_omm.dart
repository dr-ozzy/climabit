import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'fontes.dart';

/// Reserva para os alertas do INMET: a Organização Meteorológica Mundial (OMM) publica uma
/// cópia dos avisos oficiais do INMET no resumo público do centro de alertas
/// (`https://severeweather.wmo.int/v2/json/wmo_all.json`). Só é usado quando o INMET não
/// responde.
///
/// O resumo não traz a lista de municípios, só as mesorregiões do IBGE atingidas; por isso
/// o app guarda a mesorregião de cada município (`assets/mesorregioes.json`).
const enderecoAlertasOmm = 'https://severeweather.wmo.int/v2/json/wmo_all.json';

/// Mesorregião (IBGE) de cada município.
class Mesorregioes {
  Mesorregioes._(this._nomes, this._municipios);

  final List<String> _nomes;
  final Map<String, int> _municipios;

  static Mesorregioes? _cache;

  static Future<Mesorregioes> carregar() async {
    if (_cache != null) return _cache!;
    final j = jsonDecode(await rootBundle.loadString('assets/mesorregioes.json'))
        as Map<String, dynamic>;
    return _cache = Mesorregioes._(
      (j['nomes'] as List).cast<String>(),
      (j['municipios'] as Map<String, dynamic>).cast<String, int>(),
    );
  }

  String? de(int geocode) {
    final i = _municipios['$geocode'];
    return i == null ? null : _nomes[i];
  }
}

/// A OMM perdeu os acentos (as letras acentuadas chegam como "�"). Para comparar nomes,
/// fica só o que é letra sem acento: "Triângulo" e "Tri�ngulo" viram "tringulo".
String chaveSemAcentos(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Nomes dos avisos do INMET com acento (o resumo da OMM chega sem eles).
const _eventosInmet = [
  'Tempestade',
  'Chuvas Intensas',
  'Acumulado de Chuva',
  'Baixa Umidade',
  'Onda de Calor',
  'Declínio de Temperatura',
  'Geada',
  'Vendaval',
  'Ventos Costeiros',
  'Tempestade Tropical',
  'Ciclone',
  'Ressaca',
  'Nevoeiro',
  'Granizo',
];

String _nomeDoEvento(String evento) {
  final k = chaveSemAcentos(evento);
  for (final e in _eventosInmet) {
    if (chaveSemAcentos(e) == k) return e;
  }
  return evento.contains('�') ? 'Aviso' : evento;
}

/// Gravidade do padrão CAP → nível e cor do INMET (conferido em 2026-11-22: o aviso amarelo
/// "Perigo Potencial" chega como "Moderate"; o laranja "Perigo", como "Severe").
(String, String) _nivelInmet(String headline) {
  final h = headline.toLowerCase();
  if (h.contains('extreme')) return ('Grande Perigo', '#FF0000');
  if (h.contains('severe')) return ('Perigo', '#F96602');
  return ('Perigo Potencial', '#FFFE00');
}

/// Horário da OMM (UTC, sem fuso no texto) → hora local.
DateTime? _horaUtc(Object? v) {
  final s = (v ?? '').toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse('${s.replaceFirst(' ', 'T')}Z')?.toLocal();
}

/// Avisos do INMET no resumo da OMM que atingem a [mesorregiao].
///
/// O resumo não traz a hora de início: usa a publicação ou, se o aviso for para outro dia,
/// a meia-noite do dia em que ele termina (os avisos do INMET valem por dia).
/// O número do aviso é o mesmo do INMET, para não repetir notificações.
List<Alerta> lerAlertasOmm(String corpo, String mesorregiao) {
  final j = jsonDecode(corpo);
  final itens = j is Map ? j['items'] : null;
  if (itens is! List) return [];
  final alvo = chaveSemAcentos(mesorregiao);
  final r = <Alerta>[];
  final vistos = <String>{};
  for (final i in itens.whereType<Map>()) {
    if (!'${i['url'] ?? i['capURL'] ?? ''}'.startsWith('br-inmet')) continue;
    final areas = '${i['areaDesc'] ?? ''}'.split(':').last.split(',');
    if (!areas.any((a) => chaveSemAcentos(a) == alvo)) continue;
    final fim = _horaUtc(i['expires']);
    final enviado = _horaUtc(i['effective']) ?? _horaUtc(i['sent']);
    if (fim == null || enviado == null) continue;
    final diaDoFim = DateTime(fim.year, fim.month, fim.day);
    final inicio = enviado.isAfter(diaDoFim) ? enviado : diaDoFim;
    // "urn:oid:2.49.0.0.76.0.2026.28747.1" → 28747 (número do aviso no INMET).
    final partes = '${i['id'] ?? ''}'.split('.');
    final id = partes.length >= 2 ? partes[partes.length - 2] : '${i['id']}';
    if (!vistos.add(id)) continue;
    final (nivel, cor) = _nivelInmet('${i['headline'] ?? ''}');
    r.add(Alerta(
      id: id,
      descricao: _nomeDoEvento('${i['event'] ?? ''}'),
      severidade: nivel,
      cor: cor,
      inicio: inicio,
      fim: fim,
      instrucoes: const [
        'Aviso oficial do INMET recebido pela cópia da Organização Meteorológica Mundial '
            '(o site do INMET não respondeu). O horário de início é aproximado.',
      ],
    ));
  }
  r.sort((a, b) => a.inicio.compareTo(b.inicio));
  return r;
}
