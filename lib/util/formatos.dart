import 'package:material_ui/material_ui.dart';
import 'dart:math' as math;
import 'package:intl/intl.dart';

final _decimal = NumberFormat('0.0', 'pt_BR');
final _hora = DateFormat('HH:mm', 'pt_BR');
final _diaHora = DateFormat("d/MM 'às' HH:mm", 'pt_BR');

String decimal(double? v) => v == null ? '–' : _decimal.format(v);

String inteiro(num? v) => v == null ? '–' : v.round().toString();

/// "14:00" se for hoje; "12/11 às 14:00" se for outro dia.
String quando(DateTime t, {DateTime? agora}) {
  final a = agora ?? DateTime.now();
  final mesmoDia = t.year == a.year && t.month == a.month && t.day == a.day;
  return mesmoDia ? _hora.format(t) : _diaHora.format(t);
}

String hora(DateTime t) => _hora.format(t);

const _direcoes = ['N', 'NE', 'L', 'SE', 'S', 'SO', 'O', 'NO'];

/// Graus (0–360) para ponto cardeal em português (L = leste, O = oeste).
String direcaoVento(int? graus) {
  if (graus == null) return '';
  return _direcoes[((graus % 360) / 45).round() % 8];
}

/// Ícone aproximado a partir do texto da previsão.
/// Ícone do resumo do tempo: nuvem com chuva (desenhada) quando o texto fala em chuva.
Widget simboloTempo(String resumo, {double size = 24, Color? color}) {
  final r = resumo.toLowerCase();
  final trovoada = r.contains('trovo') || r.contains('tempest');
  if (!trovoada && (r.contains('chuv') || r.contains('pancada'))) {
    return NuvemChuva(size: size, color: color);
  }
  return Icon(iconeTempo(resumo), size: size, color: color);
}

IconData iconeTempo(String resumo) {
  final r = resumo.toLowerCase();
  if (r.contains('trovo') || r.contains('tempest')) return Icons.thunderstorm;
  if (r.contains('chuv') || r.contains('pancada')) return Icons.umbrella;
  if (r.contains('nevoeiro') || r.contains('névoa')) return Icons.foggy;
  if (r.contains('encoberto') || r.contains('nublado') || r.contains('muitas nuvens')) {
    if (r.contains('parcial')) return Icons.wb_cloudy;
    return Icons.cloud;
  }
  if (r.contains('poucas nuvens') || r.contains('variação')) return Icons.wb_cloudy;
  if (r.contains('claro') || r.contains('sol')) return Icons.wb_sunny;
  return Icons.cloud_queue;
}

/// Cor oficial do aviso (#RRGGBB) para Color.
Color corAviso(String hex) {
  final h = hex.replaceAll('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return Color(v ?? 0xFFFFFE00);
}

/// Categoria oficial do índice ultravioleta (OMS).
String categoriaUv(double uv) {
  if (uv < 3) return 'baixo';
  if (uv < 6) return 'moderado';
  if (uv < 8) return 'alto';
  if (uv < 11) return 'muito alto';
  return 'extremo';
}

/// "80 %" ou "sem dado" quando a estação não enviou o valor.
String comUnidade(num? v, String unidade, {bool decimais = false}) {
  if (v == null) return 'sem dado';
  return '${decimais ? decimal(v.toDouble()) : inteiro(v)} $unidade';
}

/// Guarda-chuva aberto (reto, desenhado pelo app) quando há chuva medida; fechado
/// (ícone do Material) quando não há.
Widget iconeChuva(double? mm, {double size = 24, Color? color}) => (mm ?? 0) > 0
    ? GuardaChuvaAberto(size: size, color: color)
    : Icon(Icons.umbrella, size: size, color: color);

/// Guarda-chuva aberto na vertical: copa com borda recortada, haste e cabo em gancho.
class GuardaChuvaAberto extends StatelessWidget {
  const GuardaChuvaAberto({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cor = color ?? IconTheme.of(context).color ?? Colors.black;
    return Semantics(
      label: 'Guarda-chuva aberto',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _PintorGuardaChuva(cor)),
      ),
    );
  }
}

class _PintorGuardaChuva extends CustomPainter {
  _PintorGuardaChuva(this.cor);

  final Color cor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final copa = Path()
      ..moveTo(2, 12.5)
      ..arcToPoint(const Offset(22, 12.5), radius: const Radius.circular(10))
      ..arcToPoint(const Offset(15.34, 12.5), radius: const Radius.circular(3.4), clockwise: false)
      ..arcToPoint(const Offset(8.66, 12.5), radius: const Radius.circular(3.4), clockwise: false)
      ..arcToPoint(const Offset(2, 12.5), radius: const Radius.circular(3.4), clockwise: false)
      ..close();
    canvas.drawPath(copa, Paint()..color = cor);
    final traco = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(12, 2.5), const Offset(12, 1.2), traco);
    final haste = Path()
      ..moveTo(12, 11)
      ..lineTo(12, 20)
      ..arcToPoint(const Offset(8.4, 20), radius: const Radius.circular(1.8));
    canvas.drawPath(haste, traco);
  }

  @override
  bool shouldRepaint(_PintorGuardaChuva old) => old.cor != cor;
}

/// Sensação térmica calculada com temperatura (°C), umidade (%) e vento (km/h).
/// Calor (27 °C ou mais e umidade de 40 % ou mais): índice de calor da NOAA (Rothfusz).
/// Frio (10 °C ou menos e vento acima de 4,8 km/h): fórmula de sensação com vento do
/// Serviço Meteorológico do Canadá. Fora dessas faixas, a sensação é a própria temperatura.
double? sensacaoTermica(double? t, double? umidade, double? ventoKmh) {
  if (t == null) return null;
  if (t >= 27 && umidade != null && umidade >= 40) {
    final f = t * 9 / 5 + 32;
    final r = umidade;
    final hi = -42.379 +
        2.04901523 * f +
        10.14333127 * r -
        0.22475541 * f * r -
        0.00683783 * f * f -
        0.05481717 * r * r +
        0.00122874 * f * f * r +
        0.00085282 * f * r * r -
        0.00000199 * f * f * r * r;
    return (hi - 32) * 5 / 9;
  }
  if (t <= 10 && ventoKmh != null && ventoKmh > 4.8) {
    final v = math.pow(ventoKmh, 0.16);
    return 13.12 + 0.6215 * t - 11.37 * v + 0.3965 * t * v;
  }
  return t;
}

/// Nuvem com chuva (três gotas inclinadas), desenhada pelo app: o Material não tem esse ícone.
class NuvemChuva extends StatelessWidget {
  const NuvemChuva({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cor = color ?? IconTheme.of(context).color ?? Colors.black;
    final tamanho = size == 24 ? (IconTheme.of(context).size ?? 24) : size;
    return Semantics(
      label: 'Chuva',
      child: SizedBox.square(
        dimension: tamanho,
        child: CustomPaint(painter: _PintorNuvemChuva(cor)),
      ),
    );
  }
}

class _PintorNuvemChuva extends CustomPainter {
  _PintorNuvemChuva(this.cor);

  final Color cor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final cheio = Paint()..color = cor;
    canvas.drawCircle(const Offset(8, 10), 4, cheio);
    canvas.drawCircle(const Offset(13, 7.5), 5, cheio);
    canvas.drawCircle(const Offset(17.5, 10.5), 3.5, cheio);
    canvas.drawRRect(
        RRect.fromLTRBR(4, 9, 21, 14, const Radius.circular(2.5)), cheio);
    final traco = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (final x in [8.5, 13.0, 17.5]) {
      canvas.drawLine(Offset(x, 16.5), Offset(x - 1.5, 20.5), traco);
    }
  }

  @override
  bool shouldRepaint(_PintorNuvemChuva old) => old.cor != cor;
}


/// Cores das avaliações ("Bom", "Muito úmido"...), legíveis no tema claro e no escuro.
const corBoa = Color(0xFF2E9D46);
const corAtencao = Color(0xFFC98A00);
const corRuim = Color(0xFFE5631A);
const corPerigo = Color(0xFFD83A34);
const corFrio = Color(0xFF3B82D6);

/// Avaliação da umidade do ar (referências da OMS e da Defesa Civil para tempo seco).
(String, Color) avaliarUmidade(double ur) {
  if (ur < 12) return ('Emergência: ar muito seco', corPerigo);
  if (ur < 20) return ('Alerta: ar seco', corPerigo);
  if (ur < 30) return ('Atenção: ar seco', corRuim);
  if (ur <= 60) return ('Confortável', corBoa);
  if (ur <= 80) return ('Úmido', corAtencao);
  return ('Muito úmido', corRuim);
}

/// Avaliação da sensação térmica.
(String, Color) avaliarSensacao(double t) {
  if (t < 10) return ('Frio', corFrio);
  if (t < 18) return ('Fresco', corFrio);
  if (t < 27) return ('Agradável', corBoa);
  if (t < 32) return ('Quente', corAtencao);
  if (t < 41) return ('Muito quente', corRuim);
  return ('Calor perigoso', corPerigo);
}

/// Avaliação do vento (escala de Beaufort simplificada).
(String, Color) avaliarVento(double kmh) {
  if (kmh < 1) return ('Calmo', corBoa);
  if (kmh < 20) return ('Fraco', corBoa);
  if (kmh < 39) return ('Moderado', corAtencao);
  if (kmh < 62) return ('Forte', corRuim);
  return ('Muito forte', corPerigo);
}

/// Avaliação da chuva em 1 hora (classes usadas pelo INMET e pela Defesa Civil).
(String, Color) avaliarChuva(double mm) {
  if (mm <= 0) return ('Sem chuva', corBoa);
  if (mm < 5) return ('Fraca', corAtencao);
  if (mm < 25) return ('Moderada', corRuim);
  if (mm < 50) return ('Forte', corPerigo);
  return ('Muito forte', corPerigo);
}

/// Avaliação da visibilidade horizontal (km).
(String, Color) avaliarVisibilidade(double km) {
  if (km >= 10) return ('Boa', corBoa);
  if (km >= 5) return ('Moderada', corAtencao);
  if (km >= 1) return ('Ruim', corRuim);
  return ('Nevoeiro', corPerigo);
}

/// Avaliação da pressão (hPa): abaixo de 1005 costuma vir com tempo instável.
(String, Color) avaliarPressao(double hpa) {
  if (hpa < 1005) return ('Baixa pressão', corAtencao);
  if (hpa <= 1022) return ('Normal', corBoa);
  return ('Alta pressão', corBoa);
}

/// Avaliação do ponto de orvalho (°C): quanto mais alto, mais abafado.
(String, Color) avaliarOrvalho(double td) {
  if (td < 10) return ('Seco', corBoa);
  if (td < 16) return ('Confortável', corBoa);
  if (td < 19) return ('Úmido', corAtencao);
  if (td < 22) return ('Abafado', corRuim);
  return ('Muito abafado', corRuim);
}

/// Ponto de orvalho calculado pela fórmula de Magnus (temperatura em °C, umidade em %).
double? orvalhoCalculado(double? t, double? ur) {
  if (t == null || ur == null || ur <= 0) return null;
  final g = math.log(ur / 100) + 17.625 * t / (243.04 + t);
  return 243.04 * g / (17.625 - g);
}

/// Avaliação do índice UV (escala da OMS).
(String, Color) avaliarUv(double uv) {
  final c = categoriaUv(uv);
  final cor = uv < 3 ? corBoa : (uv < 6 ? corAtencao : (uv < 8 ? corRuim : corPerigo));
  return ('${c[0].toUpperCase()}${c.substring(1)}', cor);
}


/// Ícone pelo código de tempo da OMS (WMO), usado na previsão por hora do Open-Meteo.
Widget simboloCodigoWmo(int? codigo, bool dia, {double size = 24, Color? color}) {
  final c = codigo ?? 2;
  if (c >= 95) return Icon(Icons.thunderstorm, size: size, color: color);
  if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) {
    return NuvemChuva(size: size, color: color);
  }
  if ((c >= 71 && c <= 77) || c == 85 || c == 86) return Icon(Icons.ac_unit, size: size, color: color);
  if (c == 45 || c == 48) return Icon(Icons.foggy, size: size, color: color);
  if (c == 3) return Icon(Icons.cloud, size: size, color: color);
  if (c == 1 || c == 2) {
    return Icon(dia ? Icons.wb_cloudy_outlined : Icons.nights_stay_outlined, size: size, color: color);
  }
  return Icon(dia ? Icons.wb_sunny : Icons.nightlight_round, size: size, color: color);
}
