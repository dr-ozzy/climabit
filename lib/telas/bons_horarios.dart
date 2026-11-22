import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dados/atividades.dart';
import '../dados/fontes.dart';
import 'componentes.dart';

const _chaveAtividade = 'atividade_escolhida';
const _chaveRotinas = 'rotinas';
const _diasCurtos = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

Color corNota(Nota n) => switch (n) {
      Nota.boa => const Color(0xFF2E9D46),
      Nota.regular => const Color(0xFFE0A100),
      Nota.ruim => const Color(0xFF9E9E9E),
    };

String _hora(DateTime t) => '${t.hour}h';

/// Cartão "Bons horários": para a atividade escolhida, marca as próximas 24 horas como boas,
/// regulares ou ruins, e mostra as rotinas salvas (dia da semana e horário fixos).
/// Tudo fica guardado no aparelho.
class CartaoBonsHorarios extends StatefulWidget {
  const CartaoBonsHorarios({super.key, required this.horas, required this.horasSemana});

  /// Próximas 24 horas.
  final List<HoraChuva> horas;

  /// Próximos 7 dias, hora a hora (para as rotinas).
  final List<HoraChuva> horasSemana;

  @override
  State<CartaoBonsHorarios> createState() => _CartaoBonsHorariosState();
}

class _CartaoBonsHorariosState extends State<CartaoBonsHorarios> {
  Atividade _atividade = Atividade.caminhar;
  List<Rotina> _rotinas = [];

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _atividade = Atividade.deNome(p.getString(_chaveAtividade));
        _rotinas = Rotina.lerLista(p.getString(_chaveRotinas));
      });
    });
  }

  Future<void> _escolher(Atividade a) async {
    setState(() => _atividade = a);
    (await SharedPreferences.getInstance()).setString(_chaveAtividade, a.name);
  }

  Future<void> _gravarRotinas() async =>
      (await SharedPreferences.getInstance()).setString(_chaveRotinas, Rotina.gravarLista(_rotinas));

  Future<void> _novaRotina() async {
    final r = await showDialog<Rotina>(
      context: context,
      builder: (_) => _DialogoRotina(atividade: _atividade),
    );
    if (r == null) return;
    setState(() => _rotinas = [..._rotinas, r]);
    await _gravarRotinas();
  }

  Future<void> _apagar(Rotina r) async {
    setState(() => _rotinas = [..._rotinas]..remove(r));
    await _gravarRotinas();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final agora = DateTime.now();
    final avaliacoes = [for (final h in widget.horas.take(24)) avaliarHora(_atividade, h)];
    final bons = trechosBons(avaliacoes);
    // O que atrapalha: o que deixou alguma hora ruim, juntando os horários.
    final atrapalha = resumirMotivos(avaliacoes, soRuins: true);

    return Cartao(
      titulo: 'Bons horários',
      icone: Icons.directions_walk,
      children: [
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final a in Atividade.values)
            ChoiceChip(
              label: Text(a.nome),
              selected: a == _atividade,
              onSelected: (_) => _escolher(a),
            ),
        ]),
        const SizedBox(height: 12),
        if (avaliacoes.isNotEmpty) ...[
          _Faixa(avaliacoes: avaliacoes),
          const SizedBox(height: 10),
          Text(
            bons.isEmpty
                ? 'Nenhum horário bom para ${_atividade.nome.toLowerCase()} nas próximas 24 horas.'
                : 'Bons horários para ${_atividade.nome.toLowerCase()}: '
                    '${bons.map((t) => '${_hora(t.$1)}–${_hora(t.$2)}').join(', ')}',
            style: tema.textTheme.titleSmall,
          ),
          if (atrapalha.isNotEmpty)
            Text('O que atrapalha: ${atrapalha.join(', ')}.',
                style: tema.textTheme.bodySmall),
        ],
        const SizedBox(height: 14),
        Text('Minhas rotinas', style: tema.textTheme.titleSmall),
        if (_rotinas.isEmpty)
          Text('Salve uma atividade que você faz sempre no mesmo horário para ver como '
              'vai estar o tempo na próxima vez.', style: tema.textTheme.bodySmall),
        for (final r in _rotinas) _LinhaRotina(rotina: r, horas: widget.horasSemana, agora: agora,
            aoApagar: () => _apagar(r)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _novaRotina,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar rotina'),
          ),
        ),
        const Fonte('regras simples do app aplicadas à previsão por hora (estimativa de '
            'modelo): chuva, sensação térmica, vento, índice UV e dia/noite. Verde = bom, '
            'amarelo = dá, mas com cuidado, cinza = ruim.'),
      ],
    );
  }
}

/// 24 quadradinhos coloridos, com a hora a cada 3 horas.
class _Faixa extends StatelessWidget {
  const _Faixa({required this.avaliacoes});
  final List<AvaliacaoHora> avaliacoes;

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.labelSmall;
    return Column(children: [
      Row(children: [
        for (final a in avaliacoes)
          Expanded(
            child: Container(
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 0.5),
              decoration: BoxDecoration(
                color: corNota(a.nota),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 2),
      Row(children: [
        for (var i = 0; i < avaliacoes.length; i++)
          Expanded(
            child: i % 3 == 0
                ? Text(_hora(avaliacoes[i].hora), style: estilo, softWrap: false,
                    overflow: TextOverflow.visible)
                : const SizedBox.shrink(),
          ),
      ]),
    ]);
  }
}

class _LinhaRotina extends StatelessWidget {
  const _LinhaRotina({
    required this.rotina,
    required this.horas,
    required this.agora,
    required this.aoApagar,
  });

  final Rotina rotina;
  final List<HoraChuva> horas;
  final DateTime agora;
  final VoidCallback aoApagar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final r = rotina;
    final dias = (r.dias.toList()..sort()).map((d) => _diasCurtos[d - 1]).join(', ');
    final proxima = r.proxima(agora);
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final diaProx = DateTime(proxima.year, proxima.month, proxima.day);
    final quando = diaProx == hoje
        ? 'hoje'
        : diaProx == hoje.add(const Duration(days: 1))
            ? 'amanhã'
            : '${_diasCurtos[proxima.weekday - 1]} ${proxima.day}/${proxima.month}';
    final av = avaliarRotina(r, horas, agora);
    final String situacao;
    final Color cor;
    if (av == null) {
      final ultima = horas.isEmpty ? null : horas.last.hora;
      situacao = ultima == null
          ? 'sem previsão por hora agora'
          : 'previsão ainda não chega lá (vai até ${_diasCurtos[ultima.weekday - 1]} '
              '${ultima.day}/${ultima.month})';
      cor = tema.colorScheme.outline;
    } else {
      final (nota, motivos) = av;
      final nome = switch (nota) {
        Nota.boa => 'bom',
        Nota.regular => 'dá, com cuidado',
        Nota.ruim => 'ruim',
      };
      situacao = motivos.isEmpty ? nome : '$nome: ${motivos.take(3).join(', ')}';
      cor = corNota(nota);
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(Icons.circle, color: cor, size: 14),
      title: Text('${r.atividade.nome} · $dias · ${r.inicio}h–${r.fim}h'),
      subtitle: Text('Próxima: $quando, $situacao'),
      trailing: IconButton(
        tooltip: 'Apagar rotina',
        icon: const Icon(Icons.delete_outline),
        onPressed: aoApagar,
      ),
    );
  }
}

class _DialogoRotina extends StatefulWidget {
  const _DialogoRotina({required this.atividade});
  final Atividade atividade;

  @override
  State<_DialogoRotina> createState() => _DialogoRotinaState();
}

class _DialogoRotinaState extends State<_DialogoRotina> {
  late Atividade _atividade = widget.atividade;
  final _dias = <int>{1, 3, 5};
  int _inicio = 6;
  int _fim = 7;

  @override
  Widget build(BuildContext context) {
    final valido = _dias.isNotEmpty && _fim > _inicio;
    return AlertDialog(
      title: const Text('Nova rotina'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          DropdownButton<Atividade>(
            value: _atividade,
            isExpanded: true,
            items: [
              for (final a in Atividade.values) DropdownMenuItem(value: a, child: Text(a.nome)),
            ],
            onChanged: (a) => setState(() => _atividade = a ?? _atividade),
          ),
          const SizedBox(height: 8),
          const Text('Dias'),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(_diasCurtos[d - 1]),
                selected: _dias.contains(d),
                onSelected: (s) => setState(() => s ? _dias.add(d) : _dias.remove(d)),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Das '),
            DropdownButton<int>(
              value: _inicio,
              items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h}h'))],
              onChanged: (h) => setState(() {
                _inicio = h ?? _inicio;
                if (_fim <= _inicio) _fim = _inicio + 1;
              }),
            ),
            const Text(' às '),
            DropdownButton<int>(
              value: _fim,
              items: [for (var h = 1; h <= 24; h++) DropdownMenuItem(value: h, child: Text('${h}h'))],
              onChanged: (h) => setState(() => _fim = h ?? _fim),
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: valido
              ? () => Navigator.pop(
                  context,
                  Rotina(atividade: _atividade, dias: {..._dias}, inicio: _inicio, fim: _fim))
              : null,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
