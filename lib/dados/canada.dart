import 'dart:convert';

import '../util/formatos.dart';
import 'fontes.dart';

/// Dados do serviço meteorológico oficial do Canadá (Environment and Climate Change Canada,
/// ECCC), pela interface aberta `api.weather.gc.ca` (sem cadastro, sem chave).
///
/// `https://api.weather.gc.ca/collections/citypageweather-realtime/items/<id>?f=json`
/// O texto vem em inglês e francês; o app escreve o resumo em português a partir do
/// código do ícone oficial.
class DadosCanada {
  const DadosCanada({this.medicao, this.dias = const [], this.horas = const [], this.alertas = const []});
  final Medicao? medicao;
  final List<DiaPrevisao> dias;
  final List<HoraChuva> horas;
  final List<Alerta> alertas;
}

Uri enderecoCanada(String id) => Uri.https(
    'api.weather.gc.ca', '/collections/citypageweather-realtime/items/$id', {'f': 'json'});

/// Valor em inglês de um campo bilíngue (`{"en": ..., "fr": ...}`).
Object? _en(Object? o) => o is Map ? o['en'] : o;

double? _numero(Object? o) {
  final v = _en(o is Map && o.containsKey('value') ? o['value'] : o);
  if (v is num) return v.toDouble();
  if (v is String) {
    if (v.toLowerCase() == 'calm') return 0;
    return double.tryParse(v);
  }
  return null;
}

String _texto(Object? o) {
  final v = _en(o is Map && o.containsKey('value') ? o['value'] : o);
  return v == null ? '' : '$v';
}

DateTime? _hora(Object? o) {
  final v = _en(o);
  return v is String ? DateTime.tryParse(v)?.toLocal() : null;
}

/// "43.68N" → 43.68; "79.63W" → −79.63.
double? _coord(Object? o) {
  final s = _texto(o).trim();
  if (s.isEmpty) return null;
  final n = double.tryParse(s.substring(0, s.length - 1));
  if (n == null) return null;
  final h = s[s.length - 1].toUpperCase();
  return (h == 'S' || h == 'W' || h == 'O') ? -n : n;
}

/// Resumo em português pelo código do ícone oficial do ECCC (00 a 48).
String resumoIconeCanada(int? c) => switch (c) {
      0 || 1 => 'Ensolarado',
      30 || 31 => 'Céu claro',
      2 || 32 => 'Parcialmente nublado',
      3 || 33 => 'Muitas nuvens',
      4 || 34 => 'Aumento de nuvens',
      5 || 35 => 'Diminuição de nuvens',
      10 => 'Nublado',
      6 || 36 => 'Pancadas de chuva',
      11 || 12 => 'Chuva',
      13 => 'Chuva forte',
      28 => 'Garoa',
      14 => 'Chuva congelante (geada)',
      7 || 15 || 37 => 'Chuva e neve',
      8 || 38 => 'Neve fraca',
      16 || 17 => 'Neve',
      18 => 'Neve forte',
      25 || 40 => 'Neve com vento',
      26 => 'Cristais de gelo (geada)',
      27 => 'Granizo',
      9 || 19 || 39 || 46 || 47 => 'Trovoada',
      23 => 'Névoa seca',
      24 => 'Nevoeiro',
      43 => 'Ventania',
      44 => 'Fumaça',
      41 || 42 || 48 => 'Tornado',
      _ => 'Parcialmente nublado',
    };

/// Código da OMS (WMO, o mesmo do Open-Meteo) mais próximo do ícone do ECCC.
int codigoWmoCanada(int? c) => switch (c) {
      0 || 1 || 30 || 31 => 0,
      2 || 32 || 4 || 5 || 34 || 35 => 2,
      3 || 33 || 10 => 3,
      28 => 51,
      6 || 36 => 80,
      11 || 12 => 61,
      13 => 65,
      14 => 66,
      7 || 15 || 37 || 8 || 38 || 16 || 17 || 18 || 25 || 26 || 40 => 71,
      9 || 19 || 39 || 46 || 47 || 27 => 95,
      23 || 24 || 44 => 45,
      _ => 2,
    };

/// Frio do vento ou humidex do ECCC, só quando o valor faz sentido para a temperatura.
/// O ECCC às vezes repete um frio do vento antigo (ex.: −4 °C com 13 °C, em 2026-11-18).
/// Frio do vento só existe com 10 °C ou menos e fica abaixo da temperatura; humidex só
/// com 20 °C ou mais e fica acima dela. Fora disso, devolve null (o app calcula).
double? sensacaoCanadaPlausivel(double? temp, double? windChill, double? humidex) {
  if (temp == null) return null;
  if (windChill != null && temp <= 10 && windChill <= temp && temp - windChill <= 35) {
    return windChill;
  }
  if (humidex != null && temp >= 20 && humidex >= temp && humidex - temp <= 25) {
    return humidex;
  }
  return null;
}

DadosCanada lerCanada(String corpo) {
  final j = jsonDecode(corpo);
  if (j is! Map<String, dynamic>) return const DadosCanada();
  final p = j['properties'];
  if (p is! Map<String, dynamic>) return const DadosCanada();

  // Medição atual (estação oficial, em geral um aeroporto).
  Medicao? medicao;
  int? iconeAgora;
  final cc = p['currentConditions'];
  if (cc is Map<String, dynamic> && cc['temperature'] != null) {
    final est = cc['station'] as Map<String, dynamic>? ?? {};
    final vento = cc['wind'] as Map<String, dynamic>? ?? {};
    iconeAgora = _numero(cc['iconCode'])?.round();
    medicao = Medicao(
      fonte: 'ECCC',
      estacao: _texto(est),
      codigo: _texto(est['code']).toUpperCase(),
      hora: _hora(cc['timestamp']) ?? DateTime.now(),
      temperatura: _numero(cc['temperature']),
      umidade: _numero(cc['relativeHumidity']),
      ventoKmh: _numero(vento['speed']),
      rajadaKmh: _numero(vento['gust']),
      ventoDirecao: _numero(vento['bearing'])?.round(),
      sensacao: sensacaoCanadaPlausivel(
          _numero(cc['temperature']), _numero(cc['windChill']), _numero(cc['humidex'])),
      orvalho: _numero(cc['dewpoint']),
      pressao: _numero(cc['pressure']) == null ? null : _numero(cc['pressure'])! * 10, // kPa -> hPa
      visibilidadeKm: _numero(cc['visibility']),
      latitude: _coord(est['lat']),
      longitude: _coord(est['lon']),
    );
  }

  // Previsão: períodos de dia e de noite, juntados por data.
  final dias = <DiaPrevisao>[];
  final fg = p['forecastGroup'];
  if (fg is Map<String, dynamic> && fg['forecasts'] is List) {
    final emitida = _hora(fg['timestamp']) ?? DateTime.now();
    var data = DateTime(emitida.year, emitida.month, emitida.day);
    bool? anteriorNoite;
    final porData = <DateTime, Map<String, Object?>>{};
    for (final f in (fg['forecasts'] as List).whereType<Map<String, dynamic>>()) {
      final periodo = f['period'] as Map<String, dynamic>? ?? {};
      final nome = '${_texto(periodo['textForecastName'])} ${_texto(periodo)}'.toLowerCase();
      final noite = nome.contains('night') || nome.contains('tonight');
      if (anteriorNoite == true && !noite) data = data.add(const Duration(days: 1));
      anteriorNoite = noite;
      final reg = porData.putIfAbsent(data, () => {});
      final icone = _numero((f['abbreviatedForecast'] as Map?)?['icon'])?.round();
      final temps = (f['temperatures'] as Map?)?['temperature'];
      for (final t in (temps is List ? temps : const []).whereType<Map>()) {
        final classe = _texto(t['class']);
        final v = _numero(t)?.round();
        if (classe == 'high') reg['max'] = v;
        if (classe == 'low') reg['min'] = v;
      }
      final chance = RegExp(r'(\d+) percent').firstMatch(_texto(f['cloudPrecip']));
      if (chance != null) {
        final c = int.parse(chance.group(1)!);
        reg['chance'] = [reg['chance'] as int? ?? 0, c].reduce((a, b) => a > b ? a : b);
      }
      final uv = _numero((f['uv'] as Map?)?['index']);
      if (uv != null) reg['uv'] = uv;
      (reg['periodos'] ??= <PeriodoPrevisao>[]) as List<PeriodoPrevisao>;
      (reg['periodos'] as List<PeriodoPrevisao>).add(PeriodoPrevisao(
        nome: noite ? 'Noite' : 'Dia',
        resumo: resumoIconeCanada(icone),
      ));
      if (!noite || !reg.containsKey('resumo')) reg['resumo'] = resumoIconeCanada(icone);
    }
    for (final e in porData.entries) {
      final r = e.value;
      dias.add(DiaPrevisao(
        dia: e.key,
        fonte: 'ECCC',
        resumo: r['resumo'] as String? ?? '',
        maxima: r['max'] as int?,
        minima: r['min'] as int?,
        periodos: r['periodos'] as List<PeriodoPrevisao>? ?? const [],
        uv: r['uv'] as double?,
        probabilidadeChuva: r['chance'] as int?,
      ));
    }
  }

  // Previsão de hora em hora (oficial, 24 horas).
  final horas = <HoraChuva>[];
  final hf = p['hourlyForecastGroup'];
  if (hf is Map<String, dynamic> && hf['hourlyForecasts'] is List) {
    for (final h in (hf['hourlyForecasts'] as List).whereType<Map<String, dynamic>>()) {
      final t = _hora(h['timestamp']);
      if (t == null) continue;
      final icone = _numero(h['iconCode'])?.round();
      final tempHora = _numero(h['temperature']);
      final ventoHora = h['wind'] is Map ? _numero((h['wind'] as Map)['speed']) : null;
      horas.add(HoraChuva(
        hora: t,
        temperatura: tempHora,
        // Índice oficial (humidex ou frio do vento) ou, sem ele, frio do vento calculado.
        sensacao: sensacaoCanadaPlausivel(
                tempHora, _numero(h['windChill']), _numero(h['humidex'])) ??
            sensacaoTermica(tempHora, null, ventoHora),
        probabilidade: _numero(h['lop'])?.round(),
        codigo: codigoWmoCanada(icone),
        dia: icone == null ? null : icone < 30,
      ));
    }
  }

  // Avisos oficiais. Cor oficial: amarelo = perigo potencial; laranja = perigo;
  // vermelho = grande perigo.
  final alertas = <Alerta>[];
  final avisos = p['warnings'];
  if (avisos is List) {
    for (final a in avisos.whereType<Map<String, dynamic>>()) {
      final cor = _texto(a['alertColourLevel']).toLowerCase();
      final url = _texto(a['url']);
      final inicio = _hora(a['eventIssue']) ?? DateTime.now().subtract(const Duration(hours: 1));
      final fim = _hora(a['expiryTime']) ?? DateTime.now().add(const Duration(hours: 12));
      alertas.add(Alerta(
        id: 'eccc-${url.contains('#') ? url.split('#').last : _texto(a['description']).hashCode}',
        descricao: traduzirAvisoCanada(_texto(a['description']), _texto(a['type'])),
        severidade: switch (cor) {
          'red' => 'Grande Perigo',
          'orange' => 'Perigo',
          _ => 'Perigo Potencial',
        },
        cor: switch (cor) {
          'red' => '#FF0000',
          'orange' => '#FF9900',
          _ => '#FFFF00',
        },
        inicio: inicio,
        fim: fim,
      ));
    }
  }

  // Condição observada agora entra como período "Agora" do primeiro dia (para o céu).
  if (iconeAgora != null && dias.isNotEmpty) {
    final d = dias.first;
    dias[0] = DiaPrevisao(
      dia: d.dia,
      fonte: d.fonte,
      resumo: d.resumo,
      maxima: d.maxima,
      minima: d.minima,
      periodos: [PeriodoPrevisao(nome: 'Agora', resumo: resumoIconeCanada(iconeAgora)), ...d.periodos],
      uv: d.uv,
      probabilidadeChuva: d.probabilidadeChuva,
    );
  }
  return DadosCanada(medicao: medicao, dias: dias, horas: horas, alertas: alertas);
}

/// "YELLOW WARNING - RAINFALL" → "Aviso: chuva forte". Termos que o app não conhece ficam
/// em inglês, para não esconder o aviso.
String traduzirAvisoCanada(String descricao, String tipo) {
  final d = descricao.toUpperCase();
  const perigos = {
    'FREEZING RAIN': 'chuva congelante',
    'FREEZING DRIZZLE': 'garoa congelante',
    'RAINFALL': 'chuva forte',
    'SNOWFALL': 'neve forte',
    'SNOW SQUALL': 'rajadas de neve',
    'BLOWING SNOW': 'neve com vento',
    'BLIZZARD': 'nevasca',
    'WINTER STORM': 'tempestade de inverno',
    'FLASH FREEZE': 'congelamento rápido',
    'EXTREME COLD': 'frio extremo',
    'ARCTIC OUTFLOW': 'onda de frio',
    'FROST': 'geada',
    'HEAT': 'calor',
    'THUNDERSTORM': 'tempestade com raios',
    'TORNADO': 'tornado',
    'HURRICANE': 'furacão',
    'TROPICAL STORM': 'tempestade tropical',
    'STORM SURGE': 'ressaca e maré alta',
    'WIND': 'ventania',
    'FOG': 'nevoeiro',
    'AIR QUALITY': 'qualidade do ar',
    'SMOKE': 'fumaça',
    'WEATHER': 'tempo',
  };
  String? perigo;
  for (final e in perigos.entries) {
    if (d.contains(e.key)) {
      perigo = e.value;
      break;
    }
  }
  final tipoPt = switch (tipo.toLowerCase()) {
    'warning' => 'Aviso',
    'watch' => 'Possibilidade',
    'advisory' => 'Atenção',
    'statement' => 'Boletim especial',
    _ => 'Aviso',
  };
  if (perigo == null) return '$tipoPt: ${descricao.toLowerCase()}';
  return '$tipoPt: $perigo';
}
