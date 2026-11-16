import 'dart:convert';
import 'dart:math' as math;

import 'package:xml/xml.dart';

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

/// Medição de uma estação meteorológica automática.
class Medicao {
  Medicao({
    required this.fonte,
    required this.estacao,
    required this.codigo,
    required this.hora,
    this.distanciaKm,
    this.temperatura,
    this.sensacao,
    this.umidade,
    this.ventoKmh,
    this.rajadaKmh,
    this.ventoDirecao,
    this.pressao,
    this.orvalho,
    this.visibilidadeKm,
    this.chuva1h,
    this.temperaturaMax,
    this.temperaturaMin,
    this.chuvaHoje,
    this.uv,
    this.latitude,
    this.longitude,
  });

  /// Posição da estação (quando a fonte informa).
  final double? latitude;
  final double? longitude;

  /// Chuva acumulada desde a meia-noite (algumas estações informam isso em vez da última hora).
  final double? chuvaHoje;

  /// Índice ultravioleta medido agora.
  final double? uv;

  final String fonte;
  final String estacao;
  final String codigo;
  final DateTime hora;
  final double? distanciaKm;
  final double? temperatura;
  final double? sensacao;
  final double? umidade;
  final double? ventoKmh;
  final double? rajadaKmh;
  final int? ventoDirecao;
  /// Pressão ao nível da estação ou do mar, em hPa.
  final double? pressao;

  /// Ponto de orvalho (°C).
  final double? orvalho;

  /// Visibilidade horizontal (km).
  final double? visibilidadeKm;
  final double? chuva1h;
  final double? temperaturaMax;
  final double? temperaturaMin;
}

class PeriodoPrevisao {
  const PeriodoPrevisao({
    required this.nome,
    required this.resumo,
    this.maxima,
    this.minima,
    this.ventoDirecao,
    this.ventoIntensidade,
    this.umidadeMax,
    this.umidadeMin,
  });

  final String nome;
  final String resumo;
  final int? maxima;
  final int? minima;
  final String? ventoDirecao;
  final String? ventoIntensidade;
  final int? umidadeMax;
  final int? umidadeMin;
}

class DiaPrevisao {
  DiaPrevisao({
    required this.dia,
    required this.fonte,
    required this.resumo,
    this.maxima,
    this.minima,
    this.periodos = const [],
    this.uv,
    this.ventoDirecao,
    this.ventoIntensidade,
    this.umidadeMax,
    this.umidadeMin,
    this.probabilidadeChuva,
  });

  /// Chance de chuva em % (só o Open-Meteo informa).
  final int? probabilidadeChuva;

  final DateTime dia;
  final String fonte;
  final String resumo;
  final int? maxima;
  final int? minima;
  final List<PeriodoPrevisao> periodos;
  double? uv;
  final String? ventoDirecao;
  final String? ventoIntensidade;
  final int? umidadeMax;
  final int? umidadeMin;
}

/// Leitura de um pluviômetro (medidor de chuva).
class Pluviometro {
  const Pluviometro({
    required this.nome,
    required this.fonte,
    required this.hora,
    this.chuva1h,
    this.chuva24h,
  });

  final String nome;
  final String fonte;
  final DateTime? hora;
  final double? chuva1h;
  final double? chuva24h;

  static const validade = Duration(hours: 2);

  /// Leitura das últimas 2 horas. Hora no futuro (relógio da estação errado) não conta.
  bool recente(DateTime agora) =>
      hora != null &&
      agora.difference(hora!) <= validade &&
      hora!.isBefore(agora.add(const Duration(minutes: 15)));
}

class Alerta {
  const Alerta({
    required this.id,
    required this.descricao,
    required this.severidade,
    required this.cor,
    required this.inicio,
    required this.fim,
    this.riscos = const [],
    this.instrucoes = const [],
  });

  final String id;
  final String descricao;
  final String severidade;

  /// Cor oficial do aviso, no formato #RRGGBB.
  final String cor;
  final DateTime inicio;
  final DateTime fim;
  final List<String> riscos;
  final List<String> instrucoes;

  bool ativo(DateTime agora) => !agora.isBefore(inicio) && agora.isBefore(fim);
}

// ---------------------------------------------------------------------------
// Conversões
// ---------------------------------------------------------------------------

double? _num(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final s = v.toString().trim().replaceAll(',', '.');
  if (s.isEmpty || s == '-' || s == 'null') return null;
  return double.tryParse(s);
}

int? _int(Object? v) => _num(v)?.round();

String _texto(Object? v) => (v ?? '').toString().trim();

// ---------------------------------------------------------------------------
// INMET
// ---------------------------------------------------------------------------

/// `https://apiprevmet3.inmet.gov.br/estacao/proxima/<geocode>`
Medicao? lerEstacaoInmet(String corpo) {
  final j = jsonDecode(corpo) as Map<String, dynamic>;
  final est = j['estacao'] as Map<String, dynamic>?;
  final d = j['dados'] as Map<String, dynamic>?;
  if (est == null || d == null) return null;
  final data = _texto(d['DT_MEDICAO']);
  final hr = _texto(d['HR_MEDICAO']).padLeft(4, '0');
  if (data.isEmpty) return null;
  final hora = DateTime.parse(
    '${data}T${hr.substring(0, 2)}:${hr.substring(2, 4)}:00Z',
  ).toLocal();
  final vel = _num(d['VEN_VEL']);
  final raj = _num(d['VEN_RAJ']);
  return Medicao(
    fonte: 'INMET',
    estacao: _texto(est['NOME']),
    codigo: _texto(est['CODIGO']),
    distanciaKm: _num(est['DISTANCIA_EM_KM']),
    hora: hora,
    temperatura: _num(d['TEM_INS']),
    sensacao: _num(d['TEM_SEN']),
    umidade: _num(d['UMD_INS']),
    ventoKmh: vel == null ? null : vel * 3.6,
    rajadaKmh: raj == null ? null : raj * 3.6,
    ventoDirecao: _int(d['VEN_DIR']),
    pressao: _num(d['PRE_INS']),
    orvalho: _num(d['PTO_INS']),
    chuva1h: _num(d['CHUVA']),
    temperaturaMax: _num(d['TEM_MAX']),
    temperaturaMin: _num(d['TEM_MIN']),
    latitude: _num(est['LATITUDE']) ?? _num(d['VL_LATITUDE']),
    longitude: _num(est['LONGITUDE']) ?? _num(d['VL_LONGITUDE']),
  );
}

/// Distância em km entre dois pontos (fórmula de haversine).
double distanciaEntre(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// A mesma medição com a distância recalculada a partir de um ponto (sede do município).
Medicao comDistanciaDe(Medicao m, double lat, double lon) {
  if (m.latitude == null || m.longitude == null) return m;
  return Medicao(
    fonte: m.fonte,
    estacao: m.estacao,
    codigo: m.codigo,
    hora: m.hora,
    distanciaKm: distanciaEntre(lat, lon, m.latitude!, m.longitude!),
    temperatura: m.temperatura,
    sensacao: m.sensacao,
    umidade: m.umidade,
    ventoKmh: m.ventoKmh,
    rajadaKmh: m.rajadaKmh,
    ventoDirecao: m.ventoDirecao,
    pressao: m.pressao,
    orvalho: m.orvalho,
    visibilidadeKm: m.visibilidadeKm,
    chuva1h: m.chuva1h,
    temperaturaMax: m.temperaturaMax,
    temperaturaMin: m.temperaturaMin,
    chuvaHoje: m.chuvaHoje,
    uv: m.uv,
    latitude: m.latitude,
    longitude: m.longitude,
  );
}

const _nomesPeriodos = {'manha': 'Manhã', 'tarde': 'Tarde', 'noite': 'Noite'};

PeriodoPrevisao _periodoInmet(String nome, Map<String, dynamic> p) =>
    PeriodoPrevisao(
      nome: nome,
      resumo: _texto(p['resumo']),
      maxima: _int(p['temp_max']),
      minima: _int(p['temp_min']),
      ventoDirecao: _texto(p['dir_vento']),
      ventoIntensidade: _texto(p['int_vento']),
      umidadeMax: _int(p['umidade_max']),
      umidadeMin: _int(p['umidade_min']),
    );

/// `https://apiprevmet3.inmet.gov.br/previsao/<geocode>`
List<DiaPrevisao> lerPrevisaoInmet(String corpo, int geocode) {
  final j = jsonDecode(corpo) as Map<String, dynamic>;
  final cidade = j['$geocode'] as Map<String, dynamic>?;
  if (cidade == null) return [];
  final dias = <DiaPrevisao>[];
  cidade.forEach((dataStr, valor) {
    final partes = dataStr.split('/');
    if (partes.length != 3) return;
    final dia = DateTime(
      int.parse(partes[2]),
      int.parse(partes[1]),
      int.parse(partes[0]),
    );
    final v = valor as Map<String, dynamic>;
    if (v.containsKey('manha') || v.containsKey('tarde')) {
      final periodos = <PeriodoPrevisao>[
        for (final e in _nomesPeriodos.entries)
          if (v[e.key] is Map<String, dynamic>)
            _periodoInmet(e.value, v[e.key] as Map<String, dynamic>),
      ];
      final maximas = periodos.map((p) => p.maxima).whereType<int>();
      final minimas = periodos.map((p) => p.minima).whereType<int>();
      final umMax = periodos.map((p) => p.umidadeMax).whereType<int>();
      final umMin = periodos.map((p) => p.umidadeMin).whereType<int>();
      final principal = periodos.firstWhere(
        (p) => p.nome == 'Tarde',
        orElse: () => periodos.first,
      );
      dias.add(DiaPrevisao(
        dia: dia,
        fonte: 'INMET',
        resumo: principal.resumo,
        maxima: maximas.isEmpty ? null : maximas.reduce((a, b) => a > b ? a : b),
        minima: minimas.isEmpty ? null : minimas.reduce((a, b) => a < b ? a : b),
        periodos: periodos,
        ventoDirecao: principal.ventoDirecao,
        ventoIntensidade: principal.ventoIntensidade,
        umidadeMax: umMax.isEmpty ? null : umMax.reduce((a, b) => a > b ? a : b),
        umidadeMin: umMin.isEmpty ? null : umMin.reduce((a, b) => a < b ? a : b),
      ));
    } else {
      final p = _periodoInmet('Dia', v);
      dias.add(DiaPrevisao(
        dia: dia,
        fonte: 'INMET',
        resumo: p.resumo,
        maxima: p.maxima,
        minima: p.minima,
        ventoDirecao: p.ventoDirecao,
        ventoIntensidade: p.ventoIntensidade,
        umidadeMax: p.umidadeMax,
        umidadeMin: p.umidadeMin,
      ));
    }
  });
  dias.sort((a, b) => a.dia.compareTo(b.dia));
  return dias;
}

/// Lê uma lista no formato "['texto 1', 'texto 2']" usada pelo INMET.
List<String> _listaInmet(Object? v) {
  if (v is List) {
    return v.map(_texto).where((t) => t.isNotEmpty).toList();
  }
  final s = _texto(v);
  if (s.isEmpty || s == 'None' || s == 'null') return [];
  final itens = RegExp(r"'((?:[^'\\]|\\.)*)'")
      .allMatches(s)
      .map((m) => m.group(1)!.replaceAll(r"\'", "'").trim())
      .where((t) => t.isNotEmpty)
      .toList();
  return itens.isEmpty ? [s] : itens;
}

/// "2026-11-12 08:50" no horário de Brasília (UTC−3) → hora do aparelho.
DateTime? _horaBrasilia(String s) {
  final t = DateTime.tryParse(s.replaceFirst(' ', 'T'));
  if (t == null) return null;
  return DateTime.utc(t.year, t.month, t.day, t.hour + 3, t.minute).toLocal();
}

/// `https://apiprevmet3.inmet.gov.br/avisos/ativos` — só os avisos que incluem a cidade.
List<Alerta> lerAlertasInmet(String corpo, int geocode) {
  final j = jsonDecode(corpo) as Map<String, dynamic>;
  final alvo = '$geocode';
  final resultado = <Alerta>[];
  final vistos = <String>{};
  for (final grupo in ['hoje', 'futuro']) {
    final lista = j[grupo];
    if (lista is! List) continue;
    for (final a in lista.whereType<Map<String, dynamic>>()) {
      final geocodes = _texto(a['geocodes']).split(',').map((g) => g.trim());
      if (!geocodes.contains(alvo)) continue;
      final id = _texto(a['id_aviso']);
      if (!vistos.add(id)) continue;
      final inicio = _horaBrasilia(_texto(a['inicio']));
      final fim = _horaBrasilia(_texto(a['fim']));
      if (inicio == null || fim == null) continue;
      resultado.add(Alerta(
        id: id,
        descricao: _texto(a['descricao']),
        severidade: _texto(a['severidade']),
        cor: _texto(a['aviso_cor']).isEmpty ? '#FFFE00' : _texto(a['aviso_cor']),
        inicio: inicio,
        fim: fim,
        riscos: _listaInmet(a['riscos']),
        instrucoes: _listaInmet(a['instrucoes']),
      ));
    }
  }
  resultado.sort((a, b) => a.inicio.compareTo(b.inicio));
  return resultado;
}

// ---------------------------------------------------------------------------
// CPTEC/INPE
// ---------------------------------------------------------------------------

/// Siglas de tempo publicadas pelo CPTEC/INPE.
const siglasCptec = {
  'ec': 'Encoberto com chuvas isoladas',
  'ci': 'Chuvas isoladas',
  'c': 'Chuva',
  'in': 'Instável',
  'pp': 'Possibilidade de pancadas de chuva',
  'cm': 'Chuva pela manhã',
  'cn': 'Chuva à noite',
  'pt': 'Pancadas de chuva à tarde',
  'pm': 'Pancadas de chuva pela manhã',
  'np': 'Nublado e pancadas de chuva',
  'pc': 'Pancadas de chuva',
  'pn': 'Parcialmente nublado',
  'cv': 'Chuvisco',
  'ch': 'Chuvoso',
  't': 'Tempestade',
  'ps': 'Predomínio de sol',
  'e': 'Encoberto',
  'n': 'Nublado',
  'cl': 'Céu claro',
  'nv': 'Nevoeiro',
  'g': 'Geada',
  'ne': 'Neve',
  'nd': 'Não definido',
  'pnt': 'Pancadas de chuva à noite',
  'psc': 'Possibilidade de chuva',
  'pcm': 'Possibilidade de chuva pela manhã',
  'pct': 'Possibilidade de chuva à tarde',
  'pcn': 'Possibilidade de chuva à noite',
  'npt': 'Nublado com pancadas à tarde',
  'npn': 'Nublado com pancadas à noite',
  'ncn': 'Nublado com possibilidade de chuva à noite',
  'nct': 'Nublado com possibilidade de chuva à tarde',
  'ncm': 'Nublado com possibilidade de chuva pela manhã',
  'npm': 'Nublado com pancadas pela manhã',
  'npp': 'Nublado com possibilidade de chuva',
  'vn': 'Variação de nebulosidade',
  'ct': 'Chuva à tarde',
  'ppn': 'Possibilidade de pancadas de chuva à noite',
  'ppt': 'Possibilidade de pancadas de chuva à tarde',
  'ppm': 'Possibilidade de pancadas de chuva pela manhã',
};

/// `https://servicos.cptec.inpe.br/XML/cidade/7dias/<id>/previsao.xml`
List<DiaPrevisao> lerPrevisaoCptec(String corpo) {
  final doc = XmlDocument.parse(corpo);
  final dias = <DiaPrevisao>[];
  for (final p in doc.findAllElements('previsao')) {
    final dia = DateTime.tryParse(p.getElement('dia')?.innerText.trim() ?? '');
    if (dia == null) continue;
    final sigla = p.getElement('tempo')?.innerText.trim() ?? '';
    dias.add(DiaPrevisao(
      dia: dia,
      fonte: 'CPTEC/INPE',
      resumo: siglasCptec[sigla] ?? sigla,
      maxima: _int(p.getElement('maxima')?.innerText),
      minima: _int(p.getElement('minima')?.innerText),
      // O CPTEC publica 0.0 quando ainda não calculou o índice.
      uv: switch (_num(p.getElement('iuv')?.innerText)) {
        final v? when v > 0 => v,
        _ => null,
      },
    ));
  }
  return dias;
}

/// Previsão de ondas do CPTEC/INPE para cidades do litoral.
class PrevisaoOnda {
  const PrevisaoOnda({
    required this.hora,
    required this.agitacao,
    this.altura,
    this.direcao = '',
    this.ventoKmh,
    this.ventoDirecao = '',
  });

  final DateTime hora;
  final String agitacao;

  /// Altura das ondas em metros.
  final double? altura;
  final String direcao;

  /// Vento sobre o mar em km/h (unidade indicada na documentação do CPTEC).
  final double? ventoKmh;
  final String ventoDirecao;
}

/// `https://servicos.cptec.inpe.br/XML/cidade/<id>/todos/tempos/ondas.xml`
/// Horários em UTC ("13-11-2026 00h Z"), de 3 em 3 horas.
List<PrevisaoOnda> lerOndasCptec(String corpo) {
  final doc = XmlDocument.parse(corpo);
  final r = <PrevisaoOnda>[];
  for (final p in doc.findAllElements('previsao')) {
    final m = RegExp(r'(\d{2})-(\d{2})-(\d{4}) (\d{2})h')
        .firstMatch(p.getElement('dia')?.innerText ?? '');
    if (m == null) continue;
    r.add(PrevisaoOnda(
      hora: DateTime.utc(int.parse(m.group(3)!), int.parse(m.group(2)!),
              int.parse(m.group(1)!), int.parse(m.group(4)!))
          .toLocal(),
      agitacao: _texto(p.getElement('agitacao')?.innerText),
      altura: _num(p.getElement('altura')?.innerText),
      direcao: _texto(p.getElement('direcao')?.innerText),
      ventoKmh: _num(p.getElement('vento')?.innerText),
      ventoDirecao: _texto(p.getElement('vento_dir')?.innerText),
    ));
  }
  r.sort((a, b) => a.hora.compareTo(b.hora));
  return r;
}

/// `https://servicos.cptec.inpe.br/XML/listaCidades?city=<nome>`
Map<String, int> lerListaCidadesCptec(String corpo) {
  final doc = XmlDocument.parse(corpo);
  return {
    for (final c in doc.findAllElements('cidade'))
      '${c.getElement('nome')?.innerText.trim()}|${c.getElement('uf')?.innerText.trim()}':
          int.parse(c.getElement('id')!.innerText.trim()),
  };
}

// ---------------------------------------------------------------------------
// Cemaden
// ---------------------------------------------------------------------------

/// `https://resources.cemaden.gov.br/graficos/interativo/getJson2.php?uf=<UF>`
///
/// Horários em UTC. "-" no acumulado significa que não houve chuva registrada.
List<Pluviometro> lerPluviometrosCemaden(String corpo, int geocode) {
  final lista = jsonDecode(corpo);
  if (lista is! List) return [];
  final r = <Pluviometro>[];
  for (final e in lista.whereType<Map<String, dynamic>>()) {
    if (_int(e['codibge']) != geocode) continue;
    r.add(Pluviometro(
      nome: _texto(e['nomeestacao']),
      fonte: 'Cemaden',
      hora: _horaCemaden(_texto(e['datahoraUltimovalor'])),
      chuva1h: _num(e['acc1hr']) ?? 0,
      chuva24h: _num(e['acc24hr']) ?? 0,
    ));
  }
  return r;
}

DateTime? _horaCemaden(String s) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{2}) (\d{2}):(\d{2})$').firstMatch(s);
  if (m == null) return null;
  return DateTime.utc(
    2000 + int.parse(m.group(3)!),
    int.parse(m.group(2)!),
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
  ).toLocal();
}

// ---------------------------------------------------------------------------
// UNIFEI (estação meteorológica do campus de Itajubá, universidade federal)
// ---------------------------------------------------------------------------

/// Posição aproximada da estação, no campus da UNIFEI (Av. BPS, Pinheirinho, Itajubá).
const unifeiLatitude = -22.4131;
const unifeiLongitude = -45.4497;

/// `https://meteorologia.unifei.edu.br/homepage/blocks/current/updater.php?interval=20`
/// Campos: T temperatura, A aparente, H umidade, P pressão ao nível do mar, W vento (km/h),
/// G rajada (km/h), B direção (graus), R chuva acumulada hoje (mm), UV, DateTime (Unix).
Medicao? lerEstacaoUnifei(String corpo) {
  final j = jsonDecode(corpo);
  if (j is! Map<String, dynamic>) return null;
  if (_int(j['offline']) != 0) return null;
  final unix = _int(j['DateTime']);
  if (unix == null) return null;
  return Medicao(
    fonte: 'UNIFEI',
    estacao: 'UNIFEI (campus de Itajubá)',
    codigo: '',
    hora: DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true).toLocal(),
    temperatura: _num(j['T']),
    sensacao: _num(j['A']),
    umidade: _num(j['H']),
    ventoKmh: _num(j['W']),
    rajadaKmh: _num(j['G']),
    ventoDirecao: _int(j['B']),
    pressao: _num(j['P']),
    chuvaHoje: _num(j['R']),
    uv: _num(j['UV']),
    latitude: unifeiLatitude,
    longitude: unifeiLongitude,
  );
}

// ---------------------------------------------------------------------------
// Open-Meteo (reserva quando não há dado oficial; valores de modelo, não medições)
// ---------------------------------------------------------------------------

/// Códigos de tempo da OMM usados pelo Open-Meteo.
String descricaoOmm(int? codigo) => switch (codigo) {
      0 => 'Céu limpo',
      1 => 'Predomínio de sol',
      2 => 'Parcialmente nublado',
      3 => 'Nublado',
      45 || 48 => 'Nevoeiro',
      51 || 53 || 55 => 'Chuvisco',
      56 || 57 => 'Chuvisco congelante',
      61 => 'Chuva fraca',
      63 => 'Chuva moderada',
      65 => 'Chuva forte',
      66 || 67 => 'Chuva congelante',
      71 || 73 || 75 || 77 => 'Neve',
      80 => 'Pancadas de chuva fracas',
      81 => 'Pancadas de chuva moderadas',
      82 => 'Pancadas de chuva fortes',
      85 || 86 => 'Pancadas de neve',
      95 => 'Trovoada',
      96 || 99 => 'Trovoada com granizo',
      _ => 'Sem descrição',
    };

/// Chuva prevista para uma hora (Open-Meteo, estimativa de modelo).
/// Uma hora da previsão por hora (Open-Meteo, estimativa de modelo).
class HoraChuva {
  const HoraChuva({
    required this.hora,
    this.probabilidade,
    this.milimetros,
    this.codigo,
    this.temperatura,
    this.sensacao,
    this.uv,
    this.dia,
  });
  final DateTime hora;

  /// Temperatura prevista (°C).
  final double? temperatura;

  /// Sensação térmica prevista (°C).
  final double? sensacao;

  /// Índice ultravioleta previsto.
  final double? uv;

  /// É dia nessa hora (para o ícone de sol ou lua).
  final bool? dia;

  /// Chance de chuva, em %.
  final int? probabilidade;
  final double? milimetros;
  final int? codigo;
}

/// `https://api.open-meteo.com/v1/forecast?...&hourly=precipitation_probability,precipitation,weather_code&timezone=GMT`
List<HoraChuva> lerChuvaHoraria(String corpo) {
  final j = jsonDecode(corpo);
  if (j is! Map<String, dynamic>) return [];
  final h = j['hourly'];
  if (h is! Map<String, dynamic> || h['time'] is! List) return [];
  final horas = h['time'] as List;
  List<dynamic> col(String k) => h[k] is List ? h[k] as List : const [];
  final prob = col('precipitation_probability');
  final mm = col('precipitation');
  final cod = col('weather_code');
  final temp = col('temperature_2m');
  final aparente = col('apparent_temperature');
  final uv = col('uv_index');
  final dia = col('is_day');
  final r = <HoraChuva>[];
  for (var i = 0; i < horas.length; i++) {
    final t = DateTime.tryParse('${horas[i]}Z');
    if (t == null) continue;
    r.add(HoraChuva(
      hora: t.toLocal(),
      probabilidade: i < prob.length ? _int(prob[i]) : null,
      milimetros: i < mm.length ? _num(mm[i]) : null,
      codigo: i < cod.length ? _int(cod[i]) : null,
      temperatura: i < temp.length ? _num(temp[i])?.toDouble() : null,
      sensacao: i < aparente.length ? _num(aparente[i])?.toDouble() : null,
      uv: i < uv.length ? _num(uv[i])?.toDouble() : null,
      dia: i < dia.length && dia[i] is num ? dia[i] == 1 : null,
    ));
  }
  return r;
}

class EstimativaOpenMeteo {
  const EstimativaOpenMeteo({this.atual, this.dias = const []});
  final Medicao? atual;
  final List<DiaPrevisao> dias;
}

/// `https://api.open-meteo.com/v1/forecast?...&timezone=America/Sao_Paulo&wind_speed_unit=kmh`
EstimativaOpenMeteo lerOpenMeteo(String corpo) {
  final j = jsonDecode(corpo) as Map<String, dynamic>;
  Medicao? atual;
  final c = j['current'];
  if (c is Map<String, dynamic>) {
    final hora = DateTime.tryParse(_texto(c['time']));
    if (hora != null) {
      atual = Medicao(
        fonte: 'Open-Meteo',
        estacao: 'modelo',
        codigo: '',
        hora: hora,
        temperatura: _num(c['temperature_2m']),
        sensacao: _num(c['apparent_temperature']),
        umidade: _num(c['relative_humidity_2m']),
        ventoKmh: _num(c['wind_speed_10m']),
        rajadaKmh: _num(c['wind_gusts_10m']),
        ventoDirecao: _int(c['wind_direction_10m']),
        pressao: _num(c['pressure_msl']),
        orvalho: _num(c['dew_point_2m']),
        visibilidadeKm: _num(c['visibility']) == null ? null : _num(c['visibility'])! / 1000,
        chuva1h: _num(c['precipitation']),
      );
    }
  }
  final dias = <DiaPrevisao>[];
  final d = j['daily'];
  if (d is Map<String, dynamic> && d['time'] is List) {
    final datas = (d['time'] as List).map((e) => DateTime.tryParse('$e')).toList();
    List<dynamic> col(String k) => d[k] is List ? d[k] as List : const [];
    T? em<T>(List<dynamic> l, int i, T? Function(Object?) f) => i < l.length ? f(l[i]) : null;
    for (var i = 0; i < datas.length; i++) {
      final dia = datas[i];
      if (dia == null) continue;
      dias.add(DiaPrevisao(
        dia: DateTime(dia.year, dia.month, dia.day),
        fonte: 'Open-Meteo',
        resumo: descricaoOmm(em(col('weather_code'), i, _int)),
        maxima: em(col('temperature_2m_max'), i, _int),
        minima: em(col('temperature_2m_min'), i, _int),
        uv: em(col('uv_index_max'), i, _num),
        probabilidadeChuva: em(col('precipitation_probability_max'), i, _int),
      ));
    }
  }
  return EstimativaOpenMeteo(atual: atual, dias: dias);
}

// ---------------------------------------------------------------------------
// Aeroportos (METAR do DECEA, redistribuído pela NOAA em aviationweather.gov)
// ---------------------------------------------------------------------------

/// Vento medido pela estação meteorológica de um aeroporto.
class VentoAeroporto {
  const VentoAeroporto({
    required this.codigo,
    required this.nome,
    required this.hora,
    required this.latitude,
    required this.longitude,
    this.ventoKmh,
    this.rajadaKmh,
    this.direcao,
    this.variavel = false,
    this.temperatura,
    this.orvalho,
    this.visibilidadeKm,
    this.pressao,
  });

  /// Visibilidade (km) e pressão ajustada ao nível do mar (hPa) do boletim.
  final double? visibilidadeKm;
  final double? pressao;

  /// Temperatura e ponto de orvalho (°C) do boletim do aeroporto.
  final double? temperatura;
  final double? orvalho;

  /// Umidade relativa (%) pela fórmula de Magnus, a partir da temperatura e do orvalho.
  double? get umidade {
    final t = temperatura, td = orvalho;
    if (t == null || td == null) return null;
    double e(double x) => math.exp(17.625 * x / (243.04 + x));
    return (100 * e(td) / e(t)).clamp(0, 100).toDouble();
  }

  final String codigo;
  final String nome;
  final DateTime hora;
  final double latitude;
  final double longitude;
  final double? ventoKmh;
  final double? rajadaKmh;

  /// Graus de onde o vento vem (0 a 360).
  final int? direcao;

  /// Direção variável ("VRB" no boletim).
  final bool variavel;

  double distanciaKm(double lat, double lon) => distanciaEntre(lat, lon, latitude, longitude);
}

const _noParaKmh = 1.852;

/// Visibilidade do METAR em milhas terrestres ("10+" = 10 ou mais) convertida para km.
double? visibilidadeMetarKm(Object? v) {
  if (v is num) return v * 1.609;
  if (v is String) {
    final n = double.tryParse(v.replaceAll('+', '').trim());
    return n == null ? null : n * 1.609;
  }
  return null;
}

/// `https://aviationweather.gov/api/data/metar?bbox=<s>,<o>,<n>,<l>&format=json`
List<VentoAeroporto> lerVentoAeroportos(String corpo) {
  final lista = jsonDecode(corpo);
  if (lista is! List) return [];
  final r = <VentoAeroporto>[];
  for (final m in lista.whereType<Map<String, dynamic>>()) {
    final obs = _int(m['obsTime']);
    final lat = _num(m['lat']);
    final lon = _num(m['lon']);
    if (obs == null || lat == null || lon == null) continue;
    final wdir = m['wdir'];
    final wspd = _num(m['wspd']);
    final wgst = _num(m['wgst']);
    // Nome como "Rio de Janeiro/Dumont Arpt, RJ, BR" → "Rio de Janeiro/Dumont".
    final nome = _texto(m['name']).split(',').first.replaceAll(RegExp(r'\s+(Intl|Arpt)\b.*'), '');
    r.add(VentoAeroporto(
      codigo: _texto(m['icaoId']),
      nome: nome,
      hora: DateTime.fromMillisecondsSinceEpoch(obs * 1000, isUtc: true).toLocal(),
      latitude: lat,
      longitude: lon,
      ventoKmh: wspd == null ? null : wspd * _noParaKmh,
      rajadaKmh: wgst == null ? null : wgst * _noParaKmh,
      direcao: wdir is num ? wdir.round() : null,
      variavel: wdir is String && wdir.toUpperCase() == 'VRB',
      temperatura: _num(m['temp'])?.toDouble(),
      orvalho: _num(m['dewp'])?.toDouble(),
      visibilidadeKm: visibilidadeMetarKm(m['visib']),
      pressao: _num(m['altim'])?.toDouble(),
    ));
  }
  return r;
}

// ---------------------------------------------------------------------------
// Defesa Civil de Niterói
// ---------------------------------------------------------------------------

/// Boletim de previsão escrito pela Defesa Civil de Niterói.
/// `https://www.defesacivildeniteroi.com.br/monitoramento/` (texto em `<pre class="marquee">`).
String? lerBoletimNiteroi(String html) {
  final m = RegExp(r'<pre class="marquee">(.*?)</pre>', dotAll: true).firstMatch(html);
  if (m == null) return null;
  var t = m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), ' ');
  t = t
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      // O site junta frases sem espaço ("declínio.No sábado").
      .replaceAllMapped(RegExp(r'\.([A-ZÁÉÍÓÚ])'), (x) => '. ${x.group(1)}')
      .trim();
  if (t.isEmpty) return null;
  return t.endsWith('.') ? t : '$t.';
}

class Sirene {
  const Sirene({required this.nome, required this.status});
  final String nome;

  /// Texto oficial, por exemplo "Desmobilizada" ou "Acionada".
  final String status;

  bool get acionada {
    final s = status.toLowerCase();
    return s.isNotEmpty && !s.contains('desmobiliz') && !s.contains('inativ');
  }
}

/// Sirenes da Defesa Civil de Niterói, do mapa publicado em
/// `https://svidaniteroi.com.br/mapa_iframe/`.
List<Sirene> lerSirenesNiteroi(String html) {
  final r = <Sirene>[];
  final marcador = RegExp(
      r'L\.marker\(\[[-0-9.]+,\s*[-0-9.]+\][^)]*\)\.addTo\(sirenes\)\.bindPopup\("(.*?)"\)',
      dotAll: true);
  for (final m in marcador.allMatches(html)) {
    final texto = m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '|');
    // O rótulo e o valor podem vir separados por marcações ("<b>Sirene: </b>Nome").
    final nome = RegExp(r'Sirene:[\s|]*([^|]+)').firstMatch(texto)?.group(1)?.trim() ?? '';
    final status = RegExp(r'Status:[\s|]*([^|]*)').firstMatch(texto)?.group(1)?.trim() ?? '';
    if (nome.isNotEmpty) r.add(Sirene(nome: nome, status: status));
  }
  return r;
}

// ---------------------------------------------------------------------------
// Alerta Rio
// ---------------------------------------------------------------------------

/// `http://websirene.rio.rj.gov.br/xml/chuvas.xml`
List<Pluviometro> lerPluviometrosAlertaRio(String corpo) {
  final doc = XmlDocument.parse(corpo);
  final r = <Pluviometro>[];
  for (final e in doc.findAllElements('estacao')) {
    final c = e.getElement('chuvas');
    if (c == null) continue;
    r.add(Pluviometro(
      nome: e.getAttribute('nome') ?? '',
      fonte: 'Alerta Rio',
      hora: DateTime.tryParse(c.getAttribute('hora') ?? '')?.toLocal(),
      chuva1h: _num(c.getAttribute('h01')),
      chuva24h: _num(c.getAttribute('h24')),
    ));
  }
  return r;
}
