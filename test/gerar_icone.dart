// Gera o ícone do app em pixel art (sol atrás de uma nuvem, céu com morros).
// Não roda com os testes comuns. Para gerar de novo:
//   flutter test --update-goldens test/gerar_icone.dart
// e copie test/icone/* para android/app/src/main/res/ (as pastas já vêm com o nome certo).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Grade do ícone adaptável: 27 × 27 "pixels" de arte (108 dp do Android).
const _grade = 27;

const _bayer = [
  [0, 8, 2, 10],
  [12, 4, 14, 6],
  [3, 11, 1, 9],
  [15, 7, 13, 5],
];

/// Fundo: céu em degradê pontilhado e dois morros verdes embaixo.
Color? _fundo(int x, int y) {
  const ceu = [Color(0xFF2A6BD0), Color(0xFF4A8FE4), Color(0xFF86BFF1), Color(0xFFC8E6F8)];
  final morroFundo = (19 + 2 * math.sin(x * 0.35 + 0.8)).round();
  final morroFrente = (22 + 1.5 * math.sin(x * 0.5 + 2.6)).round();
  if (y >= morroFrente) return y == morroFrente ? const Color(0xFF5DAD45) : const Color(0xFF3C7D4E);
  if (y >= morroFundo) return y == morroFundo ? const Color(0xFF79B48D) : const Color(0xFF5E9C78);
  final t = y / (_grade - 1) * 3;
  final i = t.floor().clamp(0, 2);
  final f = t - i;
  return ceu[_bayer[y % 4][x % 4] < (f * 16).floor() ? i + 1 : i];
}

bool _nuvem(int x, int y) {
  // Nuvem desenhada pixel a pixel: três "bolhas" com reentrâncias entre elas.
  const desenho = [
    '......####.....',
    '.....######....',
    '.###.######.##.',
    '#####.####.####',
    '###############',
    '###############',
    '###############',
    '.#############.',
  ];
  final cx = x - 6, cy = y - 10;
  if (cy < 0 || cy >= desenho.length || cx < 0 || cx >= desenho[0].length) return false;
  return desenho[cy][cx] == '#';
}

/// Frente centralizada na zona segura do ícone adaptável (o desenho foi feito mais acima).
Color? _frente(int x, int y) => _desenhoFrente(x + 1, y - 3);

/// Sol com raios no alto à direita e nuvem branca com contorno.
Color? _desenhoFrente(int x, int y) {
  const contorno = Color(0xFF2B3A55);
  if (_nuvem(x, y)) {
    if (y >= 16) return const Color(0xFFB5C4D8);
    if (!_nuvem(x - 1, y - 1)) return const Color(0xFFFFFFFF);
    return const Color(0xFFE6EDF6);
  }
  final vizinho = _nuvem(x + 1, y) || _nuvem(x - 1, y) || _nuvem(x, y + 1) || _nuvem(x, y - 1);
  if (vizinho) return contorno;
  // Sol.
  const sx = 17.0, sy = 9.0, r = 4.3;
  final d2 = (x - sx) * (x - sx) + (y - sy) * (y - sy);
  if (d2 <= r * r) {
    if (d2 > (r - 1.2) * (r - 1.2)) return const Color(0xFFFFB627);
    return (x < sx && y < sy) ? const Color(0xFFFFF7C2) : const Color(0xFFFFE066);
  }
  // Raios (8 direções).
  const raios = [
    (17, 3), (17, 2), (23, 9), (24, 9), (11, 9), (21, 5), (22, 4), (13, 5), (12, 4), (21, 13), (22, 14),
  ];
  for (final (rx, ry) in raios) {
    if (x == rx && y == ry) return const Color(0xFFFFD84A);
  }
  return null;
}

class _Pintor extends CustomPainter {
  _Pintor(this.camada, {this.recorte = 0, this.forma = 0});

  /// 0 = fundo, 1 = frente, 2 = frente monocromática, 3 = ícone completo (antigo).
  final int camada;

  /// Células cortadas de cada lado (ícone antigo mostra só o centro).
  final int recorte;

  /// 0 = quadrado arredondado, 1 = círculo (só para o ícone antigo).
  final int forma;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _grade - 2 * recorte;
    final s = size.width / n;
    final p = Paint()..isAntiAlias = false;
    if (camada == 3) {
      final ret = Offset.zero & size;
      canvas.clipPath(Path()
        ..addRRect(forma == 1
            ? RRect.fromRectAndRadius(ret, Radius.circular(size.width / 2))
            : RRect.fromRectAndRadius(ret, Radius.circular(size.width * 0.18))));
    }
    for (var gy = 0; gy < n; gy++) {
      for (var gx = 0; gx < n; gx++) {
        final x = gx + recorte, y = gy + recorte;
        Color? cor;
        switch (camada) {
          case 0:
            cor = _fundo(x, y);
          case 1:
            cor = _frente(x, y);
          case 2:
            cor = _frente(x, y) == null ? null : const Color(0xFFFFFFFF);
          default:
            cor = _frente(x, y) ?? _fundo(x, y);
        }
        if (cor == null) continue;
        p.color = cor;
        canvas.drawRect(Rect.fromLTWH(gx * s, gy * s, s + 0.5, s + 0.5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Pintor old) => true;
}

void main() {
  testWidgets('ícone do app', (t) async {
    t.view.devicePixelRatio = 1;
    const densidades = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
    Future<void> gerar(String arquivo, double lado, _Pintor pintor) async {
      t.view.physicalSize = Size(lado, lado);
      await t.pumpWidget(Center(
        child: RepaintBoundary(
          key: const Key('i'),
          child: SizedBox.square(dimension: lado, child: CustomPaint(painter: pintor)),
        ),
      ));
      await expectLater(find.byKey(const Key('i')), matchesGoldenFile('icone/$arquivo'));
    }

    for (final MapEntry(key: nome, value: d) in densidades.entries) {
      await gerar('mipmap-$nome/ic_launcher_fundo.png', 108 * d, _Pintor(0));
      await gerar('mipmap-$nome/ic_launcher_frente.png', 108 * d, _Pintor(1));
      await gerar('mipmap-$nome/ic_launcher_mono.png', 108 * d, _Pintor(2));
      await gerar('mipmap-$nome/ic_launcher.png', 48 * d, _Pintor(3, recorte: 4));
      await gerar('mipmap-$nome/ic_launcher_round.png', 48 * d, _Pintor(3, recorte: 4, forma: 1));
    }
    // Visão grande para conferir o desenho.
    await gerar('amostra.png', 432, _Pintor(3, recorte: 0));
  });
}
