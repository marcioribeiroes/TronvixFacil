/// O cliente vendo o entregador chegar.
///
/// Dois aparelhos, simulados por duas sessões: o aplicativo fica logado como
/// **cliente**, na tela de acompanhar o pedido, enquanto um segundo cliente
/// Supabase — autenticado como **entregador** — publica posições ao longo do
/// caminho, como o celular dele faria na rua.
///
/// É a única forma honesta de verificar rastreio num aparelho só: se o teste
/// publicasse a posição com a mesma sessão que olha o mapa, ele provaria
/// apenas que a tela desenha o que ela mesma escreveu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tronvix_facil/ambiente.dart';
import 'package:tronvix_facil/cliente/acompanhar.dart';
import 'package:tronvix_facil/dados/balcao.dart';
import 'package:tronvix_facil/dados/carrinho.dart';
import 'package:tronvix_facil/dados/corridas.dart';
import 'package:tronvix_facil/dados/enderecos.dart';
import 'package:tronvix_facil/dados/pedidos.dart';
import 'package:tronvix_facil/dados/supabase.dart';
import 'package:tronvix_facil/main.dart' as app;
import 'package:tronvix_facil/modelos/modelos.dart';
import 'package:tronvix_facil/sessao.dart';

/// O trajeto: da Burger House até o endereço do cliente, no Setor Bueno.
/// Quatro medidas, como um celular emitindo a cada 25 metros emitiria.
const _caminho = [
  (-16.70450, -49.27260), // saindo da loja
  (-16.70380, -49.27180),
  (-16.70290, -49.27080),
  (-16.70210, -49.27005), // quase na porta
];

/// Um pedido de entrega, com endereço que tem coordenada — sem ela não há
/// destino no mapa e o rastreio perde metade do sentido.
Future<void> _fazerUmPedido() async {
  await Carrinho.instancia.carregar();
  if (!Carrinho.instancia.vazio) await Carrinho.instancia.esvaziar();

  var enderecos = await Enderecos.meus();
  var comPonto = enderecos.where((e) => e.latitude != null).firstOrNull;
  if (comPonto == null) {
    await banco.from('addresses').insert({
      'user_id': usuarioId,
      'label': 'Casa',
      'street': 'Rua T 30',
      'number': '120',
      'district': 'Setor Bueno',
      'city': 'Goiânia',
      'state': 'GO',
      'postal_code': '74210060',
      'latitude': -16.7020,
      'longitude': -49.2700,
    });
    enderecos = await Enderecos.meus();
    comPonto = enderecos.firstWhere((e) => e.latitude != null);
  }

  final restaurantes = await banco
      .from('restaurants')
      .select()
      .eq('slug', 'burger-house')
      .single();
  final restaurante = Restaurante.deMapa(restaurantes);

  final produto = Produto.deMapa(await banco
      .from('products')
      .select()
      .eq('restaurant_id', restaurante.id)
      .eq('is_available', true)
      .order('price_cents', ascending: false)
      .limit(1)
      .single());

  await Carrinho.instancia.adicionar(
    restaurante: restaurante,
    produto: produto,
    quantidade: 2,
  );

  await Pedidos.fechar(
    carrinhoId: Carrinho.instancia.id!,
    tipo: TipoDeEntrega.entrega,
    forma: FormaDePagamento.dinheiro,
    momento: MomentoDoPagamento.naEntrega,
    enderecoId: comPonto.id,
  );
  Carrinho.instancia.esquecer();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> respirar(WidgetTester tester, [int voltas = 10]) async {
    for (var i = 0; i < voltas; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('o cliente acompanha o entregador no mapa', (tester) async {
    await app.prepararApp();

    // --- cenário: o teste monta o próprio pedido ----------------------------
    // Não herda o que outra execução deixou: a rodada anterior termina com a
    // entrega concluída, e um teste que depende de sobra passa uma vez só.
    if (Sessao.instancia.autenticado) await Sessao.instancia.sair();
    await Sessao.instancia.entrar('cliente@tronvixfacil.com.br', 'tronvix123');
    await _fazerUmPedido();

    await Sessao.instancia.sair();
    await Sessao.instancia.entrar('dono@burgerhouse.com.br', 'tronvix123');
    final restauranteId = Sessao.instancia.vinculo!.restauranteId;

    var fila = await Balcao.fila(restauranteId);
    expect(fila, isNotEmpty, reason: 'nada na fila para despachar');

    // O mais novo: é o que este teste acabou de criar.
    var pedido = fila
        .where((p) => p.tipo == TipoDeEntrega.entrega)
        .reduce((a, b) => a.criadoEm.isAfter(b.criadoEm) ? a : b);
    while (pedido.status != StatusDoPedido.saiuParaEntrega) {
      final passo = Balcao.proximoPasso(pedido);
      if (passo == null || passo == StatusDoPedido.entregue) break;
      await Balcao.avancar(pedido, passo);
      fila = await Balcao.fila(restauranteId);
      pedido = fila.firstWhere((p) => p.id == pedido.id);
    }
    expect(pedido.status, StatusDoPedido.saiuParaEntrega);

    // --- o entregador aceita -------------------------------------------------
    await Sessao.instancia.sair();
    await Sessao.instancia.entrar('entregador@tronvixfacil.com.br', 'tronvix123');
    final entregador = Sessao.instancia.entregador!;
    await Corridas.mudarDisponibilidade(
        entregador.id, DisponibilidadeDoEntregador.online);

    final disponiveis = await Corridas.disponiveis();
    final minha = disponiveis.firstWhere(
      (c) => c.entrega.pedidoId == pedido.id,
      orElse: () => throw StateError(
          'a corrida do pedido recém-despachado não chegou ao entregador'),
    );
    await Corridas.aceitar(minha.entrega.id, entregador.id);

    // --- o segundo aparelho --------------------------------------------------
    // Um cliente Supabase à parte, autenticado como o entregador. É ele que
    // publica as posições enquanto o aplicativo olha como cliente.
    final celularDoEntregador = SupabaseClient(
      Ambiente.urlSupabase,
      Ambiente.chaveAnonima,
    );
    await celularDoEntregador.auth.signInWithPassword(
      email: 'entregador@tronvixfacil.com.br',
      password: 'tronvix123',
    );

    Future<void> publicar(int passo) => celularDoEntregador.rpc(
          'publicar_posicao',
          params: {
            'p_latitude': _caminho[passo].$1,
            'p_longitude': _caminho[passo].$2,
          },
        );

    await publicar(0);

    // --- o aplicativo vira o cliente ----------------------------------------
    await Sessao.instancia.sair();
    await Sessao.instancia.entrar('cliente@tronvixfacil.com.br', 'tronvix123');

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: app.AppTronvixFacil.tema,
      home: TelaAcompanhar(pedidoId: pedido.id),
    ));
    await respirar(tester, 24);

    // A tela consulta a cada oito segundos; esperar um pouco mais que isso
    // entre os passos é o que faz o alfinete andar de verdade.
    await binding.takeScreenshot('60-rastreio-saindo-da-loja');

    for (var passo = 1; passo < _caminho.length; passo++) {
      await publicar(passo);
      await respirar(tester, 34);
      await binding.takeScreenshot('6$passo-rastreio-a-caminho');
    }

    // O que o cliente vê tem de ser o que o entregador publicou.
    final ondeEstava = await banco.rpc('onde_esta_o_entregador',
        params: {'p_order': pedido.id}) as Map<String, dynamic>;
    expect(double.parse(ondeEstava['latitude'].toString()),
        closeTo(_caminho.last.$1, 0.00001),
        reason: 'a posição que o cliente lê não é a que o entregador publicou');

    // --- entregue: o entregador some do mapa --------------------------------
    // Passo a passo: a máquina de estados do banco recusa atalho, e com razão —
    // uma corrida não vai de "aceita" a "entregue" sem passar pela rua.
    for (final etapa in [
      StatusDaEntrega.indoAoRestaurante,
      StatusDaEntrega.retirada,
      StatusDaEntrega.indoAoCliente,
      StatusDaEntrega.entregue,
    ]) {
      await celularDoEntregador
          .from('deliveries')
          .update({'status': etapa.noBanco})
          .eq('id', minha.entrega.id);
    }
    await celularDoEntregador
        .from('orders')
        .update({'status': StatusDoPedido.entregue.noBanco})
        .eq('id', pedido.id);

    await respirar(tester, 34);
    await binding.takeScreenshot('64-rastreio-entregue');

    // A tela tem de ter percebido sozinha, por Realtime, que o pedido acabou.
    // Não é detalhe: se isto falhar, o cliente fica olhando "saiu para entrega"
    // com a comida já na mão.
    expect(find.text('Entregue'), findsWidgets,
        reason: 'a tela não percebeu, por Realtime, que o pedido foi entregue');

    expect(
      await banco.rpc('onde_esta_o_entregador', params: {'p_order': pedido.id}),
      isNull,
      reason: 'entregue, o entregador precisa parar de ser rastreável',
    );

    await celularDoEntregador.dispose();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
