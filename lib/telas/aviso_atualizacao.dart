import 'package:material_ui/material_ui.dart';

import '../dados/atualizacao.dart';

/// Aviso no alto da tela inicial quando há versão nova publicada no GitHub.
class AvisoAtualizacao extends StatefulWidget {
  const AvisoAtualizacao({super.key});

  @override
  State<AvisoAtualizacao> createState() => _AvisoAtualizacaoState();
}

class _AvisoAtualizacaoState extends State<AvisoAtualizacao> {
  NovaVersao? _nova;
  double? _progresso;
  String? _mensagem;
  bool _fechado = false;

  @override
  void initState() {
    super.initState();
    verificarAtualizacao().then((v) {
      if (mounted) setState(() => _nova = v);
    });
  }

  Future<void> _atualizar() async {
    final v = _nova;
    if (v == null) return;
    setState(() {
      _progresso = 0;
      _mensagem = null;
    });
    final r = await baixarEInstalar(v, (p) {
      if (mounted) setState(() => _progresso = p);
    });
    if (!mounted) return;
    setState(() {
      _progresso = null;
      _mensagem = switch (r) {
        ResultadoAtualizacao.instalador => null,
        ResultadoAtualizacao.precisaPermissao =>
          'Ative "Permitir desta fonte" para o ClimaBit, volte aqui e toque em Atualizar de novo.',
        ResultadoAtualizacao.falhou =>
          'Não foi possível baixar a atualização. Confira a internet e tente de novo.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = _nova;
    if (v == null || _fechado) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final baixando = _progresso != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cores.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.system_update, color: cores.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Nova versão ${v.versao} disponível',
                      style: tema.textTheme.titleSmall?.copyWith(color: cores.onPrimaryContainer)),
                  Text(
                      baixando
                          ? 'Baixando… ${(_progresso! * 100).round()} %'
                          : 'Toque em Atualizar para instalar${v.tamanhoMb.isEmpty ? '' : ' (${v.tamanhoMb})'}.',
                      style: tema.textTheme.bodySmall?.copyWith(color: cores.onPrimaryContainer)),
                ]),
              ),
            ]),
            if (baixando) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progresso),
            ],
            if (_mensagem != null) ...[
              const SizedBox(height: 8),
              Text(_mensagem!, style: tema.textTheme.bodySmall?.copyWith(color: cores.onPrimaryContainer)),
            ],
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: baixando
                    ? null
                    : () {
                        adiarAtualizacao();
                        setState(() => _fechado = true);
                      },
                child: const Text('Agora não'),
              ),
              const SizedBox(width: 4),
              FilledButton(onPressed: baixando ? null : _atualizar, child: const Text('Atualizar')),
            ]),
          ]),
        ),
      ),
    );
  }
}
