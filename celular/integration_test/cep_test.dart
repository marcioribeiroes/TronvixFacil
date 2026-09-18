/// O CEP preenchendo o endereço, na tela de verdade.
///
/// Toca no campo, digita, e confere que os outros campos se preencheram —
/// contra o serviço real. É proposital: o que pode quebrar aqui é o contrato
/// com o ViaCEP mudar, e um teste com resposta fingida nunca perceberia isso.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tronvix_facil/cliente/enderecos.dart';
import 'package:tronvix_facil/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> respirar(WidgetTester tester, [int voltas = 10]) async {
    for (var i = 0; i < voltas; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  String valor(WidgetTester tester, String rotulo) {
    final campo = tester.widget<TextField>(
      find.descendant(
        of: find.ancestor(
          of: find.text(rotulo),
          matching: find.byType(TextFormField),
        ),
        matching: find.byType(TextField),
      ),
    );
    return campo.controller?.text ?? '';
  }

  testWidgets('digitar o CEP preenche rua, bairro, cidade e UF',
      (tester) async {
    await app.prepararApp();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: app.AppTronvixFacil.tema,
      home: const TelaEnderecoFormulario(),
    ));
    await respirar(tester, 4);

    await binding.takeScreenshot('50-endereco-vazio');

    // Um CEP real de Goiânia, o mesmo da Burger House na semente.
    await tester.enterText(find.widgetWithText(TextFormField, 'CEP'), '74210060');
    await respirar(tester, 26);

    expect(valor(tester, 'CEP'), '74210-060',
        reason: 'o campo formata enquanto se digita');
    expect(valor(tester, 'Rua'), isNotEmpty,
        reason: 'a rua não veio do CEP');
    expect(valor(tester, 'Bairro'), 'Setor Bueno');
    expect(valor(tester, 'Cidade'), 'Goiânia');
    expect(valor(tester, 'UF'), 'GO');

    await binding.takeScreenshot('51-endereco-preenchido');

    // CEP que não existe: avisa e deixa digitar.
    //
    // O toque antes de digitar é necessário: depois do preenchimento o foco
    // saltou para "Número", e sem devolver o foco ao CEP o texto cairia lá —
    // que é exatamente o que aconteceu na primeira versão deste teste.
    await tester.tap(find.widgetWithText(TextFormField, 'CEP'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.widgetWithText(TextFormField, 'CEP'), '00000000');
    await respirar(tester, 26);

    await binding.takeScreenshot('52-endereco-cep-nao-achado');
    expect(find.textContaining('Não achei esse CEP'), findsOneWidget,
        reason: 'CEP inexistente precisa dizer isso, e não travar o formulário');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
