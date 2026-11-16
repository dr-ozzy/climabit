import 'dart:math' as math;

/// Nascer e pôr (hora local do aparelho). Nulo quando não acontece no dia.
class NascerPor {
  const NascerPor(this.nascer, this.por);
  final DateTime? nascer;
  final DateTime? por;
}

/// Posição do sol e da lua no céu, calculada no aparelho, sem internet.
///
/// Fórmulas de baixa precisão do Astronomical Almanac (sol: cerca de 0,01°; lua: cerca de
/// 0,3°), suficientes para nascer e pôr com erro de 1 a 3 minutos.
class Astro {
  Astro._();

  static const _rad = math.pi / 180;
  static final _j2000 = DateTime.utc(2000, 1, 1, 12);

  static double _dias(DateTime t) => t.toUtc().difference(_j2000).inMicroseconds / 8.64e10;

  static double _seno(double g) => math.sin(g * _rad);
  static double _cos(double g) => math.cos(g * _rad);

  /// Altitude (graus) de um astro com ascensão reta [ra] e declinação [dec] (graus).
  static double _altitude(double d, double ra, double dec, double lat, double lon) {
    final tsg = 280.46061837 + 360.98564736629 * d;
    final h = tsg + lon - ra;
    final s = _seno(lat) * _seno(dec) + _cos(lat) * _cos(dec) * _cos(h);
    return math.asin(s.clamp(-1.0, 1.0)) / _rad;
  }

  static (double, double) _equatorial(double d, double lambda, double beta) {
    final eps = 23.439 - 0.0000004 * d;
    final ra = math.atan2(
            _seno(lambda) * _cos(eps) - math.tan(beta * _rad) * _seno(eps), _cos(lambda)) /
        _rad;
    final dec = math.asin(
            _seno(beta) * _cos(eps) + _cos(beta) * _seno(eps) * _seno(lambda)) /
        _rad;
    return (ra, dec);
  }

  /// Altitude do centro do sol (graus) num instante e lugar.
  static double altitudeSol(DateTime t, double lat, double lon) {
    final d = _dias(t);
    final l = 280.460 + 0.9856474 * d;
    final g = 357.528 + 0.9856003 * d;
    final lambda = l + 1.915 * _seno(g) + 0.020 * _seno(2 * g);
    final (ra, dec) = _equatorial(d, lambda, 0);
    return _altitude(d, ra, dec, lat, lon);
  }

  /// Altitude geocêntrica da lua (graus) e paralaxe horizontal (graus).
  static (double, double) _lua(DateTime t, double lat, double lon) {
    final d = _dias(t);
    final tt = d / 36525;
    final lambda = 218.32 + 481267.881 * tt +
        6.29 * _seno(135.0 + 477198.87 * tt) -
        1.27 * _seno(259.3 - 413335.36 * tt) +
        0.66 * _seno(235.7 + 890534.22 * tt) +
        0.21 * _seno(269.9 + 954397.74 * tt) -
        0.19 * _seno(357.5 + 35999.05 * tt) -
        0.11 * _seno(186.5 + 966404.03 * tt);
    final beta = 5.13 * _seno(93.3 + 483202.02 * tt) +
        0.28 * _seno(228.2 + 960400.89 * tt) -
        0.28 * _seno(318.3 + 6003.15 * tt) -
        0.17 * _seno(217.6 - 407332.21 * tt);
    final paralaxe = 0.9508 +
        0.0518 * _cos(135.0 + 477198.87 * tt) +
        0.0095 * _cos(259.3 - 413335.36 * tt) +
        0.0078 * _cos(235.7 + 890534.22 * tt) +
        0.0028 * _cos(269.9 + 954397.74 * tt);
    final (ra, dec) = _equatorial(d, lambda, beta);
    return (_altitude(d, ra, dec, lat, lon), paralaxe);
  }

  /// O sol está abaixo do horizonte (contando a refração).
  static bool noite(DateTime t, double lat, double lon) => altitudeSol(t, lat, lon) < -0.833;

  /// Nascer e pôr do sol no dia local de [dia].
  static NascerPor sol(DateTime dia, double lat, double lon) =>
      _cruzamentos(dia, (t) => altitudeSol(t, lat, lon) + 0.833);

  /// Nascer e pôr da lua no dia local de [dia] (borda superior, com refração e paralaxe).
  static NascerPor lua(DateTime dia, double lat, double lon) => _cruzamentos(dia, (t) {
        final (alt, par) = _lua(t, lat, lon);
        return alt - (0.7275 * par - 0.5667);
      });

  /// Procura, de 10 em 10 minutos, onde [f] troca de sinal, e refina por bisseção.
  static NascerPor _cruzamentos(DateTime dia, double Function(DateTime) f) {
    final inicio = DateTime(dia.year, dia.month, dia.day);
    final fim = inicio.add(const Duration(days: 1));
    DateTime? nascer;
    DateTime? por;
    var t0 = inicio;
    var y0 = f(t0);
    while (t0.isBefore(fim)) {
      final t1 = t0.add(const Duration(minutes: 10));
      final y1 = f(t1);
      if ((y0 < 0) != (y1 < 0)) {
        var a = t0;
        var b = t1;
        var ya = y0;
        for (var i = 0; i < 12; i++) {
          final m = a.add(Duration(microseconds: b.difference(a).inMicroseconds ~/ 2));
          final ym = f(m);
          if ((ya < 0) == (ym < 0)) {
            a = m;
            ya = ym;
          } else {
            b = m;
          }
        }
        final momento = a;
        if (momento.isBefore(fim)) {
          if (y0 < 0) {
            nascer ??= momento;
          } else {
            por ??= momento;
          }
        }
      }
      t0 = t1;
      y0 = y1;
    }
    return NascerPor(nascer, por);
  }
}
