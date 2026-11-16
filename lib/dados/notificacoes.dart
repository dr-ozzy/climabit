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
        await verificarAlertas();
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
