import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'dart:typed_data';

import '../dados/radar.dart';
import '../dados/repositorio.dart';
import '../util/formatos.dart';

/// Imagens dos radares oficiais (Sumaré e Niterói) sobre o mapa do IBGE.
/// Abre no radar com a imagem mais recente entre os que cobrem a cidade.
class TelaRadar extends StatefulWidget {
  const TelaRadar({super.key, required this.repo, this.radares});

  final Repositorio repo;
  final List<FonteRadar>? radares;

  @override
  State<TelaRadar> createState() => _TelaRadarState();
}

class _EstadoRadar {
  _EstadoRadar(this.fonte);
  final FonteRadar fonte;
  List<QuadroRadar> quadros = [];
  SituacaoRadar? situacao;
  bool carregado = false;
}

class _TelaRadarState extends State<TelaRadar> {
  late final List<_EstadoRadar> _radares = [
    for (final f in widget.radares ?? _radaresDaCidade()) _EstadoRadar(f),
  ];

  /// Canadá: radar oficial de lá, centrado na cidade. Brasil: radares do Rio e de Niterói.
  List<FonteRadar> _radaresDaCidade() {
    final c = widget.repo.cidade;
    if (c.noCanada && c.latitude != null && c.longitude != null) {
      return [RadarCanada(c.latitude!, c.longitude!)];
    }
    return [RadarNiteroi(), RadarSumare()];
  }

  Uint8List? _fundo;
  int _escolhido = 0;
  bool _escolhaDoUsuario = false;
  ContornosMapa? _mapa;
  bool _carregando = true;
  int _atual = 0;
  Timer? _animacao;
  DateTime? _obtidoEm;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _animacao?.cancel();
    super.dispose();
  }

  /// Radares cuja área inclui a cidade (todos, se a cidade não tiver coordenadas).
  List<int> _queCobrem() {
    final c = widget.repo.cidade;
    if (c.latitude == null || c.longitude == null) {
      return [for (var i = 0; i < _radares.length; i++) i];
    }
    return [
      for (var i = 0; i < _radares.length; i++)
        if (_radares[i].fonte.area.contem(c.latitude!, c.longitude!)) i,
    ];
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    _parar();
    // O mapa fica no app: aparece logo, enquanto as imagens chegam.
    final mapa = await ContornosMapa.carregar();
    if (!mounted) return;
    setState(() => _mapa = mapa);
    // Mapa de fundo em imagem (radar fora da área do mapa do IBGE).
    _radares[_escolhido].fonte.mapaDeFundo().then((b) {
      if (mounted && b != null) setState(() => _fundo = b);
    });

    await Future.wait([
      for (final r in _radares)
        Future.wait([r.fonte.quadros(), r.fonte.situacao()]).then((v) {
          r.quadros = v[0] as List<QuadroRadar>;
          r.situacao = v[1] as SituacaoRadar?;
          r.carregado = true;
        }),
    ]);
    if (!mounted) return;

    if (!_escolhaDoUsuario) _escolhido = _maisRecente();
    setState(() {
      _carregando = false;
      _obtidoEm = DateTime.now();
      _atual = math.max(0, _radares[_escolhido].quadros.length - 1);
    });
    for (final r in _radares) {
      for (final q in r.quadros) {
        // Pré-carrega as imagens para a animação não piscar.
        precacheImage(MemoryImage(q.bytes), context);
      }
    }
  }

  /// Entre os radares que cobrem a cidade e estão funcionando, o de imagem mais recente.
  /// Radar com aviso de desligamento só é escolhido se nenhum outro tiver imagens.
  int _maisRecente() {
    final cobrem = _queCobrem();
    final base = cobrem.isEmpty
        ? [for (var i = 0; i < _radares.length; i++) i]
        : cobrem;
    final ligados = base
        .where(
          (i) =>
              _radares[i].situacao?.normal != false &&
              _radares[i].quadros.isNotEmpty,
        )
        .toList();
    final lista = ligados.isNotEmpty ? ligados : base;
    var melhor = lista.first;
    DateTime? horaMelhor;
    for (final i in lista) {
      final q = _radares[i].quadros;
      if (q.isEmpty) continue;
      if (horaMelhor == null || q.last.hora.isAfter(horaMelhor)) {
        horaMelhor = q.last.hora;
        melhor = i;
      }
    }
    return melhor;
  }

  void _escolher(int i) {
    _parar();
    setState(() {
      _escolhido = i;
      _escolhaDoUsuario = true;
      _atual = math.max(0, _radares[i].quadros.length - 1);
    });
  }

  void _tocar() {
    final n = _radares[_escolhido].quadros.length;
    if (n < 2) return;
    _animacao = Timer.periodic(const Duration(milliseconds: 600), (_) {
      setState(() => _atual = (_atual + 1) % n);
    });
    setState(() {});
  }

  void _parar() {
    _animacao?.cancel();
    _animacao = null;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cidade = widget.repo.cidade;
    final r = _radares[_escolhido];
    final fonte = r.fonte;
    final quadros = r.quadros;
    final cobrem = _queCobrem();
    final dentro = cobrem.contains(_escolhido);
    final tocando = _animacao != null;
    final quadro = quadros.isEmpty
        ? null
        : quadros[math.min(_atual, quadros.length - 1)];
    final maisRecente = quadros.isNotEmpty && _atual >= quadros.length - 1;
    final antigo =
        quadro != null &&
        DateTime.now().difference(quadro.hora) > const Duration(minutes: 30);
    final proporcao = fonte.area.proporcao;
    final larguraMax = math.max(
      320.0,
      math.min(900.0, (MediaQuery.sizeOf(context).height - 360) * proporcao),
    );

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: larguraMax),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_radares.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SegmentedButton<int>(
                        segments: [
                          for (var i = 0; i < _radares.length; i++)
                            ButtonSegment(
                              value: i,
                              label: Text('Radar ${_radares[i].fonte.nome}'),
                            ),
                        ],
                        selected: {_escolhido},
                        onSelectionChanged: (s) => _escolher(s.first),
                      ),
                    ),
                  if (!dentro && cidade.latitude != null)
                    Card(
                      color: tema.colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '${cidade.nome} fica fora da área do radar ${fonte.nome}.',
                        ),
                      ),
                    ),
                  if (r.situacao != null && !r.situacao!.normal)
                    Card(
                      color: tema.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Aviso do ${fonte.orgao}: ${r.situacao!.texto}',
                        ),
                      ),
                    ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: proporcao,
                      child: _mapa == null
                          ? const Center(child: CircularProgressIndicator())
                          : InteractiveViewer(
                              maxScale: 6,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (_fundo != null)
                                    Image.memory(_fundo!, fit: BoxFit.fill)
                                  else
                                    CustomPaint(
                                      painter: _PintorMapa(
                                        _mapa!,
                                        fonte.area,
                                        terra: tema
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        mar:
                                            tema.colorScheme.brightness ==
                                                Brightness.dark
                                            ? const Color(0xFF0D2236)
                                            : const Color(0xFFD6E9F8),
                                        linha: tema.colorScheme.outlineVariant,
                                        linhaEstado: tema.colorScheme.outline,
                                      ),
                                    ),
                                  if (quadro != null)
                                    Image.memory(
                                      quadro.bytes,
                                      fit: BoxFit.fill,
                                      gaplessPlayback: true,
                                    ),
                                  CustomPaint(
                                    painter: _PintorMarcadores(
                                      fonte.area,
                                      [
                                        if (dentro && cidade.latitude != null)
                                          (
                                            cidade.latitude!,
                                            cidade.longitude!,
                                            cidade.nome,
                                            true,
                                          ),
                                        for (final (lat, lon, nome)
                                            in fonte.referencias)
                                          if (nome != cidade.nome)
                                            (lat, lon, nome, false),
                                      ],
                                      cor: tema.colorScheme.onSurface,
                                      contorno: tema.colorScheme.surface,
                                      destaque: tema.colorScheme.primary,
                                    ),
                                  ),
                                  if (_carregando && quadros.isEmpty)
                                    const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ),
                  if (!fonte.legendaNaImagem && fonte.legenda.isNotEmpty)
                    _Legenda(
                      cores: fonte.legenda,
                      unidade: fonte.unidadeLegenda,
                    ),
                  const SizedBox(height: 12),
                  if (quadro != null) ...[
                    Text(
                      '${fonte.rotuloHora} ${quando(quadro.hora)}${maisRecente ? ' (mais recente)' : ''}',
                      style: tema.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (antigo && maisRecente)
                      Text(
                        'O radar não publica imagem nova há mais de 30 minutos.',
                        style: TextStyle(color: tema.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: tocando ? 'Pausar' : 'Animar',
                          icon: Icon(tocando ? Icons.pause : Icons.play_arrow),
                          onPressed: () =>
                              tocando ? setState(_parar) : _tocar(),
                        ),
                        Expanded(
                          child: Slider(
                            value: math
                                .min(_atual, quadros.length - 1)
                                .toDouble(),
                            max: (quadros.length - 1).toDouble().clamp(0, 100),
                            divisions: quadros.length > 1
                                ? quadros.length - 1
                                : null,
                            label: hora(quadro.hora),
                            onChanged: quadros.length < 2
                                ? null
                                : (v) => setState(() {
                                    _parar();
                                    _atual = v.round();
                                  }),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${quadros.length} imagens, de ${hora(quadros.first.hora)} a '
                      '${hora(quadros.last.hora)} (uma a cada ${fonte.intervaloMin} minutos). '
                      'Use dois dedos para aproximar o mapa.',
                      style: tema.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ] else if (!_carregando)
                    Text(
                      'O radar ${fonte.nome} não respondeu. Puxe a tela para baixo para tentar de novo.',
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Fonte: ${fonte.orgao}, radar meteorológico ${fonte.nome}. '
                    'Mapa: ${fonte.creditoMapa}.'
                    '${_obtidoEm != null ? ' Obtido às ${hora(_obtidoEm!)}.' : ''}',
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Escala de cores do radar (refletividade em dBZ: quanto maior, mais forte a chuva).
class _Legenda extends StatelessWidget {
  const _Legenda({required this.cores, this.unidade = 'dBZ'});

  final List<(String, Color)> cores;
  final String unidade;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estilo = tema.textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (_, cor) in cores)
                    Expanded(child: ColoredBox(color: cor)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text('chuva fraca (${cores.first.$1} $unidade)', style: estilo),
              const Spacer(),
              Text('muito forte (${cores.last.$1} $unidade)', style: estilo),
            ],
          ),
        ],
      ),
    );
  }
}

Offset _ponto(AreaRadar area, double lat, double lon, Size s) {
  final (x, y) = area.posicao(lat, lon);
  return Offset(x * s.width, y * s.height);
}

class _PintorMapa extends CustomPainter {
  _PintorMapa(
    this.mapa,
    this.area, {
    required this.terra,
    required this.mar,
    required this.linha,
    required this.linhaEstado,
  });

  final ContornosMapa mapa;
  final AreaRadar area;
  final Color terra;
  final Color mar;
  final Color linha;
  final Color linhaEstado;

  Path _caminho(List<(double, double)> anel, Size s) {
    final p = Path();
    for (var i = 0; i < anel.length; i++) {
      final o = _ponto(area, anel[i].$1, anel[i].$2, s);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size s) {
    canvas.clipRect(Offset.zero & s);
    canvas.drawRect(Offset.zero & s, Paint()..color = mar);
    final preenchimento = Paint()..color = terra;
    final borda = Paint()
      ..color = linha
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    final bordaEstado = Paint()
      ..color = linhaEstado
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final a in mapa.estados) {
      final p = _caminho(a, s);
      canvas.drawPath(p, preenchimento);
      canvas.drawPath(p, bordaEstado);
    }
    for (final a in mapa.municipios) {
      final p = _caminho(a, s);
      canvas.drawPath(p, preenchimento);
      canvas.drawPath(p, borda);
    }
  }

  @override
  bool shouldRepaint(_PintorMapa old) =>
      old.mapa != mapa ||
      old.area != area ||
      old.terra != terra ||
      old.mar != mar;
}

class _PintorMarcadores extends CustomPainter {
  _PintorMarcadores(
    this.area,
    this.pontos, {
    required this.cor,
    required this.destaque,
    required this.contorno,
  });

  final AreaRadar area;
  final List<(double, double, String, bool)> pontos;
  final Color cor;
  final Color destaque;

  /// Cor da sombra em volta do texto (fundo do tema, para dar contraste).
  final Color contorno;

  @override
  void paint(Canvas canvas, Size s) {
    for (final (lat, lon, nome, principal) in pontos) {
      if (!area.contem(lat, lon)) continue;
      final o = _ponto(area, lat, lon, s);
      final c = principal ? destaque : cor;
      canvas.drawCircle(o, principal ? 5 : 3, Paint()..color = c);
      canvas.drawCircle(
        o,
        principal ? 5 : 3,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: nome,
          style: TextStyle(
            color: c,
            fontSize: principal ? 13 : 11,
            fontWeight: principal ? FontWeight.bold : FontWeight.normal,
            shadows: [Shadow(color: contorno, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final esquerda = nome == 'Rio de Janeiro';
      tp.paint(
        canvas,
        Offset(
          esquerda ? o.dx - tp.width - 6 : o.dx + 7,
          o.dy - tp.height / 2 + (esquerda ? -8 : 0),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_PintorMarcadores old) => true;
}
