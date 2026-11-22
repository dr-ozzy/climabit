import 'package:material_ui/material_ui.dart';

import '../dados/fontes.dart';
import '../util/formatos.dart';
import 'ceu.dart';
import 'componentes.dart';

/// Chance de chuva a partir da qual a hora conta como "com chuva" no resumo.
const _limiarChance = 30;

/// Tipo de chuva pelo código do tempo (WMO) da hora.
String _tipoChuva(int? codigo) => switch (codigo ?? 61) {
      >= 95 => 'trovoadas',
      >= 80 && <= 82 => 'pancadas de chuva',
      >= 51 && <= 57 => 'garoa',
      >= 71 && <= 77 || 85 || 86 => 'neve',
      _ => 'chuva',
    };

bool _chuvosa(HoraChuva h) => (h.probabilidade ?? 0) >= _limiarChance;

/// Frase de uma linha sobre as próximas 12 horas, ao estilo "Ensolarado até as 17h;
/// pancadas de chuva a partir das 18h." (ideia tirada de outros apps de clima; o texto
/// é do ClimaBit). [ceu] é o céu de agora; [horas] começa na hora atual.
String fraseResumo(EstadoCeu? ceu, bool noite, List<HoraChuva> horas, DateTime agora) {
  final proximas = horas.where((h) => h.hora.isAfter(agora.subtract(const Duration(minutes: 59))))
      .take(12)
      .toList();
  final chovendo = ceu == EstadoCeu.chuva || ceu == EstadoCeu.trovoada;
  final String frase;
  if (chovendo) {
    final para = proximas.skip(1).where((h) => !_chuvosa(h)).firstOrNull;
    frase = para == null
        ? '${nomeCeu(ceu!, noite)} agora; a chuva deve continuar nas próximas horas.'
        : '${nomeCeu(ceu!, noite)} agora; deve melhorar por volta das ${para.hora.hour}h.';
  } else {
    final chuva = proximas.where(_chuvosa).firstOrNull;
    final ceuTexto = ceu == null ? 'Sem chuva' : nomeCeu(ceu, noite);
    if (chuva == null) {
      frase = '$ceuTexto, sem chuva prevista nas próximas 12 horas.';
    } else if (!chuva.hora.isAfter(agora.add(const Duration(minutes: 30)))) {
      final tipo = _tipoChuva(chuva.codigo);
      frase = '${tipo[0].toUpperCase()}${tipo.substring(1)} possível a qualquer momento '
          '(${chuva.probabilidade} %).';
    } else {
      final antes = chuva.hora.subtract(const Duration(hours: 1));
      frase = '$ceuTexto até as ${antes.hour}h; ${_tipoChuva(chuva.codigo)} '
          'a partir das ${chuva.hora.hour}h (${chuva.probabilidade} %).';
    }
  }
  // Calor forte nas próximas horas.
  final quentes = proximas.where((h) => h.temperatura != null).toList();
  if (quentes.isNotEmpty) {
    final pico = quentes.reduce((a, b) => b.temperatura! > a.temperatura! ? b : a);
    if (pico.temperatura! >= 35) {
      return '$frase Calor forte: até ${inteiro(pico.temperatura)}° às ${pico.hora.hour}h.';
    }
  }
  return frase;
}

/// "Chance de chuva na próxima hora: 7 %", ou nulo sem dado.
String? chanceProximaHora(List<HoraChuva> horas, DateTime agora) {
  final h = horas.where((h) => h.hora.isAfter(agora)).firstOrNull;
  if (h?.probabilidade == null) return null;
  return 'Chance de chuva na próxima hora: ${h!.probabilidade} %';
}

/// Comparação com a mesma hora de ontem, pelo mesmo modelo (Open-Meteo):
/// "3° mais quente que ontem a esta hora". Nulo quando falta a hora de ontem.
String? comparacaoOntem(List<HoraChuva> horas, List<HoraChuva> passadas, DateTime agora) {
  HoraChuva? perto(List<HoraChuva> l, DateTime alvo) {
    HoraChuva? melhor;
    for (final h in l) {
      if (h.temperatura == null) continue;
      final d = h.hora.difference(alvo).inMinutes.abs();
      if (d <= 40 && (melhor == null || d < melhor.hora.difference(alvo).inMinutes.abs())) {
        melhor = h;
      }
    }
    return melhor;
  }

  final hoje = perto(horas, agora) ?? perto(passadas, agora);
  final ontem = perto(passadas, agora.subtract(const Duration(hours: 24)));
  if (hoje == null || ontem == null) return null;
  final dif = hoje.temperatura! - ontem.temperatura!;
  if (dif.abs() < 1.5) return 'Temperatura parecida com a de ontem a esta hora.';
  final graus = dif.abs().round();
  return '$graus° ${dif > 0 ? 'mais quente' : 'mais frio'} que ontem a esta hora.';
}

/// Cartão do topo da tela Agora: frase do dia, chance na próxima hora e comparação com
/// ontem. Tudo vem da previsão por hora (estimativa de modelo no Brasil).
/// Risco de trovoada nas próximas 12 horas, pela energia disponível para tempestades (CAPE)
/// e pelo código de trovoada do modelo: "Risco de trovoada: alto entre 14h e 18h".
/// Nulo quando o risco é baixo ou não há CAPE (ex.: previsão oficial do Canadá).
String? riscoTrovoada(List<HoraChuva> horas, DateTime agora) {
  final proximas = horas
      .where((h) => h.hora.isAfter(agora.subtract(const Duration(minutes: 59))))
      .take(12)
      .toList();
  if (proximas.every((h) => h.cape == null)) return null;
  int nivel(HoraChuva h) {
    final cape = h.cape ?? 0;
    final codigo = h.codigo ?? 0;
    final chance = h.probabilidade ?? 0;
    if (codigo >= 95 || (cape >= 2500 && chance >= 30)) return 2;
    if (cape >= 1000 && chance >= 20) return 1;
    return 0;
  }

  final niveis = [for (final h in proximas) nivel(h)];
  final maior = niveis.fold(0, (a, b) => a > b ? a : b);
  if (maior == 0) return null;
  final i0 = niveis.indexOf(maior);
  final i1 = niveis.lastIndexOf(maior);
  final ini = proximas[i0].hora.hour;
  final fim = proximas[i1].hora.add(const Duration(hours: 1)).hour;
  final nome = maior == 2 ? 'alto' : 'moderado';
  return 'Risco de trovoada: $nome entre ${ini}h e ${fim}h (estimativa).';
}

const _diasSemana = [
  'Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado',
  'Domingo'
];

/// Aviso de tempo marcante nos próximos 6 dias (a partir de amanhã), ao estilo
/// "Quinta-feira: chuva forte prevista." Nulo quando nenhum dia se destaca.
/// "Trovoadas isoladas" sozinhas não contam (o INMET escreve isso quase todo dia no verão).
String? avisoProximosDias(List<DiaPrevisao> dias, DateTime agora, {bool canada = false}) {
  final hoje = DateTime(agora.year, agora.month, agora.day);
  for (final d in dias) {
    final dia = DateTime(d.dia.year, d.dia.month, d.dia.day);
    final diff = dia.difference(hoje).inDays;
    if (diff < 1 || diff > 6) continue;
    final texto = d.resumo.toLowerCase();
    final String? oQue;
    if (texto.contains('tempestade') || texto.contains('temporal')) {
      oQue = 'tempestade prevista';
    } else if (texto.contains('chuva forte') || texto.contains('chuvas fortes') ||
        texto.contains('heavy rain') || texto.contains('pluie forte')) {
      oQue = 'chuva forte prevista';
    } else if ((d.maxima ?? 0) >= 35) {
      oQue = 'calor forte (máx. ${d.maxima}°)';
    } else if (d.minima != null && d.minima! <= (canada ? -15 : 10)) {
      oQue = 'frio (mín. ${d.minima}°)';
    } else {
      oQue = null;
    }
    if (oQue == null) continue;
    final nome = diff == 1 ? 'Amanhã' : _diasSemana[dia.weekday - 1];
    return '$nome: $oQue.';
  }
  return null;
}

class CartaoResumo extends StatelessWidget {
  const CartaoResumo({
    super.key,
    required this.ceu,
    required this.noite,
    required this.horas,
    required this.passadas,
    required this.agora,
    this.oficial = false,
    this.dias = const [],
    this.canada = false,
  });

  /// Previsão por dia (para o aviso dos próximos dias).
  final List<DiaPrevisao> dias;
  final bool canada;

  final EstadoCeu? ceu;
  final bool noite;
  final List<HoraChuva> horas;
  final List<HoraChuva> passadas;
  final DateTime agora;

  /// Previsão por hora oficial (Canadá).
  final bool oficial;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final proxima = chanceProximaHora(horas, agora);
    final ontem = comparacaoOntem(horas, passadas, agora);
    final marcante = avisoProximosDias(dias, agora, canada: canada);
    final trovoada = riscoTrovoada(horas, agora);
    return Cartao(
      titulo: 'Resumo',
      icone: Icons.short_text,
      children: [
        Text(fraseResumo(ceu, noite, horas, agora), style: tema.textTheme.titleMedium),
        if (proxima != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.water_drop_outlined, size: 18, color: tema.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(proxima)),
          ]),
        ],
        if (ontem != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.history, size: 18, color: tema.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(ontem)),
          ]),
        ],
        if (trovoada != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.thunderstorm_outlined, size: 18, color: tema.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(trovoada)),
          ]),
        ],
        if (marcante != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.event_note, size: 18, color: tema.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(marcante, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ],
        const SizedBox(height: 6),
        Fonte(oficial
            ? 'previsão por hora do Environment and Climate Change Canada'
            : 'céu de agora: medição; próximas horas e ontem: Open-Meteo (modelo, estimativa)'),
      ],
    );
  }
}
