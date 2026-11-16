import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Fases principais da lua.
enum FasePrincipal { nova, quartoCrescente, cheia, quartoMinguante }

/// Data e hora (UTC) de uma fase principal.
class MomentoFase {
  const MomentoFase(this.fase, this.quando);
  final FasePrincipal fase;
  final DateTime quando;
}

/// Fases da lua pelo algoritmo de Jean Meeus ("Astronomical Algorithms", cap. 49),
/// com os termos principais (erro de poucos minutos). Calculado no aparelho, sem internet.
class Lua {
  Lua._();

  static double _rad(double g) => g * math.pi / 180;

  /// Momento da fase para o número k (inteiro = lua nova; +0,25 quarto crescente;
  /// +0,5 cheia; +0,75 quarto minguante).
  static DateTime momento(double k) {
    final t = k / 1236.85;
    var jde = 2451550.09766 + 29.530588861 * k + 0.00015437 * t * t -
        0.000000150 * t * t * t + 0.00000000073 * t * t * t * t;
    final e = 1 - 0.002516 * t - 0.0000074 * t * t;
    final m = _rad(2.5534 + 29.10535670 * k - 0.0000014 * t * t - 0.00000011 * t * t * t);
    final ml = _rad(201.5643 + 385.81693528 * k + 0.0107582 * t * t + 0.00001238 * t * t * t -
        0.000000058 * t * t * t * t);
    final f = _rad(160.7108 + 390.67050284 * k - 0.0016118 * t * t - 0.00000227 * t * t * t +
        0.000000011 * t * t * t * t);
    final om = _rad(124.7746 - 1.56375588 * k + 0.0020672 * t * t + 0.00000215 * t * t * t);
    final s = math.sin;
    final c = math.cos;
    final fracao = k - k.floorToDouble();
    double corr;
    if (fracao < 0.01 || fracao > 0.99) {
      corr = -0.40720 * s(ml) + 0.17241 * e * s(m) + 0.01608 * s(2 * ml) + 0.01039 * s(2 * f) +
          0.00739 * e * s(ml - m) - 0.00514 * e * s(ml + m) + 0.00208 * e * e * s(2 * m) -
          0.00111 * s(ml - 2 * f) - 0.00057 * s(ml + 2 * f) + 0.00056 * e * s(2 * ml + m) -
          0.00042 * s(3 * ml) + 0.00042 * e * s(m + 2 * f) + 0.00038 * e * s(m - 2 * f) -
          0.00024 * e * s(2 * ml - m) - 0.00017 * s(om);
    } else if ((fracao - 0.5).abs() < 0.01) {
      corr = -0.40614 * s(ml) + 0.17302 * e * s(m) + 0.01614 * s(2 * ml) + 0.01043 * s(2 * f) +
          0.00734 * e * s(ml - m) - 0.00515 * e * s(ml + m) + 0.00209 * e * e * s(2 * m) -
          0.00111 * s(ml - 2 * f) - 0.00057 * s(ml + 2 * f) + 0.00056 * e * s(2 * ml + m) -
          0.00042 * s(3 * ml) + 0.00042 * e * s(m + 2 * f) + 0.00038 * e * s(m - 2 * f) -
          0.00024 * e * s(2 * ml - m) - 0.00017 * s(om);
    } else {
      corr = -0.62801 * s(ml) + 0.17172 * e * s(m) - 0.01183 * e * s(ml + m) +
          0.00862 * s(2 * ml) + 0.00804 * s(2 * f) + 0.00454 * e * s(ml - m) +
          0.00204 * e * e * s(2 * m) - 0.00180 * s(ml - 2 * f) - 0.00070 * s(ml + 2 * f) -
          0.00040 * s(3 * ml) - 0.00034 * e * s(2 * ml - m) + 0.00032 * e * s(m + 2 * f) +
          0.00032 * e * s(m - 2 * f) - 0.00028 * e * e * s(ml + 2 * m) +
          0.00027 * e * s(2 * ml + m) - 0.00017 * s(om);
      final w = 0.00306 - 0.00038 * e * c(m) + 0.00026 * c(ml) - 0.00002 * c(ml - m) +
          0.00002 * c(ml + m) + 0.00002 * c(2 * f);
      corr += fracao < 0.5 ? w : -w;
    }
    jde += corr;
    final ms = ((jde - 2440587.5) * 86400000).round();
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  static double _kAproximado(DateTime t) {
    final anos = t.toUtc().difference(DateTime.utc(2000, 1, 6, 18, 14)).inMinutes /
        (60 * 24 * 365.25);
    return anos * 12.3685;
  }

  /// Fases principais entre [inicio] e [fim], em ordem.
  static List<MomentoFase> fases(DateTime inicio, DateTime fim) {
    final r = <MomentoFase>[];
    final k0 = _kAproximado(inicio).floorToDouble() - 1;
    for (var k = k0; ; k += 0.25) {
      final q = momento(k);
      if (q.isAfter(fim)) break;
      if (!q.isBefore(inicio)) {
        final i = ((k - k.floorToDouble()) * 4).round() % 4;
        r.add(MomentoFase(FasePrincipal.values[i], q));
      }
    }
    return r;
  }

  /// Idade da lunação (0 = nova, 0,5 = cheia, perto de 1 = nova de novo).
  static double idade(DateTime t) {
    final k0 = _kAproximado(t).floorToDouble() - 1;
    var anterior = momento(k0);
    for (var k = k0 + 1; ; k++) {
      final proxima = momento(k);
      if (proxima.isAfter(t)) {
        return t.difference(anterior).inSeconds / proxima.difference(anterior).inSeconds;
      }
      anterior = proxima;
    }
  }

  /// Fração do disco iluminada (0 a 1).
  static double iluminada(DateTime t) => (1 - math.cos(2 * math.pi * idade(t))) / 2;

  /// Nome da fase para mostrar ("Lua cheia", "Lua crescente"...). Fase principal quando
  /// ela acontece a menos de 1 dia.
  static String nome(DateTime t) {
    for (final f in fases(t.subtract(const Duration(days: 1)), t.add(const Duration(days: 1)))) {
      return nomeFase(f.fase);
    }
    return idade(t) < 0.5 ? 'Lua crescente' : 'Lua minguante';
  }

  static String nomeFase(FasePrincipal f) => switch (f) {
        FasePrincipal.nova => 'Lua nova',
        FasePrincipal.quartoCrescente => 'Quarto crescente',
        FasePrincipal.cheia => 'Lua cheia',
        FasePrincipal.quartoMinguante => 'Quarto minguante',
      };
}

/// Desenho da lua como vista do hemisfério sul: na fase crescente a parte iluminada
/// fica à esquerda; na minguante, à direita.
class DesenhoLua extends StatelessWidget {
  const DesenhoLua({super.key, required this.idade, this.size = 24, this.corEscura});

  /// Idade da lunação, de 0 (nova) a 1.
  final double idade;
  final double size;

  /// Cor da parte não iluminada (padrão: cor de fundo do tema).
  final Color? corEscura;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _PintorLua(
          idade,
          clara: const Color(0xFFF2D65C),
          escura: corEscura ?? tema.colorScheme.surfaceContainerHighest,
          borda: tema.colorScheme.outline,
        ),
      ),
    );
  }
}

class _PintorLua extends CustomPainter {
  _PintorLua(this.idade, {required this.clara, required this.escura, required this.borda});

  final double idade;
  final Color clara;
  final Color escura;
  final Color borda;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 1;
    final centro = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(centro, r, Paint()..color = escura);
    final fracao = (1 - math.cos(2 * math.pi * idade)) / 2;
    if (fracao > 0.01) {
      // Hemisfério sul: crescente iluminada à esquerda.
      final esquerda = idade < 0.5;
      canvas.save();
      if (!esquerda) {
        canvas.translate(size.width, 0);
        canvas.scale(-1, 1);
      }
      final topo = Offset(centro.dx, centro.dy - r);
      final base = Offset(centro.dx, centro.dy + r);
      final rx = r * (1 - 2 * fracao).abs();
      final caminho = Path()
        ..moveTo(topo.dx, topo.dy)
        ..arcToPoint(base, radius: Radius.circular(r), clockwise: false)
        ..arcToPoint(topo, radius: Radius.elliptical(rx < 0.01 ? 0.01 : rx, r), clockwise: fracao < 0.5)
        ..close();
      canvas.drawPath(caminho, Paint()..color = clara);
      canvas.restore();
    }
    canvas.drawCircle(
        centro,
        r,
        Paint()
          ..color = borda
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_PintorLua old) => old.idade != idade;
}
