import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../dados/chuva_prevista.dart';
import '../dados/fontes.dart';
import '../dados/repositorio.dart';
import '../util/formatos.dart';
import 'componentes.dart';

final _diaSemana = DateFormat('EEEE', 'pt_BR');
final _data = DateFormat("d 'de' MMMM", 'pt_BR');

/// Previsão de até 7 dias (INMET nos dias que ele cobre; CPTEC/INPE nos demais).
class TelaPrevisao extends StatelessWidget {
  const TelaPrevisao({super.key, required this.repo});

  final Repositorio repo;

  @override
  Widget build(BuildContext context) {
    final dias = repo.previsao;
    if (dias.isEmpty) {
      return ListaAtualizavel(repo: repo, children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: repo.carregando
                ? const CircularProgressIndicator()
                : const Text('INMET e CPTEC/INPE não responderam. Puxe a tela para baixo para tentar de novo.',
                    textAlign: TextAlign.center),
          ),
        ),
        RodapeFontes(repo: repo),
      ]);
    }
    return ListaAtualizavel(repo: repo, children: [
      if (repo.previsaoEstimada)
        Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('INMET e CPTEC/INPE sem previsão para esta cidade agora. '
                'Previsão estimada por modelo (Open-Meteo), não é previsão oficial.'),
          ),
        ),
      Colunas(children: [for (final d in dias) _CartaoDia(dia: d, ondaMax: _ondaMaxima(repo.ondas, d.dia))]),
      RodapeFontes(repo: repo),
    ]);
  }
}

class _CartaoDia extends StatelessWidget {
  const _CartaoDia({required this.dia, this.ondaMax});

  final DiaPrevisao dia;
  final PrevisaoOnda? ondaMax;

  String _titulo(DateTime agora) {
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final dif = dia.dia.difference(hoje).inDays;
    final nome = dif == 0
        ? 'Hoje'
        : dif == 1
            ? 'Amanhã'
            : toBeginningOfSentenceCase(_diaSemana.format(dia.dia));
    return '$nome, ${_data.format(dia.dia)}';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final umidade = dia.umidadeMin != null && dia.umidadeMax != null
        ? '${dia.umidadeMin}–${dia.umidadeMax} %'
        : null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_titulo(DateTime.now()),
              style: tema.textTheme.titleSmall?.copyWith(color: tema.colorScheme.primary)),
          const SizedBox(height: 8),
          Row(children: [
            simboloTempo(dia.resumo, size: 40, color: tema.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(dia.resumo, style: tema.textTheme.titleMedium)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${inteiro(dia.maxima)}°',
                  style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              Text('${inteiro(dia.minima)}°', style: tema.textTheme.titleMedium),
            ]),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 4, children: [
            if (umidade != null) _Info(Icons.water_drop_outlined, 'Umidade $umidade'),
            if ((dia.ventoIntensidade ?? '').isNotEmpty)
              _Info(Icons.air, 'Vento: ${dia.ventoIntensidade!.toLowerCase()} ${dia.ventoDirecao ?? ''}'.trim()),
            if (dia.uv != null) _Info(Icons.wb_sunny_outlined, 'UV ${decimal(dia.uv)} (${categoriaUv(dia.uv!)})'),
            if (dia.probabilidadeChuva != null)
              _Info(Icons.umbrella, 'Chance de chuva ${dia.probabilidadeChuva} %'),
            if (ondaMax != null)
              _Info(Icons.waves,
                  'Ondas até ${decimal(ondaMax!.altura)} m (${ondaMax!.agitacao.toLowerCase()})'),
          ]),
          _LinhaChuva(dia: dia),
          if (dia.periodos.length > 1) ...[
            const Divider(height: 24),
            for (final p in dia.periodos) _LinhaPeriodo(periodo: p),
          ],
          const SizedBox(height: 8),
          Fonte(dia.fonte + (dia.uv != null && dia.fonte == 'INMET' ? ' · UV: CPTEC/INPE' : '')),
        ]),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icone, this.texto);

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icone, size: 16, color: cor),
      const SizedBox(width: 4),
      Text(texto, style: TextStyle(color: cor)),
    ]);
  }
}

class _LinhaPeriodo extends StatelessWidget {
  const _LinhaPeriodo({required this.periodo});

  final PeriodoPrevisao periodo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 64,
          child: Text(periodo.nome, style: tema.textTheme.labelLarge),
        ),
        simboloTempo(periodo.resumo, size: 20, color: tema.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(periodo.resumo)),
      ]),
    );
  }
}

/// Maior onda prevista no dia (CPTEC/INPE).
PrevisaoOnda? _ondaMaxima(List<PrevisaoOnda> ondas, DateTime dia) {
  PrevisaoOnda? maior;
  for (final o in ondas) {
    if (!DateUtils.isSameDay(o.hora, dia) || o.altura == null) continue;
    if (maior == null || o.altura! > maior.altura!) maior = o;
  }
  return maior;
}

/// "Chuva: tarde e noite" / "Possível chuva: manhã" em destaque.
class _LinhaChuva extends StatelessWidget {
  const _LinhaChuva({required this.dia});

  final DiaPrevisao dia;

  @override
  Widget build(BuildContext context) {
    final (periodos, certeza) = periodosComChuva(dia, DateTime.now());
    if (certeza == Certeza.nenhuma) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final rotulo = certeza == Certeza.prevista ? 'Chuva' : 'Possível chuva';
    final quando = periodos.isEmpty ? 'no dia' : juntarComE(periodos);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tema.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.umbrella, size: 18, color: tema.colorScheme.onTertiaryContainer),
          const SizedBox(width: 6),
          Flexible(
            child: Text('$rotulo: $quando',
                style: TextStyle(
                    color: tema.colorScheme.onTertiaryContainer, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}
