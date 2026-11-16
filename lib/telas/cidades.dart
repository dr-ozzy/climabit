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
    final resultados = _municipios?.buscar(texto) ?? [];
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
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Buscar cidade do Brasil',
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
              if (texto.trim().length >= 2) ...[
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
