import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Uma imagem de radar meteorológico.
class QuadroRadar {
  const QuadroRadar(this.bytes, this.hora);
  final Uint8List bytes;
  final DateTime hora;
}

class SituacaoRadar {
  const SituacaoRadar({required this.normal, required this.texto});
  final bool normal;
  final String texto;
}

/// Retângulo coberto pela imagem, na projeção de Mercator (a mesma dos mapas dos sites).
class AreaRadar {
  const AreaRadar({
    required this.oeste,
    required this.sul,
    required this.leste,
    required this.norte,
  });

  final double oeste;
  final double sul;
  final double leste;
  final double norte;

  bool contem(double lat, double lon) =>
      lat >= sul && lat <= norte && lon >= oeste && lon <= leste;

  static double _merc(double lat) {
    final r = lat * math.pi / 180;
    return math.log(math.tan(math.pi / 4 + r / 2));
  }

  /// Posição (0 a 1) de um ponto dentro da imagem.
  (double, double) posicao(double lat, double lon) {
    final x = (lon - oeste) / (leste - oeste);
    final y = (_merc(norte) - _merc(lat)) / (_merc(norte) - _merc(sul));
    return (x, y);
  }

  /// Largura ÷ altura da área no mapa.
  double get proporcao =>
      ((leste - oeste) * math.pi / 180) / (_merc(norte) - _merc(sul));
}

/// Um radar meteorológico oficial.
abstract class FonteRadar {
  String get nome;
  String get orgao;
  AreaRadar get area;

  /// Intervalo entre imagens, em minutos.
  int get intervaloMin;

  /// Verdadeiro quando a imagem já traz a legenda de cores.
  bool get legendaNaImagem;

  /// Texto antes da hora: "Imagem das" (hora da varredura) ou "Imagem publicada às".
  String get rotuloHora;

  /// Cores da legenda (valor em dBZ → cor), quando a imagem não traz a sua.
  List<(String, Color)> get legenda => const [];

  Future<List<QuadroRadar>> quadros();
  Future<SituacaoRadar?> situacao() async => null;

  /// Unidade da legenda ("dBZ" ou "mm/h").
  String get unidadeLegenda => 'dBZ';

  /// Mapa de fundo pronto (imagem), quando o radar fica fora do mapa do IBGE guardado no app.
  Future<Uint8List?> mapaDeFundo() async => null;

  /// De onde vem o mapa de fundo.
  String get creditoMapa => 'IBGE';

  /// Cidades de referência marcadas no mapa (além da cidade escolhida).
  List<(double, double, String)> get referencias =>
      const [(-22.9068, -43.1729, 'Rio de Janeiro'), (-22.8832, -43.1034, 'Niterói')];
}

/// Radar do Canadá: mosaico oficial do Environment and Climate Change Canada (taxa de
/// precipitação, 1 km, uma imagem a cada 6 minutos), pelo serviço aberto GeoMet (WMS).
/// Mapa de fundo: mapa base oficial do governo do Canadá (Natural Resources Canada, CBMT).
class RadarCanada extends FonteRadar {
  RadarCanada(this.latitude, this.longitude, {http.Client? cliente})
      : _cliente = cliente ?? http.Client();

  final double latitude;
  final double longitude;
  final http.Client _cliente;

  static const _wms = 'https://geo.weather.gc.ca/geomet';
  static const _camada = 'RADAR_1KM_RRAI';

  @override
  String get nome => 'do Canadá';
  @override
  String get orgao => 'Environment and Climate Change Canada';
  @override
  int get intervaloMin => 6;
  @override
  bool get legendaNaImagem => false;
  @override
  String get rotuloHora => 'Imagem das';
  @override
  String get unidadeLegenda => 'mm/h';
  @override
  String get creditoMapa => 'Natural Resources Canada';
  @override
  List<(double, double, String)> get referencias => const [];

  /// Cores oficiais da legenda (taxa de chuva em mm/h).
  @override
  List<(String, Color)> get legenda => const [
        ('0,1', Color(0xFF85C5FE)),
        ('1', Color(0xFF40AEFE)),
        ('2', Color(0xFF00DC98)),
        ('4', Color(0xFF00DA1E)),
        ('8', Color(0xFF00A300)),
        ('12', Color(0xFF006C00)),
        ('16', Color(0xFFF3F800)),
        ('24', Color(0xFFFECB00)),
        ('32', Color(0xFFFE9600)),
        ('50', Color(0xFFFE5900)),
        ('64', Color(0xFFFE0020)),
        ('100', Color(0xFFE010A7)),
        ('125', Color(0xFF8520B8)),
        ('200', Color(0xFF500079)),
      ];

  /// Quadrado de uns 400 km em volta da cidade.
  @override
  AreaRadar get area {
    const dLat = 1.8;
    final dLon = dLat / math.cos(latitude * math.pi / 180);
    return AreaRadar(
      oeste: longitude - dLon,
      sul: latitude - dLat,
      leste: longitude + dLon,
      norte: latitude + dLat,
    );
  }

  /// Limites da área em metros (projeção de Mercator da web, EPSG:3857).
  String get _bbox {
    const r = 6378137.0;
    double x(double lon) => lon * math.pi / 180 * r;
    double y(double lat) => math.log(math.tan(math.pi / 4 + lat * math.pi / 360)) * r;
    final a = area;
    return '${x(a.oeste)},${y(a.sul)},${x(a.leste)},${y(a.norte)}';
  }

  Uri _mapa(String base, String camada, {String? tempo, bool transparente = true}) =>
      Uri.parse('$base?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=$camada&STYLES='
          '&CRS=EPSG:3857&BBOX=$_bbox&WIDTH=640&HEIGHT=640&FORMAT=image/png'
          '${transparente ? '&TRANSPARENT=TRUE' : ''}${tempo != null ? '&TIME=$tempo' : ''}');

  @override
  Future<Uint8List?> mapaDeFundo() async {
    try {
      final r = await _cliente
          .get(_mapa('https://maps.geogratis.gc.ca/wms/CBMT', 'CBMT', transparente: false),
              headers: _cabecalhos)
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200 || !(r.headers['content-type'] ?? '').contains('image')) return null;
      return r.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<QuadroRadar>> quadros() async {
    try {
      // Horários disponíveis: "início/fim/PT6M" na descrição da camada.
      final cap = await _cliente
          .get(Uri.parse('$_wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetCapabilities&LAYER=$_camada'),
              headers: _cabecalhos)
          .timeout(const Duration(seconds: 25));
      final m = RegExp(r'<Dimension name="time"[^>]*>([^/<]+)/([^/<]+)/PT(\d+)M')
          .firstMatch(utf8.decode(cap.bodyBytes));
      if (m == null) return [];
      final fim = DateTime.parse(m.group(2)!);
      final passo = Duration(minutes: int.parse(m.group(3)!));
      final horas = [for (var i = 9; i >= 0; i--) fim.subtract(passo * i)];
      final r = await Future.wait([
        for (final t in horas)
          _cliente
              .get(_mapa(_wms, _camada, tempo: t.toIso8601String().replaceAll('.000', '')),
                  headers: _cabecalhos)
              .timeout(const Duration(seconds: 25))
              .then<QuadroRadar?>((resp) => resp.statusCode == 200 &&
                      (resp.headers['content-type'] ?? '').contains('image')
                  ? QuadroRadar(resp.bodyBytes, t.toLocal())
                  : null)
              .catchError((_) => null),
      ]);
      return r.whereType<QuadroRadar>().toList();
    } catch (_) {
      return [];
    }
  }
}

const _cabecalhos = {'User-Agent': 'ClimaBit/1.17 (Android)'};

/// Radar do Sumaré, do Alerta Rio (Prefeitura do Rio).
class RadarSumare extends FonteRadar {
  RadarSumare({http.Client? cliente}) : _cliente = cliente ?? http.Client();

  final http.Client _cliente;
  static const _base = 'https://alertario.rio.rj.gov.br/upload/Mapa';

  @override
  String get nome => 'Sumaré';
  @override
  String get orgao => 'Alerta Rio (Prefeitura do Rio)';
  @override
  int get intervaloMin => 2;
  @override
  bool get legendaNaImagem => true;
  @override
  String get rotuloHora => 'Imagem publicada às';

  /// Os mesmos limites usados pelo mapa do site do Alerta Rio.
  @override
  AreaRadar get area => const AreaRadar(
        oeste: -45.336972,
        sul: -24.431567,
        leste: -41.159092,
        norte: -21.478793,
      );

  /// As 20 imagens publicadas (uma a cada 2 minutos), da mais antiga para a mais recente.
  @override
  Future<List<QuadroRadar>> quadros() async {
    final r = (await Future.wait([for (var i = 1; i <= 20; i++) _quadro(i)]))
        .whereType<QuadroRadar>()
        .toList()
      ..sort((a, b) => a.hora.compareTo(b.hora));
    return r;
  }

  Future<QuadroRadar?> _quadro(int i) async {
    final nome = 'radar${i.toString().padLeft(3, '0')}.png';
    try {
      final r = await _cliente
          .get(Uri.parse('$_base/semfundo/$nome'), headers: _cabecalhos)
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) return null;
      final hora = _lerData(r.headers['last-modified']);
      if (hora == null) return null;
      return QuadroRadar(r.bodyBytes, hora);
    } catch (_) {
      return null;
    }
  }

  /// "Fri, 13 Nov 2026 02:52:02 GMT" (formato HTTP) → hora do aparelho.
  static DateTime? _lerData(String? s) {
    if (s == null) return null;
    try {
      return DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en_US')
          .parseUtc(s.replaceAll(' GMT', ''))
          .toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Aviso de manutenção publicado pelo Alerta Rio.
  @override
  Future<SituacaoRadar?> situacao() async {
    try {
      final r = await _cliente
          .get(Uri.parse('$_base/str.json'), headers: _cabecalhos)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final texto = [j['estado'], j['descricao']]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' – ');
      return SituacaoRadar(normal: j['id'] == 1, texto: texto);
    } catch (_) {
      return null;
    }
  }
}

/// Radar de Niterói, da Defesa Civil de Niterói (Prefeitura de Niterói).
/// Dados públicos do site radar.niteroi.rj.gov.br.
class RadarNiteroi extends FonteRadar {
  RadarNiteroi({http.Client? cliente}) : _cliente = cliente ?? http.Client();

  final http.Client _cliente;
  static const _base = 'https://radar.niteroi.rj.gov.br:3337';
  static const _idRadar = 'b35bf5fe-a016-4516-81bb-681088e72ce7';

  List<(String, Color)> _legenda = const [];

  @override
  String get nome => 'Niterói';
  @override
  String get orgao => 'Defesa Civil de Niterói';
  @override
  int get intervaloMin => 5;
  @override
  bool get legendaNaImagem => false;
  @override
  String get rotuloHora => 'Imagem das';
  @override
  List<(String, Color)> get legenda => _legenda;

  /// Limites publicados pelo próprio radar (raio de 100 km).
  @override
  AreaRadar get area => const AreaRadar(
        oeste: -44.063540906953534,
        sul: -23.828487624961028,
        leste: -42.11079267870416,
        norte: -22.029734127406552,
      );

  Future<dynamic> _json(String caminho) async {
    final r = await _cliente
        .get(Uri.parse('$_base$caminho'), headers: _cabecalhos)
        .timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) throw Exception('radar Niterói ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  @override
  Future<List<QuadroRadar>> quadros() async {
    try {
      final tipos = (await _json('/radars/product-types') as List).cast<Map<String, dynamic>>();
      final tipo = tipos.firstWhere((t) => t['is_map'] == true, orElse: () => tipos.first);
      _legenda = [
        for (final c in (tipo['colormaps'] as List? ?? []).cast<Map<String, dynamic>>())
          ('${c['value']}', _cor('${c['color']}')),
      ]..sort((a, b) => (double.tryParse(a.$1) ?? 0).compareTo(double.tryParse(b.$1) ?? 0));

      final agora = DateTime.now().millisecondsSinceEpoch;
      final produtos = (await _json(
              '/radars/$_idRadar/products?type_id=${tipo['id']}&cutoff_datetime=$agora&amount=20')
          as List)
          .cast<Map<String, dynamic>>();
      final pedidos = <Future<QuadroRadar?>>[];
      for (final p in produtos) {
        final imagens = (p['images'] as List? ?? []).cast<Map<String, dynamic>>();
        final ms = int.tryParse('${p['datetime']}');
        if (imagens.isEmpty || ms == null) continue;
        pedidos.add(_imagem('${imagens.first['path']}',
            DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal()));
      }
      final r = (await Future.wait(pedidos)).whereType<QuadroRadar>().toList()
        ..sort((a, b) => a.hora.compareTo(b.hora));
      return r;
    } catch (_) {
      return [];
    }
  }

  Future<QuadroRadar?> _imagem(String caminho, DateTime hora) async {
    try {
      final r = await _cliente
          .get(Uri.parse('$_base$caminho'), headers: _cabecalhos)
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) return null;
      return QuadroRadar(r.bodyBytes, hora);
    } catch (_) {
      return null;
    }
  }

  static Color _cor(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.tryParse('FF$h', radix: 16) ?? 0xFF888888);
  }
}

/// Contornos oficiais do IBGE (municípios do RJ e estados vizinhos), guardados no app.
class ContornosMapa {
  ContornosMapa(this.estados, this.municipios);

  final List<List<(double, double)>> estados;
  final List<List<(double, double)>> municipios;

  static ContornosMapa? _cache;

  static Future<ContornosMapa> carregar() async {
    if (_cache != null) return _cache!;
    final j = jsonDecode(await rootBundle.loadString('assets/mapa_radar.json'))
        as Map<String, dynamic>;
    List<List<(double, double)>> aneis(String chave) => [
          for (final anel in j[chave] as List)
            [
              // No arquivo: [longitude, latitude]. Aqui: (latitude, longitude).
              for (final p in (anel as List).cast<List>())
                ((p[1] as num).toDouble(), (p[0] as num).toDouble()),
            ],
        ];
    return _cache = ContornosMapa(aneis('estados'), aneis('municipios'));
  }
}
