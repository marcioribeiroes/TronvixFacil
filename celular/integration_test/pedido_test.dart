/// Um pedido de ponta a ponta, no aplicativo de verdade, contra o Supabase de
/// verdade.
///
/// Não é teste de widget: sobe o aplicativo inteiro, entra com um usuário de
/// demonstração, monta um pedido e confere que o **banco** devolveu um pedido
/// com os valores certos. É o único teste que prova a frase que sustenta o
/// projeto — "o preço não vem do aplicativo" — no caminho real.
///
/// Como rodar:
///   flutter test integration_test/pedido_test.dart \
///     -d `<simulador>` \
///     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
///
/// Ou, mais simples, com as chaves do projeto:
///   ./testar-no-aparelho.sh -d "iPhone 17"
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tronvix_facil/dados/carrinho.dart';
import 'package:tronvix_facil/dados/pedidos.dart';
import 'package:tronvix_facil/dados/supabase.dart';
import 'package:tronvix_facil/main.dart' as app;
import 'package:tronvix_facil/modelos/modelos.dart';
import 'package:tronvix_facil/sessao.dart';

const _email = 'cliente@tronvixfacil.com.br';
const _senha = 'tronvix123';

/// Bombeia até o finder encontrar alguma coisa, ou desiste.
///
/// Esperar um número fixo de quadros é aposta: a rede do dia bom responde em
/// 300 ms e a do dia ruim em 3 s, e o teste que passa numa não passa na outra.
Future<void> esperarPor(
  WidgetTester tester,
  Finder alvo, {
  Duration limite = const Duration(seconds: 20),
}) async {
  final fim = DateTime.now().add(limite);
  while (DateTime.now().isBefore(fim)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (alvo.evaluate().isNotEmpty) return;
  }
}

Future<void> assentar(WidgetTester tester, [int voltas = 12]) async {
  // pumpAndSettle não serve aqui: a tela fica com um indicador de progresso
  // girando enquanto a rede responde, e girar para sempre é exatamente o que
  // ele faz. Bombear com intervalo espera a rede sem travar o teste.
  for (var i = 0; i < voltas; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('do cardápio ao pedido gravado', (tester) async {
    await app.prepararApp();
    await tester.pumpWidget(const app.AppTronvixFacil());
    await assentar(tester, 20);

    // --- entra ------------------------------------------------------------
    if (!Sessao.instancia.autenticado) {
      await Sessao.instancia.entrar(_email, _senha);
      await assentar(tester, 20);
    }
    expect(Sessao.instancia.autenticado, isTrue,
        reason: 'não entrou com o usuário de demonstração');

    // Um carrinho deixado por uma execução anterior atrapalharia a conta.
    await Carrinho.instancia.carregar();
    if (!Carrinho.instancia.vazio) await Carrinho.instancia.esvaziar();

    // --- monta o pedido ---------------------------------------------------
    final restaurantes = await banco
        .from('restaurants')
        .select()
        .eq('status', 'approved')
        .eq('is_open', true)
        .limit(1);
    expect(restaurantes, isNotEmpty, reason: 'nenhum estabelecimento aberto');
    final restaurante = Restaurante.deMapa(restaurantes.first);

    final produtos = await banco
        .from('products')
        .select()
        .eq('restaurant_id', restaurante.id)
        .eq('is_available', true)
        .limit(1);
    expect(produtos, isNotEmpty, reason: 'cardápio vazio');
    final produto = Produto.deMapa(produtos.first);

    // Grupo obrigatório precisa de escolha — é o banco que exige, em
    // fechar_pedido, e o teste passa pelo mesmo caminho do aplicativo.
    final grupos = await banco
        .from('addon_groups')
        .select('*, addons(*)')
        .eq('product_id', produto.id)
        .eq('is_active', true);

    final escolhidos = <AdicionalEscolhido>[];
    for (final g in grupos.map(GrupoDeAdicionais.deMapa)) {
      for (var i = 0; i < g.minimo && i < g.adicionais.length; i++) {
        escolhidos.add(AdicionalEscolhido(adicional: g.adicionais[i]));
      }
    }

    final adicionaisCentavos =
        escolhidos.fold<int>(0, (s, a) => s + a.totalCentavos);
    final unitario = produto.precoQueVale + adicionaisCentavos;

    // Quantidade suficiente para passar do pedido mínimo do estabelecimento —
    // senão o banco recusa, com razão, e o teste mede a coisa errada.
    final quantidade = restaurante.pedidoMinimoCentavos <= unitario
        ? 2
        : ((restaurante.pedidoMinimoCentavos + unitario - 1) ~/ unitario)
            .clamp(2, 99);

    await Carrinho.instancia.adicionar(
      restaurante: restaurante,
      produto: produto,
      quantidade: quantidade,
      adicionais: escolhidos,
      observacao: 'Teste de integração',
    );
    await assentar(tester);

    expect(Carrinho.instancia.quantidadeDeItens, quantidade);

    final subtotalEsperado = unitario * quantidade;
    expect(Carrinho.instancia.subtotalCentavos, subtotalEsperado,
        reason: 'a conta da tela divergiu do cardápio');

    // --- endereço ---------------------------------------------------------
    final enderecos = await banco
        .from('addresses')
        .select()
        .eq('user_id', usuarioId!)
        .isFilter('deleted_at', null)
        .limit(1);

    final enderecoId = enderecos.isNotEmpty
        ? enderecos.first['id'] as String
        : (await banco
            .from('addresses')
            .insert({
              'user_id': usuarioId,
              'label': 'Teste',
              'street': 'Rua das Flores',
              'number': '100',
              'district': 'Centro',
              'city': 'Vitória',
              'state': 'ES',
              'postal_code': '29010000',
            })
            .select('id')
            .single())['id'] as String;

    // --- fecha ------------------------------------------------------------
    final pedido = await Pedidos.fechar(
      carrinhoId: Carrinho.instancia.id!,
      tipo: TipoDeEntrega.entrega,
      forma: FormaDePagamento.dinheiro,
      momento: MomentoDoPagamento.naEntrega,
      enderecoId: enderecoId,
    );
    Carrinho.instancia.esquecer();
    await assentar(tester);

    // --- o que o banco gravou --------------------------------------------
    expect(pedido.subtotalCentavos, subtotalEsperado,
        reason: 'o banco recalculou um subtotal diferente do cardápio');

    final taxaEsperada = restaurante.taxaPara(subtotalEsperado);
    expect(pedido.taxaDeEntregaCentavos, taxaEsperada);
    expect(pedido.totalCentavos,
        pedido.subtotalCentavos + pedido.taxaDeEntregaCentavos - pedido.descontoCentavos,
        reason: 'o total não fecha com as partes');

    // Pagamento na entrega entra direto na fila do balcão.
    expect(pedido.status, StatusDoPedido.recebido);
    expect(pedido.numero, greaterThan(0));
    expect(pedido.itens, hasLength(1));
    expect(pedido.itens.first.quantidade, quantidade);
    expect(pedido.itens.first.adicionais, hasLength(escolhidos.length));
    expect(pedido.entrega, isNotNull,
        reason: 'pedido de entrega precisa nascer com corrida');

    // O carrinho morreu junto com o fechamento.
    final carrinhos = await banco.from('carts').select('id');
    expect(carrinhos, isEmpty);

    // --- a tela mostra o pedido -------------------------------------------
    await Sessao.instancia.carregar();

    // Remontar de verdade, e não só repumpar: bombear o mesmo widget raiz
    // reaproveita o elemento, `initState` não roda de novo e a vitrine fica
    // com o estado de antes do pedido existir. Um widget diferente no meio
    // desfaz a árvore e obriga a tela a nascer outra vez.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(const app.AppTronvixFacil());

    final faixa = find.textContaining('nº ${pedido.numero}');
    await esperarPor(tester, faixa);

    expect(faixa, findsWidgets,
        reason: 'a faixa do pedido em andamento não apareceu na vitrine');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
