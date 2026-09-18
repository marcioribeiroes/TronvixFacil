/// Um passeio pelas telas, fotografando cada uma.
///
/// Serve para duas coisas, e as duas importam: conferir que a navegação
/// funciona tocando nos widgets de verdade, e produzir imagens do aplicativo
/// rodando contra dados reais — para manual, para revisão, para mostrar a
/// alguém sem precisar instalar nada.
///
/// Como rodar:
///   ./passear.sh -d "iPhone 17"
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tronvix_facil/dados/balcao.dart';
import 'package:tronvix_facil/dados/carrinho.dart';
import 'package:tronvix_facil/dados/corridas.dart';
import 'package:tronvix_facil/dados/enderecos.dart';
import 'package:tronvix_facil/dados/supabase.dart';
import 'package:tronvix_facil/modelos/modelos.dart';
import 'package:tronvix_facil/main.dart' as app;
import 'package:tronvix_facil/sessao.dart';

const _email = 'cliente@tronvixfacil.com.br';
const _senha = 'tronvix123';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> esperar(WidgetTester tester, Finder alvo,
      {Duration limite = const Duration(seconds: 20)}) async {
    final fim = DateTime.now().add(limite);
    while (DateTime.now().isBefore(fim)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (alvo.evaluate().isNotEmpty) return;
    }
  }

  Future<void> respirar(WidgetTester tester, [int voltas = 8]) async {
    for (var i = 0; i < voltas; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('passeio pelas telas do cliente', (tester) async {
    await app.prepararApp();

    if (!Sessao.instancia.autenticado) {
      await Sessao.instancia.entrar(_email, _senha);
    }
    await Carrinho.instancia.carregar();
    if (!Carrinho.instancia.vazio) await Carrinho.instancia.esvaziar();

    // O passeio monta o proprio cenario. Depender do estado deixado por outra
    // execucao e como um teste passa numa maquina e falha na seguinte — e foi
    // o que aconteceu no primeiro banco recriado do zero.
    if ((await Enderecos.meus()).isEmpty) {
      await banco.from('addresses').insert({
        'user_id': usuarioId,
        'label': 'Casa',
        'street': 'Rua T 30',
        'number': '120',
        'district': 'Setor Bueno',
        'city': 'Goiânia',
        'state': 'GO',
        // CEP real, conferido no ViaCEP: a demonstração precisa sobreviver a
        // alguém digitá-lo no cadastro de endereço.
        'postal_code': '74210060',
        'is_default': true,
        // Perto da Burger House da semente: o mapa do entregador precisa dos
        // dois alfinetes para valer alguma coisa.
        'latitude': -16.7020,
        'longitude': -49.2700,
      });
    }

    await tester.pumpWidget(const app.AppTronvixFacil());

    // --- vitrine ----------------------------------------------------------
    await esperar(tester, find.text('Burger House'));
    await binding.takeScreenshot('01-vitrine');

    // --- cardápio ---------------------------------------------------------
    await tester.tap(find.text('Burger House'));
    await respirar(tester);
    await esperar(tester, find.textContaining('X-'));
    await binding.takeScreenshot('02-cardapio');

    // --- produto ----------------------------------------------------------
    // O X-Tudo é o que tem grupo de adicionais no cardápio de demonstração, e
    // é caro o bastante para passar do pedido mínimo com duas unidades.
    await tester.scrollUntilVisible(find.text('X-Tudo'), 200,
        scrollable: find.byType(Scrollable).first);
    await respirar(tester, 4);
    await tester.tap(find.text('X-Tudo'));
    await respirar(tester);
    await esperar(tester, find.text('Adicionar ao carrinho'));
    await binding.takeScreenshot('03-produto');

    // Grupo obrigatório: escolher é o que a tela exige antes de deixar
    // adicionar — e é o que fechar_pedido exige depois.
    final opcoes = find.byType(RadioListTile<String>);
    if (opcoes.evaluate().isNotEmpty) {
      await tester.tap(opcoes.first);
      await respirar(tester, 4);
      await binding.takeScreenshot('04-produto-com-adicional');
    }

    // Duas unidades, para passar do pedido mínimo de R$ 20,00.
    await tester.tap(find.byIcon(Icons.add).last);
    await respirar(tester, 4);

    await tester.tap(find.text('Adicionar ao carrinho'));
    await respirar(tester, 16);

    // --- carrinho ---------------------------------------------------------
    // A barra do carrinho vive na tela de baixo, não no cardápio: é preciso
    // voltar antes de tocá-la.
    await tester.pageBack();
    await respirar(tester, 10);

    await esperar(tester, find.byKey(const Key('barra-do-carrinho')));
    await binding.takeScreenshot('05-vitrine-com-carrinho');

    await tester.tap(find.byKey(const Key('barra-do-carrinho')));
    await respirar(tester, 12);
    await esperar(tester, find.text('Continuar'));
    await binding.takeScreenshot('06-carrinho');

    // --- checkout ---------------------------------------------------------
    await tester.tap(find.text('Continuar'));
    await respirar(tester, 16);
    await esperar(tester, find.textContaining('Fazer pedido'));
    await binding.takeScreenshot('07-checkout');

    expect(find.textContaining('Fazer pedido'), findsOneWidget);

    // --- pedido feito -----------------------------------------------------
    await tester.tap(find.textContaining('Fazer pedido'));
    await respirar(tester, 20);
    await esperar(tester, find.text('Pedido enviado'),
        limite: const Duration(seconds: 30));
    await binding.takeScreenshot('08-acompanhar');

    // Aparece duas vezes: na faixa de comemoração e como primeira etapa da
    // trilha. As duas dizem a mesma coisa para públicos diferentes de atenção.
    expect(find.text('Pedido enviado'), findsWidgets,
        reason: 'o pedido não foi fechado');
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('passeio pelo balcão', (tester) async {
    await app.prepararApp();

    // Sair antes: a sessão do cliente ficou gravada no aparelho pelo teste
    // anterior, e o fluxo que abre depende de quem está autenticado.
    if (Sessao.instancia.autenticado) await Sessao.instancia.sair();
    await Sessao.instancia.entrar('dono@burgerhouse.com.br', 'tronvix123');

    expect(Sessao.instancia.vinculo, isNotNull,
        reason: 'o dono precisa ter vínculo com o estabelecimento');
    expect(Sessao.instancia.fluxo, Fluxo.restaurante,
        reason: 'quem tem vínculo com um estabelecimento abre no balcão');

    await tester.pumpWidget(const app.AppTronvixFacil());
    await esperar(tester, find.text('Burger House'),
        limite: const Duration(seconds: 30));
    await respirar(tester, 12);
    await binding.takeScreenshot('10-balcao');

    // O pedido feito no passeio anterior tem de estar na fila — é a prova de
    // que o que o cliente enviou chegou a quem prepara.
    expect(find.textContaining('nº '), findsWidgets,
        reason: 'a fila do balcão está vazia');

    await tester.tap(find.textContaining('nº ').first);
    await respirar(tester, 12);
    await binding.takeScreenshot('11-balcao-pedido');
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('passeio pelo aplicativo de entregas', (tester) async {
    await app.prepararApp();

    // --- o balcão despacha ------------------------------------------------
    // Feito pela camada de dados, não tocando na tela: o que esta prova
    // interessa é o que o entregador vê, e o caminho do balcão já foi
    // verificado no passeio anterior.
    if (Sessao.instancia.autenticado) await Sessao.instancia.sair();
    await Sessao.instancia.entrar('dono@burgerhouse.com.br', 'tronvix123');

    final restauranteId = Sessao.instancia.vinculo!.restauranteId;
    var fila = await Balcao.fila(restauranteId);
    expect(fila, isNotEmpty, reason: 'nada na fila para despachar');

    var pedido = fila.first;
    while (pedido.status != StatusDoPedido.saiuParaEntrega) {
      final passo = Balcao.proximoPasso(pedido);
      if (passo == null || passo == StatusDoPedido.entregue) break;
      await Balcao.avancar(pedido, passo);
      fila = await Balcao.fila(restauranteId);
      pedido = fila.firstWhere((p) => p.id == pedido.id);
    }

    expect(pedido.status, StatusDoPedido.saiuParaEntrega,
        reason: 'o pedido não chegou a ser despachado');

    // --- o entregador ------------------------------------------------------
    await Sessao.instancia.sair();
    await Sessao.instancia.entrar('entregador@tronvixfacil.com.br', 'tronvix123');


    final eu = Sessao.instancia.entregador;
    expect(eu, isNotNull, reason: 'o entregador precisa ter cadastro');
    expect(eu!.restauranteId, isNotNull,
        reason: 'o entregador é DE um estabelecimento, não da plataforma');
    expect(Sessao.instancia.fluxo, Fluxo.entregador);

    // Disponível, senão a fila não faz sentido na tela.
    await Corridas.mudarDisponibilidade(
        eu.id, DisponibilidadeDoEntregador.online);
    await Sessao.instancia.carregar();

    final disponiveis = await Corridas.disponiveis();
    expect(disponiveis, isNotEmpty,
        reason: 'a corrida despachada não chegou ao entregador do estabelecimento');

    expect(disponiveis.first.ondeRetirar, isNotNull,
        reason: 'sem coordenada da loja não há alfinete no mapa');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(const app.AppTronvixFacil());

    await esperar(tester, find.textContaining('corrida'),
        limite: const Duration(seconds: 30));
    await respirar(tester, 30);
    await binding.takeScreenshot('20-entregas-mapa');

    // --- a corrida ---------------------------------------------------------
    await tester.tap(find.text('Burger House').last);
    await respirar(tester, 20);
    await esperar(tester, find.text('Aceitar corrida'));
    await binding.takeScreenshot('21-corrida');

    expect(find.text('Aceitar corrida'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
