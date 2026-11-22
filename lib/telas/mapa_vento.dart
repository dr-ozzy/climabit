import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../dados/cidade.dart';
import '../dados/radar.dart';
import '../dados/vento.dart';
import '../util/formatos.dart';
import 'radar.dart';

/// Faixas de velocidade das linhas de vento (km/h).
const _limitesVento = [15.0, 35.0];

/// Cores das linhas: fraco, moderado, forte (tema claro e escuro).
const _coresClaro = [Color(0xFF37474F), Color(0xFF7B1FA2), Color(0xFFC62828)];
const _coresEscuro = [Color(0xFFF5F5F5), Color(0xFFCE93D8), Color(0xFFFFAB40)];

/// Mapa de vento: linhas animadas que andam com o vento previsto (Open-Meteo, estimativa).
class MapaVento extends StatefulWidget {
  const MapaVento({super.key, required this.cidade, required this.mapa});

  final Cidade cidade;
  final ContornosMapa? mapa;

  @override
  State<MapaVento> createState() => _MapaVentoState();
}

class _MapaVentoState extends State<MapaVento> {
  GradeVento? _grade;
  bool _carregando = true;
  final int _hora = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final c = widget.cidade;
    if (c.latitude == null || c.longitude == null) {
      setState(() => _carregando = false);
      return;
    }
    final g = await FonteVento().grade(c.latitude!, c.longitude!);
    if (!mounted) return;
    setState(() {
      _grade = g;
      _carregando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final c = widget.cidade;
    if (c.latitude == null || c.longitude == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Esta cidade não tem localização. Escolha a cidade de novo na lista para ver o vento.',
          textAlign: TextAlign.center,
        ),
      );
    }
    final escuro = tema.colorScheme.brightness == Brightness.dark;
    final grade = _grade;
    final area = grade?.area ?? areaAoRedor(c.latitude!, c.longitude!);
    // O contorno do IBGE só existe para a região do Rio; fora dela, fundo liso de terra.
    final noMapa = RadarSumare().area.contem(c.latitude!, c.longitude!);
    final terra = tema.colorScheme.surfaceContainerHighest;
    final (cx, cy) = area.posicao(c.latitude!, c.longitude!);
    final ventoCidade = grade?.ventoEm(cx, cy, _hora.toDouble());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: area.proporcao,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (noMapa && widget.mapa != null)
                  CustomPaint(
                    painter: PintorMapa(
                      widget.mapa!,
                      area,
                      terra: terra,
                      mar: escuro
                          ? const Color(0xFF0D2236)
                          : const Color(0xFFD6E9F8),
                      linha: tema.colorScheme.outlineVariant,
                      linhaEstado: tema.colorScheme.outline,
                    ),
                  )
                else
                  ColoredBox(color: terra),
                if (grade != null)
                  CustomPaint(painter: _PintorFundo(grade, _hora)),
                if (grade != null)
                  _LinhasVento(
                    grade: grade,
                    hora: _hora.toDouble(),
                    cores: escuro ? _coresEscuro : _coresClaro,
                  ),
                CustomPaint(
                  painter: PintorMarcadores(
                    area,
                    [(c.latitude!, c.longitude!, c.nome, true)],
                    cor: tema.colorScheme.onSurface,
                    contorno: tema.colorScheme.surface,
                    destaque: tema.colorScheme.primary,
                  ),
                ),
                if (_carregando)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
        const _LegendaChuva(),
        _LegendaVento(cores: escuro ? _coresEscuro : _coresClaro),
        const SizedBox(height: 12),
        if (grade != null && ventoCidade != null) ...[
          Text(
            _frase(c.nome, ventoCidade, grade.horas[_hora]),
            style: tema.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Estimativa de modelo (Open-Meteo), não é medição.'
            '${grade.doCache ? ' Sem internet: dados guardados de ${hora(grade.obtidoEm)}.' : ''}',
            style: tema.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ] else if (!_carregando)
          const Text(
            'Não foi possível obter o vento agora. Puxe a tela para baixo para tentar de novo.',
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 12),
        Text(
          'Fonte: Open-Meteo (CC BY 4.0), previsão de modelos meteorológicos.'
          '${noMapa ? ' Mapa: IBGE.' : ''}'
          '${grade != null ? ' Obtido às ${hora(grade.obtidoEm)}.' : ''}',
          style: tema.textTheme.bodySmall?.copyWith(
            color: tema.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _frase(String cidade, (double, double) vento, DateTime quando) {
    final (u, v) = vento;
    final kmh = math.sqrt(u * u + v * v);
    // A primeira hora da previsão é a hora atual.
    final momento = DateTime.now().difference(quando).inMinutes < 60
        ? 'agora'
        : 'às ${hora(quando)}';
    if (kmh < 2) return 'Vento em $cidade $momento: calmo';
    // De onde vem: o contrário do sentido em que sopra.
    final de = (math.atan2(-u, -v) * 180 / math.pi + 360) % 360;
    return 'Vento em $cidade $momento: ${kmh.round()} km/h, '
        'vindo de ${direcaoVento(de.round())}';
  }
}

/// Partículas que andam com o vento e deixam um rastro curto.
class _LinhasVento extends StatefulWidget {
  const _LinhasVento({
    required this.grade,
    required this.hora,
    required this.cores,
  });

  final GradeVento grade;
  final double hora;
  final List<Color> cores;

  @override
  State<_LinhasVento> createState() => _LinhasVentoState();
}

class _LinhasVentoState extends State<_LinhasVento>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _particulas = _Particulas();
  Duration _anterior = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_passo)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _particulas.dispose();
    super.dispose();
  }

  void _passo(Duration agora) {
    final dt = ((agora - _anterior).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _anterior = agora;
    if (dt == 0) return;
    _particulas.avancar(widget.grade, widget.hora, dt);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _particulas.preparar(box.maxWidth * box.maxHeight, widget.grade.area);
        return RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _PintorLinhas(_particulas, widget.cores),
          ),
        );
      },
    );
  }
}

/// Posições guardadas em listas de números (sem criar objetos a cada quadro).
class _Particulas extends ChangeNotifier {
  static const rastro = 10;
  final _sorte = math.Random();

  int n = 0;

  /// Posições de 0 a 1; [rastro] posições por partícula, a mais nova no índice [_cabeca].
  Float32List x = Float32List(0);
  Float32List y = Float32List(0);
  Float32List idade = Float32List(0);
  Float32List vida = Float32List(0);
  Float32List velocidade = Float32List(0);
  int _cabeca = 0;
  double _acumulado = 0;
  int passos = 0;
  double _proporcao = 1;

  void preparar(double pixels, AreaRadar area) {
    final quer = (pixels / 150).clamp(300, 1100).round();
    _proporcao = area.proporcao;
    if (quer == n) return;
    n = quer;
    x = Float32List(n * rastro);
    y = Float32List(n * rastro);
    idade = Float32List(n);
    vida = Float32List(n);
    velocidade = Float32List(n);
    for (var i = 0; i < n; i++) {
      _nascer(i);
      // Idades sorteadas: as partículas não somem todas juntas.
      idade[i] = _sorte.nextDouble() * vida[i];
    }
  }

  void _nascer(int i) {
    final px = _sorte.nextDouble();
    final py = _sorte.nextDouble();
    for (var k = 0; k < rastro; k++) {
      x[i * rastro + k] = px;
      y[i * rastro + k] = py;
    }
    idade[i] = 0;
    vida[i] = 2 + _sorte.nextDouble() * 2;
  }

  /// Velocidade visual: 30 km/h atravessa o mapa em cerca de 8 segundos.
  static const _escala = 0.004;

  void avancar(GradeVento g, double hora, double dt) {
    if (n == 0) return;
    // Um ponto novo no rastro a cada 70 ms: o rastro dura cerca de 0,7 s, seja qual for a
    // velocidade de quadros do aparelho. Entre um ponto e outro, só a ponta anda.
    _acumulado += dt;
    final girar = _acumulado >= 0.07;
    if (girar) _acumulado = 0;
    final novo = girar ? (_cabeca + 1) % rastro : _cabeca;
    for (var i = 0; i < n; i++) {
      final b = i * rastro;
      final ax = x[b + _cabeca];
      final ay = y[b + _cabeca];
      final (u, v) = g.ventoEm(ax, ay, hora);
      final s = math.sqrt(u * u + v * v);
      velocidade[i] = s;
      // Vento quase parado envelhece mais rápido (não acumula pontos parados).
      idade[i] += dt * (s < 3 ? 2.5 : 1);
      final nx = ax + u * _escala * dt;
      final ny = ay - v * _escala * dt * _proporcao;
      if (idade[i] > vida[i] || nx < 0 || nx > 1 || ny < 0 || ny > 1) {
        _nascer(i);
      } else {
        x[b + novo] = nx;
        y[b + novo] = ny;
      }
    }
    _cabeca = novo;
    passos++;
    notifyListeners();
  }

  int get cabeca => _cabeca;
}

class _PintorLinhas extends CustomPainter {
  _PintorLinhas(this.p, this.cores) : super(repaint: p);

  final _Particulas p;
  final List<Color> cores;

  // Um conjunto de segmentos por faixa de velocidade e posição no rastro.
  static const _faixas = 3;
  final List<Float32List> _buffers = [];
  final List<int> _contagem = List.filled(_faixas * _Particulas.rastro, 0);
  final _tinta = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 1.7;

  @override
  void paint(Canvas canvas, Size s) {
    final n = p.n;
    if (n == 0) return;
    const r = _Particulas.rastro;
    if (_buffers.length != _faixas * r || _buffers.first.length < n * 4) {
      _buffers
        ..clear()
        ..addAll([for (var i = 0; i < _faixas * r; i++) Float32List(n * 4)]);
    }
    _contagem.fillRange(0, _contagem.length, 0);
    final w = s.width;
    final h = s.height;
    for (var i = 0; i < n; i++) {
      final vel = p.velocidade[i];
      final faixa = vel < _limitesVento[0]
          ? 0
          : (vel < _limitesVento[1] ? 1 : 2);
      // Esmaece ao nascer e ao morrer.
      final vidaRel = p.idade[i] / p.vida[i];
      if (vidaRel < 0.05 || vidaRel > 0.97) continue;
      final b = i * r;
      // Segmentos do mais novo (k = 1) ao mais velho (k = r - 1).
      for (var k = 1; k < r; k++) {
        final a = (p.cabeca - k + 1 + r) % r;
        final c = (p.cabeca - k + r) % r;
        final x1 = p.x[b + a], y1 = p.y[b + a];
        final x2 = p.x[b + c], y2 = p.y[b + c];
        if (x1 == x2 && y1 == y2) continue;
        final idx = faixa * r + k;
        final buf = _buffers[idx];
        final o = _contagem[idx] * 4;
        buf[o] = x1 * w;
        buf[o + 1] = y1 * h;
        buf[o + 2] = x2 * w;
        buf[o + 3] = y2 * h;
        _contagem[idx]++;
      }
    }
    for (var f = 0; f < _faixas; f++) {
      for (var k = 1; k < r; k++) {
        final idx = f * r + k;
        final cnt = _contagem[idx];
        if (cnt == 0) continue;
        final alfa = 1 - (k - 1) / (r - 1);
        _tinta.color = cores[f].withValues(alpha: 0.95 * alfa);
        canvas.drawRawPoints(
          ui.PointMode.lines,
          Float32List.sublistView(_buffers[idx], 0, cnt * 4),
          _tinta,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PintorLinhas old) => old.p != p || old.cores != cores;
}

/// Escala da chuva (mm/h → cor). Abaixo de 0,1 mm/h não há chuva: aparecem só as nuvens.
const _escalaChuva = <(double, Color)>[
  (0.1, Color(0x9942A5F5)), // azul: fraca
  (1, Color(0xAA1E88E5)),
  (3, Color(0xB343A047)), // verde: moderada
  (6, Color(0xBF7CB342)),
  (10, Color(0xC7FDD835)), // amarelo: forte
  (20, Color(0xCCFB8C00)), // laranja: muito forte
];

/// Nuvem cheia (100 %): branco translúcido.
const _nuvemCheia = Color(0x5CFFFFFF);

Color corChuvaNuvem(double mm, double nuvens) {
  if (mm < _escalaChuva.first.$1) {
    final a = (nuvens.clamp(0, 100) / 100) * _nuvemCheia.a;
    return _nuvemCheia.withValues(alpha: a);
  }
  for (var i = 1; i < _escalaChuva.length; i++) {
    final (v1, c1) = _escalaChuva[i];
    if (mm <= v1) {
      final (v0, c0) = _escalaChuva[i - 1];
      return Color.lerp(c0, c1, (mm - v0) / (v1 - v0))!;
    }
  }
  return _escalaChuva.last.$2;
}

/// Fundo de chuva e nuvens: triângulos entre os pontos da grade, com as cores misturadas
/// pela placa de vídeo (transição suave, sem gerar imagem).
class _PintorFundo extends CustomPainter {
  _PintorFundo(this.grade, this.hora);

  final GradeVento grade;
  final int hora;

  @override
  void paint(Canvas canvas, Size s) {
    final g = grade;
    final nc = g.colunas, nl = g.linhas;
    final h = hora.clamp(0, g.horas.length - 1);
    final pos = Float32List(nc * nl * 2);
    final cores = Int32List(nc * nl);
    final a = g.area;
    for (var l = 0; l < nl; l++) {
      final lat = a.norte - (a.norte - a.sul) * l / (nl - 1);
      final (_, y) = a.posicao(lat, a.oeste);
      for (var c = 0; c < nc; c++) {
        final i = l * nc + c;
        pos[i * 2] = c / (nc - 1) * s.width;
        pos[i * 2 + 1] = y * s.height;
        cores[i] = corChuvaNuvem(g.chuva[h][i], g.nuvens[h][i]).toARGB32();
      }
    }
    final indices = Uint16List((nc - 1) * (nl - 1) * 6);
    var k = 0;
    for (var l = 0; l < nl - 1; l++) {
      for (var c = 0; c < nc - 1; c++) {
        final i = l * nc + c;
        indices
          ..[k++] = i
          ..[k++] = i + 1
          ..[k++] = i + nc
          ..[k++] = i + 1
          ..[k++] = i + nc + 1
          ..[k++] = i + nc;
      }
    }
    final v = ui.Vertices.raw(
      ui.VertexMode.triangles,
      pos,
      colors: cores,
      indices: indices,
    );
    canvas.drawVertices(v, BlendMode.dst, Paint());
    v.dispose();
  }

  @override
  bool shouldRepaint(_PintorFundo old) =>
      old.grade != grade || old.hora != hora;
}

class _LegendaChuva extends StatelessWidget {
  const _LegendaChuva();

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text('Chuva', style: estilo),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: [
                        for (final (_, c) in _escalaChuva)
                          c.withValues(alpha: 1),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Text('fraca', style: estilo),
                    const Spacer(),
                    Text('moderada', style: estilo),
                    const Spacer(),
                    Text('forte (10 mm/h)', style: estilo),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 18,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.black26, width: 0.5),
            ),
          ),
          const SizedBox(width: 4),
          Text('nuvens', style: estilo),
        ],
      ),
    );
  }
}

class _LegendaVento extends StatelessWidget {
  const _LegendaVento({required this.cores});

  final List<Color> cores;

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.labelSmall;
    final nomes = [
      'fraco (até ${_limitesVento[0].round()} km/h)',
      'moderado',
      'forte (mais de ${_limitesVento[1].round()} km/h)',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          for (var i = 0; i < 3; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 18,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cores[i],
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: Colors.black26, width: 0.5),
                  ),
                ),
                const SizedBox(width: 4),
                Text(nomes[i], style: estilo),
              ],
            ),
        ],
      ),
    );
  }
}
