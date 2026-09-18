/// Em qual tela o aplicativo abre.
///
/// A pergunta parece boba até alguém ter dois papéis. Quem é dono de
/// restaurante também pede comida — e abria direto no balcão, sem conseguir
/// nem ver a vitrine do próprio produto.
///
/// Este aplicativo é, antes de tudo, o de quem pede. É ele que vai para a loja
/// de aplicativos, e é a vitrine que um cliente novo precisa ver primeiro.
///
/// Como rodar:
///   ./testar-no-aparelho.sh -d "iPhone 17 Pro" integration_test/abertura_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tronvix_facil/main.dart' as app;
import 'package:tronvix_facil/sessao.dart';

/// Dono da Burger House na semente: tem loja E é cliente.
const _dono = 'dono@burgerhouse.com.br';
const _senha = 'tronvix123';

Future<void> assentar(WidgetTester tester, [int voltas = 12]) async {
  for (var i = 0; i < voltas; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('quem tem restaurante ainda abre como cliente', (tester) async {
    await app.prepararApp();

    if (Sessao.instancia.autenticado &&
        Sessao.instancia.perfil?.email != _dono) {
      await Sessao.instancia.sair();
    }
    if (!Sessao.instancia.autenticado) {
      await Sessao.instancia.entrar(_dono, _senha);
    }

    await tester.pumpWidget(const app.AppTronvixFacil());
    await assentar(tester, 20);

    expect(Sessao.instancia.vinculo, isNotNull,
        reason: 'o roteiro precisa de alguém que tenha loja');

    expect(Sessao.instancia.fluxo, Fluxo.cliente,
        reason: 'o dono de restaurante deve abrir na vitrine, não no balcão');

    expect(Sessao.instancia.fluxosDisponiveis, contains(Fluxo.restaurante),
        reason: 'e o balcão precisa continuar ao alcance de um toque');

    // Trocar leva ao balcão, e a escolha passa a valer.
    Sessao.instancia.trocarDeFluxo(Fluxo.restaurante);
    await assentar(tester);
    expect(Sessao.instancia.fluxo, Fluxo.restaurante);

    // E voltar devolve à vitrine.
    Sessao.instancia.trocarDeFluxo(Fluxo.cliente);
    await assentar(tester);
    expect(Sessao.instancia.fluxo, Fluxo.cliente);
  });
}
