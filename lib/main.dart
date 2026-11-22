import 'dart:io' show SecurityContext;

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'dados/cidade.dart';
import 'dados/mare.dart';
import 'dados/municipios.dart';
import 'dados/notificacoes.dart';
import 'dados/preferencias.dart';
import 'dados/repositorio.dart';
import 'dados/widget_tela.dart';
import 'telas/agora.dart';
import 'telas/ajustes.dart';
import 'telas/alertas.dart';
import 'telas/chuva.dart';
import 'telas/cidades.dart';
import 'telas/previsao.dart';
import 'telas/radar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  await _completarCertificados();
  final prefs = await Preferencias.carregar();
  await _atualizarPosicoes(prefs);
  await EstacaoMare.carregar();
  try {
    await Notificacoes.iniciar();
  } catch (e) {
    // Sem notificações o restante do app continua funcionando.
    debugPrint('ClimaBit: falha ao iniciar notificações: $e');
  }
  final repo = Repositorio(cidade: prefs.cidadeAtual)
    ..aoObterAlertas = (cidade, alertas) {
      if (prefs.avisosLigados && cidade == prefs.cidadeDosAvisos) {
        Notificacoes.marcarVistos(alertas);
      }
    }
    ..aoCompletarCidade = (cidade) {
      prefs.salvarCidades([
        for (final c in prefs.cidadesSalvas) c == cidade ? cidade : c,
      ]);
      if (prefs.cidadeDosAvisos == cidade) prefs.definirCidadeDosAvisos(cidade);
    };
  // Widgets da tela inicial: redesenha quando termina cada consulta.
  var carregava = false;
  repo.addListener(() {
    if (carregava && !repo.carregando) atualizarWidgets(repo);
    carregava = repo.carregando;
  });
  agendarAtualizacaoDosWidgets();
  runApp(ClimaBrApp(repo: repo, prefs: prefs));
  // Abre na hora com os últimos dados guardados e, em seguida, busca os novos.
  repo.carregarGuardado().whenComplete(repo.atualizar);
}

class ClimaBrApp extends StatelessWidget {
  const ClimaBrApp({super.key, required this.repo, required this.prefs});

  final Repositorio repo;
  final Preferencias prefs;

  @override
  Widget build(BuildContext context) {
    const semente = Color(0xFF006A60);
    return MaterialApp(
      title: 'ClimaBit',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(colorSchemeSeed: semente, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: semente,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: Inicio(repo: repo, prefs: prefs),
    );
  }
}

class _Destino {
  const _Destino(this.rotulo, this.icone, this.iconeSelecionado);
  final String rotulo;
  final IconData icone;
  final IconData iconeSelecionado;
}

const _destinos = [
  _Destino('Agora', Icons.thermostat_outlined, Icons.thermostat),
  _Destino('Próximos dias', Icons.calendar_month_outlined, Icons.calendar_month),
  _Destino('Chuva', Icons.water_drop_outlined, Icons.water_drop),
  _Destino('Radar', Icons.radar_outlined, Icons.radar),
];

/// Estrutura principal: barra superior com a cidade e navegação entre as abas.
class Inicio extends StatefulWidget {
  const Inicio({super.key, required this.repo, required this.prefs});

  final Repositorio repo;
  final Preferencias prefs;

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  int _aba = 0;

  void _abrirAlertas() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TelaAlertas(repo: widget.repo),
    ));
  }

  void _abrirCidades() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TelaCidades(repo: widget.repo, prefs: widget.prefs),
    ));
  }

  void _abrirAjustes() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TelaAjustes(repo: widget.repo, prefs: widget.prefs),
    ));
  }

  Widget _conteudo() {
    switch (_aba) {
      case 0:
        return TelaAgora(repo: widget.repo, abrirAlertas: _abrirAlertas);
      case 1:
        return TelaPrevisao(repo: widget.repo);
      case 2:
        return TelaChuva(repo: widget.repo);
      case 3:
        // Chave da cidade: trocar de cidade recria a aba (radares e vento da cidade nova).
        return TelaRadar(
          key: ValueKey('${widget.repo.cidade.geocode} ${widget.repo.cidade.latitude}'),
          repo: widget.repo,
        );
      default:
        return Center(child: Text('${_destinos[_aba].rotulo}: em construção'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final largo = MediaQuery.sizeOf(context).width >= 700;
    return ListenableBuilder(
      listenable: widget.repo,
      builder: (context, _) {
        final repo = widget.repo;
        final corpo = _conteudo();
        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              onTap: _abrirCidades,
              borderRadius: BorderRadius.circular(8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(repo.cidade.rotulo, overflow: TextOverflow.ellipsis),
                    Text('Trocar cidade',
                        style: Theme.of(context).textTheme.labelMedium),
                  ]),
                ),
                const Icon(Icons.arrow_drop_down),
              ]),
            ),
            actions: [
              Builder(builder: (context) {
                final agora = DateTime.now();
                final n = repo.alertas.where((a) => a.ativo(agora)).length;
                return IconButton(
                  tooltip: 'Alertas',
                  onPressed: _abrirAlertas,
                  icon: Badge(
                    isLabelVisible: n > 0,
                    label: Text('$n'),
                    child: Icon(n > 0
                        ? Icons.notifications_active
                        : Icons.notifications_none),
                  ),
                );
              }),
              if (repo.carregando)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                IconButton(
                  tooltip: 'Atualizar',
                  icon: const Icon(Icons.refresh),
                  onPressed: repo.atualizar,
                ),
              IconButton(
                tooltip: 'Ajustes',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _abrirAjustes,
              ),
            ],
          ),
          body: largo
              ? Row(children: [
                  NavigationRail(
                    selectedIndex: _aba,
                    onDestinationSelected: (i) => setState(() => _aba = i),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final d in _destinos)
                        NavigationRailDestination(
                          icon: Icon(d.icone),
                          selectedIcon: Icon(d.iconeSelecionado),
                          label: Text(d.rotulo),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: corpo),
                ])
              : corpo,
          bottomNavigationBar: largo
              ? null
              : NavigationBar(
                  selectedIndex: _aba,
                  onDestinationSelected: (i) => setState(() => _aba = i),
                  destinations: [
                    for (final d in _destinos)
                      NavigationDestination(
                        icon: Icon(d.icone),
                        selectedIcon: Icon(d.iconeSelecionado),
                        label: d.rotulo,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// O servidor da UNIFEI não envia o certificado intermediário da RNP, e o Android não o
/// busca sozinho. O certificado público da RNP (emitido pela GlobalSign Root R46, válido
/// até 2030) vai junto com o app só para completar essa verificação; a raiz continua sendo
/// a do sistema.
Future<void> _completarCertificados() async {
  try {
    final dados = await rootBundle.load('assets/certificados/rnp_icpedu_gr46_ov_tls_ca_2025.pem');
    SecurityContext.defaultContext.setTrustedCertificatesBytes(dados.buffer.asUint8List());
  } catch (_) {
    // Já carregado ou indisponível: só a estação da UNIFEI deixa de responder.
  }
}

/// Cidades salvas em versões anteriores usavam o centro geográfico do município.
/// Troca pelo ponto da sede (lista do IBGE guardada no app).
Future<void> _atualizarPosicoes(Preferencias prefs) async {
  try {
    final m = await Municipios.carregar();
    Cidade atualizar(Cidade c) {
      final ref = m.porGeocode(c.geocode);
      if (ref == null || ref.latitude == null || ref.longitude == null) return c;
      if (ref.latitude == c.latitude && ref.longitude == c.longitude) return c;
      return c.comPosicao(ref.latitude!, ref.longitude!);
    }
    await prefs.salvarCidades([for (final c in prefs.cidadesSalvas) atualizar(c)]);
    await prefs.definirCidadeDosAvisos(atualizar(prefs.cidadeDosAvisos));
  } catch (_) {
    // Sem a lista, as cidades continuam com o ponto anterior.
  }
}
