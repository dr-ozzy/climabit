import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'http_cache.dart';
import 'radar.dart';

/// Mapa de vento: grade de pontos ao redor da cidade com vento, chuva e nuvens de hora em
/// hora (Open-Meteo, estimativa de modelo, não medição).
///
/// Uma única consulta com todos os pontos. A grade fica na memória por 30 minutos para
/// não gastar a cota gratuita do Open-Meteo; sem internet, usa a última cópia guardada.
class GradeVento {
  GradeVento({
    required this.area,
    required this.colunas,
    required this.linhas,
    required this.horas,
    required this.u,
    required this.v,
    required this.chuva,
    required this.nuvens,
    required this.obtidoEm,
    required this.doCache,
  });

  /// Área do mapa (mesma projeção dos radares).
  final AreaRadar area;

  /// Pontos da grade: [colunas] de oeste para leste, [linhas] de norte para sul.
  final int colunas;
  final int linhas;

  /// Horas da previsão (hora local do aparelho).
  final List<DateTime> horas;

  /// Por hora, valores na ordem linha × colunas + coluna (linha 0 = norte).
  /// [u]: componente leste do vento (km/h); [v]: componente norte (km/h).
  final List<Float32List> u;
  final List<Float32List> v;

  /// Chuva (mm/h) e nuvens (0 a 100 %).
  final List<Float32List> chuva;
  final List<Float32List> nuvens;

  final DateTime obtidoEm;
  final bool doCache;

  int get pontos => colunas * linhas;

  /// Vento interpolado no ponto (x, y) do mapa, de 0 a 1 (x para leste, y para baixo),
  /// na hora [h] (pode ser fracionária: 1,5 = meio caminho entre a 2ª e a 3ª hora).
  /// Devolve (leste, norte) em km/h.
  (double, double) ventoEm(double x, double y, double h) {
    final h0 = h.floor().clamp(0, horas.length - 1);
    final h1 = math.min(h0 + 1, horas.length - 1);
    final f = (h - h0).clamp(0.0, 1.0);
    final (ua, va) = (_bilinear(u[h0], x, y), _bilinear(v[h0], x, y));
    if (f == 0 || h1 == h0) return (ua, va);
    final (ub, vb) = (_bilinear(u[h1], x, y), _bilinear(v[h1], x, y));
    return interpolarVento(ua, va, ub, vb, f);
  }

  /// Valor de chuva ou nuvem interpolado (para a cidade).
  double valorEm(List<Float32List> campo, double x, double y, int h) =>
      _bilinear(campo[h.clamp(0, horas.length - 1)], x, y);

  double _bilinear(Float32List c, double x, double y) {
    final fx = (x.clamp(0.0, 1.0)) * (colunas - 1);
    final fy = (y.clamp(0.0, 1.0)) * (linhas - 1);
    final x0 = fx.floor().clamp(0, colunas - 2);
    final y0 = fy.floor().clamp(0, linhas - 2);
    final ax = fx - x0;
    final ay = fy - y0;
    final i = y0 * colunas + x0;
    final a = c[i] + (c[i + 1] - c[i]) * ax;
    final b = c[i + colunas] + (c[i + colunas + 1] - c[i + colunas]) * ax;
    return a + (b - a) * ay;
  }
}

/// Converte a direção do Open-Meteo (de onde o vento vem, graus a partir do norte, sentido
/// horário) em componentes (leste, norte). Vento "de 0°" (norte) sopra para o sul: (0, −v).
(double, double) componentesVento(double velocidade, double direcaoGraus) {
  final t = direcaoGraus * math.pi / 180;
  return (-velocidade * math.sin(t), -velocidade * math.cos(t));
}

/// Entre duas horas: interpola velocidade e ângulo pelo caminho mais curto, para uma virada
/// de vento não passar por uma calmaria que o modelo não previu.
(double, double) interpolarVento(
    double ua, double va, double ub, double vb, double f) {
  final sa = math.sqrt(ua * ua + va * va);
  final sb = math.sqrt(ub * ub + vb * vb);
  if (sa < 0.01 || sb < 0.01) {
    return (ua + (ub - ua) * f, va + (vb - va) * f);
  }
  final aa = math.atan2(va, ua);
  var d = math.atan2(vb, ub) - aa;
  while (d > math.pi) {
    d -= 2 * math.pi;
  }
  while (d < -math.pi) {
    d += 2 * math.pi;
  }
  final a = aa + d * f;
  final s = sa + (sb - sa) * f;
  return (s * math.cos(a), s * math.sin(a));
}

/// Área quadrada de [ladoKm] ao redor do ponto, medida em km (não em graus), para não
/// achatar o mapa em latitudes altas.
AreaRadar areaAoRedor(double lat, double lon, {double ladoKm = 300}) {
  final dLat = ladoKm / 2 / 111.32;
  final dLon = dLat / math.cos(lat * math.pi / 180).clamp(0.2, 1.0);
  return AreaRadar(
    oeste: lon - dLon,
    sul: lat - dLat,
    leste: lon + dLon,
    norte: lat + dLat,
  );
}

/// Endereço da consulta ao Open-Meteo para uma grade [n] × [n] na [area].
Uri enderecoGradeVento(AreaRadar area, {int n = 11, int horas = 13}) {
  final lats = <String>[];
  final lons = <String>[];
  for (var l = 0; l < n; l++) {
    final lat = area.norte - (area.norte - area.sul) * l / (n - 1);
    for (var c = 0; c < n; c++) {
      final lon = area.oeste + (area.leste - area.oeste) * c / (n - 1);
      lats.add(lat.toStringAsFixed(3));
      lons.add(lon.toStringAsFixed(3));
    }
  }
  return Uri.parse('https://api.open-meteo.com/v1/forecast'
      '?latitude=${lats.join(',')}&longitude=${lons.join(',')}'
      '&hourly=wind_speed_10m,wind_direction_10m,precipitation,cloud_cover'
      '&wind_speed_unit=kmh&forecast_hours=$horas&timezone=GMT');
}

/// Lê a resposta (lista com um objeto por ponto, na ordem pedida).
/// Devolve null se faltar algum ponto ou se as horas não baterem.
GradeVento? lerGradeVento(
  String corpo,
  AreaRadar area, {
  required int n,
  required DateTime obtidoEm,
  bool doCache = false,
}) {
  final j = jsonDecode(corpo);
  final lista = j is List ? j : (j is Map ? [j] : const []);
  if (lista.length != n * n) return null;
  List<DateTime>? horas;
  late List<Float32List> u, v, chuva, nuvens;
  for (var p = 0; p < lista.length; p++) {
    final h = lista[p] is Map ? (lista[p] as Map)['hourly'] : null;
    if (h is! Map || h['time'] is! List) return null;
    final tempos = h['time'] as List;
    if (horas == null) {
      horas = [
        for (final t in tempos)
          (DateTime.tryParse('${t}Z') ?? DateTime.utc(1970)).toLocal(),
      ];
      if (horas.isEmpty) return null;
      Float32List nova() => Float32List(n * n);
      u = [for (final _ in horas) nova()];
      v = [for (final _ in horas) nova()];
      chuva = [for (final _ in horas) nova()];
      nuvens = [for (final _ in horas) nova()];
    }
    if (tempos.length < horas.length) return null;
    List col(String k) => h[k] is List ? h[k] as List : const [];
    final vel = col('wind_speed_10m');
    final dir = col('wind_direction_10m');
    final mm = col('precipitation');
    final nv = col('cloud_cover');
    double valor(List l, int i) =>
        i < l.length && l[i] is num ? (l[i] as num).toDouble() : 0;
    for (var i = 0; i < horas.length; i++) {
      final (a, b) = componentesVento(valor(vel, i), valor(dir, i));
      u[i][p] = a;
      v[i][p] = b;
      chuva[i][p] = valor(mm, i);
      nuvens[i][p] = valor(nv, i);
    }
  }
  return GradeVento(
    area: area,
    colunas: n,
    linhas: n,
    horas: horas!,
    u: u,
    v: v,
    chuva: chuva,
    nuvens: nuvens,
    obtidoEm: obtidoEm,
    doCache: doCache,
  );
}

/// Busca a grade (com a memória de 30 minutos).
class FonteVento {
  FonteVento({HttpCache? http}) : _http = http ?? HttpCache();

  final HttpCache _http;
  static const _n = 11;
  static const validade = Duration(minutes: 30);
  static final Map<String, GradeVento> _memoria = {};

  Future<GradeVento?> grade(double lat, double lon) async {
    // Arredonda o centro (cerca de 5 km) para a memória servir à mesma cidade.
    final la = (lat * 20).round() / 20;
    final lo = (lon * 20).round() / 20;
    final chave = '$la,$lo';
    final guardada = _memoria[chave];
    if (guardada != null &&
        !guardada.doCache &&
        DateTime.now().difference(guardada.obtidoEm) < validade) {
      return guardada;
    }
    final area = areaAoRedor(la, lo);
    try {
      final r = await _http.obter(enderecoGradeVento(area, n: _n),
          limite: const Duration(seconds: 30));
      final g = lerGradeVento(r.corpo, area,
          n: _n, obtidoEm: r.obtidoEm, doCache: r.doCache);
      if (g != null) _memoria[chave] = g;
      return g;
    } on FonteIndisponivel {
      return null;
    } on FormatException {
      return null;
    }
  }
}
