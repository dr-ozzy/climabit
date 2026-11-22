import 'package:material_ui/material_ui.dart';

import '../dados/erros.dart';
import '../dados/fontes.dart';
import '../dados/repositorio.dart';
import '../util/formatos.dart';

/// Lista com "puxar para atualizar" e largura máxima confortável no tablet.
class ListaAtualizavel extends StatelessWidget {
  const ListaAtualizavel({super.key, required this.repo, required this.children});

  final Repositorio repo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: repo.atualizar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final c in children)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: c,
              ),
            ),
        ],
      ),
    );
  }
}

/// Uma coluna no celular; duas colunas a partir de 700 pontos de largura.
class Colunas extends StatelessWidget {
  const Colunas({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 700) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      }
      final esquerda = <Widget>[];
      final direita = <Widget>[];
      for (var i = 0; i < children.length; i++) {
        (i.isEven ? esquerda : direita).add(children[i]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: esquerda)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: direita)),
        ],
      );
    });
  }
}

class Cartao extends StatelessWidget {
  const Cartao(
      {super.key, required this.titulo, this.icone, this.desenho, required this.children})
      : assert(icone != null || desenho != null);

  final String titulo;
  final IconData? icone;

  /// Ícone desenhado pelo app, no lugar de [icone].
  final Widget? desenho;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconTheme(
                data: IconThemeData(size: 20, color: tema.colorScheme.primary),
                child: desenho ?? Icon(icone),
              ),
              const SizedBox(width: 8),
              Text(titulo, style: tema.textTheme.titleSmall?.copyWith(color: tema.colorScheme.primary)),
            ]),
            const SizedBox(height: 12),
            ..._comFontesJuntas(children),
          ],
        ),
      ),
    );
  }
}

/// Um valor com ícone e rótulo ("Umidade 80 %").
/// Quadrinhos [Dado] em colunas de largura igual (2 no celular, mais no tablet),
/// para que os ícones fiquem alinhados um embaixo do outro.
class GradeDados extends StatelessWidget {
  const GradeDados({super.key, required this.children, this.espaco = 12});

  final List<Widget> children;
  final double espaco;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final colunas = (c.maxWidth / 170).floor().clamp(2, 4);
      double larguraDe(int n) => (c.maxWidth - espaco * (n - 1)) / n;
      bool largo(Widget w) => w is Dado && w.lateral != null;
      // Larguras: quadrinho com círculo ocupa a linha toda; numa sequência de quadrinhos
      // comuns, a última linha incompleta divide a largura entre os que sobraram
      // (assim não fica buraco ao lado de um quadrinho sozinho).
      final larguras = List<double>.filled(children.length, larguraDe(colunas));
      var inicio = 0;
      for (var i = 0; i <= children.length; i++) {
        if (i == children.length || largo(children[i])) {
          final n = i - inicio;
          final resto = n % colunas;
          if (resto > 0) {
            for (var k = i - resto; k < i; k++) {
              larguras[k] = larguraDe(resto);
            }
          }
          if (i < children.length) larguras[i] = c.maxWidth;
          inicio = i + 1;
        }
      }
      return Wrap(
        spacing: espaco,
        runSpacing: espaco,
        children: [
          for (var i = 0; i < children.length; i++)
            SizedBox(width: larguras[i], child: children[i]),
        ],
      );
    });
  }
}

class Dado extends StatelessWidget {
  const Dado(
      {super.key,
      this.icone,
      this.desenho,
      required this.rotulo,
      required this.valor,
      this.detalhe,
      this.corDetalhe,
      this.lateral})
      : assert(icone != null || desenho != null);

  /// Linha pequena embaixo do valor (opcional).
  final String? detalhe;

  /// Cor da linha [detalhe] (avaliação: verde = bom, vermelho = ruim).
  final Color? corDetalhe;

  final IconData? icone;

  /// Ícone desenhado pelo app, no lugar de [icone].
  final Widget? desenho;
  final String rotulo;
  final String valor;

  /// Desenho num círculo à direita. Quando existe, o quadrinho ocupa a
  /// largura inteira na [GradeDados].
  final Widget? lateral;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    // "22 °C" -> "22" grande + "°C" menor. Texto sem número fica inteiro.
    final i = valor.indexOf(' ');
    final temNumero = RegExp(r'\d').hasMatch(i > 0 ? valor.substring(0, i) : valor);
    final principal = temNumero && i > 0 ? valor.substring(0, i) : valor;
    final unidade = temNumero && i > 0 ? valor.substring(i + 1) : '';
    final texto = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconTheme(
          data: IconThemeData(size: 16, color: cores.onSurfaceVariant),
          child: SizedBox(width: 16, height: 16, child: FittedBox(child: desenho ?? Icon(icone))),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(rotulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tema.textTheme.labelLarge?.copyWith(color: cores.onSurfaceVariant)),
        ),
      ]),
      const SizedBox(height: 6),
      Text.rich(TextSpan(children: [
        TextSpan(
            text: principal,
            style: (temNumero ? tema.textTheme.headlineSmall : tema.textTheme.titleLarge)
                ?.copyWith(fontWeight: FontWeight.w500, color: cores.onSurface)),
        if (unidade.isNotEmpty)
          TextSpan(
              text: ' $unidade',
              style: tema.textTheme.titleSmall?.copyWith(color: cores.onSurface)),
      ])),
      if (detalhe != null) ...[
        const SizedBox(height: 2),
        Text(detalhe!,
            style: tema.textTheme.labelLarge?.copyWith(
                color: corDetalhe, fontWeight: corDetalhe != null ? FontWeight.w600 : null)),
      ],
    ]);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cores.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: lateral == null
          ? texto
          : Row(children: [
              Expanded(child: texto),
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: cores.primaryContainer, shape: BoxShape.circle),
                child: IconTheme(
                    data: IconThemeData(size: 30, color: cores.onPrimaryContainer), child: lateral!),
              ),
            ]),
    );
  }
}

/// Origem de um dado. Sozinha, aparece como "Fontes +" (toque para abrir); dentro de um
/// [Cartao], todas as fontes do quadro se juntam num só "Fontes +" no fim.
class Fonte extends StatelessWidget {
  const Fonte(this.texto, {super.key, this.aviso});

  final String texto;

  /// Aviso importante (ex.: "sem conexão: dado guardado"): aparece mesmo fechado.
  final String? aviso;

  @override
  Widget build(BuildContext context) => GrupoFontes(fontes: [this]);
}

/// Junta as [Fonte] do quadro no fim, num único "Fontes +".
List<Widget> _comFontesJuntas(List<Widget> filhos) {
  final fontes = filhos.whereType<Fonte>().toList();
  if (fontes.isEmpty) return filhos;
  final outros = filhos.where((w) => w is! Fonte).toList();
  while (outros.isNotEmpty && outros.last is SizedBox && (outros.last as SizedBox).child == null) {
    outros.removeLast();
  }
  return [...outros, const SizedBox(height: 4), GrupoFontes(fontes: fontes)];
}

/// "Fontes +": fechado mostra só o título (e os avisos); aberto mostra cada origem.
class GrupoFontes extends StatefulWidget {
  const GrupoFontes({super.key, required this.fontes});

  final List<Fonte> fontes;

  @override
  State<GrupoFontes> createState() => _GrupoFontesState();
}

class _GrupoFontesState extends State<GrupoFontes> {
  var _aberto = false;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme.onSurfaceVariant;
    final estilo = tema.textTheme.bodySmall?.copyWith(color: cor);
    final avisos = [for (final f in widget.fontes) if (f.aviso != null) f.aviso!];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _aberto = !_aberto),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Fontes',
                style: tema.textTheme.labelLarge?.copyWith(color: cor)),
            const SizedBox(width: 4),
            Icon(_aberto ? Icons.remove_circle_outline : Icons.add_circle_outline,
                size: 18, color: cor),
          ]),
        ),
      ),
      if (_aberto)
        for (final f in widget.fontes)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
                '${widget.fontes.length > 1 ? '• ' : ''}${f.texto[0].toUpperCase()}${f.texto.substring(1)}',
                style: estilo),
          ),
      for (final a in avisos)
        Text(a, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.error)),
    ]);
  }
}

/// Ordem de gravidade dos avisos do INMET (maior = mais grave).
int gravidadeAlerta(Alerta a) {
  final s = a.severidade.toLowerCase();
  if (s.contains('grande')) return 3;
  if (s.contains('potencial')) return 1;
  if (s.contains('perigo')) return 2;
  return 0;
}

/// Faixa única de alerta no topo da tela Agora. Junta tudo o que é alerta, de qualquer
/// fonte (avisos do INMET, sirenes acionadas da Defesa Civil de Niterói) e, junto, o
/// boletim da Defesa Civil. Só aparece quando há alerta ([temAlerta]).
/// Toque abre e fecha os detalhes.
class FaixaAlertas extends StatefulWidget {
  const FaixaAlertas({
    super.key,
    required this.alertas,
    this.sirenesAcionadas = const [],
    this.boletim,
    this.boletimObtidoEm,
    this.aoVerTodos,
  });

  final List<Alerta> alertas;
  final List<Sirene> sirenesAcionadas;
  final String? boletim;
  final DateTime? boletimObtidoEm;
  final VoidCallback? aoVerTodos;

  static bool temAlerta(List<Alerta> alertas, List<Sirene> sirenesAcionadas) =>
      alertas.isNotEmpty || sirenesAcionadas.isNotEmpty;

  @override
  State<FaixaAlertas> createState() => _FaixaAlertasState();
}

class _FaixaAlertasState extends State<FaixaAlertas> {
  bool _aberto = false;

  @override
  Widget build(BuildContext context) {
    final alertas = [...widget.alertas]
      ..sort((a, b) => gravidadeAlerta(b).compareTo(gravidadeAlerta(a)));
    final sirenes = widget.sirenesAcionadas;
    // Sirene acionada é o caso mais grave: faixa vermelha.
    final cor = sirenes.isNotEmpty
        ? const Color(0xFFD32F2F)
        : alertas.isNotEmpty
            ? corAviso(alertas.first.cor)
            : const Color(0xFFFFEB3B);
    final texto = cor.computeLuminance() > 0.4 ? Colors.black : Colors.white;
    final estilo = TextStyle(color: texto);
    final negrito = TextStyle(color: texto, fontWeight: FontWeight.bold);
    final pequeno = TextStyle(color: texto, fontSize: 12);
    final divisor = Divider(height: 24, color: texto.withValues(alpha: 0.3));

    final itens = <String>[
      if (sirenes.isNotEmpty)
        sirenes.length == 1
            ? 'Sirene acionada: ${sirenes.first.nome}'
            : '${sirenes.length} sirenes acionadas',
      for (final a in alertas) 'Alerta INMET: ${a.descricao}',
    ];
    final titulo = itens.length == 1 ? itens.first : '${itens.length} alertas em vigor';
    final subtitulo = itens.length == 1
        ? (sirenes.isNotEmpty
            ? 'Defesa Civil de Niterói'
            : '${alertas.first.severidade} · até ${quando(alertas.first.fim)}')
        : itens.join(' · ');

    return Card(
      color: cor,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () => setState(() => _aberto = !_aberto),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded, color: texto),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titulo, style: negrito.copyWith(fontSize: 16)),
                  Text(subtitulo, style: estilo),
                ]),
              ),
              Icon(_aberto ? Icons.expand_less : Icons.expand_more, size: 28,
                  color: texto, semanticLabel: _aberto ? 'Fechar detalhes' : 'Abrir detalhes'),
            ]),
            if (_aberto) ...[
              if (sirenes.isNotEmpty) ...[
                divisor,
                Text(
                    sirenes.length == 1
                        ? 'Sirene acionada: ${sirenes.first.nome}'
                        : 'Sirenes acionadas: ${sirenes.map((s) => s.nome).join(', ')}',
                    style: negrito),
                const SizedBox(height: 4),
                Text('Siga para o ponto de apoio mais próximo. Emergência: 199.',
                    style: estilo),
                const SizedBox(height: 4),
                Text('Fonte: Defesa Civil de Niterói', style: pequeno),
              ],
              for (final a in alertas) ...[
                divisor,
                _DetalheAlerta(alerta: a, cor: texto),
              ],
              if (widget.boletim != null) ...[
                divisor,
                Text('Boletim da Defesa Civil de Niterói', style: negrito),
                const SizedBox(height: 4),
                Text(widget.boletim!, style: estilo),
                const SizedBox(height: 4),
                Text(
                    'Fonte: Defesa Civil de Niterói'
                    '${widget.boletimObtidoEm != null ? ' · obtido às ${quando(widget.boletimObtidoEm!)}' : ''}',
                    style: pequeno),
              ],
              if (widget.aoVerTodos != null && alertas.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: widget.aoVerTodos,
                    style: TextButton.styleFrom(foregroundColor: texto),
                    child: const Text('Ver todos os alertas'),
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _DetalheAlerta extends StatelessWidget {
  const _DetalheAlerta({required this.alerta, required this.cor});

  final Alerta alerta;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(color: cor);
    final negrito = TextStyle(color: cor, fontWeight: FontWeight.bold);
    Widget item(String t) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•  ', style: estilo),
            Expanded(child: Text(t, style: estilo)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${alerta.descricao} – ${alerta.severidade}', style: negrito),
      Text('Até ${quando(alerta.fim)}', style: estilo),
      if (alerta.riscos.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('Riscos', style: negrito),
        for (final r in alerta.riscos) item(r),
      ],
      if (alerta.instrucoes.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('O que fazer', style: negrito),
        for (final i in alerta.instrucoes) item(i),
      ],
      const SizedBox(height: 4),
      Text('Fonte: INMET', style: TextStyle(color: cor, fontSize: 12)),
    ]);
  }
}

/// Hora da atualização e fontes com problema.
class RodapeFontes extends StatelessWidget {
  const RodapeFontes({super.key, required this.repo});

  final Repositorio repo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estilo = tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant);
    final problemas = repo.fontes.entries.where((e) => e.value.falhou || e.value.doCache);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(children: [
        if (repo.atualizadoEm != null)
          Text('Atualizado às ${hora(repo.atualizadoEm!)}. Puxe para baixo para atualizar.',
              style: estilo, textAlign: TextAlign.center),
        for (final p in problemas)
          Text(
            p.value.falhou
                ? '${p.key}: ${causaDoErro(p.value.erro)}'
                : '${p.key}: sem conexão, usando dado de ${quando(p.value.obtidoEm!)}',
            style: estilo?.copyWith(color: tema.colorScheme.error),
            textAlign: TextAlign.center,
          ),
      ]),
    );
  }
}

/// "RIO DE JANEIRO - JACAREPAGUÁ" → "Rio de Janeiro - Jacarepaguá".
String tituloProprio(String s) {
  const minusculas = {'de', 'da', 'do', 'das', 'dos', 'e'};
  return s.toLowerCase().split(' ').map((p) {
    if (p.isEmpty || minusculas.contains(p)) return p;
    return p[0].toUpperCase() + p.substring(1);
  }).join(' ');
}
