import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cidade.dart';

/// Escolhas do usuário, guardadas só no aparelho (fora do backup do Android).
class Preferencias {
  Preferencias._(this._p);

  final SharedPreferences _p;

  static Future<Preferencias> carregar() async =>
      Preferencias._(await SharedPreferences.getInstance());

  static const _salvas = 'cidades_salvas';
  static const _atual = 'cidade_atual';
  static const _avisos = 'avisos_ligados';
  static const _cidadeAvisos = 'cidade_avisos';
  static const _intervalo = 'avisos_intervalo_min';
  static const _avisoChuva = 'aviso_chuva';

  List<Cidade> get cidadesSalvas {
    final s = _p.getString(_salvas);
    if (s == null) return [niteroi];
    return [
      for (final j in (jsonDecode(s) as List).cast<Map<String, dynamic>>())
        Cidade.fromJson(j),
    ];
  }

  Future<void> salvarCidades(List<Cidade> l) =>
      _p.setString(_salvas, jsonEncode([for (final c in l) c.toJson()]));

  Cidade get cidadeAtual {
    final g = _p.getInt(_atual);
    final salvas = cidadesSalvas;
    return salvas.firstWhere((c) => c.geocode == g, orElse: () => salvas.first);
  }

  Future<void> definirCidadeAtual(Cidade c) => _p.setInt(_atual, c.geocode);

  bool get avisosLigados => _p.getBool(_avisos) ?? false;
  Future<void> definirAvisos(bool v) => _p.setBool(_avisos, v);

  /// Avisar quando a chuva (garoa, neve, trovoada) for começar nas próximas 2 horas.
  bool get avisoChuva => _p.getBool(_avisoChuva) ?? false;
  Future<void> definirAvisoChuva(bool v) => _p.setBool(_avisoChuva, v);

  /// Alguma conferência em segundo plano ligada (alertas ou chuva).
  bool get algumAviso => avisosLigados || avisoChuva;

  Cidade get cidadeDosAvisos {
    final s = _p.getString(_cidadeAvisos);
    if (s == null) return niteroi;
    return Cidade.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  Future<void> definirCidadeDosAvisos(Cidade c) =>
      _p.setString(_cidadeAvisos, jsonEncode(c.toJson()));

  /// De quanto em quanto tempo conferir os alertas (minutos).
  int get intervaloMin => _p.getInt(_intervalo) ?? 60;
  Future<void> definirIntervalo(int min) => _p.setInt(_intervalo, min);
}
