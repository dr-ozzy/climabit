import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'cidade.dart';
import 'fontes.dart';
import 'http_cache.dart';
import 'municipios.dart';

/// Uma estação automática do INMET (lista guardada no app).
class EstacaoInmet {
  const EstacaoInmet(this.codigo, this.latitude, this.longitude, this.nome, this.uf);
  final String codigo;
  final double latitude;
  final double longitude;
  final String nome;
  final String uf;

  double distanciaKm(double lat, double lon) => distanciaEntre(lat, lon, latitude, longitude);
}

/// Estações automáticas operantes do INMET (`assets/estacoes_inmet.json`) e a consulta de
/// uma estação específica. O INMET não aceita consulta pelo código da estação: o app
/// pergunta "estação mais próxima" do município cuja sede fica mais perto dela e só aceita a
/// resposta se o código bater.
class EstacoesInmet {
  EstacoesInmet._(this.todas);
  final List<EstacaoInmet> todas;
  static EstacoesInmet? _cache;

  static Future<EstacoesInmet> carregar() async {
    if (_cache != null) return _cache!;
    final j = jsonDecode(await rootBundle.loadString('assets/estacoes_inmet.json'))
        as Map<String, dynamic>;
    return _cache = EstacoesInmet._([
      for (final e in (j['estacoes'] as List).cast<List>())
        EstacaoInmet(
          e[0] as String,
          (e[1] as num).toDouble(),
          (e[2] as num).toDouble(),
          e.length > 3 ? e[3] as String : e[0] as String,
          e.length > 4 ? e[4] as String : '',
        ),
    ]);
  }

  /// Estações até [raioKm] do ponto, da mais perto para a mais longe.
  List<EstacaoInmet> proximas(double lat, double lon, {double raioKm = 80, int maximo = 10}) {
    final l = [
      for (final e in todas)
        if (e.distanciaKm(lat, lon) <= raioKm) e,
    ]..sort((a, b) => a.distanciaKm(lat, lon).compareTo(b.distanciaKm(lat, lon)));
    return l.take(maximo).toList();
  }

  EstacaoInmet? porCodigo(String codigo) {
    for (final e in todas) {
      if (e.codigo == codigo) return e;
    }
    return null;
  }

  /// Medição atual da estação [e] (nula se o INMET devolver outra estação ou falhar).
  static Future<Medicao?> medir(EstacaoInmet e, HttpCache http) async {
    final municipios = (await Municipios.carregar()).todos.where((c) => c.geocode > 0);
    Cidade? perto;
    var menor = double.infinity;
    for (final c in municipios) {
      final d = e.distanciaKm(c.latitude!, c.longitude!);
      if (d < menor) {
        menor = d;
        perto = c;
      }
    }
    if (perto == null) return null;
    try {
      final r = await http
          .obter(Uri.parse('https://apiprevmet3.inmet.gov.br/estacao/proxima/${perto.geocode}'));
      final m = lerEstacaoInmet(r.corpo);
      return m != null && m.codigo == e.codigo ? m : null;
    } catch (_) {
      return null;
    }
  }
}

/// Uma estação que o INMET entrega ao perguntar pelo município [geocodeConsulta].
class EstacaoAlcancavel {
  const EstacaoAlcancavel(this.medicao, this.geocodeConsulta);
  final Medicao medicao;
  final int geocodeConsulta;
}

/// Estações que dá para consultar perto da cidade: pergunta "estação mais próxima" para os
/// municípios a até [raioKm] (no máximo [maximo] municípios) e junta as respostas diferentes.
/// (Só as estações que são a mais próxima de algum município aparecem.)
Future<List<EstacaoAlcancavel>> estacoesAlcancaveis(Cidade c, HttpCache http,
    {double raioKm = 60, int maximo = 15}) async {
  final todos = (await Municipios.carregar()).todos.where((m) => m.geocode > 0).toList();
  double d(Cidade m) => distanciaEntre(c.latitude!, c.longitude!, m.latitude!, m.longitude!);
  final perto = [
    for (final m in todos)
      if (d(m) <= raioKm) m,
  ]..sort((a, b) => d(a).compareTo(d(b)));
  final respostas = await Future.wait([
    for (final m in perto.take(maximo))
      http
          .obter(Uri.parse('https://apiprevmet3.inmet.gov.br/estacao/proxima/${m.geocode}'))
          .then<EstacaoAlcancavel?>((r) {
        final med = lerEstacaoInmet(r.corpo);
        return med == null ? null : EstacaoAlcancavel(med, m.geocode);
      }).catchError((_) => null),
  ]);
  final vistas = <String>{};
  final r = <EstacaoAlcancavel>[];
  for (final e in respostas.whereType<EstacaoAlcancavel>()) {
    if (vistas.add(e.medicao.codigo)) r.add(e);
  }
  return r;
}

/// Estação escolhida pelo usuário para a cidade: (código, município da consulta).
/// Nula = automática, a mais próxima.
Future<(String, int)?> estacaoEscolhida(int geocode) async {
  final s = (await SharedPreferences.getInstance()).getString('estacao_escolhida_$geocode');
  final partes = s?.split('|');
  if (partes == null || partes.length != 2) return null;
  final g = int.tryParse(partes[1]);
  return g == null ? null : (partes[0], g);
}

Future<void> definirEstacaoEscolhida(int geocode, (String, int)? escolha) async {
  final p = await SharedPreferences.getInstance();
  if (escolha == null) {
    await p.remove('estacao_escolhida_$geocode');
  } else {
    await p.setString('estacao_escolhida_$geocode', '${escolha.$1}|${escolha.$2}');
  }
}

/// Medição da estação escolhida (nula se o INMET devolver outra estação ou falhar).
Future<Medicao?> medirEscolhida((String, int) escolha, HttpCache http) async {
  try {
    final r = await http
        .obter(Uri.parse('https://apiprevmet3.inmet.gov.br/estacao/proxima/${escolha.$2}'));
    final m = lerEstacaoInmet(r.corpo);
    return m != null && m.codigo == escolha.$1 ? m : null;
  } catch (_) {
    return null;
  }
}
