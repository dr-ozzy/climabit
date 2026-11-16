import 'package:material_ui/material_ui.dart';

import '../dados/fontes.dart';
import '../dados/repositorio.dart';
import '../util/formatos.dart';
import 'componentes.dart';

/// Classificação da chuva da última hora (escala usada pelo Alerta Rio, em mm/h).
String intensidade(double mm) {
  if (mm <= 0) return 'sem chuva';
  if (mm < 5) return 'fraca';
  if (mm <= 25) return 'moderada';
  if (mm <= 50) return 'forte';
  return 'muito forte';
}

Color _corIntensidade(double mm, ColorScheme c) {
  if (mm <= 0) return c.surfaceContainerHighest;
  if (mm < 5) return const Color(0xFF90CAF9);
  if (mm <= 25) return const Color(0xFF42A5F5);
  if (mm <= 50) return const Color(0xFFFFA726);
  return const Color(0xFFE53935);
}

/// Chuva medida em cada pluviômetro da cidade (Cemaden e, no Rio, Alerta Rio).
class TelaChuva extends StatefulWidget {
  const TelaChuva({super.key, required this.repo});

  final Repositorio repo;

  @override
  State<TelaChuva> createState() => _TelaChuvaState();
}

class _TelaChuvaState extends State<TelaChuva> {
  bool _por24h = false;

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final tema = Theme.of(context);
    final agora = DateTime.now();
    final recentes = repo.pluviometros.where((p) => p.recente(agora)).toList()
      ..sort((a, b) => _por24h
          ? (b.chuva24h ?? 0).compareTo(a.chuva24h ?? 0)
          : (b.chuva1h ?? 0).compareTo(a.chuva1h ?? 0));
    final antigos = repo.pluviometros.where((p) => !p.recente(agora)).toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    if (repo.pluviometros.isEmpty) {
      return ListaAtualizavel(repo: repo, children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: repo.carregando
                ? const CircularProgressIndicator()
                : const Text('Nenhum pluviômetro oficial encontrado nesta cidade.',
                    textAlign: TextAlign.center),
          ),
        ),
        RodapeFontes(repo: repo),
      ]);
    }

    return ListaAtualizavel(repo: repo, children: [
      if (repo.sirenes.isNotEmpty) _CartaoSirenes(sirenes: repo.sirenes),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Última hora')),
            ButtonSegment(value: true, label: Text('Últimas 24 horas')),
          ],
          selected: {_por24h},
          onSelectionChanged: (s) => setState(() => _por24h = s.first),
        ),
      ),
      Text(
        '${recentes.length} pluviômetros com leitura nas últimas 2 horas, '
        'do mais chuvoso para o menos chuvoso.',
        style: tema.textTheme.bodyMedium,
      ),
      const SizedBox(height: 8),
      Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < recentes.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _LinhaPluviometro(p: recentes[i], destaque24h: _por24h),
          ],
        ]),
      ),
      if (antigos.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('Sem dados recentes (${antigos.length})', style: tema.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('Estes pluviômetros não enviaram leitura nas últimas 2 horas.',
            style: tema.textTheme.bodySmall),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: [
            for (final p in antigos)
              ListTile(
                dense: true,
                title: Text(p.nome),
                subtitle: Text(p.hora == null
                    ? '${p.fonte} · nunca enviou leitura'
                    : '${p.fonte} · última leitura ${quando(p.hora!)}'),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      Text(
        'Intensidade na última hora: fraca (até 5 mm), moderada (5 a 25 mm), '
        'forte (25 a 50 mm), muito forte (acima de 50 mm).',
        style: tema.textTheme.bodySmall,
      ),
      RodapeFontes(repo: repo),
    ]);
  }
}

class _LinhaPluviometro extends StatelessWidget {
  const _LinhaPluviometro({required this.p, required this.destaque24h});

  final Pluviometro p;
  final bool destaque24h;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final h1 = p.chuva1h ?? 0;
    final h24 = p.chuva24h ?? 0;
    final cor = _corIntensidade(h1, tema.colorScheme);
    final principal = destaque24h ? h24 : h1;
    final secundario = destaque24h ? '1 h: ${decimal(h1)} mm' : '24 h: ${decimal(h24)} mm';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          width: 8,
          height: 40,
          decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.nome, style: tema.textTheme.titleMedium),
            Text('${p.fonte} · ${quando(p.hora!)} · ${intensidade(h1)}',
                style: tema.textTheme.bodySmall),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${decimal(principal)} mm', style: tema.textTheme.titleMedium),
          Text(secundario, style: tema.textTheme.bodySmall),
        ]),
      ]),
    );
  }
}

/// Sirenes de alerta de chuva da Defesa Civil de Niterói.
class _CartaoSirenes extends StatelessWidget {
  const _CartaoSirenes({required this.sirenes});

  final List<Sirene> sirenes;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final acionadas = sirenes.where((s) => s.acionada).toList();
    final alerta = acionadas.isNotEmpty;
    return Card(
      color: alerta ? tema.colorScheme.errorContainer : null,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(alerta ? Icons.campaign : Icons.campaign_outlined,
                color: alerta ? tema.colorScheme.onErrorContainer : tema.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                alerta
                    ? '${acionadas.length} ${acionadas.length == 1 ? 'sirene acionada' : 'sirenes acionadas'}'
                    : 'Nenhuma sirene acionada',
                style: tema.textTheme.titleMedium?.copyWith(
                    color: alerta ? tema.colorScheme.onErrorContainer : null),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            alerta
                ? acionadas.map((s) => '${s.nome} (${s.status.toLowerCase()})').join(', ')
                : 'As ${sirenes.length} sirenes da Defesa Civil de Niterói estão desligadas.',
            style: TextStyle(color: alerta ? tema.colorScheme.onErrorContainer : null),
          ),
          if (alerta) ...[
            const SizedBox(height: 8),
            Text('Sirene acionada: siga para o ponto de apoio mais próximo. Emergência: 199.',
                style: TextStyle(
                    color: tema.colorScheme.onErrorContainer, fontWeight: FontWeight.bold)),
          ],
          const SizedBox(height: 8),
          const Fonte('Defesa Civil de Niterói'),
        ]),
      ),
    );
  }
}
