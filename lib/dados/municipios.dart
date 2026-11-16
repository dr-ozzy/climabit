import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'cidade.dart';

/// Lista oficial dos 5.570 municípios (IBGE), guardada no app, com o ponto central de cada um.
///
/// Serve para buscar cidades pelo nome e para descobrir a cidade a partir da
/// localização sem enviar a posição para nenhum servidor.
class Municipios {
  Municipios._(this.todos);

  final List<Cidade> todos;

  static Municipios? _cache;

  static Future<Municipios> carregar() async {
    if (_cache != null) return _cache!;
    final lista = jsonDecode(await rootBundle.loadString('assets/municipios.json')) as List;
    final canada =
        jsonDecode(await rootBundle.loadString('assets/cidades_canada.json')) as List;
    return _cache = Municipios._([
      for (final m in lista.cast<List>())
        Cidade(
          geocode: m[0] as int,
          nome: m[1] as String,
          uf: m[2] as String,
          latitude: (m[3] as num).toDouble(),
          longitude: (m[4] as num).toDouble(),
        ),
      // Cidades do Canadá (lista do ECCC). Código numérico negativo, só para identificar.
      for (final m in canada.cast<Map<String, dynamic>>())
        Cidade(
          geocode: codigoCanada(m['id'] as String),
          nome: m['nome'] as String,
          uf: m['prov'] as String,
          latitude: (m['lat'] as num).toDouble(),
          longitude: (m['lon'] as num).toDouble(),
          idEccc: m['id'] as String,
        ),
    ]);
  }

  /// Busca por nome, sem diferenciar acentos e maiúsculas. Começo do nome vem primeiro.
  List<Cidade> buscar(String texto, {int limite = 30}) {
    final t = semAcento(texto.trim());
    if (t.length < 2) return [];
    final comeca = <Cidade>[];
    final contem = <Cidade>[];
    for (final c in todos) {
      final n = semAcento(c.nome);
      if (n.startsWith(t)) {
        comeca.add(c);
      } else if (n.contains(t)) {
        contem.add(c);
      }
    }
    return [...comeca, ...contem].take(limite).toList();
  }

  Cidade? porGeocode(int geocode) {
    for (final c in todos) {
      if (c.geocode == geocode) return c;
    }
    return null;
  }

  /// Município cujo ponto central está mais perto da posição dada.
  Cidade maisProximo(double lat, double lon) {
    final cosLat = math.cos(lat * math.pi / 180);
    Cidade? melhor;
    var menor = double.infinity;
    for (final c in todos) {
      final dx = (c.longitude! - lon) * cosLat;
      final dy = c.latitude! - lat;
      final d = dx * dx + dy * dy;
      if (d < menor) {
        menor = d;
        melhor = c;
      }
    }
    return melhor!;
  }
}

const _provincias = ['ab', 'bc', 'mb', 'nb', 'nl', 'ns', 'nt', 'nu', 'on', 'pe', 'qc', 'sk', 'yt'];

/// "on-143" → −9143 (número negativo que não colide com os códigos do IBGE).
int codigoCanada(String id) {
  final partes = id.split('-');
  final prov = _provincias.indexOf(partes.first) + 1;
  return -(prov * 1000 + (int.tryParse(partes.last) ?? 0));
}

const _de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
const _para = 'aaaaaeeeeiiiiooooouuuucn';

String semAcento(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = _de.indexOf(ch);
    b.write(i >= 0 ? _para[i] : ch);
  }
  return b.toString();
}
