import 'package:flutter/services.dart';

/// Pede ao Android a posição aproximada do aparelho (código em MainActivity.kt).
/// A posição só é usada para escolher o município e não é guardada.
class Localizacao {
  static const _canal = MethodChannel('tempo_oficial/localizacao');

  static Future<(double, double)> obter() async {
    try {
      final r = await _canal.invokeMapMethod<String, double>('obter');
      if (r == null) throw const ErroLocalizacao('Não foi possível obter a localização.');
      return (r['lat']!, r['lon']!);
    } on PlatformException catch (e) {
      throw ErroLocalizacao(switch (e.code) {
        'negada' => 'Permissão de localização negada. Escolha a cidade pela busca.',
        'desligada' => 'A localização do celular está desligada. Ligue-a nas configurações rápidas.',
        _ => 'Não foi possível obter a localização agora. Tente de novo em alguns minutos.',
      });
    }
  }
}

class ErroLocalizacao implements Exception {
  const ErroLocalizacao(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}
