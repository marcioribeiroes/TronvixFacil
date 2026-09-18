/// Captura da tela de entrar, para conferir o visual.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tronvix_facil/main.dart' as app;
import 'package:tronvix_facil/sessao.dart';
import 'package:tronvix_facil/telas/entrar.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> respirar(WidgetTester tester, [int voltas = 10]) async {
    for (var i = 0; i < voltas; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('a tela de entrar', (tester) async {
    await app.prepararApp();
    if (Sessao.instancia.autenticado) await Sessao.instancia.sair();

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: app.AppTronvixFacil.tema,
      home: const TelaEntrar(),
    ));
    await respirar(tester);
    await binding.takeScreenshot('40-entrar');

    await tester.tap(find.text('Criar uma conta'));
    await respirar(tester);
    await binding.takeScreenshot('41-criar-conta');

    expect(find.text('Criar conta'), findsWidgets);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
