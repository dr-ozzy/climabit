import 'package:material_ui/material_ui.dart';

import '../dados/estacoes.dart';
import '../dados/fontes.dart' show distanciaEntre;
import '../dados/http_cache.dart';
import '../dados/repositorio.dart';
import '../util/formatos.dart';
import 'componentes.dart' show tituloProprio;

/// Janela para escolher a estação do INMET usada em "Detalhes de agora". Lista só as
/// estações que o INMET entrega para os municípios vizinhos (são as que dá para consultar).
Future<void> escolherEstacao(BuildContext context, Repositorio repo) async {
  final c = repo.cidade;
  if (c.latitude == null || c.longitude == null || c.noCanada) return;
  final atual = await estacaoEscolhida(c.geocode);
  if (!context.mounted) return;
  final escolha = await showDialog<(String, int)>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Estação de medição'),
      children: [
        FutureBuilder<List<EstacaoAlcancavel>>(
          future: estacoesAlcancaveis(c, HttpCache()),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final lista = snap.data!;
            return RadioGroup<String>(
              groupValue: atual?.$1 ?? '',
              onChanged: (v) {
                if (v == null || v.isEmpty) {
                  Navigator.pop(ctx, ('', 0));
                  return;
                }
                final e = lista.firstWhere((x) => x.medicao.codigo == v);
                Navigator.pop(ctx, (v, e.geocodeConsulta));
              },
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const RadioListTile<String>(
                  value: '',
                  title: Text('Automática'),
                  subtitle: Text('A estação do INMET mais próxima com medição recente.'),
                ),
                for (final e in lista)
                  RadioListTile<String>(
                    value: e.medicao.codigo,
                    title: Text(tituloProprio(e.medicao.estacao)),
                    subtitle: Text(
                      '${distanciaEntre(c.latitude!, c.longitude!, e.medicao.latitude ?? c.latitude!, e.medicao.longitude ?? c.longitude!).round()} km'
                      ' · ${e.medicao.codigo} · medida às ${hora(e.medicao.hora)}',
                    ),
                  ),
                if (lista.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('O INMET não respondeu agora. Tente mais tarde.'),
                  ),
              ]),
            );
          },
        ),
      ],
    ),
  );
  if (escolha == null) return;
  final nova = escolha.$1.isEmpty ? null : escolha;
  if (nova?.$1 == atual?.$1) return;
  await definirEstacaoEscolhida(c.geocode, nova);
  await repo.atualizar();
}
