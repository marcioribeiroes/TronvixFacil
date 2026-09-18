/// O pedido andando, com o cliente olhando.
///
/// O aplicativo fica na tela de acompanhar, como cliente, enquanto um segundo
/// cliente Supabase — autenticado como o dono — empurra o pedido passo a
/// passo. Cada passo tem de chegar por Realtime, mudar a tela e tocar o sino.
///
/// O som não dá para afirmar por asserção: o que este teste garante é que o
/// caminho que o dispara é percorrido, e que a tela conta a mesma história que
/// o banco. Num simulador com áudio, dá para ouvir enquanto ele roda.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tronvix_facil/ambiente.dart';
import 'package:tronvix_facil/cliente/acompanhar.dart';
import 'package:tronvix_facil/dados/carrinho.dart';
import 'package:tronvix_facil/dados/enderecos.dart';
import 'package:tronvix_facil/dados/pedidos.dart';
import 'package:tronvix_facil/dados/supabase.dart';
import 'package:tronvix_facil/main.dart' as app;
import 'package:tronvix_facil/modelos/modelos.dart';
import 'package:tronvix_facil/sessao.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> esperarTexto(WidgetTester tester, String texto,
      {Duration limite = const Duration(seconds: 25)}) async {
    final fim = DateTime.now().add(limite);
    while (DateTime.now().isBefore(fim)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text(texto).evaluate().isNotEmpty) return;
    }
  }

  testWidgets('o sino toca a cada passo do pedido', (tester) async {
    await app.prepararApp();

    // --- o cliente faz um pedido -------------------------------------------
    if (Sessao.instancia.autenticado) await Sessao.instancia.sair();
    await Sessao.instancia.entrar('cliente@tronvixfacil.com.br', 'tronvix123');

    await Carrinho.instancia.carregar();
    if (!Carrinho.instancia.vazio) await Carrinho.instancia.esvaziar();

    final restaurante = Restaurante.deMapa(
      await banco.from('restaurants').select().eq('slug', 'burger-house').single(),
    );
    final produto = Produto.deMapa(
      await banco
          .from('products')
          .select()
          .eq('restaurant_id', restaurante.id)
          .eq('is_available', true)
          .order('price_cents', ascending: false)
          .limit(1)
          .single(),
    );
    final endereco = (await Enderecos.meus()).first;

    await Carrinho.instancia
        .adicionar(restaurante: restaurante, produto: produto, quantidade: 2);

    final pedido = await Pedidos.fechar(
      carrinhoId: Carrinho.instancia.id!,
      tipo: TipoDeEntrega.entrega,
      forma: FormaDePagamento.dinheiro,
      momento: MomentoDoPagamento.naEntrega,
      enderecoId: endereco.id,
    );
    Carrinho.instancia.esquecer();

    // --- a tela de acompanhar, aberta --------------------------------------
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: app.AppTronvixFacil.tema,
      home: TelaAcompanhar(pedidoId: pedido.id),
    ));
    await esperarTexto(tester, 'Enviado ao restaurante');
    await binding.takeScreenshot('70-passo-enviado');

    // --- o balcão, num segundo aparelho ------------------------------------
    final celularDoDono = SupabaseClient(Ambiente.urlSupabase, Ambiente.chaveAnonima);
    await celularDoDono.auth.signInWithPassword(
      email: 'dono@burgerhouse.com.br',
      password: 'tronvix123',
    );

    final passos = <(StatusDoPedido, String)>[
      (StatusDoPedido.confirmado, 'Pedido aceito'),
      (StatusDoPedido.emPreparo, 'Em preparo'),
      (StatusDoPedido.pronto, 'Pronto'),
      (StatusDoPedido.saiuParaEntrega, 'Saiu para entrega'),
      (StatusDoPedido.entregue, 'Entregue'),
    ];

    var indice = 70;
    for (final (situacao, naTela) in passos) {
      await celularDoDono
          .from('orders')
          .update({'status': situacao.noBanco})
          .eq('id', pedido.id);

      // Espera o Realtime chegar e a tela reagir — é aqui que o sino toca.
      await esperarTexto(tester, naTela, limite: const Duration(seconds: 30));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }

      expect(find.text(naTela), findsWidgets,
          reason: 'a tela não mostrou "$naTela" depois do passo no banco');

      indice++;
      await binding.takeScreenshot('$indice-passo-${situacao.name}');
    }

    await celularDoDono.dispose();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
