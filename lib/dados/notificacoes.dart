import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../util/formatos.dart';
import 'canada.dart';
import 'fontes.dart';
import 'preferencias.dart';
import 'widget_tela.dart';

const _tarefa = 'verificar_alertas';
const _vistos = 'alertas_vistos';
const _chuvaAvisada = 'chuva_avisada';

final _plugin = FlutterLocalNotificationsPlugin();

/// Ponto de entrada da tarefa em segundo plano (roda sem o app aberto).
@pragma('vm:entry-point')
void despachante() {
  Workmanager().executeTask((tarefa, dados) async {
    try {
      await initializeDateFormatting('pt_BR');
      if (tarefa == tarefaWidget) {
        await atualizarWidgetsEmSegundoPlano();
      } else {
        // Alertas e chuva chegando: uma falha numa não impede a outra.
        var ok = true;
        try {
          await verificarAlertas();
        } catch (_) {
          ok = false;
        }
        try {
          await verificarChuva();
        } catch (_) {
          ok = false;
        }
        return ok;
      }
      return true;
    } catch (_) {
      return false; // o Android tenta de novo mais tarde
    }
  });
}

class Notificacoes {
  static Future<void> iniciar() async {
    await _iniciarPlugin();
    await Workmanager().initialize(despachante);
  }

  /// Pede a permissão de notificação (Android 13 ou mais novo). Devolve se foi concedida.
  static Future<bool> pedirPermissao() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  static Future<void> agendar(int intervaloMin) => Workmanager().registerPeriodicTask(
        _tarefa,
        _tarefa,
        frequency: Duration(minutes: intervaloMin),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );

  static Future<void> cancelar() => Workmanager().cancelByUniqueName(_tarefa);

  /// Uma verificação logo agora (ao ligar os avisos ou trocar a cidade dos avisos).
  static Future<void> verificarAgora() => Workmanager().registerOneOffTask(
        '${_tarefa}_agora',
        _tarefa,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

  /// Marca alertas como já vistos (o usuário já está vendo no app).
  static Future<void> marcarVistos(Iterable<Alerta> alertas) async {
    final p = await SharedPreferences.getInstance();
    final vistos = {...?p.getStringList(_vistos), ...alertas.map((a) => a.id)};
    await p.setStringList(_vistos, vistos.toList());
  }
}

Future<void> _iniciarPlugin() => _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notificacao'),
      ),
    );

/// Consulta os alertas do INMET para a cidade dos avisos e notifica os novos.
Future<void> verificarAlertas() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await Preferencias.carregar();
  if (!prefs.avisosLigados) return;
  final cidade = prefs.cidadeDosAvisos;
  // Brasil: avisos do INMET. Canadá: avisos do serviço oficial de lá (ECCC).
  final r = await http.get(
    cidade.noCanada
        ? enderecoCanada(cidade.idEccc!)
        : Uri.parse('https://apiprevmet3.inmet.gov.br/avisos/ativos'),
    headers: {'User-Agent': 'ClimaBit/1.17 (Android)'},
  ).timeout(const Duration(seconds: 30));
  if (r.statusCode != 200) throw Exception('fonte ${r.statusCode}');

  final agora = DateTime.now();
  final corpo = utf8.decode(r.bodyBytes, allowMalformed: true);
  final alertas = (cidade.noCanada ? lerCanada(corpo).alertas : lerAlertasInmet(corpo, cidade.geocode))
      .where((a) => a.fim.isAfter(agora))
      .toList();
  final orgao = cidade.noCanada ? 'Canadá' : 'INMET';

  final sp = await SharedPreferences.getInstance();
  final vistos = sp.getStringList(_vistos)?.toSet() ?? {};
  final novos = alertas.where((a) => !vistos.contains(a.id)).toList();

  if (novos.isNotEmpty) await _iniciarPlugin();
  for (final a in novos) {
    final quandoTexto = a.ativo(agora)
        ? 'em vigor até ${quando(a.fim)}'
        : 'de ${quando(a.inicio)} a ${quando(a.fim)}';
    await _plugin.show(
      id: int.tryParse(a.id) ?? a.id.hashCode,
      title: 'Alerta $orgao: ${a.descricao} – ${a.severidade}',
      body: '${cidade.nome}, $quandoTexto',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'alertas_oficiais',
          'Alertas oficiais',
          channelDescription: 'Alertas meteorológicos oficiais (INMET; no Canadá, ECCC) para a cidade escolhida',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notif_alerta',
        ),
      ),
    );
  }
  // Guarda só os alertas ainda válidos, para a lista não crescer sem fim.
  await sp.setStringList(_vistos, {
    ...alertas.map((a) => a.id).where(vistos.contains),
    ...novos.map((a) => a.id),
  }.toList());
}


// ---------------------------------------------------------------------------
// Chuva chegando (estimativa de 15 em 15 minutos do Open-Meteo)
// ---------------------------------------------------------------------------

/// Precipitação mínima em 15 minutos para contar como chuva (0,2 mm ≈ 0,8 mm/h).
const limiarChuva15 = 0.2;

/// O que avisar: quando começa, o tipo e a intensidade.
class AvisoChuva {
  const AvisoChuva({
    required this.inicio,
    required this.verbo,
    required this.descricao,
    required this.agora,
  });

  /// Início do primeiro intervalo de 15 minutos com chuva.
  final DateTime inicio;

  /// "chover", "garoar", "nevar", "chover com trovoada".
  final String verbo;

  /// "chuva fraca", "garoa", "neve moderada"...
  final String descricao;

  /// A chuva já está no intervalo atual.
  final bool agora;

  String titulo(String cidade) => agora
      ? 'Começou a $verbo em $cidade'
      : 'Deve começar a $verbo por volta das ${hora(inicio)}';
}

/// Primeiro intervalo com chuva nas próximas 2 horas, ou nulo.
AvisoChuva? avisoDeChuva(List<Faixa15> faixas, DateTime agora) {
  final limite = agora.add(const Duration(hours: 2));
  for (final f in faixas) {
    final fim = f.inicio.add(const Duration(minutes: 15));
    if (!fim.isAfter(agora) || !f.inicio.isBefore(limite)) continue;
    final mm = f.milimetros ?? 0;
    if (mm < limiarChuva15) continue;
    final c = f.codigo ?? 0;
    final porHora = mm * 4;
    final intensidade = porHora < 2.5 ? 'fraca' : (porHora < 10 ? 'moderada' : 'forte');
    final (String verbo, String descricao) = switch (c) {
      >= 95 && <= 99 => ('chover com trovoada', 'chuva $intensidade com trovoada'),
      (>= 71 && <= 77) || 85 || 86 => ('nevar', 'neve $intensidade'),
      >= 51 && <= 57 => ('garoar', 'garoa'),
      _ when (f.neve ?? 0) > 0 => ('nevar', 'neve $intensidade'),
      _ => ('chover', 'chuva $intensidade'),
    };
    return AvisoChuva(
      inicio: f.inicio,
      verbo: verbo,
      descricao: descricao,
      agora: !f.inicio.isAfter(agora),
    );
  }
  return null;
}

/// O mesmo episódio de chuva já avisado (guardado = "código da cidade|início em ms")?
/// Mesmo episódio: início previsto até 90 min do avisado, ou chuva em curso depois do
/// início avisado.
bool mesmoEpisodioDeChuva(AvisoChuva a, String? guardado, int cidade, DateTime agora) {
  if (guardado == null) return false;
  final partes = guardado.split('|');
  if (partes.length != 2 || partes[0] != '$cidade') return false;
  final ms = int.tryParse(partes[1]);
  if (ms == null) return false;
  final anterior = DateTime.fromMillisecondsSinceEpoch(ms);
  if (a.inicio.difference(anterior).abs() <= const Duration(minutes: 90)) return true;
  return a.agora && !anterior.isAfter(agora);
}

/// Consulta a previsão de 15 em 15 minutos da cidade dos avisos e avisa uma vez por
/// episódio quando a chuva for começar nas próximas 2 horas.
Future<void> verificarChuva() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await Preferencias.carregar();
  if (!prefs.avisoChuva) return;
  final cidade = prefs.cidadeDosAvisos;
  if (cidade.latitude == null || cidade.longitude == null) return;
  final r = await http.get(Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': cidade.latitude!.toStringAsFixed(2),
    'longitude': cidade.longitude!.toStringAsFixed(2),
    'minutely_15': 'precipitation,snowfall,weather_code',
    'forecast_minutely_15': '10',
    'timezone': 'GMT',
  })).timeout(const Duration(seconds: 30));
  if (r.statusCode != 200) throw Exception('Open-Meteo ${r.statusCode}');

  final agora = DateTime.now();
  final aviso = avisoDeChuva(lerChuva15min(r.body), agora);
  final sp = await SharedPreferences.getInstance();
  if (aviso == null) {
    // Sem chuva nas próximas 2 horas: o próximo episódio pode ser avisado.
    await sp.remove(_chuvaAvisada);
    return;
  }
  if (mesmoEpisodioDeChuva(aviso, sp.getString(_chuvaAvisada), cidade.geocode, agora)) return;

  await _iniciarPlugin();
  await _plugin.show(
    id: 900001,
    title: aviso.titulo(cidade.nome),
    body: '${aviso.agora ? _maiuscula(aviso.descricao) : '${cidade.nome}: ${aviso.descricao}'}. '
        'Estimativa por modelo (Open-Meteo); o horário pode variar uns 15 a 30 minutos.',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'chuva_chegando',
        'Chuva chegando',
        channelDescription: 'Aviso quando a chuva, garoa ou neve for começar nas próximas 2 horas',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notif_chuva',
      ),
    ),
  );
  await sp.setString(_chuvaAvisada, '${cidade.geocode}|${aviso.inicio.millisecondsSinceEpoch}');
}

String _maiuscula(String t) => t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
