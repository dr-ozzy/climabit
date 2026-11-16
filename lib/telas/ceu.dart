import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart' show Ticker;

import 'package:material_ui/material_ui.dart';

import '../dados/fontes.dart';

/// Como está o céu agora, para escolher o fundo do topo da tela inicial.
enum EstadoCeu { limpo, parcial, nublado, chuva, trovoada }

/// Céu de agora: chuva pela medição da última hora; nuvens pelo texto da previsão do
/// período atual (manhã, tarde ou noite).
///
/// [observado]: o resumo é a condição observada agora (Canadá), não uma previsão; então
/// "chuva" no texto quer dizer que está chovendo.
EstadoCeu estadoCeu(
    {required String? resumoPeriodo, required double? chuvaUltimaHora, bool observado = false}) {
  final r = (resumoPeriodo ?? '').toLowerCase();
  final chovendo = (chuvaUltimaHora ?? 0) >= 0.2 ||
      (observado &&
          (r.contains('chuv') || r.contains('garoa') || r.contains('pancada') ||
              r.contains('trovo')));
  if (chovendo) {
    return r.contains('trovo') || r.contains('tempest') ? EstadoCeu.trovoada : EstadoCeu.chuva;
  }
  if (r.contains('encoberto') || r.contains('muitas nuvens') ||
      (r.contains('nublado') && !r.contains('parcial'))) {
    return EstadoCeu.nublado;
  }
  if (r.contains('claro') || (r.contains('sol') && !r.contains('nuve'))) return EstadoCeu.limpo;
  return EstadoCeu.parcial;
}

String nomeCeu(EstadoCeu e, bool noite) => switch (e) {
      EstadoCeu.limpo => noite ? 'Céu limpo' : 'Ensolarado',
      EstadoCeu.parcial => 'Parcialmente nublado',
      EstadoCeu.nublado => 'Nublado',
      EstadoCeu.chuva => 'Chovendo',
      EstadoCeu.trovoada => 'Chuva com trovoada',
    };

/// Cenário da paisagem, conforme o tipo de dia.
enum Paisagem {
  /// Morros com mar ou campo (dias comuns).
  morros,

  /// Dia bom: campo aberto, caminho de terra e torre de pedra.
  campo,

  /// Calor forte: vulcão e pedras com lava.
  vulcao,

  /// Chuva forte: cidade de pedra com cachoeiras.
  cachoeiras,

  /// Nevando agora: aldeia nas montanhas nevadas.
  neve,
}

/// true quando o texto do tempo diz que está nevando ("Neve fraca", "Chuva e neve").
/// "Possibilidade de neve" e geada não contam: só neve caindo de fato. Frio sozinho também
/// não conta (a neve aparecia em dias frios sem nevar).
bool estaNevando(String? resumo) {
  final r = (resumo ?? '').toLowerCase();
  if (!r.contains('neve')) return false;
  return !RegExp(r'possibilidade|chance|risco|pode |poss[ií]ve').hasMatch(r);
}

/// 23, 24 e 25 de dezembro: o trenó com renas aparece no céu (pedido do usuário).
bool ehNatal(DateTime d) => d.month == 12 && d.day >= 23 && d.day <= 25;

/// Escolhe o cenário. Ordem: nevando, calor, chuva forte, dia bom; senão, morros.
Paisagem escolherPaisagem({
  required EstadoCeu estado,
  required double? temperatura,
  required double? sensacao,
  required double? chuvaUltimaHora,
  required String? resumo,
}) {
  if (estaNevando(resumo)) return Paisagem.neve;
  final calor = sensacao ?? temperatura;
  if (calor != null && calor >= 35 && estado != EstadoCeu.chuva && estado != EstadoCeu.trovoada) {
    return Paisagem.vulcao;
  }
  if ((chuvaUltimaHora ?? 0) >= 5 || estado == EstadoCeu.trovoada) return Paisagem.cachoeiras;
  if (estado == EstadoCeu.limpo || estado == EstadoCeu.parcial) return Paisagem.campo;
  return Paisagem.morros;
}

/// Resumo do período atual (manhã até 12 h, tarde até 18 h, noite depois).
String? resumoDoPeriodo(DiaPrevisao? hoje, DateTime agora) {
  if (hoje == null) return null;
  // Condição observada agora (Canadá), quando houver.
  for (final p in hoje.periodos) {
    if (p.nome == 'Agora') return p.resumo;
  }
  final nome = agora.hour < 12 ? 'Manhã' : (agora.hour < 18 ? 'Tarde' : 'Noite');
  for (final p in hoje.periodos) {
    if (p.nome == nome) return p.resumo;
  }
  return hoje.resumo;
}

/// Topo da tela inicial: céu em pixel art (estilo 16 bits), animado, conforme o tempo e a
/// hora, com a temperatura por cima.
class TopoCeu extends StatefulWidget {
  const TopoCeu({
    super.key,
    required this.estado,
    required this.noite,
    required this.temperatura,
    this.alturaSol,
    this.litoral = false,
    this.paisagem = Paisagem.morros,
    this.sensacao,
    this.maxima,
    this.minima,
    this.idadeLua,
    this.estimativa = false,
    this.natal,
  });

  final EstadoCeu estado;
  final bool noite;

  /// Trenó do Papai Noel no céu. Nulo = automático (23, 24 e 25 de dezembro).
  final bool? natal;

  /// Altura do sol no céu em graus (nulo sem coordenadas da cidade).
  final double? alturaSol;

  /// Cidade no litoral: mostra mar na frente dos morros; senão, campo.
  final bool litoral;
  final Paisagem paisagem;
  final double? temperatura;
  final double? sensacao;
  final int? maxima;
  final int? minima;
  final double? idadeLua;
  final bool estimativa;

  @override
  State<TopoCeu> createState() => _TopoCeuState();
}

class _TopoCeuState extends State<TopoCeu> with SingleTickerProviderStateMixin {
  /// Quadro da animação (12 por segundo, como nos jogos antigos).
  final _quadro = ValueNotifier<int>(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((passado) {
      final q = passado.inMilliseconds ~/ 83;
      if (q != _quadro.value) _quadro.value = q;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final semAnimacao = MediaQuery.of(context).disableAnimations;
    if (semAnimacao && _ticker.isActive) _ticker.stop();
    if (!semAnimacao && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _quadro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    const branco = Colors.white;
    // Sombra leve e difusa (o contorno grosso ficou pesado demais, pedido do usuário).
    // A legibilidade vem do escurecimento suave atrás do texto (ver o Stack abaixo).
    const sombra = [
      Shadow(offset: Offset(0, 1), blurRadius: 6, color: Color(0x66000000)),
    ];
    const brancoSuave = Color(0xE6FFFFFF);
    final tema = Theme.of(context).textTheme;
    final temp = w.temperatura == null
        ? '–'
        : '${w.temperatura!.toStringAsFixed(1).replaceAll('.', ',')}°';
    final maxMin =
        w.maxima != null && w.minima != null ? 'Máx. ${w.maxima}° · Mín. ${w.minima}°' : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 150,
          child: Stack(children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: PintorCeuPixel(
                    estado: w.estado,
                    noite: w.noite,
                    alturaSol: w.alturaSol,
                    litoral: w.litoral,
                    paisagem: w.paisagem,
                    idadeLua: w.idadeLua,
                    quadro: _quadro,
                    natal: w.natal ?? ehNatal(DateTime.now()),
                  ),
                ),
              ),
            ),
            // Escurecimento suave da esquerda para a direita, atrás do texto.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0x59000000), Color(0x00000000)],
                    stops: [0.0, 0.75],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              top: 14,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (w.estimativa)
                  Text('Estimativa (sem estação oficial perto)',
                      style: tema.labelMedium?.copyWith(color: brancoSuave, shadows: sombra)),
                Text(temp,
                    style: tema.displayLarge?.copyWith(
                        color: branco,
                        fontWeight: FontWeight.w300,
                        letterSpacing: -1,
                        shadows: sombra,
                        height: 1.05)),
                if (w.sensacao != null)
                  Text('Sensação térmica ${w.sensacao!.round()}°',
                      style: tema.bodyLarge?.copyWith(
                          color: brancoSuave, fontWeight: FontWeight.w400, shadows: sombra)),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: nomeCeu(w.estado, w.noite),
                        style: tema.titleMedium?.copyWith(
                            color: branco, fontWeight: FontWeight.w500, shadows: sombra)),
                    if (maxMin != null)
                      TextSpan(
                          text: '  ·  $maxMin',
                          style: tema.bodyMedium?.copyWith(
                              color: brancoSuave, fontWeight: FontWeight.w400, shadows: sombra)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Paleta de uma cena.
class _Paleta {
  const _Paleta({
    required this.ceu,
    required this.nuvem,
    required this.morroFundo,
    required this.morroFrente,
    required this.chao,
    required this.agua,
  });

  /// 4 cores do céu, de cima para baixo.
  final List<Color> ceu;

  /// Nuvem: brilho, corpo, sombra.
  final List<Color> nuvem;

  /// Morro: corpo e borda de cima.
  final List<Color> morroFundo;
  final List<Color> morroFrente;

  /// Campo: duas cores misturadas.
  final List<Color> chao;

  /// Mar: corpo, reflexo.
  final List<Color> agua;
}


_Paleta _paleta(EstadoCeu e, bool noite, bool crepusculo) {
  final cinza = e == EstadoCeu.nublado || e == EstadoCeu.chuva || e == EstadoCeu.trovoada;
  final List<Color> nuvem = switch ((e, noite, crepusculo)) {
    (EstadoCeu.trovoada, _, _) => const [Color(0xFF5A6170), Color(0xFF454B57), Color(0xFF32373F)],
    (EstadoCeu.chuva, true, _) => const [Color(0xFF4A5366), Color(0xFF39414F), Color(0xFF2A303B)],
    (EstadoCeu.chuva, false, _) => const [Color(0xFF8A95A3), Color(0xFF6E7987), Color(0xFF525C69)],
    (_, true, _) => const [Color(0xFF5A6684), Color(0xFF424D69), Color(0xFF2E374D)],
    (EstadoCeu.nublado, false, _) => const [Color(0xFFE9EDF1), Color(0xFFC9D0D8), Color(0xFF9AA5B2)],
    (_, false, true) => const [Color(0xFFFFE2C2), Color(0xFFF0B49A), Color(0xFFB27786)],
    _ => const [Color(0xFFFFFFFF), Color(0xFFE6EDF6), Color(0xFFB5C4D8)],
  };
  if (noite) {
    return _Paleta(
      ceu: switch (e) {
        EstadoCeu.limpo => const [Color(0xFF060B20), Color(0xFF0D1A40), Color(0xFF182C5E), Color(0xFF27427C)],
        EstadoCeu.parcial => const [Color(0xFF0A122C), Color(0xFF142147), Color(0xFF21345D), Color(0xFF324772)],
        EstadoCeu.nublado => const [Color(0xFF151A25), Color(0xFF202836), Color(0xFF2C3545), Color(0xFF3A4455)],
        EstadoCeu.chuva => const [Color(0xFF0F131B), Color(0xFF181E29), Color(0xFF232B37), Color(0xFF303946)],
        EstadoCeu.trovoada => const [Color(0xFF0A0C11), Color(0xFF13161E), Color(0xFF1C202A), Color(0xFF282D38)],
      },
      nuvem: nuvem,
      morroFundo: const [Color(0xFF1A2836), Color(0xFF243545)],
      morroFrente: const [Color(0xFF111C26), Color(0xFF1A2A36)],
      chao: const [Color(0xFF0F1F17), Color(0xFF15291E)],
      agua: const [Color(0xFF0C1828), Color(0xFF3A5478)],
    );
  }
  if (crepusculo && !cinza) {
    return _Paleta(
      ceu: const [Color(0xFF2B3D78), Color(0xFF6D5A9C), Color(0xFFD9775E), Color(0xFFF5C27A)],
      nuvem: nuvem,
      morroFundo: const [Color(0xFF6A4D6C), Color(0xFF84617F)],
      morroFrente: const [Color(0xFF46334E), Color(0xFF5C4462)],
      chao: const [Color(0xFF3B4A3A), Color(0xFF465640)],
      agua: const [Color(0xFF5A4778), Color(0xFFF2B27C)],
    );
  }
  if (cinza) {
    return _Paleta(
      ceu: switch (e) {
        EstadoCeu.nublado => const [Color(0xFF6B7A8C), Color(0xFF8390A1), Color(0xFFA0ABB8), Color(0xFFC0C8D1)],
        EstadoCeu.chuva => const [Color(0xFF444E5C), Color(0xFF586373), Color(0xFF6D7989), Color(0xFF86919F)],
        _ => const [Color(0xFF242932), Color(0xFF323844), Color(0xFF434A57), Color(0xFF575F6C)],
      },
      nuvem: nuvem,
      morroFundo: const [Color(0xFF5B7566), Color(0xFF6C8676)],
      morroFrente: const [Color(0xFF46604F), Color(0xFF587260)],
      chao: const [Color(0xFF4C6B45), Color(0xFF587A4F)],
      agua: const [Color(0xFF4B5E6D), Color(0xFF8FA2B2)],
    );
  }
  return _Paleta(
    ceu: e == EstadoCeu.limpo
        ? const [Color(0xFF2A6BD0), Color(0xFF4A8FE4), Color(0xFF86BFF1), Color(0xFFC8E6F8)]
        : const [Color(0xFF3874C7), Color(0xFF5996DE), Color(0xFF91C4EC), Color(0xFFCEE5F3)],
    nuvem: nuvem,
    morroFundo: const [Color(0xFF5E9C78), Color(0xFF79B48D)],
    morroFrente: const [Color(0xFF3C7D4E), Color(0xFF52975F)],
    chao: const [Color(0xFF4C9A3A), Color(0xFF5DAD45)],
    agua: const [Color(0xFF2D6CB0), Color(0xFFB8DDF7)],
  );
}

typedef _Px = void Function(int x, int y, Color c, [int largura, int altura]);

/// Matriz de Bayer 4×4, para o degradê com pontilhado dos jogos de 16 bits.
const _bayer = [
  [0, 8, 2, 10],
  [12, 4, 14, 6],
  [3, 11, 1, 9],
  [15, 7, 13, 5],
];

/// Número pseudoaleatório fixo para a posição [i] (sempre o mesmo desenho).
double _sorteio(int i, int semente) {
  var x = (i * 374761393 + semente * 668265263) & 0x7fffffff;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff;
  return (x & 0xffff) / 0xffff;
}

/// Céu em pixel art: cada "pixel" do desenho vale [tamanhoPixel] pontos da tela.
/// Desenho próprio do app, feito por código (sem imagens de terceiros).
class PintorCeuPixel extends CustomPainter {
  PintorCeuPixel({
    required this.estado,
    required this.noite,
    required this.alturaSol,
    required this.litoral,
    required this.idadeLua,
    required this.quadro,
    this.paisagem = Paisagem.morros,
    this.natal = false,
  }) : super(repaint: quadro);

  /// Mostra o trenó com renas atravessando o céu.
  final bool natal;

  static const tamanhoPixel = 3.0;

  final EstadoCeu estado;
  final bool noite;
  final double? alturaSol;
  final bool litoral;
  final double? idadeLua;
  final ValueListenable<int> quadro;
  final Paisagem paisagem;

  bool get _crepusculo =>
      alturaSol != null && alturaSol! > -5 && alturaSol! < 7;

  static final Map<String, ui.Picture> _cacheFixo = {};

  @override
  void paint(Canvas canvas, Size size) {
    final s = tamanhoPixel;
    final cols = (size.width / s).ceil();
    final linhas = (size.height / s).ceil();
    final pal = _paleta(estado, noite, _crepusculo);
    final ceuCores = switch (paisagem) {
      Paisagem.vulcao => noite
          ? const [Color(0xFF1A0A0A), Color(0xFF3A1414), Color(0xFF5E2318), Color(0xFF8A3A1E)]
          : const [Color(0xFF8C5A3C), Color(0xFFC07A4A), Color(0xFFE6A060), Color(0xFFF5C98A)],
      Paisagem.neve => noite
          ? const [Color(0xFF141C2E), Color(0xFF22304A), Color(0xFF34455F), Color(0xFF4A5C78)]
          : const [Color(0xFF8FA8C4), Color(0xFFAFC2D6), Color(0xFFCAD7E4), Color(0xFFE3EAF1)],
      _ => pal.ceu,
    };
    final q = quadro.value;
    // Onde termina o céu e começam os morros e o chão.
    final linhaChao = (linhas * 0.80).round();

    final p = Paint()..isAntiAlias = false;
    void px(int x, int y, Color c, [int largura = 1, int altura = 1]) {
      p.color = c;
      canvas.drawRect(Rect.fromLTWH(x * s, y * s, largura * s, altura * s), p);
    }

    // 1) Céu com degradê pontilhado (fixo, guardado em cache).
    final chave = '${estado.name}|${paisagem.name}|$noite|$_crepusculo|$cols|$linhas';
    var fixo = _cacheFixo[chave];
    if (fixo == null) {
      if (_cacheFixo.length > 8) _cacheFixo.clear();
      final gravador = ui.PictureRecorder();
      final c2 = Canvas(gravador);
      final p2 = Paint()..isAntiAlias = false;
      for (var y = 0; y < linhaChao; y++) {
        final t = y / (linhaChao - 1) * 3;
        final i = t.floor().clamp(0, 2);
        final f = t - i;
        // Linha inteira de uma cor só quando não há pontilhado.
        final limiar = (f * 16).floor();
        for (var x = 0; x < cols; x++) {
          final usaProxima = _bayer[y % 4][x % 4] < limiar;
          p2.color = ceuCores[usaProxima ? i + 1 : i];
          c2.drawRect(Rect.fromLTWH(x * s, y * s, s, s), p2);
        }
      }
      fixo = gravador.endRecording();
      _cacheFixo[chave] = fixo;
    }
    canvas.drawPicture(fixo);

    // 2) Estrelas piscando.
    if (noite && estado != EstadoCeu.chuva && estado != EstadoCeu.trovoada &&
        paisagem != Paisagem.neve) {
      final n = (cols * (estado == EstadoCeu.nublado ? 0.08 : 0.35)).round();
      for (var i = 0; i < n; i++) {
        final x = (_sorteio(i, 1) * cols).floor();
        final y = (_sorteio(i, 2) * linhaChao * 0.7).floor();
        final fase = (q + i * 7) % 48;
        if (fase < 2) continue; // apagada por um instante
        final forte = fase > 44 && i % 3 == 0;
        px(x, y, forte ? const Color(0xFFFFFFFF) : const Color(0xFFBFD0FF));
        if (forte) {
          const brilho = Color(0x99FFFFFF);
          px(x - 1, y, brilho);
          px(x + 1, y, brilho);
          px(x, y - 1, brilho);
          px(x, y + 1, brilho);
        }
      }
    }

    // 3) Sol (altura no céu conforme a hora) ou lua (com a fase do dia).
    final mostraAstro = estado == EstadoCeu.limpo || estado == EstadoCeu.parcial;
    final ax = cols - 16;
    if (mostraAstro && !noite) {
      final alt = (alturaSol ?? 45).clamp(0.0, 50.0);
      final ay = (linhaChao - 8 - (linhaChao - 20) * (alt / 50)).round();
      const raio = 6;
      final brilhoRaio = (q ~/ 6).isEven;
      final corRaio = _crepusculo ? const Color(0xFFFFB46B) : const Color(0xFFFFF1A8);
      // Raios: oito direções, comprimento alternando.
      final comp = brilhoRaio ? 3 : 2;
      for (var k = 1; k <= comp; k++) {
        final d = raio + 1 + k;
        px(ax + d, ay, corRaio);
        px(ax - d, ay, corRaio);
        px(ax, ay + d, corRaio);
        px(ax, ay - d, corRaio);
        final dd = ((raio + k) * 0.75).round();
        px(ax + dd, ay + dd, corRaio);
        px(ax - dd, ay + dd, corRaio);
        px(ax + dd, ay - dd, corRaio);
        px(ax - dd, ay - dd, corRaio);
      }
      for (var y = -raio; y <= raio; y++) {
        for (var x = -raio; x <= raio; x++) {
          final r2 = x * x + y * y;
          if (r2 > raio * raio + 2) continue;
          final cor = _crepusculo
              ? (r2 > (raio - 2) * (raio - 2) ? const Color(0xFFF28A3C) : const Color(0xFFFFC266))
              : (r2 > (raio - 2) * (raio - 2)
                  ? const Color(0xFFFFC93C)
                  : (x < 0 && y < 0 ? const Color(0xFFFFF7C2) : const Color(0xFFFFE066)));
          px(ax + x, ay + y, cor);
        }
      }
    } else if (mostraAstro && noite && idadeLua != null) {
      const ay = 14;
      const raio = 6;
      final k = math.cos(2 * math.pi * idadeLua!);
      final crescente = idadeLua! < 0.5;
      for (var y = -raio; y <= raio; y++) {
        for (var x = -raio; x <= raio; x++) {
          if (x * x + y * y > raio * raio + 2) continue;
          final ny = y / (raio + 0.5);
          final meia = math.sqrt(math.max(0, 1 - ny * ny));
          // Hemisfério sul: crescente iluminada à esquerda.
          final nx = -(x + 0.5) / (raio + 0.5);
          final xt = meia * k;
          final iluminado = crescente ? nx > xt : nx < -xt;
          final cor = iluminado
              ? ((x + y) < -3 ? const Color(0xFFFFF6D0) : const Color(0xFFF2DE8A))
              : const Color(0xFF2E3A58);
          px(ax + x, ay + y, cor);
        }
      }
    }

    // 4) Nuvens andando devagar para a direita.
    final nuvens = paisagem == Paisagem.vulcao ? 0 : switch (estado) {
      EstadoCeu.limpo => 0,
      EstadoCeu.parcial => 3,
      EstadoCeu.nublado => 6,
      EstadoCeu.chuva || EstadoCeu.trovoada => 7,
    };
    final pesada = estado == EstadoCeu.chuva || estado == EstadoCeu.trovoada;
    final corNuvem = paisagem == Paisagem.neve && !noite
        ? const [Color(0xFFFFFFFF), Color(0xFFE8EEF4), Color(0xFFC2CEDA)]
        : pal.nuvem;
    for (var i = 0; i < nuvens; i++) {
      final larg = 14 + (_sorteio(i, 5) * (pesada ? 18 : 12)).floor();
      final alto = (larg * 0.42).round();
      final y0 = pesada
          ? (_sorteio(i, 6) * linhaChao * 0.30).floor() - 2
          : 6 + (_sorteio(i, 6) * linhaChao * 0.45).floor();
      // Velocidade: 1 pixel a cada 8 a 20 quadros.
      final passo = 8 + (_sorteio(i, 7) * 12).floor();
      final percurso = cols + larg * 2;
      final x0 = ((_sorteio(i, 8) * percurso).floor() + q ~/ passo) % percurso - larg;
      _nuvem(px, x0, y0, larg, alto, corNuvem);
    }

    // 4b) Natal: trenó com renas atravessando o céu, pequeno, no alto.
    if (natal) {
      const largura = 23;
      final passo = 2; // 1 pixel a cada 2 quadros (~6 pixels por segundo)
      final percurso = cols + largura + 160; // pausa entre uma passagem e outra
      final x = (q ~/ passo) % percurso - largura;
      if (x < cols) _treno(px, x, 1, q);
    }

    // 5) Paisagem: morros com mar ou campo, ou um cenário do tipo de dia.
    switch (paisagem) {
      case Paisagem.morros:
        _morros(px, cols, linhas, linhaChao, q, pal);
      case Paisagem.campo:
        _campo(px, cols, linhas, linhaChao, q, pal);
      case Paisagem.vulcao:
        _vulcao(px, cols, linhas, linhaChao, q);
      case Paisagem.cachoeiras:
        _cachoeiras(px, cols, linhas, linhaChao, q);
      case Paisagem.neve:
        _neve(px, cols, linhas, linhaChao, q);
    }

    // 7) Chuva caindo na diagonal (no frio, a neve já cai no lugar dela).
    if (pesada && paisagem != Paisagem.neve) {
      final gota = noite ? const Color(0xAA8EA3C4) : const Color(0xBBD5E6F7);
      final n = (cols * 0.7).round();
      for (var i = 0; i < n; i++) {
        final vel = 3 + (i % 3);
        final y = ((_sorteio(i, 14) * linhas).floor() + q * vel) % (linhas + 4) - 4;
        final x = ((_sorteio(i, 15) * cols).floor() - (q * vel) ~/ 3) % cols;
        px(x, y, gota);
        px(x, y + 1, gota);
        px(x - 1, y + 2, gota);
      }
    }

    // 8) Relâmpago de vez em quando.
    if (estado == EstadoCeu.trovoada) {
      final ciclo = q % 70;
      if (ciclo == 0 || ciclo == 1 || ciclo == 4) {
        canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x40FFFFFF));
        final bx = (cols * 0.6).round() + (q ~/ 70 % 3) * 7;
        const raio = Color(0xFFFFF0A0);
        var x = bx;
        for (var y = 8; y < linhaChao - 10; y++) {
          px(x, y, raio);
          if (y % 4 == 0) x += (y ~/ 4).isEven ? -2 : 1;
          px(x + 1, y, raio);
        }
      }
    }

    // 9) Sombra atrás do texto (canto de cima à esquerda), em pixels com pontilhado.
    // (O degradê radial do Flutter deixava uma linha fina visível em alguns celulares.)
    final chaveSombra = 'sombra|$cols|$linhas';
    var sombra = _cacheFixo[chaveSombra];
    if (sombra == null) {
      final gravador = ui.PictureRecorder();
      final c2 = Canvas(gravador);
      final p2 = Paint()..isAntiAlias = false;
      final raio = linhas * 1.35;
      for (var y = 0; y < linhas; y++) {
        for (var x = 0; x < cols; x++) {
          final d = math.sqrt(x * x + y * y) / raio;
          if (d >= 1) continue;
          // Intensidade de 0 a 0,65, em 12 degraus, com pontilhado entre degraus.
          final v = math.pow(1 - d, 1.6) * 12;
          final degrau = v.floor() + (_bayer[y % 4][x % 4] < ((v - v.floor()) * 16) ? 1 : 0);
          if (degrau <= 0) continue;
          p2.color = Color.fromARGB((degrau / 12 * 166).round(), 0, 0, 0);
          c2.drawRect(Rect.fromLTWH(x * s, y * s, s, s), p2);
        }
      }
      sombra = gravador.endRecording();
      _cacheFixo[chaveSombra] = sombra;
    }
    canvas.drawPicture(sombra);
  }

  // ---------- Paisagens ----------

  /// Padrão: morros com árvores e, na frente, mar (litoral) ou campo.
  void _morros(_Px px, int cols, int linhas, int linhaChao, int q, _Paleta pal) {
    for (var x = 0; x < cols; x++) {
      final hf = (linhaChao - 16 + 5 * math.sin(x * 0.045 + 1.3) + 3 * math.sin(x * 0.13 + 0.4))
          .round();
      px(x, hf, pal.morroFundo[1]);
      px(x, hf + 1, pal.morroFundo[0], 1, linhaChao - hf);
      final hn = (linhaChao - 7 + 3 * math.sin(x * 0.07 + 4.1) + 2 * math.sin(x * 0.19 + 2.2))
          .round();
      px(x, hn, pal.morroFrente[1]);
      px(x, hn + 1, pal.morroFrente[0], 1, linhaChao - hn + 1);
    }
    final arvores = (cols / 9).floor();
    for (var i = 0; i < arvores; i++) {
      final x = (i * 9 + _sorteio(i, 9) * 6).floor();
      final base = (linhaChao - 7 + 3 * math.sin(x * 0.07 + 4.1) + 2 * math.sin(x * 0.19 + 2.2))
          .round();
      _arvore(px, x, base, 3 + (_sorteio(i, 10) * 3).floor(), pal.morroFrente);
    }
    final altoChao = linhas - linhaChao;
    if (litoral) {
      px(0, linhaChao, pal.agua[0], cols, altoChao);
      final n = (cols * altoChao / 40).round();
      for (var i = 0; i < n; i++) {
        final y = linhaChao + 1 + (_sorteio(i, 11) * (altoChao - 1)).floor();
        final larg = 2 + (_sorteio(i, 12) * 4).floor();
        final x = ((_sorteio(i, 13) * cols).floor() + q ~/ (10 + i % 7)) % (cols + 8) - 4;
        if ((q + i * 5) % 36 < 4) continue;
        px(x, y, pal.agua[1].withValues(alpha: 0.55), larg);
      }
      px(0, linhaChao, pal.agua[1].withValues(alpha: 0.35), cols);
    } else {
      _chaoPontilhado(px, cols, linhaChao, linhas, pal.chao);
    }
  }

  void _chaoPontilhado(_Px px, int cols, int de, int ate, List<Color> cores) {
    for (var y = de; y < ate; y++) {
      for (var x = 0; x < cols; x++) {
        px(x, y, cores[_bayer[y % 4][x % 4] < 6 ? 0 : 1]);
      }
    }
  }

  void _arvore(_Px px, int x, int base, int alto, List<Color> morro) {
    final copa = Color.lerp(morro[1], const Color(0xFF000000), 0.22)!;
    final clara = Color.lerp(morro[1], const Color(0xFFFFFFFF), 0.12)!;
    final escura = Color.lerp(morro[0], const Color(0xFF000000), 0.35)!;
    px(x, base - 1, escura);
    for (var y = 0; y < alto; y++) {
      final meia = y == 0 || y == alto - 1 ? 0 : 1;
      px(x - meia, base - 2 - y, copa, meia * 2 + 1);
    }
    px(x - (alto > 2 ? 1 : 0), base - 1 - alto, clara);
    px(x + 1, base - 2, escura);
  }

  /// Dia bom: campo aberto, caminho de terra, flores e uma torre de pedra ao longe.
  void _campo(_Px px, int cols, int linhas, int linhaChao, int q, _Paleta pal) {
    int fundo(int x) =>
        (linhaChao - 14 + 4 * math.sin(x * 0.05 + 0.7) + 2 * math.sin(x * 0.15 + 1.9)).round();
    for (var x = 0; x < cols; x++) {
      final hf = fundo(x);
      px(x, hf, pal.morroFundo[1]);
      px(x, hf + 1, pal.morroFundo[0], 1, linhaChao - hf);
    }
    // Torre de pedra com bandeira.
    final tx = (cols * 0.70).round();
    final base = fundo(tx) + 1;
    const alta = 15;
    final pedra = noite ? const Color(0xFF3B4150) : const Color(0xFF9A958A);
    final sombra = noite ? const Color(0xFF2B303C) : const Color(0xFF77736A);
    px(tx - 2, base - alta, pedra, 5, alta);
    px(tx + 2, base - alta, sombra, 1, alta);
    px(tx - 3, base - alta - 1, pedra, 7, 1);
    for (final d in [-3, 0, 3]) {
      px(tx + d, base - alta - 3, pedra, 1, 2);
    }
    final luz = noite
        ? ((q ~/ 30) % 5 == 0 ? const Color(0xFFFFB84D) : const Color(0xFFFFD27A))
        : const Color(0xFF2A2620);
    px(tx, base - alta + 4, luz, 1, 2);
    px(tx, base - alta - 8, sombra, 1, 5);
    const bandeira = Color(0xFFD9483B);
    final onda = (q ~/ 4).isEven;
    px(tx + 1, base - alta - 8, bandeira, 3, 1);
    px(tx + 1, base - alta - 7, bandeira, onda ? 2 : 3, 1);

    // Planície até embaixo.
    for (var x = 0; x < cols; x++) {
      final hn = (linhaChao - 5 + 2 * math.sin(x * 0.06 + 3.0)).round();
      px(x, hn, Color.lerp(pal.chao[1], const Color(0xFFFFFFFF), 0.12)!);
      for (var y = hn + 1; y < linhas; y++) {
        px(x, y, pal.chao[_bayer[y % 4][x % 4] < 6 ? 0 : 1]);
      }
    }
    // Caminho de terra que se alarga até a frente.
    final terra = noite ? const Color(0xFF4D4235) : const Color(0xFFC9A66B);
    final terraEsc = noite ? const Color(0xFF3A3128) : const Color(0xFFA8864E);
    final inicio = linhaChao - 4;
    for (var y = inicio; y < linhas; y++) {
      final d = y - inicio;
      final cx = cols * 0.42 + 4 * math.sin(d * 0.22);
      final meia = 0.6 + d * 0.38;
      final x0 = (cx - meia).round();
      final x1 = (cx + meia).round();
      px(x0, y, terraEsc);
      if (x1 - x0 > 1) px(x0 + 1, y, terra, x1 - x0 - 1);
      px(x1, y, terraEsc);
    }
    // Flores.
    const coresFlor = [Color(0xFFFFE066), Color(0xFFFFFFFF), Color(0xFFE85A5A), Color(0xFFB98CFF)];
    final nFlores = (cols * 0.3).round();
    for (var i = 0; i < nFlores; i++) {
      final x = (_sorteio(i, 31) * cols).floor();
      final y = linhaChao - 2 + (_sorteio(i, 32) * (linhas - linhaChao + 1)).floor();
      if ((x - cols * 0.42).abs() < 3 + (y - inicio) * 0.4) continue;
      final cor = coresFlor[i % coresFlor.length];
      px(x, y, noite ? cor.withValues(alpha: 0.35) : cor);
    }
    // Árvores grandes no campo.
    for (final f in [0.10, 0.80, 0.93]) {
      final x = (cols * f).round();
      final b = (linhaChao - 5 + 2 * math.sin(x * 0.06 + 3.0)).round();
      _arvore(px, x, b, 6, pal.morroFrente);
      _arvore(px, x + 1, b, 5, pal.morroFrente);
    }
    // Vaga-lumes à noite.
    if (noite) {
      for (var i = 0; i < 10; i++) {
        if ((q + i * 9) % 30 > 14) continue;
        final x = ((_sorteio(i, 33) * cols) + math.sin((q + i * 7) * 0.1) * 3).round();
        final y = linhaChao - 6 + (_sorteio(i, 34) * 10).floor();
        px(x, y, const Color(0xFFD8FF7A));
      }
    }
  }

  /// Calor forte: vulcão com lava, fumaça, chão de pedra rachado e brasas subindo.
  void _vulcao(_Px px, int cols, int linhas, int linhaChao, int q) {
    final rocha = noite ? const Color(0xFF241A18) : const Color(0xFF4A3832);
    final rochaClara = noite ? const Color(0xFF34261F) : const Color(0xFF6A5045);
    final rochaEsc = noite ? const Color(0xFF150F0E) : const Color(0xFF32261F);
    const lava = Color(0xFFFF6A1A);
    const lavaClara = Color(0xFFFFC34A);
    final cx = (cols * 0.62).round();
    final pico = linhaChao - 36;
    const cratera = 4;
    for (var x = 0; x < cols; x++) {
      final dist = (x - cx).abs();
      final topo = dist <= cratera
          ? pico + 1
          : pico + ((dist - cratera) * 0.85).round() + (_sorteio(x, 21) * 2).floor();
      if (topo >= linhaChao) continue;
      px(x, topo, x < cx ? rochaClara : rocha);
      px(x, topo + 1, x < cx ? rocha : rochaEsc, 1, linhaChao - topo);
    }
    // Rios de lava descendo.
    for (final r in [-1, 1]) {
      for (var y = pico + 1; y < linhaChao; y++) {
        final x = cx + r * (2 + ((y - pico) * 0.55).round() + (math.sin(y * 0.6) * 1.2).round());
        px(x, y, (y - q) % 6 == 0 ? lavaClara : lava);
      }
    }
    // Cratera pulsando.
    final pulso = (q ~/ 5) % 3;
    px(cx - cratera + 1, pico, pulso == 0 ? lavaClara : lava, cratera * 2 - 1);
    px(cx - cratera + 2, pico - 1, const Color(0x88FF8A3A), cratera * 2 - 3);
    // Fumaça subindo.
    for (var i = 0; i < 7; i++) {
      final idade = (q ~/ 2 + i * 9) % 60;
      final y = pico - 2 - idade ~/ 2;
      final x = cx + (math.sin((idade + i * 13) * 0.15) * 3).round() + idade ~/ 10;
      final r = 1 + idade ~/ 15;
      final alfa = (170 - idade * 2).clamp(30, 170);
      final cor = noite
          ? Color.fromARGB(alfa, 60, 52, 50)
          : Color.fromARGB(alfa, 110, 100, 96);
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx * dx + dy * dy <= r * r + 1) px(x + dx, y + dy, cor);
        }
      }
    }
    // Pedras recortadas na frente.
    for (var x = 0; x < cols; x++) {
      final h = linhaChao - 8 + (3 * math.sin(x * 0.09 + 0.5)).round() -
          (_sorteio(x ~/ 2, 23) * 3).floor();
      px(x, h, rochaClara);
      px(x, h + 1, rocha, 1, linhas - h);
    }
    // Rachaduras com lava pulsando.
    final nRachas = cols ~/ 8;
    for (var i = 0; i < nRachas; i++) {
      var x = (_sorteio(i, 24) * cols).floor();
      var y = linhaChao + 1 + (_sorteio(i, 25) * (linhas - linhaChao - 2)).floor();
      final cor = math.sin((q + i * 7) * 0.25) > 0 ? lavaClara : lava;
      final comp = 3 + (_sorteio(i, 26) * 4).floor();
      for (var k = 0; k < comp; k++) {
        px(x, y, cor);
        x += 1;
        if (k.isOdd) y += (_sorteio(i + k, 27) > 0.5) ? 1 : -1;
      }
    }
    // Brasas subindo.
    final nBrasas = (cols * 0.25).round();
    for (var i = 0; i < nBrasas; i++) {
      final vida = (q + i * 11) % 50;
      final x = (_sorteio(i, 28) * cols + math.sin((vida + i) * 0.3) * 2).round();
      final y = linhas - 2 - vida;
      px(x, y, vida < 25 ? lavaClara : lava.withValues(alpha: 0.6));
    }
  }

  /// Chuva forte: cidade de pedra azul clara com cachoeiras caindo num lago.
  void _cachoeiras(_Px px, int cols, int linhas, int linhaChao, int q) {
    final pedra = noite ? const Color(0xFF34506E) : const Color(0xFF8DB4D2);
    final pedraEsc = noite ? const Color(0xFF253C55) : const Color(0xFF6890B3);
    final pedraClara = noite ? const Color(0xFF44658A) : const Color(0xFFB4D2E8);
    final agua1 = noite ? const Color(0xFF9CC4E8) : const Color(0xFFE6F4FF);
    final agua2 = noite ? const Color(0xFF5E8EBB) : const Color(0xFF9CCBF0);
    final janela = noite ? const Color(0xFF8FF0E0) : const Color(0xFF3E5F7E);
    final topoFundo = linhaChao - 30;
    // Paredão de pedra ao fundo, com fileiras de blocos.
    px(0, topoFundo, pedraClara, cols);
    px(0, topoFundo + 1, pedra, cols, linhaChao - topoFundo);
    for (var y = topoFundo + 4; y < linhaChao; y += 4) {
      px(0, y, pedraEsc, cols);
      for (var x = ((y ~/ 4) % 2) * 4; x < cols; x += 8) {
        px(x, y - 3, pedraEsc, 1, 3);
      }
    }
    // Cúpulas, torres finas e janelas em arco.
    for (var i = 0; i < 5; i++) {
      final bx = (cols * (0.12 + i * 0.19)).round();
      final r = 3 + (i % 2) * 2;
      for (var dy = 0; dy <= r; dy++) {
        final meia = math.sqrt(r * r - dy * dy).round();
        px(bx - meia, topoFundo - dy, pedraClara, meia * 2 + 1);
      }
      px(bx, topoFundo - r - 3, pedraClara, 1, 3);
      px(bx - 1, topoFundo + 6, janela, 3, 3);
      px(bx, topoFundo + 5, janela);
    }
    // Três quedas d'água no paredão.
    final quedas = [for (final f in [0.30, 0.55, 0.80]) (cols * f).round()];
    for (final fx in quedas) {
      for (var y = topoFundo; y < linhaChao + 2; y++) {
        for (var k = 0; k < 4; k++) {
          px(fx + k, y, ((y - q * 2 + k * 3) % 5) < 2 ? agua1 : agua2);
        }
      }
    }
    // Lago.
    final lago = linhaChao + 2;
    px(0, lago, noite ? const Color(0xFF1C3854) : const Color(0xFF3F7DB0), cols, linhas - lago);
    for (var i = 0; i < cols ~/ 6; i++) {
      final y = lago + 1 + (_sorteio(i, 41) * (linhas - lago - 1)).floor();
      final x = ((_sorteio(i, 42) * cols).floor() + q ~/ 8) % cols;
      px(x, y, agua2.withValues(alpha: 0.6), 3);
    }
    // Espuma no pé das quedas.
    for (final fx in quedas) {
      for (var k = -2; k < 6; k++) {
        if ((q + k * 3 + fx) % 4 != 0) px(fx + k, lago + (k.isEven ? 0 : 1), agua1);
      }
    }
    // Penhascos laterais em primeiro plano, com uma queda cada.
    for (var x = 0; x < cols; x++) {
      final esq = x < cols * 0.18;
      final dir = x > cols * 0.84;
      if (!esq && !dir) continue;
      final dist = esq ? x : cols - x;
      final topo = linhaChao - 22 + (dist * 0.6).round();
      px(x, topo, pedraClara);
      px(x, topo + 1, pedraEsc, 1, linhas - topo);
      for (var y = topo + 4; y < linhas; y += 4) {
        px(x, y, pedra);
      }
    }
    for (final fx in [(cols * 0.18).round() - 4, (cols * 0.84).round() + 1]) {
      final topo = linhaChao - 20;
      for (var y = topo; y < linhas; y++) {
        for (var k = 0; k < 3; k++) {
          px(fx + k, y, ((y - q * 3 + k * 2) % 5) < 2 ? agua1 : agua2);
        }
      }
    }
  }

  /// Papai Noel no trenó puxado por 2 renas, indo para a direita (23 × 6 pixels).
  /// Desenho próprio, feito por código.
  void _treno(_Px px, int x, int y, int q) {
    const cores = {
      'r': Color(0xFFD62B2B), // roupa e gorro
      'W': Color(0xFFFFFFFF), // pompom, barba, borda do gorro
      'S': Color(0xFFF2C29B), // rosto
      'R': Color(0xFF8E1B1B), // trenó
      'Y': Color(0xFFE8B83A), // esqui dourado
      'b': Color(0xFF9C6B3F), // rena
      'a': Color(0xFF5E3F22), // chifre e pernas
      'k': Color(0xFF3A2A1A), // rédea
    };
    void desenha(List<String> linhas, int x0, int y0) {
      for (var j = 0; j < linhas.length; j++) {
        final l = linhas[j];
        for (var i = 0; i < l.length; i++) {
          final c = cores[l[i]];
          if (c != null) px(x0 + i, y0 + j, c);
        }
      }
    }

    // Sobe e desce devagar; as renas galopam (pernas alternam a cada 3 quadros).
    final onda = (q ~/ 8) % 4 == 0 ? 1 : 0;
    final galope = (q ~/ 3).isEven;
    const treno = [
      '...rW...',
      '..WrrW..',
      '..SWW...',
      'R.rrrr..',
      'RRRRRRR.',
      '.YYYYYYY',
    ];
    final rena = [
      '....a.',
      '....bb',
      'bbbbb.',
      'bbbb..',
      galope ? 'a..a..' : '.aa...',
    ];
    desenha(treno, x, y + onda);
    // Rédea do trenó até a primeira rena.
    for (var i = 7; i < 9; i++) {
      px(x + i, y + 3 + onda, cores['k']!);
    }
    desenha(rena, x + 9, y + 1 + onda);
    px(x + 15, y + 3 + onda, cores['k']!);
    desenha(rena, x + 16, y + (1 - onda));
  }

  /// Frio: montanhas nevadas, casas de madeira na encosta, pinheiros e neve caindo.
  void _neve(_Px px, int cols, int linhas, int linhaChao, int q) {
    final rocha = noite ? const Color(0xFF3A4458) : const Color(0xFF7D8A9C);
    final rochaEsc = noite ? const Color(0xFF2A3242) : const Color(0xFF5F6B7C);
    final neve = noite ? const Color(0xFFB9C6D8) : const Color(0xFFF4F8FC);
    final neveSombra = noite ? const Color(0xFF8E9CB2) : const Color(0xFFD3DEEA);
    // Montanhas com pico nevado.
    const picos = [(0.15, 30), (0.42, 38), (0.70, 32), (0.95, 26)];
    for (var x = 0; x < cols; x++) {
      var topo = linhaChao;
      var linhaNeve = linhaChao;
      var direita = false;
      for (final (f, h) in picos) {
        final pxPico = cols * f;
        final t = (linhaChao - h + (x - pxPico).abs() * 1.1).round();
        if (t < topo) {
          topo = t;
          linhaNeve = linhaChao - (h * 0.55).round();
          direita = x > pxPico;
        }
      }
      for (var y = topo; y < linhaChao; y++) {
        final cor = y < linhaNeve
            ? (direita ? neveSombra : neve)
            : (direita ? rochaEsc : rocha);
        px(x, y, cor);
      }
    }
    // Encosta nevada que sobe para a direita.
    int chao(int x) => (linhaChao - 4 - math.max(0, x - cols * 0.45) * 0.35).round();
    for (var x = 0; x < cols; x++) {
      for (var y = chao(x); y < linhas; y++) {
        px(x, y, _bayer[y % 4][x % 4] < 4 ? neveSombra : neve);
      }
    }
    // Pinheiros com neve.
    final pinho = noite ? const Color(0xFF1C2E26) : const Color(0xFF2E4A3A);
    for (var i = 0; i < 6; i++) {
      final x = (cols * (0.04 + i * 0.075)).round();
      final b = chao(x);
      final alto = 7 + (i % 3);
      px(x, b - 1, rochaEsc, 1, 2);
      for (var r = 0; r < alto; r++) {
        final meia = (alto - r) ~/ 2;
        px(x - meia, b - 2 - r, pinho, meia * 2 + 1);
        if (r.isEven) px(x - meia, b - 2 - r, neve, meia + 1);
      }
    }
    // Casas de madeira com telhado nevado, janela acesa e fumaça.
    final madeira = noite ? const Color(0xFF4A3020) : const Color(0xFF8A5A34);
    final madeiraEsc = noite ? const Color(0xFF33200F) : const Color(0xFF6A4224);
    for (var i = 0; i < 4; i++) {
      final hx = (cols * (0.55 + i * 0.11)).round();
      final base = chao(hx + 3) + 1;
      const w = 7, h = 5;
      px(hx, base - h, madeira, w, h);
      for (var y = base - h + 1; y < base; y += 2) {
        px(hx, y, madeiraEsc, w);
      }
      for (var k = 0; k < 4; k++) {
        px(hx - 1 + k, base - h - 1 - k, neve, w + 2 - 2 * k);
      }
      final luz = noite
          ? ((q ~/ 40 + i) % 7 == 0 ? const Color(0xFFFFB84D) : const Color(0xFFFFD27A))
          : const Color(0xFF3A2414);
      px(hx + 1, base - 3, luz, 2, 2);
      px(hx + 5, base - 3, madeiraEsc, 1, 3);
      px(hx + w - 2, base - h - 3, rochaEsc, 1, 2);
      for (var j = 0; j < 5; j++) {
        final idade = (q ~/ 3 + j * 6 + i * 5) % 24;
        px(hx + w - 2 + idade ~/ 6, base - h - 4 - idade,
            Color.fromARGB((150 - idade * 5).clamp(20, 150), 220, 225, 235));
      }
    }
    // Flocos de neve caindo devagar, balançando.
    final n = (cols * 0.5).round();
    for (var i = 0; i < n; i++) {
      final vel = 1 + i % 2;
      final y = ((_sorteio(i, 51) * linhas).floor() + (q * vel) ~/ 3) % linhas;
      final x = (_sorteio(i, 52) * cols + math.sin((q + i * 20) * 0.08) * 2).round();
      px(x, y, const Color(0xFFFFFFFF));
      if (i % 7 == 0) {
        px(x - 1, y, const Color(0x99FFFFFF));
        px(x + 1, y, const Color(0x99FFFFFF));
      }
    }
  }

  /// Nuvem em pixels: três "bolhas" com brilho em cima e sombra embaixo.
  void _nuvem(void Function(int, int, Color, [int, int]) px, int x0, int y0, int larg, int alto,
      List<Color> cor) {
    final r1 = alto * 0.55, r2 = alto * 0.75, r3 = alto * 0.5;
    final c1x = x0 + larg * 0.28, c2x = x0 + larg * 0.52, c3x = x0 + larg * 0.76;
    final baseY = y0 + alto;
    for (var y = y0 - 2; y <= baseY; y++) {
      for (var x = x0 - 1; x <= x0 + larg + 1; x++) {
        bool dentro(double cx, double cy, double r) =>
            (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r;
        final cy = baseY - alto * 0.35;
        final ok = y <= baseY &&
            (dentro(c1x, cy, r1) || dentro(c2x, cy - alto * 0.2, r2) || dentro(c3x, cy, r3) ||
                (y >= cy && y <= baseY && x >= c1x && x <= c3x));
        if (ok) {
          final corPixel = y >= baseY - 1
              ? cor[2]
              : (y <= cy - alto * 0.45 ? cor[0] : cor[1]);
          px(x, y, corPixel);
        }
      }
    }
  }

  @override
  bool shouldRepaint(PintorCeuPixel old) =>
      old.estado != estado ||
      old.noite != noite ||
      old.litoral != litoral ||
      old.alturaSol != alturaSol ||
      old.idadeLua != idadeLua ||
      old.paisagem != paisagem ||
      old.natal != natal;
}
