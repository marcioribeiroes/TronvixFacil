/// Um pedido feito da mesa, no aplicativo de verdade, contra o Supabase de
/// verdade.
///
/// O que este teste prova, e o teste de unidade não prova: que o aplicativo
/// resolve o código do QR contra o banco, que o pedido nasce com a mesa certa,
/// sem frete e sem corrida, e que a cozinha recebe o nome da mesa.
///
/// A câmera não entra aqui — simulador não tem câmera, e emulador tem uma
/// falsa. O caminho testado é o do código resolvido, que é o mesmo que a
/// câmera alimenta depois de ler.
///
/// Como rodar:
///   ./testar-no-aparelho.sh -d "iPhone 17" integration_test/mesa_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tronvix_facil/dados/carrinho.dart';
import 'package:tronvix_facil/dados/mesa.dart';
import 'package:tronvix_facil/dados/pedidos.dart';
import 'package:tronvix_facil/dados/supabase.dart';
import 'package:tronvix_facil/main.dart' as app;
import 'package:tronvix_facil/modelos/modelos.dart';
import 'package:tronvix_facil/sessao.dart';

const _email = 'cliente@tronvixfacil.com.br';
const _senha = 'tronvix123';

Future<void> assentar(WidgetTester tester, [int voltas = 12]) async {
  for (var i = 0; i < voltas; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('do QR da mesa ao pedido na cozinha', (tester) async {
    await app.prepararApp();
    await tester.pumpWidget(const app.AppTronvixFacil());
    await assentar(tester, 20);

    if (!Sessao.instancia.autenticado) {
      await Sessao.instancia.entrar(_email, _senha);
      await assentar(tester, 20);
    }
    expect(Sessao.instancia.autenticado, isTrue,
        reason: 'não entrou com o usuário de demonstração');

    // --- acha uma mesa de verdade ------------------------------------------
    final linhas = await banco
        .from('restaurant_tables')
        .select('code, restaurant_id')
        .eq('is_active', true)
        .limit(1);

    if (linhas.isEmpty) {
      markTestSkipped('Nenhuma mesa cadastrada no servidor — pule ou crie uma.');
      return;
    }

    final codigo = linhas.first['code'] as String;

    // --- o aplicativo resolve o código, como faria depois de ler o QR ------
    final mesa = await Mesas.porCodigo(codigo);
    expect(mesa, isNotNull, reason: 'o código do QR não virou mesa');
    MesaAtual.instancia.sentar(mesa!);
    await assentar(tester);

    expect(MesaAtual.instancia.serve(mesa.restauranteId), isTrue);

    // --- monta o pedido no restaurante daquela mesa ------------------------
    await Carrinho.instancia.carregar();
    if (!Carrinho.instancia.vazio) await Carrinho.instancia.esvaziar();

    final lojas = await banco
        .from('restaurants')
        .select()
        .eq('id', mesa.restauranteId)
        .limit(1);
    final restaurante = Restaurante.deMapa(lojas.first);

    final produtos = await banco
        .from('products')
        .select()
        .eq('restaurant_id', restaurante.id)
        .eq('is_available', true)
        .limit(1);
    if (produtos.isEmpty) {
      markTestSkipped('O restaurante da mesa está sem cardápio.');
      return;
    }
    final produto = Produto.deMapa(produtos.first);

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

    // Uma unidade basta: o pedido mínimo não vale na mesa, e é justamente isso
    // que este teste aproveita para conferir.
    await Carrinho.instancia.adicionar(
      restaurante: restaurante,
      produto: produto,
      quantidade: 1,
      adicionais: escolhidos,
      observacao: 'Teste de mesa',
    );
    await assentar(tester);

    final pedido = await Pedidos.fechar(
      carrinhoId: Carrinho.instancia.id!,
      tipo: TipoDeEntrega.mesa,
      forma: FormaDePagamento.dinheiro,
      momento: MomentoDoPagamento.naEntrega,
      mesa: codigo,
    );

    // --- o que o banco gravou ---------------------------------------------
    expect(pedido.tipo, TipoDeEntrega.mesa);
    expect(pedido.taxaDeEntregaCentavos, 0,
        reason: 'mesa não paga frete');

    final gravado = await banco
        .from('orders')
        .select('table_label, fulfillment, delivery_fee_cents')
        .eq('id', pedido.id)
        .single();

    expect(gravado['table_label'], mesa.rotulo,
        reason: 'a cozinha precisa saber em qual mesa servir');
    expect(gravado['fulfillment'], 'dine_in');
    expect(gravado['delivery_fee_cents'], 0);

    final corridas =
        await banco.from('deliveries').select('id').eq('order_id', pedido.id);
    expect(corridas, isEmpty,
        reason: 'ninguém vai entregar nada: o cliente está sentado');

    // Não deixa o pedido de teste na fila da cozinha de verdade.
    await banco.from('orders').delete().eq('id', pedido.id);
    MesaAtual.instancia.levantar();
  });
}
