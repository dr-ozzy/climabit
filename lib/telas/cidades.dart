import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../dados/cidade.dart';
import '../dados/localizacao.dart';
import '../dados/municipios.dart';
import '../dados/preferencias.dart';
import '../dados/repositorio.dart';

/// Escolha da cidade: localização atual, cidades salvas e busca por nome.
class TelaCidades extends StatefulWidget {
  const TelaCidades({super.key, required this.repo, required this.prefs});

  final Repositorio repo;
  final Preferencias prefs;

  @override
  State<TelaCidades> createState() => _TelaCidadesState();
}

class _TelaCidadesState extends State<TelaCidades> {
  final _busca = TextEditingController();
  Municipios? _municipios;
  List<Cidade> _salvas = [];
  bool _localizando = false;

  // Busca pelo CEP (ViaCEP, serviço público e gratuito; só o CEP sai do celular).
  String? _cep;
  Cidade? _cidadeCep;
  String? _erroCep;
  bool _buscandoCep = false;

  /// Só números e hífen, com pelo menos 5 números: o texto é um CEP.
  static String? _soNumerosCep(String t) {
    final limpo = t.trim();
    if (!RegExp(r'^[0-9.\- ]+$').hasMatch(limpo)) return null;
    final n = limpo.replaceAll(RegExp(r'[^0-9]'), '');
    return n.length >= 5 ? n : null;
  }

  void _aoDigitar(String t) {
    setState(() {});
    final n = _soNumerosCep(t);
    if (n != null && n.length == 8 && n != _cep) _buscarCep(n);
  }

  Future<void> _buscarCep(String cep) async {
    setState(() {
      _cep = cep;
      _cidadeCep = null;
      _erroCep = null;
      _buscandoCep = true;
    });
    String? erro;
    Cidade? achada;
    try {
      final r = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 15));
      final j = r.statusCode == 200 ? jsonDecode(utf8.decode(r.bodyBytes)) : null;
      final ibge = j is Map ? int.tryParse('${j['ibge'] ?? ''}') : null;
      achada = ibge == null ? null : _municipios?.porGeocode(ibge);
      if (achada == null) erro = 'CEP não encontrado.';
    } catch (_) {
      erro = 'Não foi possível consultar o CEP agora. Confira a internet.';
    }
    if (!mounted || _cep != cep) return;
    setState(() {
      _cidadeCep = achada;
      _erroCep = erro;
      _buscandoCep = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _salvas = widget.prefs.cidadesSalvas;
    Municipios.carregar().then((m) {
      if (mounted) setState(() => _municipios = m);
    });
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _escolher(Cidade c) async {
    final ja = _salvas.indexWhere((s) => s.geocode == c.geocode);
    if (ja < 0) {
      _salvas = [..._salvas, c];
      await widget.prefs.salvarCidades(_salvas);
    }
    final escolhida = ja >= 0 ? _salvas[ja] : c;
    await widget.prefs.definirCidadeAtual(escolhida);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (escolhida != widget.repo.cidade) widget.repo.trocarCidade(escolhida);
  }

  Future<void> _remover(Cidade c) async {
    if (_salvas.length <= 1) return;
    setState(() => _salvas = _salvas.where((s) => s != c).toList());
    await widget.prefs.salvarCidades(_salvas);
    if (widget.repo.cidade == c) {
      await widget.prefs.definirCidadeAtual(_salvas.first);
      widget.repo.trocarCidade(_salvas.first);
    }
  }

  Future<void> _usarLocalizacao() async {
    final m = _municipios;
    if (m == null) return;
    setState(() => _localizando = true);
    try {
      final (lat, lon) = await Localizacao.obter();
      final c = m.maisProximo(lat, lon);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Sua localização: ${c.rotulo}')));
      await _escolher(c);
    } on ErroLocalizacao catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensagem)));
    } finally {
      if (mounted) setState(() => _localizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final texto = _busca.text;
    final cep = _soNumerosCep(texto);
    final resultados = cep != null ? <Cidade>[] : (_municipios?.buscar(texto) ?? []);
    final atual = widget.repo.cidade;

    return Scaffold(
      appBar: AppBar(title: const Text('Cidades')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              TextField(
                controller: _busca,
                onChanged: _aoDigitar,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Buscar cidade (nome ou CEP)',
                  border: const OutlineInputBorder(),
                  suffixIcon: texto.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(_busca.clear),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              if (cep != null) ...[
                if (cep.length < 8)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Digite os 8 números do CEP.', textAlign: TextAlign.center),
                  )
                else if (_buscandoCep)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_cidadeCep != null)
                  ListTile(
                    leading: const Icon(Icons.markunread_mailbox_outlined),
                    title: Text(_cidadeCep!.nome),
                    subtitle: Text('${_cidadeCep!.uf} · CEP ${cep.substring(0, 5)}-${cep.substring(5)}'),
                    onTap: () => _escolher(_cidadeCep!),
                  )
                else if (_erroCep != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_erroCep!, textAlign: TextAlign.center),
                  ),
                Text('Para buscar pelo CEP, o app envia só o CEP ao ViaCEP (serviço público).',
                    style: tema.textTheme.bodySmall, textAlign: TextAlign.center),
              ] else if (texto.trim().length >= 2) ...[
                if (_municipios == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (resultados.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nenhuma cidade encontrada.', textAlign: TextAlign.center),
                  )
                else
                  for (final c in resultados)
                    ListTile(
                      leading: const Icon(Icons.location_city),
                      title: Text(c.nome),
                      subtitle: Text(c.noCanada ? '${c.uf} · Canadá' : c.uf),
                      onTap: () => _escolher(c),
                    ),
              ] else ...[
                Card(
                  child: ListTile(
                    leading: _localizando
                        ? const SizedBox(
                            width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location),
                    title: const Text('Usar minha localização'),
                    subtitle: const Text(
                        'A posição fica no celular. Às fontes, o app envia só o código da cidade.'),
                    onTap: _localizando ? null : _usarLocalizacao,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Cidades salvas', style: tema.textTheme.titleSmall),
                const SizedBox(height: 4),
                Card(
                  child: Column(children: [
                    for (final c in _salvas)
                      ListTile(
                        leading: Icon(
                          c == atual ? Icons.check_circle : Icons.location_city,
                          color: c == atual ? tema.colorScheme.primary : null,
                        ),
                        title: Text(c.nome),
                        subtitle: Text(
                            '${c.noCanada ? '${c.uf} · Canadá' : c.uf}${c == atual ? ' · mostrando agora' : ''}'),
                        onTap: () => _escolher(c),
                        trailing: _salvas.length > 1
                            ? IconButton(
                                tooltip: 'Remover ${c.nome}',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _remover(c),
                              )
                            : null,
                      ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
