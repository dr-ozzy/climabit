import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tempo_oficial/telas/componentes.dart';

void main() {
  testWidgets('fontes do quadro ficam juntas em "Fontes +" e abrem ao tocar', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Cartao(titulo: 'Teste', icone: Icons.info, children: [
          Text('valor'),
          Fonte('INMET · estação A627'),
          Fonte('máxima e mínima: previsão INMET', aviso: 'sem conexão: dado guardado'),
        ]),
      ),
    ));
    expect(find.text('Fontes'), findsOneWidget);
    expect(find.textContaining('A627'), findsNothing);
    expect(find.text('sem conexão: dado guardado'), findsOneWidget);
    await t.tap(find.text('Fontes'));
    await t.pump();
    expect(find.textContaining('A627'), findsOneWidget);
    expect(find.textContaining('Máxima e mínima'), findsOneWidget);
  });
}
