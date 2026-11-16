// Gera as imagens de fundo dos widgets da tela inicial (pixel art parado).
// Não roda com os testes comuns. Para gerar de novo:
//   flutter test --update-goldens test/gerar_fundos_widget.dart
// e copie test/fundos_widget/*.png para android/app/src/main/res/drawable-nodpi/.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tempo_oficial/telas/ceu.dart';

void main() {
  testWidgets('fundos dos widgets', (t) async {
    t.view.devicePixelRatio = 2;
    for (final formato in ['q', 'l']) {
      final tamanho = formato == 'q' ? const Size(180, 180) : const Size(360, 170);
      t.view.physicalSize = tamanho * 2;
      // Cenários do tipo de dia (um estado de céu típico para cada).
      const temas = {
        Paisagem.campo: EstadoCeu.parcial,
        Paisagem.vulcao: EstadoCeu.limpo,
        Paisagem.cachoeiras: EstadoCeu.chuva,
        Paisagem.neve: EstadoCeu.nublado,
      };
      for (final MapEntry(key: paisagem, value: estado) in temas.entries) {
        for (final noite in [false, true]) {
          final nome = 'ceu_${formato}_tema_${paisagem.name}_${noite ? 'noite' : 'dia'}';
          await t.pumpWidget(Center(
            child: RepaintBoundary(
              key: const Key('f'),
              child: SizedBox.fromSize(
                size: tamanho,
                child: CustomPaint(
                  painter: PintorCeuPixel(
                    estado: noite && estado == EstadoCeu.parcial ? EstadoCeu.limpo : estado,
                    noite: noite,
                    alturaSol: noite ? -30 : 45,
                    litoral: false,
                    idadeLua: 0.3,
                    paisagem: paisagem,
                    quadro: ValueNotifier(5),
                  ),
                ),
              ),
            ),
          ));
          await expectLater(find.byKey(const Key('f')), matchesGoldenFile('fundos_widget/$nome.png'));
        }
      }
      for (final estado in EstadoCeu.values) {
        for (final hora in ['dia', 'noite', 'tarde']) {
          if (hora == 'tarde' && estado != EstadoCeu.limpo && estado != EstadoCeu.parcial) continue;
          for (final local in ['mar', 'campo']) {
            final nome = 'ceu_${formato}_${estado.name}_${hora}_$local';
            await t.pumpWidget(Center(
              child: RepaintBoundary(
                key: const Key('f'),
                child: SizedBox.fromSize(
                  size: tamanho,
                  child: CustomPaint(
                    painter: PintorCeuPixel(
                      estado: estado,
                      noite: hora == 'noite',
                      alturaSol: hora == 'tarde' ? 3 : (hora == 'noite' ? -30 : 45),
                      litoral: local == 'mar',
                      idadeLua: 0.3,
                      quadro: ValueNotifier(estado == EstadoCeu.trovoada ? 1 : 5),
                    ),
                  ),
                ),
              ),
            ));
            await expectLater(find.byKey(const Key('f')), matchesGoldenFile('fundos_widget/$nome.png'));
          }
        }
      }
    }
  });
}
