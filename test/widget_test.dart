import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tempo_oficial/telas/componentes.dart';
import 'package:tempo_oficial/dados/http_cache.dart';
import 'package:tempo_oficial/util/formatos.dart';
import 'package:tempo_oficial/dados/fontes.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tempo_oficial/dados/chuva_prevista.dart';
import 'package:tempo_oficial/dados/cidade.dart';
import 'package:tempo_oficial/dados/repositorio.dart';
import 'package:tempo_oficial/dados/mare.dart';
import 'package:tempo_oficial/dados/lua.dart';
import 'dart:io' show File;

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  test('fases da lua de novembro de 2026', () {
    final f = Lua.fases(DateTime.utc(2026, 11, 1), DateTime.utc(2026, 12, 1));
    final cheia = f.firstWhere((x) => x.fase == FasePrincipal.cheia).quando;
    final nova = f.firstWhere((x) => x.fase == FasePrincipal.nova).quando;
    // Referência: lua nova 09/11/2026 ~07:02 UTC; lua cheia 24/11/2026 ~14:53 UTC.
    expect(nova.difference(DateTime.utc(2026, 11, 9, 7, 2)).inMinutes.abs(), lessThan(30));
    expect(cheia.difference(DateTime.utc(2026, 11, 24, 14, 53)).inMinutes.abs(), lessThan(30));
    expect(Lua.iluminada(DateTime.utc(2026, 11, 24, 15)), greaterThan(0.99));
    expect(Lua.nome(DateTime.utc(2026, 11, 14, 12)), 'Lua crescente');
  });

  test('maré da Ilha Fiscal: mesmos valores do cálculo de referência e da tábua oficial', () {
    final e = EstacaoMare.deJson(File('assets/mare/ilha_fiscal.json').readAsStringSync());
    // Valores do cálculo de referência (fora do app), horário de Brasília (UTC-3).
    expect(e.altura(DateTime.utc(2025, 1, 1, 7, 1)), closeTo(1.2771, 0.0005));
    expect(e.altura(DateTime.utc(2026, 11, 14, 15)), closeTo(0.6509, 0.0005));
    expect(e.altura(DateTime.utc(2030, 6, 1, 3)), closeTo(0.8737, 0.0005));
    // Tábua oficial 2025, 1º de janeiro: 04:01 1,29 m; 10:36 0,42 m; 15:38 1,17 m; 22:49 0,04 m.
    final x = e.extremos(DateTime.utc(2025, 1, 1, 3), DateTime.utc(2025, 1, 2, 3));
    final oficiais = [(4, 1, 1.29), (10, 36, 0.42), (15, 38, 1.17), (22, 49, 0.04)];
    expect(x.length, 4);
    for (var i = 0; i < 4; i++) {
      final o = DateTime.utc(2025, 1, 1, oficiais[i].$1 + 3, oficiais[i].$2);
      expect(x[i].hora.difference(o).inMinutes.abs(), lessThan(20));
      expect(x[i].altura, closeTo(oficiais[i].$3, 0.05));
      // Estofo em volta do horário da maré, com duração razoável.
      expect(x[i].estofoInicio.isBefore(x[i].hora), isTrue);
      expect(x[i].estofoFim.isAfter(x[i].hora), isTrue);
      final duracao = x[i].estofoFim.difference(x[i].estofoInicio).inMinutes;
      expect(duracao, inInclusiveRange(10, 180));
    }
  });

  test('sensação térmica calculada no calor, no frio e no meio-termo', () {
    expect(sensacaoTermica(32, 70, 5), inInclusiveRange(39, 42));
    expect(sensacaoTermica(0, 80, 20), inInclusiveRange(-6, -4.5));
    expect(sensacaoTermica(22, 60, 10), 22);
    expect(sensacaoTermica(null, 60, 10), isNull);
  });

  testWidgets('faixa de alertas junta alerta, sirene e boletim', (tester) async {
    final a = Alerta(
      id: '1',
      descricao: 'Tempestade',
      severidade: 'Perigo Potencial',
      cor: '#FFFF00',
      inicio: DateTime(2026, 11, 13),
      fim: DateTime(2026, 11, 13, 23, 59),
      riscos: const ['Queda de galhos'],
    );
    const sirene = Sirene(nome: 'Morro do Estado', status: 'Acionada');
    expect(FaixaAlertas.temAlerta(const [], const []), isFalse);
    expect(FaixaAlertas.temAlerta([a], const []), isTrue);
    expect(FaixaAlertas.temAlerta(const [], const [sirene]), isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FaixaAlertas(
            alertas: [a],
            sirenesAcionadas: const [sirene],
            boletim: 'Céu nublado com pancadas.',
          ),
        ),
      ),
    ));
    expect(find.text('2 alertas em vigor'), findsOneWidget);
    expect(find.text('Céu nublado com pancadas.'), findsNothing);
    await tester.tap(find.text('2 alertas em vigor'));
    await tester.pump();
    expect(find.text('Céu nublado com pancadas.'), findsOneWidget);
    expect(find.text('Queda de galhos'), findsOneWidget);
    expect(find.text('Sirene acionada: Morro do Estado'), findsOneWidget);
  });

  test('lê a estação do INMET e converte vento para km/h', () {
    const corpo = '{"estacao":{"CODIGO":"A627","NOME":"NITERÓI","DISTANCIA_EM_KM":"7"},'
        '"dados":{"DT_MEDICAO":"2026-11-13","HR_MEDICAO":"0200","TEM_INS":"23.5",'
        '"TEM_SEN":null,"UMD_INS":"97","VEN_VEL":"0.5","VEN_DIR":"23","CHUVA":"0"}}';
    final m = lerEstacaoInmet(corpo)!;
    expect(m.codigo, 'A627');
    expect(m.temperatura, 23.5);
    expect(m.sensacao, isNull);
    expect(m.ventoKmh, closeTo(1.8, 0.001));
    expect(m.hora.toUtc(), DateTime.utc(2026, 11, 13, 2));
  });

  test('Cemaden: "-" vira 0 e hora em UTC', () {
    const corpo = '[{"codibge":3303302,"nomeestacao":"Itaipu","datahoraUltimovalor":"13\\/11\\/26 02:10",'
        '"acc1hr":"-","acc24hr":42.72},{"codibge":1,"nomeestacao":"Outra","datahoraUltimovalor":null}]';
    final l = lerPluviometrosCemaden(corpo, 3303302);
    expect(l, hasLength(1));
    expect(l.first.chuva1h, 0);
    expect(l.first.chuva24h, 42.72);
    expect(l.first.hora!.toUtc(), DateTime.utc(2026, 11, 13, 2, 10));
  });

  test('alertas do INMET filtrados pela cidade', () {
    const corpo = '{"hoje":[{"id_aviso":"1","geocodes":"3303302,3304557","descricao":"Tempestade",'
        '"severidade":"Perigo Potencial","aviso_cor":"#FFFE00","inicio":"2026-11-12 08:50",'
        '"fim":"2026-11-12 23:59","riscos":"[\'Chuva forte\', \'Granizo\']","instrucoes":"None"},'
        '{"id_aviso":"2","geocodes":"5200050","descricao":"Outro","inicio":"2026-11-12 08:50","fim":"2026-11-12 23:59"}],'
        '"futuro":[]}';
    final a = lerAlertasInmet(corpo, 3303302);
    expect(a, hasLength(1));
    expect(a.first.riscos, ['Chuva forte', 'Granizo']);
    expect(a.first.instrucoes, isEmpty);

    const comLista = '{"hoje":[{"id_aviso":"3","geocodes":"3303302","descricao":"Tempestade",'
        '"inicio":"2026-11-12 08:50","fim":"2026-11-12 23:59",'
        '"riscos":["Chuva forte."],"instrucoes":["Evite árvores. ","Ligue 199."]}],"futuro":[]}';
    final b = lerAlertasInmet(comLista, 3303302);
    expect(b.first.riscos, ['Chuva forte.']);
    expect(b.first.instrucoes, ['Evite árvores.', 'Ligue 199.']);
  });

  test('previsão: INMET tem prioridade, CPTEC completa os dias e o UV', () {
    final hoje = DateTime(2026, 11, 12);
    final inmet = [
      DiaPrevisao(dia: hoje, fonte: 'INMET', resumo: 'Nublado', maxima: 32),
      DiaPrevisao(dia: DateTime(2026, 11, 13), fonte: 'INMET', resumo: 'Chuva'),
    ];
    final cptec = [
      DiaPrevisao(dia: DateTime(2026, 11, 13), fonte: 'CPTEC/INPE', resumo: 'Chuva', uv: 7),
      DiaPrevisao(dia: DateTime(2026, 11, 19), fonte: 'CPTEC/INPE', resumo: 'Sol', uv: 11),
    ];
    final r = combinarPrevisoes(inmet, cptec, hoje.add(const Duration(hours: 10)));
    expect(r.map((d) => d.fonte), ['INMET', 'INMET', 'CPTEC/INPE']);
    expect(r[1].uv, 7);
  });


  test('período da chuva: ignora o que já passou e junta os períodos', () {
    final dia = DiaPrevisao(
      dia: DateTime(2026, 11, 13),
      fonte: 'INMET',
      resumo: 'x',
      periodos: const [
        PeriodoPrevisao(nome: 'Manhã', resumo: 'Nublado com pancadas de chuva'),
        PeriodoPrevisao(nome: 'Tarde', resumo: 'Muitas nuvens com pancadas de chuva e trovoadas'),
        PeriodoPrevisao(nome: 'Noite', resumo: 'Muitas nuvens com possibilidade de chuva isolada'),
      ],
    );
    final agora = DateTime(2026, 11, 13, 13);
    final c = proximaChuva([dia], agora)!;
    expect(c.periodos, ['tarde', 'noite']);
    expect(c.certeza, Certeza.prevista);
    expect(fraseChuva(c, agora), 'Chuva prevista hoje à tarde e à noite');
    expect(certezaDaChuva('Muitas nuvens'), Certeza.nenhuma);
    expect(fraseChuva(null, agora, diasConsultados: 6),
        'Sem chuva prevista nos próximos 6 dias');
  });

  test('boletim da Defesa Civil de Niterói', () {
    const html = '<div><pre class="marquee">Hoje chuva a partir da tarde.No sábado (14/11), '
        'chuva na madrugada</pre></div>';
    expect(lerBoletimNiteroi(html),
        'Hoje chuva a partir da tarde. No sábado (14/11), chuva na madrugada.');
    expect(lerBoletimNiteroi('<p>nada</p>'), isNull);
  });

  test('sirenes de Niterói', () {
    const html = 'L.marker([-22.90,-43.09], { icon: redIcon }).addTo(sirenes).bindPopup("<p>'
        '<b>Sirene: </b>Alarico de Souza<br><b>Data: </b><br><b>Status: </b>Desmobilizada</p>");'
        'L.marker([-22.89,-43.10], { icon: redIcon }).addTo(sirenes).bindPopup("<p>'
        '<b>Sirene: </b>Fátima<br><b>Status: </b>Acionada</p>");';
    final s = lerSirenesNiteroi(html);
    expect(s.map((e) => e.nome), ['Alarico de Souza', 'Fátima']);
    expect(s.map((e) => e.acionada), [false, true]);
  });

  test('ondas do CPTEC em UTC', () {
    const xml = "<?xml version='1.0'?><cidade><previsao><dia>13-11-2026 12h Z</dia>"
        '<agitacao>Fraco</agitacao><altura>1.3</altura><direcao>SSE</direcao>'
        '<vento>4.3</vento><vento_dir>NE</vento_dir></previsao></cidade>';
    final o = lerOndasCptec(xml).single;
    expect(o.hora.toUtc(), DateTime.utc(2026, 11, 13, 12));
    expect(o.altura, 1.3);
    expect(o.ventoKmh, 4.3);
  });

  test('vento do aeroporto: o mais próximo, só quando o INMET não tem', () {
    const json = '[{"icaoId":"SBGL","name":"Rio de Janeiro/Galeão Intl, RJ, BR","obsTime":1794574800,'
        '"lat":-22.815,"lon":-43.261,"wdir":340,"wspd":5},'
        '{"icaoId":"SBRJ","name":"Rio de Janeiro/Dumont Arpt, RJ, BR","obsTime":1794574800,'
        '"lat":-22.91,"lon":-43.163,"wdir":"VRB","wspd":10,"wgst":20}]';
    final l = lerVentoAeroportos(json);
    expect(l.map((v) => v.nome), ['Rio de Janeiro/Galeão', 'Rio de Janeiro/Dumont']);
    expect(l[1].ventoKmh, closeTo(18.52, 0.01));
    expect(l[1].variavel, isTrue);
    final agora = DateTime.fromMillisecondsSinceEpoch(1794574800 * 1000).add(const Duration(minutes: 20));
    final semVento = Medicao(fonte: 'INMET', estacao: 'X', codigo: 'A627', hora: agora);
    expect(escolherVentoAeroporto(l, semVento, niteroi, agora)?.codigo, 'SBRJ');
    final comVento = Medicao(
        fonte: 'INMET', estacao: 'X', codigo: 'A627', hora: agora, ventoKmh: 5);
    expect(escolherVentoAeroporto(l, comVento, niteroi, agora), isNull);
  });

  test('Open-Meteo: leitura e regra de quando usar', () {
    const json = '{"current":{"time":"2026-11-13T10:00","temperature_2m":29.7,'
        '"relative_humidity_2m":60,"wind_speed_10m":6.1,"wind_direction_10m":236},'
        '"daily":{"time":["2026-11-13","2026-11-14"],"weather_code":[2,95],'
        '"temperature_2m_max":[30.0,26.2],"temperature_2m_min":[21.9,20.6],'
        '"precipitation_probability_max":[20,75],"uv_index_max":[8.8,6.0]}}';
    final om = lerOpenMeteo(json);
    expect(om.atual!.temperatura, 29.7);
    expect(om.dias.map((d) => d.resumo), ['Parcialmente nublado', 'Trovoada']);
    final agora = DateTime(2026, 11, 13, 10, 30);
    expect(proximaChuva(om.dias, agora)!.dia, DateTime(2026, 11, 14));

    Medicao estacao(double km, DateTime hora) => Medicao(
        fonte: 'INMET', estacao: 'X', codigo: 'A1', hora: hora, distanciaKm: km, temperatura: 25);
    expect(medicaoOficialValida(estacao(7, agora), agora), isTrue);
    expect(medicaoOficialValida(estacao(60, agora), agora), isFalse);
    expect(medicaoOficialValida(estacao(7, agora.subtract(const Duration(hours: 4))), agora),
        isFalse);
  });

  test('UNIFEI: leitura e troca pela estação do INMET em Itajubá', () {
    const json = '{"T":"24.3","H":"73.0","P":"1015.6","W":"3.2","G":"6.4","R":"1.2","A":"27.0",'
        '"B":93,"UV":"8.1","DateTime":1794575702,"offline":0}';
    final u = lerEstacaoUnifei(json)!;
    expect(u.temperatura, 24.3);
    expect(u.chuvaHoje, 1.2);
    expect(u.chuva1h, isNull);
    expect(lerEstacaoUnifei('{"offline":1,"DateTime":1794575702}'), isNull);
    final itajuba = const Cidade(
        nome: 'Itajubá', uf: 'MG', geocode: 3132404, latitude: -22.43, longitude: -45.45);
    final agora = u.hora.add(const Duration(minutes: 5));
    final inmet = Medicao(fonte: 'INMET', estacao: 'MARIA DA FÉ', codigo: 'A531',
        hora: agora.subtract(const Duration(hours: 1)), distanciaKm: 13, temperatura: 21.2);
    final escolhida = escolherEstacaoLocal(u, inmet, itajuba, agora)!;
    expect(escolhida.fonte, 'UNIFEI');
    expect(escolhida.distanciaKm, lessThan(5));
    expect(escolherEstacaoLocal(u, inmet, itajuba, agora.add(const Duration(hours: 4))), isNull);
  });

  test('Região dos Lagos: nome do CPTEC, aeroportos em 2 passos e distância da sede', () {
    const buzios = Cidade(nome: 'Armação dos Búzios', uf: 'RJ', geocode: 3300233,
        latitude: -22.7583, longitude: -41.8862);
    expect(palavraPrincipal(buzios.nome), 'armacao');
    expect(idCptecDaLista({'Armação de Búzios|RJ': 628, 'Armação|PE': 1}, buzios), 628);

    const estacoes = '[{"icaoId":"SBCB","siteType":["METAR","TAF"]},'
        '{"icaoId":"SBES","siteType":["METAR"]},{"icaoId":"XXXX","siteType":["TAF"]}]';
    expect(lerCodigosAeroportos(estacoes), ['SBCB', 'SBES']);

    final arraial = Medicao(fonte: 'INMET', estacao: 'ARRAIAL DO CABO', codigo: 'A606',
        hora: DateTime(2026, 11, 13, 10), distanciaKm: 30, temperatura: 27.4,
        latitude: -22.9755, longitude: -42.0214);
    final cabofrio = comDistanciaDe(arraial, -22.8772, -42.0141);
    expect(cabofrio.distanciaKm, closeTo(11, 1));
  });

  test('chuva por hora do Open-Meteo em UTC', () {
    const json = '{"hourly":{"time":["2026-11-13T17:00","2026-11-13T18:00"],'
        '"precipitation_probability":[59,75],"precipitation":[0.0,0.3],"weather_code":[3,61]}}';
    final h = lerChuvaHoraria(json);
    expect(h, hasLength(2));
    expect(h[0].hora.toUtc(), DateTime.utc(2026, 11, 13, 17));
    expect(h[1].probabilidade, 75);
    expect(h[1].milimetros, 0.3);
  });

  test('trocar de cidade durante uma consulta carrega a cidade nova', () async {
    final repo = Repositorio(http: _HttpLento());
    final primeira = repo.atualizar();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final nova = const Cidade(nome: 'Cabo Frio', uf: 'RJ', geocode: 3300704);
    final troca = repo.trocarCidade(nova);
    await primeira;
    await troca;
    for (var i = 0; i < 50 && repo.carregando; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(repo.cidade, nova);
    expect(repo.carregando, isFalse);
    expect(repo.atualizadoEm, isNotNull);
  });
  test('ícone da caixa Chuva: aberto com chuva, fechado sem chuva', () {
    expect(iconeChuva(0.2), isA<GuardaChuvaAberto>());
    expect((iconeChuva(0) as Icon).icon, Icons.umbrella);
    expect((iconeChuva(null) as Icon).icon, Icons.umbrella);
    expect(simboloTempo('Muitas nuvens com possibilidade de chuva isolada'), isA<NuvemChuva>());
    expect((simboloTempo('Pancadas de chuva e trovoadas') as Icon).icon, Icons.thunderstorm);
    expect((simboloTempo('Céu claro') as Icon).icon, Icons.wb_sunny);
  });
}


/// Fonte falsa: responde vazio depois de um pequeno atraso, sem usar a internet.
class _HttpLento extends HttpCache {
  @override
  Future<RespostaFonte> obter(Uri uri,
      {Encoding codificacao = utf8, Duration limite = const Duration(seconds: 20)}) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    throw FonteIndisponivel('teste');
  }
}
