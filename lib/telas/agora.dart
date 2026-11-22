import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../dados/erros.dart';
import '../dados/astro.dart';
import '../dados/chuva_prevista.dart';
import '../dados/cidade.dart';
import '../dados/fontes.dart';
import '../dados/lua.dart';
import '../dados/mare.dart';
import '../dados/repositorio.dart';
import '../util/formatos.dart';
import 'bons_horarios.dart';
import 'escolher_estacao.dart';
import 'aviso_atualizacao.dart';
import 'ceu.dart';
import 'componentes.dart';
import 'resumo.dart';

/// Tela inicial: medição de agora, chuva (agora e hoje), próximas horas e mar.
class TelaAgora extends StatelessWidget {
  const TelaAgora({super.key, required this.repo, this.abrirAlertas});

  final Repositorio repo;
  final VoidCallback? abrirAlertas;

  @override
  Widget build(BuildContext context) {
    final agora = DateTime.now();
    final alertasAtivos = repo.alertas.where((a) => a.ativo(agora)).toList();
    final sirenesAcionadas = repo.sirenes.where((s) => s.acionada).toList();
    final estacaoMare = EstacaoMare.proxima(repo.cidade.latitude, repo.cidade.longitude);
    final hoje = repo.previsao.isNotEmpty &&
            DateUtils.isSameDay(repo.previsao.first.dia, agora)
        ? repo.previsao.first
        : null;
    final lat = repo.cidade.latitude;
    final lon = repo.cidade.longitude;
    final m = repo.estimativaAtual ?? repo.medicao;
    final noite = lat != null && lon != null
        ? Astro.noite(agora, lat, lon)
        : (agora.hour < 6 || agora.hour >= 18);
    final ventoKmh =
        repo.ventoAeroporto?.ventoKmh ?? m?.ventoKmh ?? repo.ventoEstimado?.ventoKmh;
    final resumoAgora = resumoDoPeriodo(hoje, agora);
    final ceuAgora =
        m == null
            ? null
            : estadoCeu(
                resumoPeriodo: resumoAgora,
                chuvaUltimaHora: m.chuva1h,
                observado: hoje?.periodos.any((p) => p.nome == 'Agora') ?? false,
                coberturaAeroporto: repo.ceuAeroporto?.cobertura,
                tempoAeroporto: repo.ceuAeroporto?.tempoPresente ?? '',
                codigoModelo: repo.horasOficiais ? null : codigoDaHora(repo.chuvaHoraria, agora));
    final sensacaoAgora =
        m == null ? null : m.sensacao ?? sensacaoTermica(m.temperatura, m.umidade, ventoKmh);
    final topo = m == null || ceuAgora == null
        ? null
        : TopoCeu(
            estado: ceuAgora,
            noite: noite,
            alturaSol: lat != null && lon != null ? Astro.altitudeSol(agora, lat, lon) : null,
            litoral: repo.ondas.isNotEmpty || estacaoMare != null,
            paisagem: escolherPaisagem(
              estado: ceuAgora,
              temperatura: m.temperatura,
              sensacao: sensacaoAgora,
              chuvaUltimaHora: m.chuva1h,
              resumo: resumoAgora,
            ),
            temperatura: m.temperatura,
            sensacao: sensacaoAgora,
            maxima: hoje?.maxima,
            minima: hoje?.minima,
            idadeLua: Lua.idade(agora),
            estimativa: repo.estimativaAtual != null,
          );

    // Ordem pedida pelo usuário: Vai chover hoje?, hora em hora, Detalhes, Sol e lua, Mar.
    final cartoes = <Widget>[
      // Frase do dia, chuva na próxima hora e comparação com ontem (ideias de outros apps).
      if (repo.chuvaHoraria.isNotEmpty)
        CartaoResumo(
          ceu: ceuAgora,
          noite: noite,
          horas: repo.chuvaHoraria,
          passadas: repo.horasPassadas,
          agora: agora,
          oficial: repo.horasOficiais,
          dias: repo.previsao,
          canada: repo.cidade.noCanada,
        ),
      if (repo.previsao.isNotEmpty) _CartaoChuva(repo: repo, agora: agora, hoje: hoje),
      if (repo.chuvaHoraria.isNotEmpty)
        _CartaoProximasHoras(horas: repo.chuvaHoraria, oficial: repo.horasOficiais),
      if (repo.chuvaHoraria.isNotEmpty)
        CartaoBonsHorarios(horas: repo.chuvaHoraria, horasSemana: repo.horasSemana),
      _CartaoMedicao(
          medicao: repo.medicao,
          estado: repo.fontes['INMET estação'],
          aeroporto: repo.ventoAeroporto,
          estimativa: repo.estimativaAtual,
          ventoEstimado: repo.ventoEstimado,
          reserva: repo.medicaoReserva,
          hoje: hoje,
          horas: repo.chuvaHoraria,
          cidade: repo.cidade,
          aoTrocarEstacao:
              repo.cidade.noCanada ? null : () => escolherEstacao(context, repo)),
      if (lat != null && lon != null) _CartaoSolLua(agora: agora, lat: lat, lon: lon),
      if (repo.ondas.isNotEmpty || estacaoMare != null)
        _CartaoMar(ondas: repo.ondas, agora: agora, estacao: estacaoMare, cidade: repo.cidade),
    ];

    return ListaAtualizavel(
      repo: repo,
      children: [
        const AvisoAtualizacao(key: ValueKey('aviso_atualizacao')),
        if (FaixaAlertas.temAlerta(alertasAtivos, sirenesAcionadas))
          FaixaAlertas(
            alertas: alertasAtivos,
            sirenesAcionadas: sirenesAcionadas,
            boletim: repo.boletimNiteroi,
            boletimObtidoEm: repo.boletimObtidoEm,
            aoVerTodos: abrirAlertas,
          ),
        if (repo.mostrandoGuardado && repo.guardadoDe != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(children: [
              if (repo.carregando) const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 4),
              Text(
                'Dados guardados de ${quando(repo.guardadoDe!)}'
                '${repo.carregando ? ' · atualizando…' : ' · sem conexão agora'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
        if (repo.medicao == null && repo.estimativaAtual == null && repo.carregando)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ?topo,
        Colunas(children: cartoes),
        RodapeFontes(repo: repo),
      ],
    );
  }
}

class _CartaoMedicao extends StatelessWidget {
  const _CartaoMedicao({
    required this.medicao,
    required this.estado,
    required this.cidade,
    this.aeroporto,
    this.estimativa,
    this.ventoEstimado,
    this.reserva,
    this.hoje,
    this.horas = const [],
    this.aoTrocarEstacao,
  });

  /// Abre a escolha da estação do INMET (só no Brasil).
  final VoidCallback? aoTrocarEstacao;

  /// Próximas horas (estimativa): índice UV quando não há UV oficial.
  final List<HoraChuva> horas;

  /// Previsão de hoje (máxima, mínima e índice UV previsto).
  final DiaPrevisao? hoje;

  /// Estação do INMET guardada quando uma estação local é usada.
  final Medicao? reserva;

  /// Medição oficial do INMET (pode estar longe ou antiga).
  final Medicao? medicao;
  final EstadoFonte? estado;
  final Cidade cidade;

  /// Vento do aeroporto, quando substitui o do INMET.
  final VentoAeroporto? aeroporto;

  /// Open-Meteo: valores de modelo, usados só quando falta o dado oficial.
  final Medicao? estimativa;
  final Medicao? ventoEstimado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final oficial = medicao;
    final est = estimativa;
    final m = est ?? oficial;
    if (m == null) {
      return Cartao(
        titulo: 'Detalhes de agora',
        icone: Icons.thermostat,
        children: [
          Text(estado?.falhou == true
              ? 'A estação do INMET não respondeu (${causaDoErro(estado?.erro)}). '
                  'Puxe a tela para baixo para tentar de novo.'
              : 'Carregando…'),
        ],
      );
    }
    final a = aeroporto;
    final ve = est == null ? ventoEstimado : null;
    final ventoKmh = a?.ventoKmh ?? m.ventoKmh ?? ve?.ventoKmh;
    final rajadaKmh = a != null ? a.rajadaKmh : (m.ventoKmh != null ? m.rajadaKmh : ve?.rajadaKmh);
    final direcao = a != null
        ? (a.variavel ? 'variável' : direcaoVento(a.direcao))
        : direcaoVento(m.ventoKmh != null ? m.ventoDirecao : ve?.ventoDirecao);
    // Visibilidade: aeroporto (METAR) ou a própria fonte (Canadá, estimativa).
    // Arredondada como aparece na tela, para a avaliação combinar com o número mostrado.
    final visBruta = a?.visibilidadeKm ?? m.visibilidadeKm;
    final visibilidade =
        visBruta == null ? null : (visBruta < 1 ? visBruta : visBruta.roundToDouble());
    final pressao = m.pressao ?? a?.pressao;
    // Ponto de orvalho medido; senão, calculado da temperatura e da umidade mostradas.
    final orvalho = m.orvalho ?? orvalhoCalculado(m.temperatura, m.umidade);
    final int? graus = a != null
        ? (a.variavel ? null : a.direcao)
        : (m.ventoKmh != null ? m.ventoDirecao : ve?.ventoDirecao);
    final vento = ventoKmh == null
        ? 'sem dado'
        : ventoKmh < 1
            ? 'calmo'
            : '${inteiro(ventoKmh)} km/h $direcao'.trim();
    final sensacaoCalculada = m.sensacao == null;
    // UV estimado: hora atual e maior valor do resto de hoje.
    final agoraH = DateTime.now();
    final horasHoje =
        horas.where((h) => h.uv != null && DateUtils.isSameDay(h.hora, agoraH)).toList();
    final uvAgora = horasHoje.isEmpty ? null : horasHoje.first.uv;
    final uvMax = horasHoje.isEmpty
        ? null
        : horasHoje.reduce((a, b) => (b.uv ?? 0) > (a.uv ?? 0) ? b : a);
    final uvEstimado = m.uv == null && hoje?.uv == null && uvAgora != null;
    final sensacao = m.sensacao ?? sensacaoTermica(m.temperatura, m.umidade, ventoKmh);
    return Cartao(
      titulo: est != null ? 'Detalhes de agora (estimativa)' : 'Detalhes de agora',
      icone: Icons.thermostat,
      children: [
        if (est != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tema.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Sem estação oficial a até 50 km com medição recente. '
              'Valores estimados por modelo (Open-Meteo), não são medições.',
              style: TextStyle(color: tema.colorScheme.onTertiaryContainer),
            ),
          ),
          const SizedBox(height: 12),
        ],
        GradeDados(
          children: [
            // Caixa Chuva só quando a estação mediu chuva (> 0 mm). Com 0,0 mm ela repetia
            // o que "Vai chover hoje?" já diz. Estação sem medidor (aeroporto, Canadá): nunca.
            if ((m.chuva1h ?? 0) > 0 || (m.chuva1h == null && (m.chuvaHoje ?? 0) > 0))
              if (m.chuva1h == null)
                Dado(
                    desenho: iconeChuva(m.chuvaHoje, size: 20),
                    lateral: iconeChuva(m.chuvaHoje, size: 30),
                    rotulo: 'Chuva hoje',
                    valor: comUnidade(m.chuvaHoje, 'mm', decimais: true))
              else
                Dado(
                    desenho: iconeChuva(m.chuva1h, size: 20),
                    lateral: iconeChuva(m.chuva1h, size: 30),
                    rotulo: 'Chuva (1 h)',
                    valor: comUnidade(m.chuva1h, 'mm', decimais: true),
                    detalhe: m.chuva1h == null ? null : avaliarChuva(m.chuva1h!).$1,
                    corDetalhe: m.chuva1h == null ? null : avaliarChuva(m.chuva1h!).$2),
            // Sensação térmica fica no quadro do céu, embaixo da temperatura.
            _avaliado(Icons.water_drop_outlined, 'Umidade', comUnidade(m.umidade, '%'),
                m.umidade == null ? null : avaliarUmidade(m.umidade!)),
            if (visibilidade != null)
              _avaliado(
                  Icons.visibility_outlined,
                  'Visibilidade',
                  visibilidade < 1 ? '${decimal(visibilidade)} km' : '${inteiro(visibilidade)} km',
                  avaliarVisibilidade(visibilidade)),
            // Rajada entra no quadrinho do Vento.
            _avaliado(Icons.air, 'Vento', vento,
                ventoKmh == null
                    ? null
                    : rajadaKmh == null
                        ? avaliarVento(ventoKmh)
                        : ('${avaliarVento(ventoKmh).$1} · rajadas de ${inteiro(rajadaKmh)} km/h',
                            avaliarVento(rajadaKmh).$2),
                lateral: graus != null && (ventoKmh ?? 0) >= 1 ? _setaVento(graus) : null),
            if (m.uv != null)
              _avaliado(Icons.wb_sunny_outlined, 'Índice UV agora', decimal(m.uv),
                  avaliarUv(m.uv!))
            else if (hoje?.uv != null)
              _avaliado(Icons.wb_sunny_outlined, 'UV máximo hoje', decimal(hoje!.uv),
                  avaliarUv(hoje!.uv!))
            else if (uvAgora != null)
              _avaliado(Icons.wb_sunny_outlined, 'Índice UV agora', inteiro(uvAgora),
                  avaliarUv(uvAgora)),
            // Máximo do resto do dia, só quando for maior que o de agora.
            if (m.uv == null &&
                hoje?.uv == null &&
                uvMax != null &&
                uvMax.uv!.round() > (uvAgora ?? 0).round())
              _avaliado(Icons.wb_sunny, 'UV máximo hoje',
                  '${inteiro(uvMax.uv)} às ${uvMax.hora.hour}h', avaliarUv(uvMax.uv!)),
            if (pressao != null)
              _avaliado(Icons.compress, 'Pressão', '${inteiro(pressao)} hPa', avaliarPressao(pressao)),
            if (orvalho != null)
              _avaliado(Icons.opacity, 'Ponto de orvalho', '${inteiro(orvalho)} °C',
                  avaliarOrvalho(orvalho)),
          ],
        ),
        const SizedBox(height: 12),
        if (est != null) ...[
          Fonte('Open-Meteo (modelo, open-meteo.com) · estimativa para ${quando(est.hora)}'),
          if (oficial != null)
            Fonte('estação oficial mais próxima: INMET ${tituloProprio(oficial.estacao)} '
                '(${oficial.codigo})'
                '${oficial.distanciaKm != null ? ', a ${inteiro(oficial.distanciaKm)} km' : ''}'
                ', medida às ${quando(oficial.hora)}'),
        ] else if (m.fonte == 'ECCC')
          Fonte('Environment and Climate Change Canada (serviço meteorológico oficial do '
              'Canadá) · estação ${m.estacao}'
              '${m.distanciaKm != null ? ', a ${inteiro(m.distanciaKm)} km' : ''}'
              ' · medido às ${quando(m.hora)}')
        else if (m.fonte == 'INMET')
          Fonte(
            'INMET · estação ${tituloProprio(m.estacao)} (${m.codigo})'
            '${m.distanciaKm != null ? ', a ${inteiro(m.distanciaKm)} km' : ''}'
            ' · medido às ${quando(m.hora)}',
            aviso: estado?.doCache == true ? 'sem conexão: dado guardado' : null,
          )
        else ...[
          Fonte('estação meteorológica da ${m.estacao}'
              '${m.distanciaKm != null ? ', a ${inteiro(m.distanciaKm)} km da sede do município' : ''}'
              ' · medido às ${quando(m.hora)}'),
          if (reserva != null)
            Fonte('reserva: INMET ${tituloProprio(reserva!.estacao)} (${reserva!.codigo})'
                '${reserva!.distanciaKm != null ? ', a ${inteiro(reserva!.distanciaKm)} km' : ''}'
                ': ${comUnidade(reserva!.temperatura, '°C', decimais: true)} às ${quando(reserva!.hora)}'),
        ],
        if (aoTrocarEstacao != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: aoTrocarEstacao,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Trocar estação'),
            ),
          ),
        if (hoje != null && (hoje!.maxima != null || hoje!.minima != null))
          Fonte('máxima e mínima: previsão ${hoje!.fonte}'
              '${m.uv == null && hoje!.uv != null ? ' · UV: ${hoje!.fonte == 'INMET' ? 'CPTEC/INPE' : hoje!.fonte}' : ''}'),
        if (uvEstimado)
          const Fonte('índice UV: estimativa do modelo Open-Meteo (open-meteo.com). '
              'O serviço de UV do CPTEC/INPE está enviando zero para todos os dias.'),
        if (sensacao != null && sensacaoCalculada)
          const Fonte('sensação térmica: calculada pelo app com temperatura, umidade e vento '
              '(índice de calor da NOAA; no frio, fórmula do Serviço Meteorológico do Canadá)'),
        if (a != null && cidade.latitude != null)
          Fonte(
            'vento e rajada: aeroporto ${a.nome} (${a.codigo}), '
            'a ${inteiro(a.distanciaKm(cidade.latitude!, cidade.longitude!))} km · '
            'medido às ${quando(a.hora)} (DECEA, via NOAA)',
          )
        else if (ve != null && m.ventoKmh == null)
          Fonte('vento e rajada: estimativa do modelo Open-Meteo para ${quando(ve.hora)}'),
      ],
    );
  }
}


/// Mar: maré (calculada a partir da tábua da Marinha) e ondas (CPTEC/INPE).
class _CartaoMar extends StatelessWidget {
  const _CartaoMar({required this.ondas, required this.agora, this.estacao, this.cidade});

  final List<PrevisaoOnda> ondas;
  final DateTime agora;
  final EstacaoMare? estacao;
  final Cidade? cidade;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final secao = tema.textTheme.titleSmall
        ?.copyWith(color: tema.colorScheme.primary, fontWeight: FontWeight.bold);
    final partes = <List<Widget>>[
      if (estacao != null) _mare(context, estacao!),
      if (ondas.isNotEmpty) _ondas(context),
    ];
    return Cartao(
      titulo: 'Mar',
      icone: Icons.waves,
      children: [
        for (var i = 0; i < partes.length; i++) ...[
          if (i > 0) const Divider(height: 28),
          if (partes.length > 1) ...[
            Text(i == 0 && estacao != null ? 'Maré' : 'Ondas', style: secao),
            const SizedBox(height: 6),
          ],
          ...partes[i],
        ],
      ],
    );
  }

  List<Widget> _mare(BuildContext context, EstacaoMare e) {
    final tema = Theme.of(context);
    final inicioDia = DateTime(agora.year, agora.month, agora.day);
    // Mesma grade de minutos para a lista de hoje e para a próxima maré.
    final doisDias = e.extremos(inicioDia, inicioDia.add(const Duration(hours: 48)));
    final amanha = inicioDia.add(const Duration(days: 1));
    final hoje = doisDias.where((x) => x.hora.isBefore(amanha)).toList();
    final proxima = doisDias.where((x) => x.hora.isAfter(agora)).firstOrNull;
    final enchendo = proxima?.alta ?? false;
    // Agora dentro de um estofo?
    final parada = doisDias
        .where((x) => !agora.isBefore(x.estofoInicio) && !agora.isAfter(x.estofoFim))
        .firstOrNull;
    String metros(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
    final cidadeLat = cidade?.latitude;
    final cidadeLon = cidade?.longitude;
    final km = cidadeLat != null && cidadeLon != null ? e.distanciaKm(cidadeLat, cidadeLon) : null;

    final cabecalho = tema.textTheme.labelSmall;
    final celula = tema.textTheme.bodyMedium;
    TableRow linha(ExtremoMare x) {
      final passou = x.hora.isBefore(agora);
      final cor = passou ? tema.colorScheme.onSurface.withValues(alpha: 0.45) : null;
      final estilo = celula?.copyWith(color: cor);
      Widget cel(String t, {TextStyle? s}) =>
          Padding(padding: const EdgeInsets.fromLTRB(0, 5, 14, 5), child: Text(t, style: s ?? estilo));
      return TableRow(children: [
        Padding(
          padding: const EdgeInsets.only(top: 5, right: 6),
          child: Icon(x.alta ? Icons.arrow_upward : Icons.arrow_downward,
              size: 18, color: cor ?? tema.colorScheme.onSurfaceVariant),
        ),
        cel(x.alta ? 'Alta' : 'Baixa'),
        cel(hora(x.hora), s: estilo?.copyWith(fontWeight: FontWeight.bold)),
        cel('${metros(x.altura)} m'),
        cel('${hora(x.estofoInicio)}–${hora(x.estofoFim)}'),
      ]);
    }

    return [
      if (parada != null) ...[
        Row(children: [
          Icon(Icons.pause_circle_outline, size: 32, color: tema.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text('Maré parada (estofo)', style: tema.textTheme.titleLarge)),
        ]),
        Text('Maré ${parada.alta ? 'alta' : 'baixa'} às ${hora(parada.hora)} '
            '(${metros(parada.altura)} m). Parada até ${hora(parada.estofoFim)}.'),
        const SizedBox(height: 10),
      ] else if (proxima != null) ...[
        Row(children: [
          Icon(enchendo ? Icons.north_east : Icons.south_east,
              size: 32, color: tema.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(enchendo ? 'Maré subindo' : 'Maré descendo',
                style: tema.textTheme.titleLarge),
          ),
        ]),
        Text('Próxima maré ${proxima.alta ? 'alta' : 'baixa'} às ${hora(proxima.hora)} '
            '(${metros(proxima.altura)} m)'),
        const SizedBox(height: 10),
      ],
      Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        columnWidths: const {
          0: IntrinsicColumnWidth(),
          1: IntrinsicColumnWidth(),
          2: IntrinsicColumnWidth(),
          3: IntrinsicColumnWidth(),
          4: FlexColumnWidth(),
        },
        children: [
          TableRow(children: [
            const SizedBox(),
            Padding(padding: const EdgeInsets.only(right: 14), child: Text('Maré', style: cabecalho)),
            Padding(padding: const EdgeInsets.only(right: 14), child: Text('Hora', style: cabecalho)),
            Padding(padding: const EdgeInsets.only(right: 14), child: Text('Altura', style: cabecalho)),
            Text('Estofo (parada)', style: cabecalho),
          ]),
          for (final x in hoje) linha(x),
        ],
      ),
      const SizedBox(height: 12),
      Fonte('maré calculada pelo app a partir da Tábua das Marés da Marinha do Brasil, '
          'estação ${e.nome}${km != null ? ', a ${inteiro(km)} km' : ''}. '
          'Erro típico: ${e.erro}. Alturas acima do nível de referência da carta náutica. '
          'Estofo: período em que o nível sobe ou desce menos de 5 cm por hora; '
          'a corrente pode virar em outro horário.'),
    ];
  }

  List<Widget> _ondas(BuildContext context) {
    final tema = Theme.of(context);
    // Previsão em vigor: o último horário que já começou (ou o primeiro, se nenhum começou).
    var i = ondas.lastIndexWhere((o) => !o.hora.isAfter(agora));
    if (i < 0) i = 0;
    final atual = ondas[i];
    final proximas = ondas.skip(i + 1).take(4).toList();
    return [
      Text('Ondas de ${decimal(atual.altura)} m', style: tema.textTheme.headlineSmall),
      Text('Agitação ${atual.agitacao.toLowerCase()}'
          '${atual.direcao.isNotEmpty ? ' · vindas de ${atual.direcao}' : ''}'),
      if (atual.ventoKmh != null)
        Text('Vento no mar: ${inteiro(atual.ventoKmh)} km/h ${atual.ventoDirecao}'.trim()),
      if (proximas.isNotEmpty) ...[
        const SizedBox(height: 12),
        GradeDados(children: [
          for (final o in proximas)
            Dado(
              icone: Icons.waves,
              rotulo: quando(o.hora, agora: agora),
              valor: '${decimal(o.altura)} m',
            ),
        ]),
      ],
      const SizedBox(height: 12),
      Fonte('previsão de ondas CPTEC/INPE para ${quando(atual.hora, agora: agora)}'),
    ];
  }
}

/// Próximas 24 horas (Open-Meteo, estimativa): temperatura, chuva e UV de hora em hora.
/// Não há fonte oficial brasileira com previsão por hora.
/// O que a linha do gráfico das próximas horas mostra (abas do cartão).
enum _Linha { temperatura, sensacao, chuva, vento }

class _CartaoProximasHoras extends StatefulWidget {
  const _CartaoProximasHoras({required this.horas, this.oficial = false});

  final List<HoraChuva> horas;

  /// Previsão por hora oficial (Canadá) em vez de estimativa.
  final bool oficial;

  @override
  State<_CartaoProximasHoras> createState() => _CartaoProximasHorasState();
}

class _CartaoProximasHorasState extends State<_CartaoProximasHoras> {
  var _linha = _Linha.temperatura;

  List<HoraChuva> get horas => widget.horas;
  bool get oficial => widget.oficial;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final inicioHora = DateTime.now().subtract(const Duration(minutes: 59));
    final lista = horas.where((h) => h.hora.isAfter(inicioHora)).take(24).toList();
    final temps = lista.map((h) => h.temperatura).whereType<double>().toList();
    final comChance = lista.take(12).where((h) => (h.probabilidade ?? 0) >= 30).toList();
    String chuva;
    if (comChance.isEmpty) {
      chuva = 'Chance baixa de chuva nas próximas 12 horas';
    } else {
      final maior =
          comChance.reduce((a, b) => (b.probabilidade ?? 0) > (a.probabilidade ?? 0) ? b : a);
      final primeira = comChance.first;
      chuva = primeira == maior
          ? 'Maior chance de chuva às ${primeira.hora.hour}h (${maior.probabilidade} %)'
          : 'Chance de chuva a partir das ${primeira.hora.hour}h; '
              'maior às ${maior.hora.hour}h (${maior.probabilidade} %)';
    }
    String? faixa;
    if (temps.isNotEmpty) {
      final quente = lista.where((h) => h.temperatura != null).reduce(
          (a, b) => b.temperatura! > a.temperatura! ? b : a);
      final fria = lista.where((h) => h.temperatura != null).reduce(
          (a, b) => b.temperatura! < a.temperatura! ? b : a);
      faixa = 'De ${inteiro(fria.temperatura)}° (${fria.hora.hour}h) '
          'a ${inteiro(quente.temperatura)}° (${quente.hora.hour}h)';
    }
    return Cartao(
      // No Brasil a previsão por hora é estimativa de modelo; o aviso fica em Fontes.
      titulo: 'Próximas 24 horas',
      icone: Icons.schedule,
      children: [
        if (faixa != null) Text(faixa, style: tema.textTheme.titleMedium),
        Text(chuva),
        const SizedBox(height: 10),
        // Abas: o que a linha mostra (ideia de outros apps de clima).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (l, nome) in [
              (_Linha.temperatura, 'Temperatura'),
              (_Linha.sensacao, 'Sensação'),
              (_Linha.chuva, 'Chuva (mm)'),
              (_Linha.vento, 'Vento (km/h)'),
            ])
              if (lista.any((h) => _valor(h, l) != null))
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(nome),
                    selected: _linha == l,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _linha = l),
                  ),
                ),
          ]),
        ),
        const SizedBox(height: 10),
        // Quadradinhos por hora com a linha da temperatura passando por dentro, no alto
        // deles (mistura dos dois estilos que o usuário mostrou).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Stack(children: [
            Row(children: [
              for (var i = 0; i < lista.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _ColunaHora(hora: lista[i]),
              ],
            ]),
            Positioned(
              left: 0,
              top: 0,
              child: IgnorePointer(
                child: CustomPaint(
                  size: Size(lista.length * _passoHora - 6, _alturaGrafico),
                  painter: _PintorTemperaturas(
                    temps: [for (final h in lista) _valor(h, _linha)],
                    rotulo: switch (_linha) {
                      _Linha.chuva => (v) => v == 0 ? '0' : decimal(v),
                      _Linha.vento => (v) => '${v.round()}',
                      _ => (v) => '${v.round()}°',
                    },
                    // Chuva: a linha começa no zero (sem chuva fica embaixo).
                    minimo: _linha == _Linha.chuva ? 0 : null,
                    linha: tema.colorScheme.primary,
                    texto: tema.textTheme.titleSmall!.copyWith(
                        color: tema.colorScheme.onSurface, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        if (oficial)
          const Fonte('previsão por hora do Environment and Climate Change Canada '
              '(serviço meteorológico oficial do Canadá)')
        else
          const Fonte('Open-Meteo (modelo, open-meteo.com): temperatura (gráfico), sensação térmica, chance de chuva e '
              'índice UV de hora em hora. Estimativa: não é previsão oficial.'),
      ],
    );
  }
}

/// Valor da hora para a aba escolhida.
double? _valor(HoraChuva h, _Linha l) => switch (l) {
      _Linha.temperatura => h.temperatura,
      _Linha.sensacao => h.sensacao,
      _Linha.chuva => h.milimetros?.toDouble(),
      _Linha.vento => h.ventoKmh,
    };

/// Largura de cada hora (coluna de 62 + espaço de 6), igual no gráfico e nas colunas.
const double _passoHora = 68;

/// Altura da parte de cima de cada quadradinho, onde passa a linha da temperatura.
const double _alturaGrafico = 88;

/// Linha das temperaturas das próximas horas, com o valor sobre cada ponto.
class _PintorTemperaturas extends CustomPainter {
  _PintorTemperaturas({
    required this.temps,
    required this.linha,
    required this.texto,
    required this.rotulo,
    this.minimo,
  });

  final List<double?> temps;

  /// Texto sobre cada ponto ("31°", "2,5", "18").
  final String Function(double) rotulo;

  /// Valor que fica na base do gráfico (chuva: zero); nulo = menor valor da lista.
  final double? minimo;
  final Color linha;
  final TextStyle texto;

  @override
  void paint(Canvas canvas, Size size) {
    final validos = temps.whereType<double>().toList();
    if (validos.isEmpty) return;
    final menor = minimo ?? validos.reduce(math.min);
    // Faixa mínima, para variações pequenas não parecerem enormes.
    final maior = math.max(validos.reduce(math.max), menor + (minimo == null ? 4 : 1));
    const topo = 30.0; // espaço para o número acima do ponto mais alto
    const base = 10.0;
    final alturaUtil = size.height - topo - base;
    Offset? ponto(int i) {
      final t = temps[i];
      if (t == null) return null;
      final frac = maior == menor ? 0.5 : (t - menor) / (maior - menor);
      return Offset(i * _passoHora + (_passoHora - 6) / 2, topo + (1 - frac) * alturaUtil);
    }

    final pontos = [for (var i = 0; i < temps.length; i++) ponto(i)];
    final caminho = Path();
    final area = Path();
    Offset? primeiro;
    Offset? ultimo;
    for (final p in pontos) {
      if (p == null) continue;
      if (primeiro == null) {
        caminho.moveTo(p.dx, p.dy);
        area.moveTo(p.dx, size.height);
        area.lineTo(p.dx, p.dy);
        primeiro = p;
      } else {
        caminho.lineTo(p.dx, p.dy);
        area.lineTo(p.dx, p.dy);
      }
      ultimo = p;
    }
    if (primeiro != null && ultimo != null) {
      area
        ..lineTo(ultimo.dx, size.height)
        ..close();
      canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [linha.withValues(alpha: 0.28), linha.withValues(alpha: 0.0)],
            ).createShader(Offset.zero & size));
    }
    canvas.drawPath(
        caminho,
        Paint()
          ..color = linha
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < pontos.length; i++) {
      final p = pontos[i];
      if (p == null) continue;
      canvas.drawCircle(p, 3.5, Paint()..color = linha);
      final tp = TextPainter(
        text: TextSpan(text: rotulo(temps[i]!), style: texto),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height - 4));
    }
  }

  @override
  bool shouldRepaint(_PintorTemperaturas antigo) =>
      !listEquals(antigo.temps, temps) || antigo.linha != linha || antigo.texto != texto;
}

class _ColunaHora extends StatelessWidget {
  const _ColunaHora({required this.hora});

  final HoraChuva hora;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final p = hora.probabilidade ?? 0;
    final destaque = p >= 50;
    final fundo = destaque
        ? tema.colorScheme.tertiaryContainer
        : tema.colorScheme.surfaceContainerHighest;
    final texto = destaque ? tema.colorScheme.onTertiaryContainer : tema.colorScheme.onSurface;
    final uv = hora.uv;
    return Container(
      width: _passoHora - 6,
      height: _alturaGrafico + 124,
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(12)),
      // No alto, a linha da temperatura (desenhada por cima); embaixo, céu, hora,
      // sensação, chuva e UV.
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const SizedBox(height: _alturaGrafico),
        simboloCodigoWmo(hora.codigo, hora.dia ?? true, size: 26, color: texto),
        Text('${hora.hora.hour}h',
            style: tema.textTheme.labelLarge?.copyWith(color: texto, fontWeight: FontWeight.w600)),
        // Sensação térmica da hora (importante no frio do Canadá e no calor do Rio).
        Text(hora.sensacao == null ? '' : 'sens. ${inteiro(hora.sensacao)}°',
            style: tema.textTheme.labelSmall?.copyWith(color: texto.withValues(alpha: 0.85))),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.water_drop, size: 12, color: texto.withValues(alpha: 0.7)),
          Text(' $p %', style: tema.textTheme.labelSmall?.copyWith(color: texto)),
        ]),
        Text(uv == null || (hora.dia == false && uv < 0.5) ? '' : 'UV ${inteiro(uv)}',
            style: tema.textTheme.labelSmall?.copyWith(
                color: uv == null ? texto : avaliarUv(uv).$2, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}


/// Quadro "Vai chover hoje?": período da chuva na previsão oficial e resumo do dia.
/// (A chuva medida agora fica na caixa "Chuva" do quadro Agora e na aba Chuva.)
class _CartaoChuva extends StatelessWidget {
  const _CartaoChuva({required this.repo, required this.agora, this.hoje});

  final Repositorio repo;
  final DateTime agora;
  final DiaPrevisao? hoje;

  @override
  Widget build(BuildContext context) {
    return Cartao(
      titulo: 'Vai chover hoje?',
      desenho: const NuvemChuva(),
      children: _hoje(context),
    );
  }

  List<Widget> _hoje(BuildContext context) {
    final tema = Theme.of(context);
    final proxima = proximaChuva(repo.previsao, agora);
    return [
      Text(fraseChuva(proxima, agora, diasConsultados: repo.previsao.length),
          style: tema.textTheme.titleLarge),
      if (hoje != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          simboloTempo(hoje!.resumo, size: 32, color: tema.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(hoje!.resumo, style: tema.textTheme.titleMedium)),
        ]),
      ],
      const SizedBox(height: 6),
      Fonte('previsão ${proxima?.fonte ?? repo.previsao.first.fonte}'
          ' (manhã: 6h às 12h, tarde: 12h às 18h, noite: 18h às 24h)'),
    ];
  }
}

Dado _avaliado(IconData icone, String rotulo, String valor, (String, Color)? avaliacao,
        {Widget? lateral}) =>
    Dado(
      icone: icone,
      rotulo: rotulo,
      valor: valor,
      detalhe: avaliacao?.$1,
      corDetalhe: avaliacao?.$2,
      lateral: lateral,
    );

/// Seta que aponta para onde o vento vai ([graus] = de onde ele vem, 0 = norte).
Widget _setaVento(int graus) =>
    Transform.rotate(angle: (graus + 180) * math.pi / 180, child: const Icon(Icons.navigation));

/// Nascer e pôr do sol e da lua e fase da lua, calculados no aparelho.
class _CartaoSolLua extends StatelessWidget {
  const _CartaoSolLua({required this.agora, required this.lat, required this.lon});

  final DateTime agora;
  final double lat;
  final double lon;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final sol = Astro.sol(agora, lat, lon);
    final lua = Astro.lua(agora, lat, lon);
    final idadeLua = Lua.idade(agora);
    final proximasFases = Lua.fases(agora, agora.add(const Duration(days: 30)))
        .where((f) => f.fase == FasePrincipal.cheia || f.fase == FasePrincipal.nova)
        .take(2)
        .toList();
    String dia(DateTime t) {
      final l = t.toLocal();
      return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
    }

    String h(DateTime? t) => t == null ? 'não há hoje' : hora(t);
    String? duracao;
    if (sol.nascer != null && sol.por != null) {
      final min = sol.por!.difference(sol.nascer!).inMinutes;
      duracao = 'Duração do dia: ${min ~/ 60} h ${min % 60} min';
    }
    final luz = Astro.solNaAltitude(agora, lat, lon, -6);
    final menos4 = Astro.solNaAltitude(agora, lat, lon, -4);
    final mais6 = Astro.solNaAltitude(agora, lat, lon, 6);
    String faixa(DateTime? a, DateTime? b) =>
        a == null || b == null ? '' : '${hora(a)}–${hora(b)}';
    String juntar(String manha, String tarde) =>
        [manha, tarde].where((x) => x.isNotEmpty).join(' e ');
    final horaAzul = juntar(faixa(luz.nascer, menos4.nascer), faixa(menos4.por, luz.por));
    final horaDourada =
        juntar(faixa(menos4.nascer, mais6.nascer), faixa(mais6.por, menos4.por));
    final luaPequena = DesenhoLua(idade: idadeLua, size: 20);
    return Cartao(
      titulo: 'Sol e lua',
      icone: Icons.wb_twilight,
      children: [
        GradeDados(children: [
          Dado(icone: Icons.wb_sunny_outlined, rotulo: 'Nascer do sol', valor: h(sol.nascer)),
          Dado(icone: Icons.wb_twilight, rotulo: 'Pôr do sol', valor: h(sol.por)),
          Dado(icone: Icons.light_mode_outlined, rotulo: 'Primeira luz', valor: h(luz.nascer)),
          Dado(icone: Icons.nights_stay_outlined, rotulo: 'Última luz', valor: h(luz.por)),
          Dado(desenho: luaPequena, rotulo: 'Nascer da lua', valor: h(lua.nascer)),
          Dado(desenho: luaPequena, rotulo: 'Pôr da lua', valor: h(lua.por)),
        ]),
        if (duracao != null) ...[
          const SizedBox(height: 10),
          Text(duracao),
        ],
        if (horaDourada.isNotEmpty || horaAzul.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (horaDourada.isNotEmpty)
            Text('Hora dourada (luz baixa e quente): $horaDourada'),
          if (horaAzul.isNotEmpty)
            Text('Hora azul (céu azul-escuro, antes do nascer e depois do pôr): $horaAzul'),
        ],
        const SizedBox(height: 12),
        Row(children: [
          DesenhoLua(idade: idadeLua, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${Lua.nome(agora)} · ${inteiro(Lua.iluminada(agora) * 100)} % iluminada',
                  style: tema.textTheme.titleSmall),
              if (proximasFases.isNotEmpty)
                Text(proximasFases.map((f) => '${Lua.nomeFase(f.fase)} ${dia(f.quando)}').join(' · '),
                    style: tema.textTheme.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        const Fonte('calculado pelo app com a posição do sol e da lua (fórmulas do '
            'Astronomical Almanac), para a sede do município. Erro típico: 1 a 3 minutos. '
            'Primeira e última luz: sol 6° abaixo do horizonte. Hora azul: sol entre 6° e 4° '
            'abaixo; hora dourada: entre 4° abaixo e 6° acima. '
            'A lua aparece como vista do hemisfério sul.'),
      ],
    );
  }
}
