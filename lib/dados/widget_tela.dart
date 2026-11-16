import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workmanager/workmanager.dart';

import '../telas/ceu.dart';
import '../telas/componentes.dart' show gravidadeAlerta;
import '../util/formatos.dart';
import 'astro.dart';
import 'fontes.dart';
import 'mare.dart';
import 'preferencias.dart';
import 'repositorio.dart';

/// Nomes das classes Android dos widgets da tela inicial do celular.
const _provedores = [
  'app.climabit.WidgetClima1x1',
  'app.climabit.WidgetClima2x2',
  'app.climabit.WidgetClima4x2',
  'app.climabit.WidgetSimples1x1',
  'app.climabit.WidgetSimples2x2',
  'app.climabit.WidgetSimples4x2',
  'app.climabit.WidgetClima4x1',
  'app.climabit.WidgetSimples4x1',
];

const tarefaWidget = 'atualizar_widget';

/// Dados que os widgets mostram (textos prontos, calculados aqui).
class DadosWidget {
  const DadosWidget({
    required this.temperatura,
    required this.ceu,
    required this.maxMin,
    required this.chuva,
    required this.cidade,
    required this.hora,
    required this.fundo,
    required this.icone,
    required this.nivelAlerta,
    required this.textoAlerta,
    this.sensacao = '',
    this.horas = const [],
    this.alertaCurto = '',
  });

  /// Resumo do alerta em uma linha breve (barra 4 × 1): "Tempestade até 23:59 (+1)".
  final String alertaCurto;

  /// "sensação 26°" (barra 4 × 1).
  final String sensacao;

  /// Até 3 horas do dia para a barra 4 × 1: ("15h", "26°", "sens. 28°").
  final List<(String, String, String)> horas;

  final String temperatura;
  final String ceu;
  final String maxMin;
  final String chuva;
  final String cidade;
  final String hora;

  /// Parte do nome da imagem de fundo: `estado_momento_local` (ex.: `parcial_dia_mar`).
  final String fundo;

  /// Ícone dos widgets simples: sol, parcial_dia, nublado, chuva, trovoada, lua,
  /// parcial_noite.
  final String icone;

  /// 0 = sem alerta; 1 = amarelo; 2 = vermelho.
  final int nivelAlerta;
  final String textoAlerta;

  Map<String, Object> paraMapa() => {
        'temperatura': temperatura,
        'ceu': ceu,
        'max_min': maxMin,
        'chuva': chuva,
        'cidade': cidade,
        'hora': hora,
        'fundo': fundo,
        'icone': icone,
        'nivel_alerta': nivelAlerta,
        'texto_alerta': textoAlerta,
        'sensacao': sensacao,
        'alerta_curto': alertaCurto,
        for (var i = 0; i < 3; i++) ...{
          'h${i + 1}_hora': i < horas.length ? horas[i].$1 : '',
          'h${i + 1}_temp': i < horas.length ? horas[i].$2 : '',
          'h${i + 1}_sens': i < horas.length ? horas[i].$3 : '',
        },
      };
}

/// Calcula o que os widgets mostram a partir dos dados já obtidos. Nulo sem medição.
DadosWidget? calcularDadosWidget(Repositorio repo, DateTime agora) {
  final m = repo.estimativaAtual ?? repo.medicao;
  if (m == null || m.temperatura == null) return null;
  final hoje = repo.previsao.isNotEmpty && DateUtils.isSameDay(repo.previsao.first.dia, agora)
      ? repo.previsao.first
      : null;
  final lat = repo.cidade.latitude;
  final lon = repo.cidade.longitude;
  final alt = lat != null && lon != null ? Astro.altitudeSol(agora, lat, lon) : null;
  final noite = alt != null ? alt < -0.833 : (agora.hour < 6 || agora.hour >= 18);
  final estado =
      estadoCeu(
          resumoPeriodo: resumoDoPeriodo(hoje, agora),
          chuvaUltimaHora: m.chuva1h,
          observado: hoje?.periodos.any((p) => p.nome == 'Agora') ?? false);
  final litoral = repo.ondas.isNotEmpty || EstacaoMare.proxima(lat, lon) != null;
  final tarde = !noite &&
      alt != null &&
      alt < 7 &&
      (estado == EstadoCeu.limpo || estado == EstadoCeu.parcial);
  final momento = noite ? 'noite' : (tarde ? 'tarde' : 'dia');
  final ventoKmh = repo.ventoAeroporto?.ventoKmh ?? m.ventoKmh ?? repo.ventoEstimado?.ventoKmh;
  final sensacaoAgora = m.sensacao ?? sensacaoTermica(m.temperatura, m.umidade, ventoKmh);
  final paisagem = escolherPaisagem(
    estado: estado,
    temperatura: m.temperatura,
    sensacao: sensacaoAgora,
    chuvaUltimaHora: m.chuva1h,
    resumo: resumoDoPeriodo(hoje, agora),
  );

  // Chance de chuva: maior das próximas 12 horas; senão, a do dia.
  final chances = repo.chuvaHoraria.take(12).map((h) => h.probabilidade).whereType<int>();
  final chance = chances.isNotEmpty
      ? chances.reduce((a, b) => a > b ? a : b)
      : hoje?.probabilidadeChuva;

  // Alerta: sirene acionada ou aviso grave = vermelho; aviso de potencial perigo = amarelo.
  final alertas = repo.alertas.where((a) => a.ativo(agora)).toList()
    ..sort((a, b) => gravidadeAlerta(b).compareTo(gravidadeAlerta(a)));
  final sirenes = repo.sirenes.where((s) => s.acionada).toList();
  var nivel = 0;
  var texto = '';
  var curto = '';
  if (sirenes.isNotEmpty) {
    nivel = 2;
    texto = sirenes.length == 1 ? 'Sirene acionada' : '${sirenes.length} sirenes acionadas';
    curto = texto;
  } else if (alertas.isNotEmpty) {
    nivel = gravidadeAlerta(alertas.first) >= 2 ? 2 : 1;
    texto = alertas.length == 1
        ? 'Alerta: ${alertas.first.descricao}'
        : '${alertas.length} alertas: ${alertas.first.descricao}';
    curto = resumoAlerta(alertas.first, alertas.length, agora);
  }

  return DadosWidget(
    temperatura: '${m.temperatura!.round()}°',
    ceu: nomeCeu(estado, noite),
    maxMin: hoje?.maxima != null && hoje?.minima != null
        ? '↑${hoje!.maxima}° ↓${hoje.minima}°'
        : '',
    chuva: chance == null ? '' : 'Chuva $chance %',
    cidade: repo.cidade.nome,
    hora: hora(agora),
    // Cenário do tipo de dia (campo, vulcão, cachoeiras, neve) ou morros comuns.
    fundo: paisagem == Paisagem.morros
        ? '${estado.name}_${momento}_${litoral ? 'mar' : 'campo'}'
        : 'tema_${paisagem.name}_${noite ? 'noite' : 'dia'}',
    icone: switch (estado) {
      EstadoCeu.limpo => noite ? 'lua' : 'sol',
      EstadoCeu.parcial => noite ? 'parcial_noite' : 'parcial_dia',
      EstadoCeu.nublado => 'nublado',
      EstadoCeu.chuva => 'chuva',
      EstadoCeu.trovoada => 'trovoada',
    },
    nivelAlerta: nivel,
    textoAlerta: texto,
    sensacao: sensacaoAgora == null ? '' : 'sensação ${sensacaoAgora.round()}°',
    alertaCurto: curto,
    horas: [
      for (final h in horasDoDia(repo.chuvaHoraria, agora))
        (
          '${h.hora.hour}h',
          '${h.temperatura!.round()}°',
          'sens. ${(h.sensacao ?? h.temperatura!).round()}°',
        ),
    ],
  );
}

/// Alerta em uma linha: descrição sem o prefixo "Aviso:", até quando vale e quantos
/// alertas a mais existem.
String resumoAlerta(Alerta a, int total, DateTime agora) {
  final d = a.descricao.replaceFirst(RegExp(r'^(Alerta|Aviso)\s*:\s*', caseSensitive: false), '');
  final nome = d.isEmpty ? 'Alerta' : '${d[0].toUpperCase()}${d.substring(1)}';
  return '$nome até ${quando(a.fim, agora: agora)}${total > 1 ? ' (+${total - 1})' : ''}';
}

/// 3 horas à frente, de 3 em 3 horas (15h, 18h, 21h...), com temperatura prevista.
List<HoraChuva> horasDoDia(List<HoraChuva> horas, DateTime agora) => horas
    .where((h) => h.temperatura != null && h.hora.isAfter(agora) && h.hora.hour % 3 == 0)
    .take(3)
    .toList();

/// Grava os dados e redesenha os widgets (com o app aberto ou em segundo plano).
Future<void> atualizarWidgets(Repositorio repo) async {
  final d = calcularDadosWidget(repo, DateTime.now());
  if (d == null) return;
  for (final e in d.paraMapa().entries) {
    await HomeWidget.saveWidgetData(e.key, e.value);
  }
  for (final p in _provedores) {
    try {
      await HomeWidget.updateWidget(qualifiedAndroidName: p);
    } catch (_) {
      // Widget ainda não colocado na tela: nada a redesenhar.
    }
  }
}

/// Liga a atualização a cada 30 minutos só quando há widget na tela inicial.
Future<void> agendarAtualizacaoDosWidgets() async {
  try {
    final instalados = await HomeWidget.getInstalledWidgets();
    if (instalados.isEmpty) {
      await Workmanager().cancelByUniqueName(tarefaWidget);
    } else {
      await Workmanager().registerPeriodicTask(
        tarefaWidget,
        tarefaWidget,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    }
  } catch (_) {
    // Sem widgets ou sem suporte: o app funciona igual.
  }
}

/// Tarefa em segundo plano: consulta as fontes da cidade atual e atualiza os widgets.
Future<void> atualizarWidgetsEmSegundoPlano() async {
  final instalados = await HomeWidget.getInstalledWidgets();
  if (instalados.isEmpty) {
    await Workmanager().cancelByUniqueName(tarefaWidget);
    return;
  }
  final prefs = await Preferencias.carregar();
  await EstacaoMare.carregar();
  final repo = Repositorio(cidade: prefs.cidadeAtual);
  await repo.atualizar();
  await atualizarWidgets(repo);
}
