import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'alertas_omm.dart';
import 'canada.dart';
import 'estacoes.dart';
import 'cidade.dart';
import 'fontes.dart';
import 'http_cache.dart';
import 'municipios.dart' show semAcento;

/// Situação de uma fonte na última atualização.
class EstadoFonte {
  const EstadoFonte({required this.obtidoEm, required this.doCache, this.erro});

  final DateTime? obtidoEm;
  final bool doCache;
  final String? erro;

  bool get falhou => erro != null;
}

/// Junta os dados de todas as fontes oficiais e escolhe o mais recente de cada tipo.
class Repositorio extends ChangeNotifier {
  Repositorio({HttpCache? http, Cidade cidade = niteroi})
      : _http = http ?? HttpCache(),
        _cidade = cidade;

  final HttpCache _http;
  Cidade _cidade;

  /// Chamado quando os alertas da cidade são obtidos (para não notificar o que já se viu).
  void Function(Cidade, List<Alerta>)? aoObterAlertas;

  /// Chamado quando o código do CPTEC da cidade é descoberto (para guardar).
  void Function(Cidade)? aoCompletarCidade;

  Cidade get cidade => _cidade;
  bool carregando = false;

  /// A tela mostra os últimos dados guardados enquanto a consulta nova não termina.
  bool mostrandoGuardado = false;

  /// Hora em que os dados guardados foram obtidos (o mais recente deles).
  DateTime? guardadoDe;

  bool _modoGuardado = false;

  void _concluir() {
    if (_modoGuardado) {
      mostrandoGuardado = guardadoDe != null && (medicao != null || previsao.isNotEmpty);
    } else {
      mostrandoGuardado = false;
      atualizadoEm = DateTime.now();
    }
    carregando = false;
    notifyListeners();
  }

  /// Abertura rápida: monta a tela com as respostas guardadas no aparelho, sem internet.
  /// Depois disso o app chama [atualizar] para buscar os dados novos.
  Future<void> carregarGuardado() async {
    if (carregando) return;
    _http.somenteGuardado = true;
    _modoGuardado = true;
    guardadoDe = null;
    try {
      await atualizar();
    } finally {
      _http.somenteGuardado = false;
      _modoGuardado = false;
    }
  }
  DateTime? atualizadoEm;

  Medicao? medicao;
  List<DiaPrevisao> previsao = [];
  List<Pluviometro> pluviometros = [];
  List<Alerta> alertas = [];
  List<PrevisaoOnda> ondas = [];

  /// Só para Niterói: boletim e sirenes da Defesa Civil municipal.
  String? boletimNiteroi;
  DateTime? boletimObtidoEm;
  List<Sirene> sirenes = [];

  /// Vento do aeroporto mais próximo, quando a estação do INMET não tem o vento
  /// ou quando a medição do aeroporto é mais recente. Nulo = usar o do INMET.
  VentoAeroporto? ventoAeroporto;

  /// Aeroporto mais próximo (até 40 km, boletim de até 3 h) com as nuvens observadas,
  /// usado para o desenho do céu de agora.
  VentoAeroporto? ceuAeroporto;

  /// Estação do INMET guardada como reserva quando uma estação local (UNIFEI) é usada.
  Medicao? medicaoReserva;

  /// Estimativas do Open-Meteo, usadas só quando falta o dado oficial.
  Medicao? estimativaAtual;
  Medicao? ventoEstimado;

  /// Próximas 24 horas: temperatura, chuva e UV (Open-Meteo, estimativa; não há fonte
  /// oficial brasileira por hora).
  List<HoraChuva> chuvaHoraria = [];

  /// Últimas 24 horas do mesmo modelo (Open-Meteo), para comparar agora com ontem.
  List<HoraChuva> horasPassadas = [];

  /// Previsão por hora dos próximos 7 dias (para as rotinas de atividades). As outras
  /// telas usam só [chuvaHoraria] (próximas 25 horas).
  List<HoraChuva> horasSemana = [];

  /// Chuva de 15 em 15 minutos nas próximas 2 horas (Open-Meteo), para o widget dizer
  /// "Chuva às 18:15" quando a chuva estiver perto.
  List<Faixa15> faixas15 = [];

  /// A previsão por hora é oficial (Canadá) e não estimativa de modelo.
  bool horasOficiais = false;
  bool previsaoEstimada = false;

  /// Nome da fonte → situação (INMET estação, INMET previsão, CPTEC...).
  final Map<String, EstadoFonte> fontes = {};

  Future<void> trocarCidade(Cidade nova) async {
    _cidade = nova;
    medicao = null;
    previsao = [];
    pluviometros = [];
    alertas = [];
    ondas = [];
    boletimNiteroi = null;
    boletimObtidoEm = null;
    sirenes = [];
    ventoAeroporto = null;
    ceuAeroporto = null;
    medicaoReserva = null;
    estimativaAtual = null;
    ventoEstimado = null;
    previsaoEstimada = false;
    chuvaHoraria = [];
    horasSemana = [];
    horasPassadas = [];
    fontes.clear();
    notifyListeners();
    await atualizar();
  }

  Future<void> atualizar() async {
    if (carregando) return;
    carregando = true;
    notifyListeners();
    if (_cidade.noCanada) {
      await _atualizarCanada();
      return;
    }
    horasOficiais = false;
    if (_cidade.idCptec == null) await _descobrirIdCptec();
    final c = _cidade;

    final resultados = await Future.wait([
      _consultar('INMET estação',
          Uri.parse('https://apiprevmet3.inmet.gov.br/estacao/proxima/${c.geocode}')),
      _consultar('INMET previsão',
          Uri.parse('https://apiprevmet3.inmet.gov.br/previsao/${c.geocode}')),
      _consultar('INMET alertas',
          Uri.parse('https://apiprevmet3.inmet.gov.br/avisos/ativos')),
      if (c.idCptec != null)
        _consultar(
            'CPTEC/INPE previsão',
            Uri.parse(
                'https://servicos.cptec.inpe.br/XML/cidade/7dias/${c.idCptec}/previsao.xml'),
            codificacao: latin1)
      else
        Future.value(null),
      _consultar('Cemaden',
          Uri.parse(
              'https://resources.cemaden.gov.br/graficos/interativo/getJson2.php?uf=${c.uf}')),
      if (c.ehRioDeJaneiro)
        _consultar('Alerta Rio',
            Uri.parse('http://websirene.rio.rj.gov.br/xml/chuvas.xml'))
      else
        Future.value(null),
      _consultarOndas(c),
      if (c.ehNiteroi)
        _consultar('Defesa Civil de Niterói (boletim)',
            Uri.parse('https://www.defesacivildeniteroi.com.br/monitoramento/'))
      else
        Future.value(null),
      if (c.ehNiteroi)
        _consultar('Defesa Civil de Niterói (sirenes)',
            Uri.parse('https://svidaniteroi.com.br/mapa_iframe/'))
      else
        Future.value(null),
      if (c.latitude != null && c.longitude != null)
        _consultarAeroportos(c.latitude!, c.longitude!)
      else
        Future.value(null),
      if (c.ehItajuba)
        _consultar(
            'UNIFEI (estação)',
            Uri.parse(
                'https://meteorologia.unifei.edu.br/homepage/blocks/current/updater.php?interval=20'))
      else
        Future.value(null),
      if (c.latitude != null && c.longitude != null)
        _consultar('Open-Meteo (por hora)', _enderecoChuvaHoraria(c.latitude!, c.longitude!))
      else
        Future.value(null),
    ]);
    if (c != _cidade) {
      // A cidade mudou durante a consulta: descarta e consulta a cidade nova.
      carregando = false;
      atualizar();
      return;
    }
    ondas = resultados[6] == null
        ? []
        : (_ler('CPTEC/INPE ondas', resultados[6], lerOndasCptec) ?? []);
    boletimNiteroi =
        _ler('Defesa Civil de Niterói (boletim)', resultados[7], lerBoletimNiteroi);
    boletimObtidoEm = resultados[7]?.obtidoEm;
    sirenes =
        _ler('Defesa Civil de Niterói (sirenes)', resultados[8], lerSirenesNiteroi) ?? [];

    final estacao = resultados[0];
    final prevInmet = resultados[1];
    final avisos = resultados[2];
    final prevCptec = resultados[3];
    final cemaden = resultados[4];
    final alertaRio = resultados[5];

    medicao = _ler('INMET estação', estacao, (s) => lerEstacaoInmet(s)) ?? medicao;
    // O INMET mede a distância a partir de um ponto próprio; recalcula a partir da sede.
    // Estação escolhida pelo usuário (Detalhes de agora › Trocar estação), se tiver medição
    // recente; senão, fica a automática.
    final escolhida = c.noCanada ? null : await estacaoEscolhida(c.geocode);
    if (escolhida != null && !_modoGuardado && escolhida.$1 != medicao?.codigo) {
      final m = await medirEscolhida(escolhida, _http);
      if (m != null && medicaoOficialValida(m, DateTime.now())) medicao = m;
    }
    if (medicao != null && c.latitude != null && c.longitude != null) {
      medicao = comDistanciaDe(medicao!, c.latitude!, c.longitude!);
    }
    medicaoReserva = null;
    final local = escolherEstacaoLocal(
      _ler('UNIFEI (estação)', resultados[10], lerEstacaoUnifei),
      medicao,
      c,
      DateTime.now(),
    );
    if (local != null) {
      medicaoReserva = medicao;
      medicao = local;
    }
    final aeroportos = _ler('Aeroportos (vento)', resultados[9], lerVentoAeroportos) ?? [];
    ventoAeroporto = escolherVentoAeroporto(aeroportos, medicao, c, DateTime.now());
    ceuAeroporto = escolherCeuAeroporto(aeroportos, c, DateTime.now());

    // Sem estação do INMET perto e recente: usa a medição oficial do aeroporto (Aeronáutica,
    // DECEA) a até 30 km, antes de cair na estimativa por modelo.
    final aero = ventoAeroporto;
    if (!medicaoOficialValida(medicao, DateTime.now()) &&
        aero != null &&
        aero.temperatura != null &&
        c.latitude != null &&
        aero.distanciaKm(c.latitude!, c.longitude!) <= 30) {
      medicaoReserva = medicao;
      medicao = Medicao(
        fonte: 'Aeroporto',
        estacao: 'Aeronáutica (DECEA) no aeroporto ${aero.nome}, ${aero.codigo}',
        codigo: aero.codigo,
        hora: aero.hora,
        distanciaKm: aero.distanciaKm(c.latitude!, c.longitude!),
        temperatura: aero.temperatura,
        umidade: aero.umidade,
        ventoKmh: aero.ventoKmh,
        rajadaKmh: aero.rajadaKmh,
        ventoDirecao: aero.direcao,
        orvalho: aero.orvalho,
        pressao: aero.pressao,
        visibilidadeKm: aero.visibilidadeKm,
        latitude: aero.latitude,
        longitude: aero.longitude,
      );
    }

    final diasInmet =
        _ler('INMET previsão', prevInmet, (s) => lerPrevisaoInmet(s, c.geocode)) ?? [];
    final diasCptec = _ler('CPTEC/INPE previsão', prevCptec, lerPrevisaoCptec) ?? [];
    previsao = combinarPrevisoes(diasInmet, diasCptec, DateTime.now());

    var novosAlertas =
        _ler('INMET alertas', avisos, (s) => lerAlertasInmet(s, c.geocode));
    // INMET fora do ar (ou só a cópia antiga guardada): usa a cópia dos avisos do INMET
    // publicada pela OMM.
    if ((avisos == null || avisos.doCache || novosAlertas == null) && !_modoGuardado) {
      final omm = await _alertasPelaOmm(c, semInmet: novosAlertas == null);
      if (omm != null) novosAlertas = omm;
    }
    if (novosAlertas != null) {
      alertas = novosAlertas;
      if (!_modoGuardado) aoObterAlertas?.call(c, novosAlertas);
    }

    pluviometros = [
      ...?_ler('Cemaden', cemaden, (s) => lerPluviometrosCemaden(s, c.geocode)),
      ...?_ler('Alerta Rio', alertaRio, lerPluviometrosAlertaRio),
    ];

    // A consulta traz também as 24 horas passadas (para "comparado com ontem"); o resto
    // do app usa só a hora atual em diante.
    final todasHoras = _ler('Open-Meteo (por hora)', resultados[11], lerChuvaHoraria) ?? [];
    final corte = DateTime.now().subtract(const Duration(minutes: 59));
    horasSemana = todasHoras.where((h) => h.hora.isAfter(corte)).toList();
    faixas15 = _ler('Open-Meteo (por hora)', resultados[11], lerChuva15min) ?? [];
    chuvaHoraria = horasSemana.take(25).toList();
    horasPassadas = todasHoras.where((h) => !h.hora.isAfter(corte)).toList();

    await _completarComOpenMeteo(c);
    if (c != _cidade) {
      // A cidade mudou durante a consulta: descarta e consulta a cidade nova.
      carregando = false;
      atualizar();
      return;
    }

    _concluir();
  }

  /// Cidade do Canadá: tudo vem do serviço meteorológico oficial de lá (ECCC).
  Future<void> _atualizarCanada() async {
    final c = _cidade;
    const nome = 'ECCC (Canadá)';
    final r = await _consultar(nome, enderecoCanada(c.idEccc!));
    final d = _ler(nome, r, lerCanada);
    var m = d?.medicao;
    if (m != null && c.latitude != null && c.longitude != null) {
      m = comDistanciaDe(m, c.latitude!, c.longitude!);
    }
    medicao = m;
    medicaoReserva = null;
    ventoAeroporto = null;
    ceuAeroporto = null;
    previsao = d?.dias ?? [];
    chuvaHoraria = d?.horas ?? [];
    horasSemana = chuvaHoraria;
    horasPassadas = [];
    horasOficiais = chuvaHoraria.isNotEmpty;
    final novos = d?.alertas;
    if (novos != null) alertas = novos;
    pluviometros = [];
    ondas = [];
    sirenes = [];
    await _completarComOpenMeteo(c);
    if (c != _cidade) {
      carregando = false;
      atualizar();
      return;
    }
    _concluir();
  }

  /// A busca de METAR por área deixa estações de fora (ex.: Cabo Frio). Por isso:
  /// 1) lista de estações da área; 2) medições dessas estações pelos códigos.
  Future<RespostaFonte?> _consultarAeroportos(double lat, double lon) async {
    const nome = 'Aeroportos (vento)';
    final area = _areaAeroportos(lat, lon);
    final estacoes = await _consultar(
        nome, Uri.parse('https://aviationweather.gov/api/data/stationinfo?bbox=$area&format=json'));
    if (estacoes == null) return null;
    List<String> codigos;
    try {
      codigos = lerCodigosAeroportos(estacoes.corpo);
    } catch (_) {
      return null;
    }
    if (codigos.isEmpty) {
      fontes.remove(nome);
      return null;
    }
    return _consultar(nome,
        Uri.parse('https://aviationweather.gov/api/data/metar?ids=${codigos.join(',')}&format=json'));
  }

  /// Usa o Open-Meteo só para o que ficou sem dado oficial:
  /// medição atual (sem estação a até 50 km com medição de até 3 h), vento e previsão.
  Future<void> _completarComOpenMeteo(Cidade c) async {
    estimativaAtual = null;
    ventoEstimado = null;
    previsaoEstimada = false;
    final agora = DateTime.now();
    final semAtual = !medicaoOficialValida(medicao, agora);
    final semVento = ventoAeroporto == null && medicao?.ventoKmh == null;
    final semPrevisao = previsao.isEmpty;
    if (!(semAtual || semVento || semPrevisao)) {
      fontes.remove('Open-Meteo (estimativa)');
      return;
    }
    if (c.latitude == null || c.longitude == null) return;
    final r = await _consultar('Open-Meteo (estimativa)', _enderecoOpenMeteo(c.latitude!, c.longitude!));
    final om = _ler('Open-Meteo (estimativa)', r, lerOpenMeteo);
    if (om == null) return;
    if (semAtual) {
      estimativaAtual = om.atual;
    } else if (semVento && om.atual?.ventoKmh != null) {
      ventoEstimado = om.atual;
    }
    if (semPrevisao && om.dias.isNotEmpty) {
      final hoje = DateTime(agora.year, agora.month, agora.day);
      previsao = om.dias.where((d) => !d.dia.isBefore(hoje)).take(7).toList();
      previsaoEstimada = true;
    }
  }

  /// Ondas só existem para cidades do litoral; nas outras o CPTEC responde com erro,
  /// que aqui não conta como fonte com problema.
  Future<RespostaFonte?> _consultarOndas(Cidade c) async {
    if (c.idCptec == null) return null;
    try {
      final r = await _http.obter(
        Uri.parse('https://servicos.cptec.inpe.br/XML/cidade/${c.idCptec}/todos/tempos/ondas.xml'),
        codificacao: latin1,
      );
      if (!r.corpo.contains('<previsao>')) return null;
      if (!_modoGuardado) fontes['CPTEC/INPE ondas'] = EstadoFonte(obtidoEm: r.obtidoEm, doCache: r.doCache);
      return r;
    } catch (_) {
      return null;
    }
  }

  /// O CPTEC usa um código próprio; procura pelo nome da cidade (sem enviar mais nada).
  /// Tenta o nome completo e, se não achar, a palavra mais longa do nome
  /// (o CPTEC escreve alguns nomes de outro jeito: "Armação de Búzios").
  Future<void> _descobrirIdCptec() async {
    final c = _cidade;
    final buscas = {semAcento(c.nome), palavraPrincipal(c.nome)};
    for (final termo in buscas) {
      try {
        final r = await _http.obter(
          Uri.https('servicos.cptec.inpe.br', '/XML/listaCidades', {'city': termo}),
          codificacao: latin1,
        );
        final id = idCptecDaLista(lerListaCidadesCptec(r.corpo), c);
        if (id != null) {
          _cidade = c.comIdCptec(id);
          aoCompletarCidade?.call(_cidade);
          return;
        }
      } catch (_) {
        // Sem o código do CPTEC a previsão usa só o INMET.
      }
    }
  }

  Future<RespostaFonte?> _consultar(String nome, Uri uri,
      {Encoding codificacao = utf8}) async {
    try {
      final r = await _http.obter(uri, codificacao: codificacao);
      if (_modoGuardado) {
        if (guardadoDe == null || r.obtidoEm.isAfter(guardadoDe!)) guardadoDe = r.obtidoEm;
        return r;
      }
      fontes[nome] = EstadoFonte(obtidoEm: r.obtidoEm, doCache: r.doCache);
      return r;
    } catch (e) {
      if (!_modoGuardado) fontes[nome] = EstadoFonte(obtidoEm: null, doCache: false, erro: '$e');
      return null;
    }
  }

  /// Avisos do INMET pela cópia da OMM, pela mesorregião da cidade. Devolve null se a OMM
  /// também falhar, ou se só houver cópia guardada e o INMET tiver a dele ([semInmet] falso).
  Future<List<Alerta>?> _alertasPelaOmm(Cidade c, {required bool semInmet}) async {
    final meso = (await Mesorregioes.carregar()).de(c.geocode);
    if (meso == null) return null;
    const nome = 'OMM (cópia dos avisos do INMET)';
    final r = await _consultar(nome, Uri.parse(enderecoAlertasOmm));
    if (r == null || (r.doCache && !semInmet)) return null;
    return _ler(nome, r, (s) => lerAlertasOmm(s, meso));
  }

  T? _ler<T>(String nome, RespostaFonte? r, T? Function(String) leitor) {
    if (r == null) return null;
    try {
      return leitor(r.corpo);
    } catch (e) {
      if (!_modoGuardado) {
        fontes[nome] = EstadoFonte(
            obtidoEm: r.obtidoEm, doCache: r.doCache, erro: 'formato inesperado');
      }
      return null;
    }
  }

  /// Pluviômetros com leitura recente, do mais chuvoso para o menos chuvoso.
  List<Pluviometro> pluviometrosRecentes(DateTime agora) {
    final l = pluviometros.where((p) => p.recente(agora)).toList()
      ..sort((a, b) => (b.chuva1h ?? 0).compareTo(a.chuva1h ?? 0));
    return l;
  }
}

/// Para cada dia usa o INMET quando ele cobre o dia; senão, o CPTEC.
/// O índice ultravioleta vem sempre do CPTEC.
List<DiaPrevisao> combinarPrevisoes(
    List<DiaPrevisao> inmet, List<DiaPrevisao> cptec, DateTime agora) {
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final porDia = <DateTime, DiaPrevisao>{};
  for (final d in cptec) {
    porDia[d.dia] = d;
  }
  for (final d in inmet) {
    final doCptec = porDia[d.dia];
    d.uv ??= doCptec?.uv;
    porDia[d.dia] = d;
  }
  final dias = porDia.values.where((d) => !d.dia.isBefore(hoje)).toList()
    ..sort((a, b) => a.dia.compareTo(b.dia));
  return dias.take(7).toList();
}

/// Área de busca de aeroportos em volta do centro da cidade (±0,5°, arredondada a 0,1°).
/// O ponto é o centro do município, o mesmo para todos os moradores.
/// Área de busca de aeroportos em volta do ponto da cidade (±0,5°, arredondada a 0,1°).
/// O ponto é o da sede do município, o mesmo para todos os moradores.
String _areaAeroportos(double lat, double lon) {
  String f(double v) => v.toStringAsFixed(1);
  final la = (lat * 10).round() / 10;
  final lo = (lon * 10).round() / 10;
  return '${f(la - 0.5)},${f(lo - 0.5)},${f(la + 0.5)},${f(lo + 0.5)}';
}

/// Códigos dos aeroportos com boletim METAR na lista de estações
/// (`/api/data/stationinfo?bbox=...`).
List<String> lerCodigosAeroportos(String corpo) {
  final lista = jsonDecode(corpo);
  if (lista is! List) return [];
  return [
    for (final e in lista.whereType<Map<String, dynamic>>())
      if ('${e['siteType']}'.contains('METAR') && '${e['icaoId'] ?? ''}'.isNotEmpty)
        '${e['icaoId']}',
  ];
}

/// Aeroporto mais próximo (até 40 km) com vento medido nas últimas 3 horas.
/// Só é usado quando o INMET não tem vento ou quando a medição do aeroporto é
/// pelo menos 30 minutos mais recente (regra do dado mais atual).
VentoAeroporto? escolherVentoAeroporto(
    List<VentoAeroporto> lista, Medicao? inmet, Cidade c, DateTime agora) {
  if (c.latitude == null || c.longitude == null) return null;
  VentoAeroporto? melhor;
  var menor = double.infinity;
  for (final v in lista) {
    if (v.ventoKmh == null) continue;
    if (agora.difference(v.hora) > const Duration(hours: 3)) continue;
    final d = v.distanciaKm(c.latitude!, c.longitude!);
    if (d > 40 || d >= menor) continue;
    menor = d;
    melhor = v;
  }
  if (melhor == null) return null;
  if (inmet?.ventoKmh == null) return melhor;
  return melhor.hora.isAfter(inmet!.hora.add(const Duration(minutes: 30))) ? melhor : null;
}

/// Aeroporto mais próximo (até 40 km) com nuvens informadas no boletim das últimas 3 horas.
VentoAeroporto? escolherCeuAeroporto(List<VentoAeroporto> lista, Cidade c, DateTime agora) {
  if (c.latitude == null || c.longitude == null) return null;
  VentoAeroporto? melhor;
  var menor = double.infinity;
  for (final v in lista) {
    if (v.cobertura == null) continue;
    if (agora.difference(v.hora) > const Duration(hours: 3)) continue;
    final d = v.distanciaKm(c.latitude!, c.longitude!);
    if (d > 40 || d >= menor) continue;
    menor = d;
    melhor = v;
  }
  return melhor;
}

/// Medição oficial que representa a cidade: com temperatura, estação a até 50 km
/// e medida há no máximo 3 horas.
bool medicaoOficialValida(Medicao? m, DateTime agora) =>
    m != null &&
    m.temperatura != null &&
    (m.distanciaKm == null || m.distanciaKm! <= 50) &&
    agora.difference(m.hora) <= const Duration(hours: 3);

/// Centro do município arredondado a 0,01° (cerca de 1 km), igual para todos os moradores.
Uri _enderecoOpenMeteo(double lat, double lon) => Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(2),
      'longitude': lon.toStringAsFixed(2),
      'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,'
          'pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,dew_point_2m,visibility',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,'
          'precipitation_probability_max,uv_index_max',
      'timezone': 'America/Sao_Paulo',
      'forecast_days': '7',
      'wind_speed_unit': 'kmh',
    });

/// Estação local (hoje só a UNIFEI, em Itajubá) no lugar da estação do INMET quando estiver
/// no ar, com temperatura medida há até 3 horas e não mais antiga que a do INMET.
Medicao? escolherEstacaoLocal(Medicao? local, Medicao? inmet, Cidade c, DateTime agora) {
  if (local == null || local.temperatura == null) return null;
  if (agora.difference(local.hora) > const Duration(hours: 3)) return null;
  if (inmet != null &&
      medicaoOficialValida(inmet, agora) &&
      local.hora.isBefore(inmet.hora.subtract(const Duration(minutes: 30)))) {
    return null;
  }
  if (c.latitude == null || c.longitude == null) return local;
  return comDistanciaDe(local, c.latitude!, c.longitude!);
}


const _palavrasLigacao = {'de', 'da', 'do', 'das', 'dos', 'd', 'e'};

/// Nome sem acentos, hífens, apóstrofos e palavras de ligação, para comparar grafias
/// diferentes ("Armação dos Búzios" e "Armação de Búzios", "Pingo-d'Água" e "Pingo d'Água").
String nomeComparavel(String s) => semAcento(s)
    .replaceAll(RegExp(r"[-'’]"), ' ')
    .split(RegExp(r'\s+'))
    .where((p) => p.isNotEmpty && !_palavrasLigacao.contains(p))
    .join(' ');

/// A palavra mais longa do nome, usada como segunda tentativa de busca.
String palavraPrincipal(String s) {
  final palavras = nomeComparavel(s).split(' ');
  palavras.sort((a, b) => b.length.compareTo(a.length));
  return palavras.first;
}

/// Código do CPTEC da cidade na lista "nome|UF" → código.
int? idCptecDaLista(Map<String, int> lista, Cidade c) {
  final alvo = nomeComparavel(c.nome);
  for (final e in lista.entries) {
    final [nome, uf] = e.key.split('|');
    if (uf == c.uf && nomeComparavel(nome) == alvo) return e.value;
  }
  return null;
}

/// Próximas 24 horas (temperatura, chuva, UV), em UTC (o app converte para a hora local).
Uri _enderecoChuvaHoraria(double lat, double lon) =>
    Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(2),
      'longitude': lon.toStringAsFixed(2),
      'hourly': 'temperature_2m,apparent_temperature,precipitation_probability,precipitation,'
          'weather_code,uv_index,is_day,wind_speed_10m',
      // 7 dias à frente (rotinas de atividades); as telas usam as primeiras 25 horas.
      'forecast_hours': '169',
      'past_hours': '25',
      'minutely_15': 'precipitation,snowfall,weather_code',
      'forecast_minutely_15': '8',
      'timezone': 'GMT',
    });
