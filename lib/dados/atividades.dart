import 'dart:convert';

import 'fontes.dart';

/// Atividades com regras simples para dizer se uma hora é boa, regular ou ruim.
/// As regras usam só a previsão por hora (chuva, sensação térmica, vento, UV, dia/noite).
enum Atividade {
  caminhar('Caminhar'),
  pedalar('Pedalar'),
  praia('Praia'),
  secarRoupa('Secar roupa');

  const Atividade(this.nome);
  final String nome;

  static Atividade deNome(String? n) =>
      values.firstWhere((a) => a.name == n, orElse: () => caminhar);
}

enum Nota { boa, regular, ruim }

/// Tipos de motivo, para juntar vários horários num texto só ("chuva (até 77 %)").
enum Motivo { trovoada, chuva, noite, frio, fresco, calor, vento, uv }

class AvaliacaoHora {
  const AvaliacaoHora(this.hora, this.nota, this.motivos, {this.itens = const [], this.previsao});
  final DateTime hora;
  final Nota nota;

  /// O que atrapalha ("chuva 60 %", "sens. 35°", "vento 30 km/h", "UV 9", "noite").
  final List<String> motivos;

  /// Os mesmos motivos, com o tipo e o peso de cada um.
  final List<(Motivo, Nota)> itens;
  final HoraChuva? previsao;
}

/// Junta os motivos de várias horas: "chuva (até 77 %)", "calor (sens. até 35°)".
/// Com [soRuins], só os motivos que deixaram a hora ruim.
List<String> resumirMotivos(List<AvaliacaoHora> lista, {bool soRuins = false}) {
  final valores = <Motivo, List<double>>{};
  for (final a in lista) {
    final h = a.previsao;
    for (final (m, n) in a.itens) {
      if (soRuins && n != Nota.ruim) continue;
      final v = switch (m) {
        Motivo.chuva => (h?.probabilidade ?? 0).toDouble(),
        Motivo.frio || Motivo.fresco || Motivo.calor => h?.sensacao ?? h?.temperatura ?? 0,
        Motivo.vento => h?.ventoKmh ?? 0,
        Motivo.uv => h?.uv ?? 0,
        _ => 0.0,
      };
      valores.putIfAbsent(m, () => []).add(v);
    }
  }
  String maior(List<double> l) => l.reduce((a, b) => a > b ? a : b).round().toString();
  String menor(List<double> l) => l.reduce((a, b) => a < b ? a : b).round().toString();
  return [
    for (final m in Motivo.values)
      if (valores[m] case final l?)
        switch (m) {
          Motivo.trovoada => 'trovoada',
          Motivo.chuva => 'chuva (até ${maior(l)} %)',
          Motivo.noite => 'noite',
          Motivo.frio => 'frio (sens. até ${menor(l)}°)',
          Motivo.fresco => 'fresco (sens. até ${menor(l)}°)',
          Motivo.calor => 'calor (sens. até ${maior(l)}°)',
          Motivo.vento => 'vento (até ${maior(l)} km/h)',
          Motivo.uv => 'UV até ${maior(l)}',
        },
  ];
}

Nota _pior(Nota a, Nota b) => a.index >= b.index ? a : b;

/// Avalia uma hora da previsão para a atividade.
AvaliacaoHora avaliarHora(Atividade a, HoraChuva h) {
  var nota = Nota.boa;
  final motivos = <String>[];
  final itens = <(Motivo, Nota)>[];
  void marcar(Nota n, String motivo) {
    nota = _pior(nota, n);
    motivos.add(motivo);
    final tipo = switch (motivo.split(' ').first) {
      'trovoada' => Motivo.trovoada,
      'chuva' => Motivo.chuva,
      'noite' => Motivo.noite,
      'frio' => Motivo.frio,
      'fresco' => Motivo.fresco,
      'calor' => Motivo.calor,
      'vento' => Motivo.vento,
      _ => Motivo.uv,
    };
    itens.add((tipo, n));
  }

  final dia = h.dia ?? true;
  final p = h.probabilidade ?? 0;
  final mm = h.milimetros ?? 0;
  final trovoada = (h.codigo ?? 0) >= 95;
  final s = h.sensacao ?? h.temperatura;
  final v = h.ventoKmh;
  final uv = h.uv;

  // Chuva (secar roupa exige mais).
  final limiteRuim = a == Atividade.secarRoupa ? 20 : 50;
  final limiteRegular = a == Atividade.secarRoupa ? 10 : 25;
  if (trovoada) {
    marcar(Nota.ruim, 'trovoada');
  } else if (mm >= 0.5 || p >= limiteRuim) {
    marcar(Nota.ruim, 'chuva $p %');
  } else if (mm >= 0.1 || p >= limiteRegular) {
    marcar(Nota.regular, 'chuva $p %');
  }

  // Dia ou noite.
  if (!dia && (a == Atividade.praia || a == Atividade.secarRoupa)) {
    marcar(Nota.ruim, 'noite');
  }

  // Sensação térmica: (ruim abaixo, regular abaixo, regular acima, ruim acima).
  final faixas = switch (a) {
    Atividade.caminhar => (12.0, 16.0, 29.0, 33.0),
    Atividade.pedalar => (10.0, 14.0, 28.0, 32.0),
    Atividade.praia => (22.0, 25.0, 35.0, 38.0),
    Atividade.secarRoupa => (10.0, 18.0, 99.0, 99.0),
  };
  if (s != null) {
    final t = '${s.round()}°';
    if (s < faixas.$1) {
      marcar(Nota.ruim, 'frio (sens. $t)');
    } else if (s < faixas.$2) {
      marcar(Nota.regular, 'fresco (sens. $t)');
    } else if (s > faixas.$4) {
      marcar(Nota.ruim, 'calor (sens. $t)');
    } else if (s > faixas.$3) {
      marcar(Nota.regular, 'calor (sens. $t)');
    }
  }

  // Vento: (regular acima, ruim acima).
  final ventos = switch (a) {
    Atividade.caminhar => (25.0, 40.0),
    Atividade.pedalar => (20.0, 30.0),
    Atividade.praia => (25.0, 35.0),
    Atividade.secarRoupa => (40.0, 55.0),
  };
  if (v != null) {
    if (v > ventos.$2) {
      marcar(Nota.ruim, 'vento ${v.round()} km/h');
    } else if (v > ventos.$1) {
      marcar(Nota.regular, 'vento ${v.round()} km/h');
    }
  }

  // UV alto não impede, mas pede cuidado.
  if (dia && uv != null && uv >= 8 && a != Atividade.secarRoupa) {
    marcar(Nota.regular, 'UV ${uv.round()}');
  }
  return AvaliacaoHora(h.hora, nota, motivos, itens: itens, previsao: h);
}

/// Trechos seguidos de horas boas: "6h–10h" (a hora final é o fim do último bloco).
List<(DateTime, DateTime)> trechosBons(List<AvaliacaoHora> lista) {
  final r = <(DateTime, DateTime)>[];
  DateTime? inicio;
  DateTime? ultimo;
  for (final a in lista) {
    if (a.nota == Nota.boa) {
      inicio ??= a.hora;
      ultimo = a.hora;
    } else if (inicio != null) {
      r.add((inicio, ultimo!.add(const Duration(hours: 1))));
      inicio = null;
    }
  }
  if (inicio != null) r.add((inicio, ultimo!.add(const Duration(hours: 1))));
  return r;
}

/// Atividade repetida em dias da semana e horário fixos ("caminhar, seg/qua/sex, 6h–7h").
class Rotina {
  const Rotina({
    required this.atividade,
    required this.dias,
    required this.inicio,
    required this.fim,
  });

  final Atividade atividade;

  /// Dias da semana, 1 = segunda … 7 = domingo (igual a `DateTime.weekday`).
  final Set<int> dias;

  /// Horas inteiras, de [inicio] até [fim] (exclusivo).
  final int inicio;
  final int fim;

  Map<String, dynamic> toJson() =>
      {'a': atividade.name, 'd': dias.toList()..sort(), 'i': inicio, 'f': fim};

  factory Rotina.fromJson(Map<String, dynamic> j) => Rotina(
        atividade: Atividade.deNome(j['a'] as String?),
        dias: {for (final d in (j['d'] as List)) (d as num).toInt()},
        inicio: (j['i'] as num).toInt(),
        fim: (j['f'] as num).toInt(),
      );

  static List<Rotina> lerLista(String? s) {
    if (s == null || s.isEmpty) return [];
    try {
      return [
        for (final j in (jsonDecode(s) as List).cast<Map<String, dynamic>>()) Rotina.fromJson(j),
      ];
    } catch (_) {
      return [];
    }
  }

  static String gravarLista(List<Rotina> l) => jsonEncode([for (final r in l) r.toJson()]);

  /// Próximo início (a partir de [agora]); a sessão que já começou e não terminou conta.
  DateTime proxima(DateTime agora) {
    for (var i = 0; i < 8; i++) {
      final d = DateTime(agora.year, agora.month, agora.day + i);
      if (!dias.contains(d.weekday)) continue;
      final fimSessao = DateTime(d.year, d.month, d.day, fim);
      if (fimSessao.isAfter(agora)) return DateTime(d.year, d.month, d.day, inicio);
    }
    return DateTime(agora.year, agora.month, agora.day + 7, inicio);
  }
}

/// Situação da próxima sessão de uma rotina. Nulo quando a previsão por hora ainda não
/// alcança o dia (o app diz a partir de quando haverá previsão).
(Nota, List<String>)? avaliarRotina(Rotina r, List<HoraChuva> horas, DateTime agora) {
  final inicio = r.proxima(agora);
  final fim = DateTime(inicio.year, inicio.month, inicio.day, r.fim);
  final trecho = [
    for (final h in horas)
      if (!h.hora.isBefore(inicio) && h.hora.isBefore(fim)) avaliarHora(r.atividade, h),
  ];
  final esperado = fim.difference(inicio).inHours;
  if (trecho.isEmpty || trecho.length < esperado) return null;
  var nota = Nota.boa;
  for (final a in trecho) {
    nota = _pior(nota, a.nota);
  }
  return (nota, resumirMotivos(trecho));
}
