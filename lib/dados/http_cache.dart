import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Resposta de uma fonte, vinda da internet ou da cópia guardada no aparelho.
class RespostaFonte {
  const RespostaFonte(this.corpo, this.obtidoEm, {required this.doCache});

  final String corpo;
  final DateTime obtidoEm;
  final bool doCache;
}

/// Faz as consultas às fontes oficiais e guarda a última resposta de cada uma.
///
/// Nenhum dado do usuário é enviado: só o endereço da fonte (com o código da cidade).
class HttpCache {
  HttpCache({http.Client? cliente}) : _cliente = cliente ?? http.Client();

  final http.Client _cliente;

  /// Ligado: devolve só a cópia guardada no aparelho, sem ir à internet (abertura rápida).
  bool somenteGuardado = false;

  static const _cabecalhos = {'User-Agent': 'ClimaBit/1.17 (Android)'};

  Future<RespostaFonte> obter(
    Uri uri, {
    Encoding codificacao = utf8,
    Duration limite = const Duration(seconds: 20),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final chave = 'cache:$uri';
    if (somenteGuardado) {
      final guardado = prefs.getString(chave);
      if (guardado == null) throw FonteIndisponivel('sem cópia guardada');
      final j = jsonDecode(guardado) as Map<String, dynamic>;
      return RespostaFonte(j['c'] as String, DateTime.parse(j['t'] as String), doCache: true);
    }
    try {
      final r = await _cliente.get(uri, headers: _cabecalhos).timeout(limite);
      if (r.statusCode != 200) {
        throw FonteIndisponivel('código ${r.statusCode}');
      }
      final corpo = _decodificar(r.bodyBytes, codificacao);
      final agora = DateTime.now();
      await prefs.setString(
        chave,
        jsonEncode({'t': agora.toIso8601String(), 'c': corpo}),
      );
      return RespostaFonte(corpo, agora, doCache: false);
    } catch (e) {
      final guardado = prefs.getString(chave);
      if (guardado != null) {
        final j = jsonDecode(guardado) as Map<String, dynamic>;
        return RespostaFonte(
          j['c'] as String,
          DateTime.parse(j['t'] as String),
          doCache: true,
        );
      }
      if (e is FonteIndisponivel) rethrow;
      throw FonteIndisponivel(e.toString());
    }
  }
}

/// UTF-8 quando o texto for UTF-8 válido; senão ISO-8859-1 (alguns sites antigos).
String _decodificar(List<int> bytes, Encoding codificacao) {
  if (codificacao == latin1) return latin1.decode(bytes);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

class FonteIndisponivel implements Exception {
  FonteIndisponivel(this.motivo);
  final String motivo;

  @override
  String toString() => 'Fonte indisponível: $motivo';
}
