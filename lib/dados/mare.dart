import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// Maré alta ou baixa num horário.
class ExtremoMare {
  const ExtremoMare({
    required this.hora,
    required this.altura,
    required this.alta,
    required this.estofoInicio,
    required this.estofoFim,
  });

  /// Estofo: período em volta da maré alta ou baixa em que o nível quase não muda
  /// (sobe ou desce menos que [EstacaoMare.limiteEstofo] por hora).
  final DateTime estofoInicio;
  final DateTime estofoFim;

  /// Hora local do aparelho.
  final DateTime hora;

  /// Metros acima do nível de redução da carta náutica (mesma referência da tábua).
  final double altura;
  final bool alta;
}

class _Constituinte {
  const _Constituinte(this.nome, this.doodson, this.nodal, this.a, this.b);
  final String nome;
  final List<int> doodson;
  final String nodal;
  final double a;
  final double b;
}

/// Previsão da maré por constantes harmônicas.
///
/// As constantes foram calculadas pelo app (fora do aparelho, uma vez) a partir das
/// preamares e baixa-mares da Tábua das Marés oficial da Marinha do Brasil. Com elas a
/// maré de qualquer data é calculada no próprio aparelho, sem internet, pelo mesmo
/// método harmônico usado na tábua (argumentos astronômicos e correções nodais).
class EstacaoMare {
  EstacaoMare._(this.nome, this.origem, this.latitude, this.longitude, this._z0, this._lista,
      {this.raioKm = 25, this.erro = '5 minutos e 1 cm'});

  /// Distância máxima (km) da cidade para usar esta estação.
  final double raioKm;

  /// Erro típico da previsão, em texto ("5 minutos e 1 cm").
  final String erro;

  final String nome;
  final String origem;
  final double latitude;
  final double longitude;
  final double _z0;
  final List<_Constituinte> _lista;

  static List<EstacaoMare>? _cache;

  static Future<List<EstacaoMare>> carregar() async {
    if (_cache != null) return _cache!;
    final r = <EstacaoMare>[];
    for (final arquivo in const ['assets/mare/ilha_fiscal.json', 'assets/mare/porto_do_forno.json']) {
      try {
        r.add(EstacaoMare.deJson(await rootBundle.loadString(arquivo)));
      } catch (_) {
        // Sem o arquivo, a cidade fica sem maré.
      }
    }
    return _cache = r;
  }

  /// Estações já carregadas (vazio antes de [carregar]).
  static List<EstacaoMare> get carregadas => _cache ?? const [];

  factory EstacaoMare.deJson(String texto) {
    final j = jsonDecode(texto) as Map<String, dynamic>;
    return EstacaoMare._(
      j['estacao'] as String,
      j['origem'] as String,
      (j['latitude'] as num).toDouble(),
      (j['longitude'] as num).toDouble(),
      (j['z0'] as num).toDouble(),
      [
        for (final c in j['constituintes'] as List)
          _Constituinte(
            c['nome'] as String,
            [for (final d in c['doodson'] as List) (d as num).toInt()],
            c['nodal'] as String,
            (c['a'] as num).toDouble(),
            (c['b'] as num).toDouble(),
          ),
      ],
      raioKm: (j['raioKm'] as num?)?.toDouble() ?? 25,
      erro: j['erro'] as String? ?? '5 minutos e 1 cm',
    );
  }

  static final _j2000 = DateTime.utc(2000, 1, 1, 12);

  static List<double> _astro(double t) {
    final T = t / (24 * 36525.0);
    final s = 218.3165 + 481267.8813 * T;
    final h = 280.4661 + 36000.7698 * T;
    final p = 83.3535 + 4069.0137 * T;
    final n = 125.0445 - 1934.1363 * T;
    final p1 = 282.9384 + 1.7195 * T;
    final horaUT = (t + 12.0) % 24.0;
    final tau = 15.0 * horaUT + 180.0 + h - s;
    return [tau, s, h, p, n, p1];
  }

  /// Fator e ângulo (graus) da correção nodal.
  static (double, double) _nodal(String tipo, double nGraus) {
    final n = nGraus * math.pi / 180;
    double c(double k) => math.cos(k * n);
    double s(double k) => math.sin(k * n);
    final fM2 = 1.0004 - 0.0373 * c(1) + 0.0002 * c(2);
    final uM2 = -2.14 * s(1);
    final fO1 = 1.0089 + 0.1871 * c(1) - 0.0147 * c(2) + 0.0014 * c(3);
    final uO1 = 10.80 * s(1) - 1.34 * s(2) + 0.19 * s(3);
    final fK1 = 1.0060 + 0.1150 * c(1) - 0.0088 * c(2) + 0.0006 * c(3);
    final uK1 = -8.86 * s(1) + 0.68 * s(2) - 0.07 * s(3);
    final fK2 = 1.0241 + 0.2863 * c(1) + 0.0083 * c(2) - 0.0015 * c(3);
    final uK2 = -17.74 * s(1) + 0.68 * s(2) - 0.04 * s(3);
    switch (tipo) {
      case 'M2':
        return (fM2, uM2);
      case '-M2':
        return (fM2, -uM2);
      case 'M2^1.5':
        return (math.pow(fM2, 1.5).toDouble(), 1.5 * uM2);
      case 'M2^2':
        return (fM2 * fM2, 2 * uM2);
      case 'M2^2f':
        return (fM2 * fM2, 0);
      case 'M2^3':
        return (fM2 * fM2 * fM2, 3 * uM2);
      case 'M2^4':
        return (math.pow(fM2, 4).toDouble(), 4 * uM2);
      case 'O1':
        return (fO1, uO1);
      case '-O1':
        return (fO1, -uO1);
      case 'K1':
        return (fK1, uK1);
      case 'K2':
        return (fK2, uK2);
      case 'M2*O1':
        return (fM2 * fO1, uM2 + uO1);
      case 'M2/O1':
        return (fM2 * fO1, uM2 - uO1);
      case 'M2*K1':
        return (fM2 * fK1, uM2 + uK1);
      case 'M2*K2':
        return (fM2 * fK2, uM2 + uK2);
      case 'M2^2*K1':
        return (fM2 * fM2 * fK1, 2 * uM2 + uK1);
      case 'M2^3*K1':
        return (fM2 * fM2 * fM2 * fK1, 3 * uM2 + uK1);
      case 'J1':
        return (
          1.0129 + 0.1676 * c(1) - 0.0170 * c(2) + 0.0016 * c(3),
          -12.94 * s(1) + 1.34 * s(2) - 0.19 * s(3)
        );
      case 'OO1':
        return (
          1.1027 + 0.6504 * c(1) + 0.0317 * c(2) - 0.0014 * c(3),
          -36.68 * s(1) + 4.02 * s(2) - 0.57 * s(3)
        );
      case 'Mf':
        return (
          1.0429 + 0.4135 * c(1) - 0.004 * c(2),
          -23.74 * s(1) + 2.68 * s(2) - 0.38 * s(3)
        );
      case 'Mm':
        return (1.0 - 0.1300 * c(1) + 0.0013 * c(2), 0);
      default:
        return (1, 0);
    }
  }

  /// Altura da maré (m) num instante.
  double altura(DateTime quando) {
    final t = quando.toUtc().difference(_j2000).inMicroseconds / 3.6e9;
    final a = _astro(t);
    final args = [a[0], a[1], a[2], a[3], -a[4], a[5]];
    var y = _z0;
    for (final c in _lista) {
      var v = 0.0;
      for (var i = 0; i < 6; i++) {
        v += c.doodson[i] * args[i];
      }
      final (f, u) = _nodal(c.nodal, a[4]);
      final fi = (v + u) * math.pi / 180;
      y += f * (c.a * math.cos(fi) + c.b * math.sin(fi));
    }
    return y;
  }

  /// Velocidade do nível abaixo da qual a maré é considerada parada (estofo): 5 cm por hora.
  static const limiteEstofo = 0.05;

  /// Velocidade do nível (m/h) num instante, por diferença de ±1 minuto.
  double velocidade(DateTime t) =>
      (altura(t.add(const Duration(minutes: 1))) - altura(t.subtract(const Duration(minutes: 1)))) * 30;

  DateTime _limiteEstofo(DateTime centro, int sentido) {
    var t = centro;
    for (var i = 0; i < 180; i++) {
      final proximo = t.add(Duration(minutes: sentido));
      if (velocidade(proximo).abs() >= limiteEstofo) break;
      t = proximo;
    }
    return t;
  }

  /// Marés altas e baixas entre [inicio] e [fim] (passo de 1 minuto), com o estofo.
  List<ExtremoMare> extremos(DateTime inicio, DateTime fim) {
    const passo = Duration(minutes: 1);
    final r = <ExtremoMare>[];
    var t0 = inicio.subtract(passo);
    var y0 = altura(t0);
    var t1 = inicio;
    var y1 = altura(t1);
    while (!t1.isAfter(fim)) {
      final t2 = t1.add(passo);
      final y2 = altura(t2);
      final alta = y1 > y0 && y1 >= y2;
      final baixa = y1 < y0 && y1 <= y2;
      if (alta || baixa) {
        r.add(ExtremoMare(
          hora: t1,
          altura: y1,
          alta: alta,
          estofoInicio: _limiteEstofo(t1, -1),
          estofoFim: _limiteEstofo(t1, 1),
        ));
      }
      t0 = t1;
      y0 = y1;
      t1 = t2;
      y1 = y2;
    }
    return _semOscilacoes(r);
  }

  /// Tira pares de alta e baixa seguidas que diferem menos de 5 cm: são ondulações da
  /// curva perto de um pico achatado, não marés de verdade (a alternância continua).
  static List<ExtremoMare> _semOscilacoes(List<ExtremoMare> lista) {
    final r = [...lista];
    var mudou = true;
    while (mudou) {
      mudou = false;
      var menor = 0.05;
      var indice = -1;
      for (var i = 0; i + 1 < r.length; i++) {
        final d = (r[i].altura - r[i + 1].altura).abs();
        // Só no meio da lista: o primeiro e o último dependem do corte do período.
        if (d < menor && i > 0 && i + 2 < r.length) {
          menor = d;
          indice = i;
        }
      }
      if (indice >= 0) {
        r.removeRange(indice, indice + 2);
        mudou = true;
      }
    }
    return r;
  }

  /// Distância (km) até um ponto.
  double distanciaKm(double lat, double lon) {
    const raio = 6371.0;
    final dLat = (lat - latitude) * math.pi / 180;
    final dLon = (lon - longitude) * math.pi / 180;
    final x = math.pow(math.sin(dLat / 2), 2) +
        math.cos(latitude * math.pi / 180) *
            math.cos(lat * math.pi / 180) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * raio * math.asin(math.sqrt(x));
  }

  /// Estação mais próxima da cidade, dentro do raio de cada estação.
  static EstacaoMare? proxima(double? lat, double? lon) {
    if (lat == null || lon == null) return null;
    EstacaoMare? melhor;
    var menor = double.infinity;
    for (final e in carregadas) {
      final d = e.distanciaKm(lat, lon);
      if (d <= e.raioKm && d < menor) {
        menor = d;
        melhor = e;
      }
    }
    return melhor;
  }
}
