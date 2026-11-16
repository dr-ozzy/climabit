import 'package:material_ui/material_ui.dart';

import '../dados/fontes.dart';
import '../dados/repositorio.dart';
import '../util/formatos.dart';

/// Alertas oficiais do INMET para a cidade escolhida (em vigor e programados).
class TelaAlertas extends StatelessWidget {
  const TelaAlertas({super.key, required this.repo});

  final Repositorio repo;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final agora = DateTime.now();
        final validos = repo.alertas.where((a) => a.fim.isAfter(agora)).toList();
        final ativos = validos.where((a) => a.ativo(agora)).toList();
        final futuros = validos.where((a) => !a.ativo(agora)).toList();
        final estado = repo.fontes['INMET alertas'];
        final tema = Theme.of(context);
        return Scaffold(
          appBar: AppBar(title: Text('Alertas – ${repo.cidade.nome}')),
          body: RefreshIndicator(
            onRefresh: repo.atualizar,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (validos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(children: [
                      Icon(Icons.check_circle_outline,
                          size: 48, color: tema.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        estado?.falhou == true
                            ? 'O INMET não respondeu. Puxe a tela para baixo para tentar de novo.'
                            : 'Nenhum alerta oficial do INMET para ${repo.cidade.nome} agora.',
                        textAlign: TextAlign.center,
                        style: tema.textTheme.titleMedium,
                      ),
                    ]),
                  ),
                if (ativos.isNotEmpty) ...[
                  Text('Em vigor', style: tema.textTheme.titleSmall),
                  for (final a in ativos) _CartaoAlerta(alerta: a),
                ],
                if (futuros.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Programados', style: tema.textTheme.titleSmall),
                  for (final a in futuros) _CartaoAlerta(alerta: a),
                ],
                const SizedBox(height: 12),
                Text(
                  'Fonte: INMET – Instituto Nacional de Meteorologia (alertas.inmet.gov.br).'
                  '${estado?.obtidoEm != null ? ' Obtido às ${quando(estado!.obtidoEm!)}.' : ''}',
                  style: tema.textTheme.bodySmall
                      ?.copyWith(color: tema.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CartaoAlerta extends StatelessWidget {
  const _CartaoAlerta({required this.alerta});

  final Alerta alerta;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = corAviso(alerta.cor);
    final textoFaixa = cor.computeLuminance() > 0.4 ? Colors.black : Colors.white;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: cor,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: textoFaixa),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${alerta.descricao} – ${alerta.severidade}',
                  style: TextStyle(
                      color: textoFaixa, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Início: ${quando(alerta.inicio)}'),
            Text('Fim: ${quando(alerta.fim)}'),
            if (alerta.riscos.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Riscos', style: tema.textTheme.titleSmall),
              for (final r in alerta.riscos) _Item(r),
            ],
            if (alerta.instrucoes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('O que fazer', style: tema.textTheme.titleSmall),
              for (final i in alerta.instrucoes) _Item(i),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('•  '),
        Expanded(child: Text(texto)),
      ]),
    );
  }
}
