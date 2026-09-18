/// O mesmo aplicativo, com outra identidade.
///
/// Prova o que a configuração promete: modo único abre no cardápio de uma loja
/// só, sem vitrine, e as cores vêm de fora. Se este teste passar com um
/// `--dart-define` diferente, o sistema é revendável sem tocar em código.
///
/// Como rodar:
///   flutter drive --driver=test_driver/integration_driver.dart \
///     --target=integration_test/marca_test.dart -d "iPhone 17" \
///     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
///     --dart-define=MODO=unique --dart-define=ESTABELECIMENTO=burger-house \
///     --dart-define=NOME_DA_MARCA="Burger House" \
///     --dart-define=COR_DA_MARCA=0xFF1D4ED8
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tronvix_facil/ambiente.dart';
import 'package:tronvix_facil/main.dart' as app;
import 'package:tronvix_facil/tema.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> esperar(WidgetTester tester, Finder alvo,
      {Duration limite = const Duration(seconds: 25)}) async {
    final fim = DateTime.now().add(limite);
    while (DateTime.now().isBefore(fim)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (alvo.evaluate().isNotEmpty) return;
    }
  }

  testWidgets('modo único abre no cardápio da loja, com a cor configurada',
      (tester) async {
    expect(Ambiente.unico, isTrue,
        reason: 'rode com --dart-define=MODO=unique');
    expect(Ambiente.estabelecimento, isNotEmpty,
        reason: 'rode com --dart-define=ESTABELECIMENTO=<slug>');

    await app.prepararApp();
    await tester.pumpWidget(const app.AppTronvixFacil());

    // Sem vitrine: nada de "O que você quer comer?" nem de outra loja.
    await esperar(tester, find.textContaining('X-'));
    expect(find.text('O que você quer comer?'), findsNothing,
        reason: 'o modo único não tem vitrine');
    expect(find.text('Pizzaria do Chef'), findsNothing,
        reason: 'o modo único não mostra outro estabelecimento');

    // A aba mudou de nome junto com o modo.
    expect(find.text('Cardápio'), findsWidgets);
    expect(find.text('Descobrir'), findsNothing);

    // E a cor da marca é a que entrou pela linha de comando.
    expect(Cores.marca, const Color(Ambiente.corDaMarca));

    // Deixa o quadro pintar antes de fotografar: `esperar` devolve assim que o
    // widget existe na árvore, e existir não é o mesmo que estar desenhado.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await binding.takeScreenshot('30-modo-unico');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
