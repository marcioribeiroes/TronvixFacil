/// Driver que grava as capturas pedidas pelos testes de integração.
///
/// `binding.takeScreenshot(nome)` só entrega os bytes quando existe um driver
/// do outro lado — é ele que escreve o arquivo. Sem isto, a chamada falha e o
/// teste não tem como fotografar o aplicativo de verdade.
///
/// As imagens caem em `capturas/`, que não vai para o Git.
library;

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String nome, List<int> bytes, [Map<String, Object?>? _]) async {
      final pasta = Directory('capturas');
      if (!pasta.existsSync()) pasta.createSync(recursive: true);
      File('capturas/$nome.png').writeAsBytesSync(bytes);
      return true;
    },
  );
}
