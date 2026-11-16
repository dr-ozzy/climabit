import 'package:intl/intl.dart';

import 'fontes.dart';

/// Grau de certeza da chuva no texto oficial da previsão.
enum Certeza { nenhuma, possivel, prevista }

/// Lê o texto da previsão ("Muitas nuvens com pancadas de chuva…").
Certeza certezaDaChuva(String resumo) {
  final r = resumo.toLowerCase();
  if (r.contains('sem chuva')) return Certeza.nenhuma;
  final temChuva = r.contains('chuv') ||
      r.contains('pancada') ||
      r.contains('trovoada') ||
      r.contains('tempestade');
  if (!temChuva) return Certeza.nenhuma;
  if (r.contains('possibilidade') || r.contains('isolad') || r.contains('poss.')) {
    return Certeza.possivel;
  }
  return Certeza.prevista;
}

/// Primeiro dia (a partir de agora) em que a previsão oficial indica chuva.
class ChuvaPrevista {
  const ChuvaPrevista({
    required this.dia,
    required this.periodos,
    required this.certeza,
    required this.fonte,
  });

  final DateTime dia;

  /// "manhã", "tarde", "noite"; vazio quando a fonte não separa por período.
  final List<String> periodos;
  final Certeza certeza;
  final String fonte;
}

const _fimDoPeriodo = {'Manhã': 12, 'Tarde': 18, 'Noite': 24};

/// Períodos com chuva num dia; ignora os que já terminaram hoje.
(List<String>, Certeza) periodosComChuva(DiaPrevisao d, DateTime agora) {
  final hoje = d.dia.year == agora.year && d.dia.month == agora.month && d.dia.day == agora.day;
  if (d.periodos.length > 1) {
    final lista = <String>[];
    var certeza = Certeza.nenhuma;
    for (final p in d.periodos) {
      if (p.nome == 'Agora') continue; // condição observada (Canadá), não é previsão
      if (hoje && agora.hour >= (_fimDoPeriodo[p.nome] ?? 24)) continue;
      final c = certezaDaChuva(p.resumo);
      if (c == Certeza.nenhuma) continue;
      lista.add(p.nome.toLowerCase());
      if (c.index > certeza.index) certeza = c;
    }
    return (lista, certeza);
  }
  // Open-Meteo: decide pela chance de chuva (60 % ou mais = prevista; 30 % ou mais = possível).
  final prob = d.probabilidadeChuva;
  if (prob != null) {
    if (prob >= 60) return (const [], Certeza.prevista);
    if (prob >= 30) return (const [], Certeza.possivel);
    return (const [], Certeza.nenhuma);
  }
  final c = certezaDaChuva(d.resumo);
  if (c == Certeza.nenhuma) return (const [], c);
  // O CPTEC às vezes diz o período no próprio texto ("Chuva à tarde").
  final r = d.resumo.toLowerCase();
  final lista = [
    if (r.contains('manhã')) 'manhã',
    if (r.contains('tarde')) 'tarde',
    if (r.contains('noite')) 'noite',
  ];
  return (lista, c);
}

ChuvaPrevista? proximaChuva(List<DiaPrevisao> dias, DateTime agora) {
  for (final d in dias) {
    final (periodos, certeza) = periodosComChuva(d, agora);
    if (certeza == Certeza.nenhuma) continue;
    return ChuvaPrevista(dia: d.dia, periodos: periodos, certeza: certeza, fonte: d.fonte);
  }
  return null;
}

final _semana = DateFormat('EEEE', 'pt_BR');
final _diaMes = DateFormat('d/MM', 'pt_BR');

String _quandoDia(DateTime dia, DateTime agora) {
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final dif = DateTime(dia.year, dia.month, dia.day).difference(hoje).inDays;
  if (dif == 0) return 'hoje';
  if (dif == 1) return 'amanhã';
  final nome = _semana.format(dia);
  final artigo = nome == 'sábado' || nome == 'domingo' ? 'no' : 'na';
  return '$artigo $nome (${_diaMes.format(dia)})';
}

String _periodoFrase(String p) => switch (p) {
      'manhã' => 'de manhã',
      'tarde' => 'à tarde',
      'noite' => 'à noite',
      'dia' => 'durante o dia',
      _ => p,
    };

String juntarComE(List<String> itens) {
  if (itens.length <= 1) return itens.join();
  return '${itens.sublist(0, itens.length - 1).join(', ')} e ${itens.last}';
}

/// "Chuva prevista hoje à tarde e à noite" / "Possibilidade de chuva amanhã de manhã".
String fraseChuva(ChuvaPrevista? c, DateTime agora, {int diasConsultados = 0}) {
  if (c == null) {
    return diasConsultados > 0
        ? 'Sem chuva prevista nos próximos $diasConsultados dias'
        : 'Sem chuva prevista';
  }
  final inicio = c.certeza == Certeza.prevista ? 'Chuva prevista' : 'Possibilidade de chuva';
  final quando = _quandoDia(c.dia, agora);
  if (c.periodos.isEmpty) return '$inicio $quando';
  return '$inicio $quando ${juntarComE(c.periodos.map(_periodoFrase).toList())}';
}
