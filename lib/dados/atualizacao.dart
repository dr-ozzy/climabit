import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Versão deste app. Mude junto com `version` no pubspec.yaml.
const versaoApp = '1.26.0';

/// Repositório público onde cada versão é publicada (GitHub Releases).
const repositorioApp = 'dr-ozzy/climabit';

const _canal = MethodChannel('tempo_oficial/atualizacao');
const _chaveAdiada = 'atualizacao_adiada_em';

/// Versão publicada mais nova que a instalada.
class NovaVersao {
  const NovaVersao({required this.versao, required this.urlApk, this.tamanho = 0, this.notas = ''});

  final String versao;
  final String urlApk;
  final int tamanho;
  final String notas;

  String get tamanhoMb => tamanho > 0 ? '${(tamanho / 1048576).round()} MB' : '';
}

/// true quando [a] é uma versão mais nova que [b] ("1.18.0" > "1.17.2").
bool versaoMaisNova(String a, String b) {
  List<int> partes(String v) => v
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[.+-]'))
      .take(3)
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = partes(a), y = partes(b);
  for (var i = 0; i < 3; i++) {
    final xi = i < x.length ? x[i] : 0;
    final yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi > yi;
  }
  return false;
}

/// Lê a resposta da API do GitHub (release mais recente). Separado para os testes.
NovaVersao? lerRelease(Map<String, dynamic> j, String instalada) {
  final tag = (j['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^[vV]'), '');
  if (tag.isEmpty || !versaoMaisNova(tag, instalada)) return null;
  final assets = (j['assets'] as List? ?? const []).whereType<Map>();
  for (final a in assets) {
    final nome = a['name'] as String? ?? '';
    final url = a['browser_download_url'] as String? ?? '';
    if (nome.endsWith('.apk') && url.startsWith('https://github.com/$repositorioApp/')) {
      return NovaVersao(
        versao: tag,
        urlApk: url,
        tamanho: (a['size'] as num?)?.toInt() ?? 0,
        notas: j['body'] as String? ?? '',
      );
    }
  }
  return null;
}

/// Consulta o GitHub. Devolve null sem versão nova, sem internet, ou quando o usuário
/// tocou em "Agora não" há menos de 24 h (a não ser que [forcar]).
Future<NovaVersao?> verificarAtualizacao({bool forcar = false}) async {
  try {
    if (!forcar) {
      final prefs = await SharedPreferences.getInstance();
      final adiada = prefs.getInt(_chaveAdiada);
      if (adiada != null &&
          DateTime.now().millisecondsSinceEpoch - adiada < const Duration(hours: 24).inMilliseconds) {
        return null;
      }
    }
    final r = await http.get(
      Uri.parse('https://api.github.com/repos/$repositorioApp/releases/latest'),
      headers: const {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final nova = lerRelease(jsonDecode(r.body) as Map<String, dynamic>, versaoApp);
    // O APK publicado é só para celulares de 64 bits: nos outros, não oferece (não instalaria).
    if (nova != null && !(await _canal.invokeMethod<bool>('suporta64') ?? true)) return null;
    return nova;
  } catch (_) {
    return null;
  }
}

/// "Agora não": o aviso volta em 24 h.
Future<void> adiarAtualizacao() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_chaveAdiada, DateTime.now().millisecondsSinceEpoch);
}

enum ResultadoAtualizacao { instalador, precisaPermissao, falhou }

/// Baixa o APK e abre o instalador do Android. O Android só aceita a atualização se o
/// APK tiver a mesma assinatura do app instalado.
Future<ResultadoAtualizacao> baixarEInstalar(NovaVersao v, void Function(double) progresso) async {
  try {
    final pode = await _canal.invokeMethod<bool>('podeInstalar') ?? false;
    if (!pode) {
      await _canal.invokeMethod('pedirPermissao');
      return ResultadoAtualizacao.precisaPermissao;
    }
    final pasta = await _canal.invokeMethod<String>('pasta');
    if (pasta == null) return ResultadoAtualizacao.falhou;
    final arquivo = File('$pasta/climabit-${v.versao}.apk');
    final cliente = http.Client();
    try {
      final resp = await cliente.send(http.Request('GET', Uri.parse(v.urlApk)));
      if (resp.statusCode != 200) return ResultadoAtualizacao.falhou;
      final total = resp.contentLength ?? v.tamanho;
      final saida = arquivo.openWrite();
      var recebido = 0;
      await for (final parte in resp.stream) {
        saida.add(parte);
        recebido += parte.length;
        if (total > 0) progresso(recebido / total);
      }
      await saida.close();
      if (total > 0 && recebido < total) return ResultadoAtualizacao.falhou;
    } finally {
      cliente.close();
    }
    await _canal.invokeMethod('instalar', {'caminho': arquivo.path});
    return ResultadoAtualizacao.instalador;
  } catch (_) {
    return ResultadoAtualizacao.falhou;
  }
}
