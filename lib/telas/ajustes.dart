import 'package:material_ui/material_ui.dart';

import '../dados/cidade.dart';
import '../dados/atualizacao.dart';
import '../dados/notificacoes.dart';
import '../dados/preferencias.dart';
import '../dados/repositorio.dart';
import 'seus_dados.dart';

const _intervalos = {15: '15 min', 30: '30 min', 60: '1 hora', 180: '3 horas'};

/// Notificações de alertas, privacidade e informações do app.
class TelaAjustes extends StatefulWidget {
  const TelaAjustes({super.key, required this.repo, required this.prefs});

  final Repositorio repo;
  final Preferencias prefs;

  @override
  State<TelaAjustes> createState() => _TelaAjustesState();
}

class _TelaAjustesState extends State<TelaAjustes> {
  Preferencias get _p => widget.prefs;

  /// Liga ou desliga um dos avisos (alertas oficiais ou chuva chegando). A conferência em
  /// segundo plano fica agendada enquanto pelo menos um estiver ligado.
  Future<void> _ligar(bool ligar, Future<void> Function(bool) gravar) async {
    if (ligar) {
      final ok = await Notificacoes.pedirPermissao();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sem a permissão de notificação o app não consegue avisar.')));
        return;
      }
    }
    // A tela muda logo depois de gravar a escolha; o agendamento e a consulta (que pode
    // levar segundos) continuam em seguida, sem prender a tela.
    await gravar(ligar);
    if (mounted) setState(() {});
    if (_p.algumAviso) {
      await Notificacoes.agendar(_p.intervaloMin);
      // Confere já (alertas em vigor, chuva chegando); também confirma que funciona.
      if (ligar) await Notificacoes.verificarAgora();
    } else {
      await Notificacoes.cancelar();
    }
  }

  Future<void> _ligarAvisos(bool ligar) => _ligar(ligar, _p.definirAvisos);

  Future<void> _ligarChuva(bool ligar) => _ligar(ligar, _p.definirAvisoChuva);

  Future<void> _ligarResumoNoite(bool ligar) => _ligar(ligar, _p.definirResumoNoite);

  Future<void> _exemplo() async {
    final ok = await Notificacoes.pedirPermissao();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sem a permissão de notificação o app não consegue avisar.')));
      return;
    }
    await mostrarAvisoExemplo(_p.cidadeDosAvisos);
  }

  Future<void> _mudarIntervalo(int min) async {
    await _p.definirIntervalo(min);
    if (mounted) setState(() {});
    if (_p.algumAviso) await Notificacoes.agendar(min);
  }

  /// Passos para o widget e os avisos não pararem (economia de bateria do Android).
  Future<void> _ajudaBateria() async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Widget ou aviso não atualiza?'),
        content: const SingleChildScrollView(
          child: Text(
            'O Android pode pausar apps para economizar bateria. Para o ClimaBit atualizar o '
            'widget e conferir os avisos:\n\n'
            '1. Toque em "Abrir configurações do ClimaBit" (abaixo).\n'
            '2. Toque em Bateria (no Motorola: "Uso da bateria do app"; no Samsung: "Bateria").\n'
            '3. Escolha "Sem restrições" (ou "Não otimizado").\n'
            '4. Volte e confira se as notificações do ClimaBit estão permitidas.\n\n'
            'O ClimaBit consulta a cada 30 minutos só quando há widget na tela ou aviso ligado.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fechar')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(c);
              final ok = await abrirDetalhesDoApp();
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Abra Configurações › Apps › ClimaBit no celular.')));
              }
            },
            child: const Text('Abrir configurações do ClimaBit'),
          ),
        ],
      ),
    );
  }

  Future<void> _escolherSilencio() async {
    final atual = _p.silencio ?? (22, 7);
    var ini = atual.$1, fim = atual.$2;
    final r = await showDialog<(int, int)>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Horário de silêncio'),
          content: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Das '),
            DropdownButton<int>(
              value: ini,
              items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h}h'))],
              onChanged: (h) => set(() => ini = h ?? ini),
            ),
            const Text(' às '),
            DropdownButton<int>(
              value: fim,
              items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h}h'))],
              onChanged: (h) => set(() => fim = h ?? fim),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, (ini, fim)), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (r == null) return;
    await _p.definirSilencio(r);
    if (mounted) setState(() {});
  }

  Future<void> _escolherCidade() async {
    final salvas = _p.cidadesSalvas;
    final atual = _p.cidadeDosAvisos;
    final c = await showDialog<Cidade>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Cidade dos avisos'),
        children: [
          for (final s in salvas)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, s),
              child: Row(children: [
                Icon(s == atual ? Icons.check_circle : Icons.circle_outlined, size: 20),
                const SizedBox(width: 12),
                Text(s.rotulo),
              ]),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text('Para outra cidade, salve-a antes na tela Cidades.'),
          ),
        ],
      ),
    );
    if (c == null) return;
    await _p.definirCidadeDosAvisos(c);
    if (mounted) setState(() {});
    await Notificacoes.verificarAgora();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    // Cidade e intervalo valem para os dois avisos (alertas e chuva chegando).
    final ligado = _p.algumAviso;
    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(t, style: tema.textTheme.titleSmall?.copyWith(color: tema.colorScheme.primary)),
        );
    Widget paragrafo(String t) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(t),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              titulo('Avisos'),
              SwitchListTile(
                title: const Text('Notificar alertas do INMET'),
                subtitle: const Text('Confere em segundo plano e avisa quando sai um alerta novo.'),
                value: _p.avisosLigados,
                onChanged: _ligarAvisos,
              ),
              SwitchListTile(
                title: const Text('Avisar quando for começar a chover'),
                subtitle: const Text('Chuva, garoa, neve ou trovoada nas próximas 2 horas. '
                    'Estimativa por modelo (Open-Meteo): o horário pode variar.'),
                value: _p.avisoChuva,
                onChanged: _ligarChuva,
              ),
              SwitchListTile(
                title: const Text('Resumo de amanhã, à noite'),
                subtitle: const Text('Uma notificação entre 19h e 23h com a previsão do dia '
                    'seguinte (INMET; no Canadá, ECCC).'),
                value: _p.resumoNoite,
                onChanged: _ligarResumoNoite,
              ),
              ListTile(
                enabled: ligado,
                leading: const Icon(Icons.location_city),
                title: const Text('Cidade dos avisos'),
                subtitle: Text(_p.cidadeDosAvisos.rotulo),
                onTap: ligado ? _escolherCidade : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Conferir a cada', style: tema.textTheme.bodyLarge?.copyWith(
                    color: ligado ? null : tema.disabledColor)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SegmentedButton<int>(
                  segments: [
                    for (final e in _intervalos.entries)
                      ButtonSegment(value: e.key, label: Text(e.value)),
                  ],
                  selected: {_p.intervaloMin},
                  // Sem a marca ✓: a cor já mostra a escolha e o texto cabe numa linha.
                  showSelectedIcon: false,
                  onSelectionChanged: ligado ? (s) => _mudarIntervalo(s.first) : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text('Quais alertas avisar', style: tema.textTheme.bodyLarge?.copyWith(
                    color: _p.avisosLigados ? null : tema.disabledColor)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Todos')),
                    ButtonSegment(value: 1, label: Text('Laranja e vermelho')),
                    ButtonSegment(value: 2, label: Text('Só vermelho')),
                  ],
                  selected: {_p.nivelMinimoAlerta},
                  showSelectedIcon: false,
                  onSelectionChanged: _p.avisosLigados
                      ? (s) async {
                          await _p.definirNivelMinimoAlerta(s.first);
                          if (mounted) setState(() {});
                        }
                      : null,
                ),
              ),
              SwitchListTile(
                title: const Text('Horário de silêncio'),
                subtitle: Text(_p.silencio == null
                    ? 'Desligado. Alertas vermelhos avisam sempre.'
                    : 'Das ${_p.silencio!.$1}h às ${_p.silencio!.$2}h, sem avisos '
                        '(alertas vermelhos avisam mesmo assim). Toque para mudar.'),
                value: _p.silencio != null,
                onChanged: ligado
                    ? (v) async {
                        if (v) {
                          await _escolherSilencio();
                        } else {
                          await _p.definirSilencio(null);
                          if (mounted) setState(() {});
                        }
                      }
                    : null,
              ),
              SwitchListTile(
                title: const Text('Chuva: só avisar se for moderada ou forte'),
                subtitle: const Text('Garoa e chuva fraca não geram aviso.'),
                value: _p.chuvaSoModerada,
                onChanged: _p.avisoChuva
                    ? (v) async {
                        await _p.definirChuvaSoModerada(v);
                        if (mounted) setState(() {});
                      }
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Mostrar um aviso de exemplo'),
                subtitle: const Text('Para ver como fica e conferir se as notificações chegam.'),
                onTap: _exemplo,
              ),
              ListTile(
                leading: const Icon(Icons.battery_alert_outlined),
                title: const Text('Widget ou aviso não atualiza?'),
                subtitle: const Text('Passos para liberar a bateria do ClimaBit.'),
                onTap: _ajudaBateria,
              ),
              titulo('Privacidade'),
              ListTile(
                leading: const Icon(Icons.folder_shared_outlined),
                title: const Text('Seus dados'),
                subtitle: const Text('O que fica guardado neste celular, e apagar tudo.'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => TelaSeusDados(repo: widget.repo))),
              ),
              paragrafo('• Sem anúncios, sem conta e sem estatísticas de uso.'),
              paragrafo('• O app só se conecta a órgãos oficiais: INMET, CPTEC/INPE, Cemaden, Alerta Rio, '
                  'Defesa Civil de Niterói, UNIFEI (em Itajubá) e o serviço de dados de aeroportos da NOAA '
                  '(governo dos EUA, aviationweather.gov). Consulta também o Open-Meteo '
                  '(open-meteo.com, serviço de código aberto) para a chuva de hora em hora, '
                  'o aviso de chuva chegando, o mapa de vento e quando falta um dado oficial; a '
                  'Organização Meteorológica Mundial (cópia dos alertas do INMET, só quando o INMET '
                  'não responde); o RainViewer (radar para cidades fora do Rio); e o ViaCEP, só '
                  'quando você busca uma cidade pelo CEP.'),
              paragrafo('• A sua localização não sai do celular: o app descobre o município '
                  'com a lista do IBGE guardada nele e envia às fontes só o código ou o ponto da sede '
                  'do município, que são os mesmos para todos os moradores.'),
              paragrafo('• Cidades salvas e ajustes ficam só neste celular e não vão para o backup.'),
              titulo('Fontes dos dados'),
              paragrafo('• INMET: medição das estações, previsão e alertas.'),
              paragrafo('• CPTEC/INPE: previsão de 7 dias, índice ultravioleta e ondas.'),
              paragrafo('• Cemaden: chuva medida pelos pluviômetros.'),
              paragrafo('• Alerta Rio (Prefeitura do Rio): radar do Sumaré e pluviômetros do Rio.'),
              paragrafo('• Defesa Civil de Niterói: radar de Niterói, boletim de previsão e sirenes.'),
              paragrafo('• Aeroportos (medições do DECEA, Força Aérea, via NOAA): vento quando a estação '
                  'do INMET não tem o dado.'),
              paragrafo('• UNIFEI (Universidade Federal de Itajubá): estação meteorológica do campus, '
                  'usada na medição atual de Itajubá.'),
              paragrafo('• IBGE: lista de municípios, mesorregiões e contornos do mapa.'),
              paragrafo('• OMM (Organização Meteorológica Mundial): cópia pública dos alertas do '
                  'INMET, usada como reserva.'),
              paragrafo('• RainViewer (rainviewer.com): mosaico de radares para cidades sem radar '
                  'oficial no app; não é fonte oficial brasileira.'),
              paragrafo('• ViaCEP (viacep.com.br): município a partir do CEP.'),
              paragrafo('• Marinha do Brasil (Centro de Hidrografia da Marinha): Tábua das Marés 2025 '
                  'da Ilha Fiscal e do Porto do Forno, usada para calcular a maré no próprio celular, '
                  'sem internet.'),
              paragrafo('• Environment and Climate Change Canada (serviço meteorológico do Canadá): '
                  'medição, previsão, avisos e radar das cidades canadenses. Mapa do radar: '
                  'Natural Resources Canada.'),
              paragrafo('• Open-Meteo (open-meteo.com, licença CC BY 4.0): estimativas de modelo, '
                  'chuva de hora em hora e reserva quando falta dado oficial. Aparecem como "estimativa".'),
              titulo('Sobre'),
              paragrafo('ClimaBit $versaoApp · software livre (licença GPL-3.0 ou posterior).'),
            ],
          ),
        ),
      ),
    );
  }
}
