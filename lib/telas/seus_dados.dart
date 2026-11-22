import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dados/cidade.dart';
import '../dados/notificacoes.dart';
import '../dados/repositorio.dart';

/// "Seus dados": tudo o que o ClimaBit guarda neste celular, e um botão para apagar tudo.
/// Nada disso sai do aparelho nem vai para o backup.
class TelaSeusDados extends StatefulWidget {
  const TelaSeusDados({super.key, required this.repo});

  final Repositorio repo;

  @override
  State<TelaSeusDados> createState() => _TelaSeusDadosState();
}

class _TelaSeusDadosState extends State<TelaSeusDados> {
  List<(String, String)>? _itens;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _ler() async {
    final p = await SharedPreferences.getInstance();
    final chaves = p.getKeys();
    final copias = chaves.where((k) => k.startsWith('cache:')).toList();
    var bytes = 0;
    for (final k in copias) {
      bytes += (p.getString(k) ?? '').length;
    }
    int contar(String chave, String marcador) =>
        RegExp(marcador).allMatches(p.getString(chave) ?? '').length;
    setState(() => _itens = [
          ('Cidades salvas', '${contar('cidades_salvas', '"geocode"')} cidade(s)'),
          ('Cidade mostrada e cidade dos avisos', 'código do município (sem a sua localização)'),
          ('Rotinas de atividades', '${contar('rotinas', '"a":')} rotina(s)'),
          ('Escolhas', 'avisos ligados ou não, intervalo, atividade escolhida, ajustes dos avisos'),
          ('Cópias das últimas consultas', '${copias.length} fonte(s), ${(bytes / 1024).round()} KB '
              '(para abrir rápido e funcionar sem internet)'),
          ('Alertas já avisados', 'números dos alertas, para não avisar duas vezes'),
        ]);
  }

  Future<void> _apagarTudo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Apagar tudo?'),
        content: const Text('Apaga as cidades salvas, as rotinas, as escolhas e as cópias das '
            'consultas. Os avisos em segundo plano são desligados. O app volta para Niterói, '
            'como se tivesse acabado de ser instalado. Não dá para desfazer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Apagar tudo')),
        ],
      ),
    );
    if (ok != true) return;
    await Notificacoes.cancelar();
    await (await SharedPreferences.getInstance()).clear();
    widget.repo.trocarCidade(niteroi);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dados apagados. O app voltou para Niterói.')));
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final itens = _itens;
    return Scaffold(
      appBar: AppBar(title: const Text('Seus dados')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Tudo o que o ClimaBit guarda fica só neste celular. Nada vai para a '
                  'internet nem para o backup do Android.'),
              const SizedBox(height: 12),
              if (itens == null)
                const Center(child: CircularProgressIndicator())
              else
                Card(
                  child: Column(children: [
                    for (final (titulo, detalhe) in itens)
                      ListTile(title: Text(titulo), subtitle: Text(detalhe)),
                  ]),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: tema.colorScheme.error,
                  foregroundColor: tema.colorScheme.onError,
                ),
                onPressed: _apagarTudo,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Apagar tudo'),
              ),
              const SizedBox(height: 8),
              Text('Os widgets na tela inicial continuam mostrando a última imagem até a '
                  'próxima atualização.', style: tema.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Abre a tela do ClimaBit nas configurações do Android (para liberar a bateria).
Future<bool> abrirDetalhesDoApp() async {
  try {
    return await const MethodChannel('tempo_oficial/sistema')
            .invokeMethod<bool>('abrirDetalhesDoApp') ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
