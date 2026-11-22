// Gera imagens de fundo dos widgets rodando no emulador (o Windows deste PC bloqueia o
// `flutter test`). Uso:
//   flutter run -t test/gerar_fundos_app.dart -d emulator-5554
// e depois copie os PNGs com `adb shell run-as app.climabit ...` (caminho no log).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:tempo_oficial/telas/ceu.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const temas = {Paisagem.deserto: EstadoCeu.limpo};
  final pasta = Directory('${Directory.systemTemp.path}/fundos')..createSync(recursive: true);
  for (final formato in ['q', 'l']) {
    final tamanho = formato == 'q' ? const Size(180, 180) : const Size(360, 170);
    for (final MapEntry(key: paisagem, value: estado) in temas.entries) {
      for (final noite in [false, true]) {
        final nome = 'ceu_${formato}_tema_${paisagem.name}_${noite ? 'noite' : 'dia'}';
        final gravador = ui.PictureRecorder();
        final canvas = Canvas(gravador)..scale(2);
        PintorCeuPixel(
          estado: estado,
          noite: noite,
          alturaSol: noite ? -30 : 45,
          litoral: false,
          idadeLua: 0.3,
          paisagem: paisagem,
          quadro: ValueNotifier(5),
        ).paint(canvas, tamanho);
        final img = await gravador
            .endRecording()
            .toImage((tamanho.width * 2).round(), (tamanho.height * 2).round());
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${pasta.path}/$nome.png').writeAsBytesSync(png!.buffer.asUint8List());
      }
    }
  }
  debugPrint('FUNDOS_PRONTOS ${pasta.path}');
  runApp(const Directionality(
      textDirection: TextDirection.ltr, child: Center(child: Text('fundos prontos'))));
}
