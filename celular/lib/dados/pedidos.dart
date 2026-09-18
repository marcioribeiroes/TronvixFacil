/// Pedidos: fechar, listar, acompanhar.
///
/// O acompanhamento usa Realtime. É o que separa um aplicativo de delivery de
/// uma página que precisa ser recarregada: quando a cozinha aperta "saiu para
/// entrega", o celular do cliente muda sozinho, e o do entregador também.
library;

import 'dart:async';

import '../modelos/modelos.dart';
import 'localizacao.dart';
import 'supabase.dart';

/// Onde o entregador estava, e há quanto tempo.
///
/// A idade da medida anda junto com ela: um alfinete parado há três minutos
/// não é a mesma coisa que um alfinete de agora, e o cliente merece saber a
/// diferença antes de concluir que o entregador sumiu.
class PosicaoDoEntregador {
  const PosicaoDoEntregador({required this.onde, required this.medidoEm});

  final Ponto onde;
  final DateTime medidoEm;

  factory PosicaoDoEntregador.deMapa(Map<String, dynamic> m) =>
      PosicaoDoEntregador(
        onde: Ponto(
          double.parse(m['latitude'].toString()),
          double.parse(m['longitude'].toString()),
        ),
        medidoEm: DateTime.parse(m['medido_em'] as String).toLocal(),
      );

  Duration get idade => DateTime.now().difference(medidoEm);

  /// Passou disso, a bolinha no mapa é história, não posição.
  bool get velha => idade > const Duration(minutes: 2);
}

/// As colunas que uma tela de pedido precisa, num lugar só. Repetir esta
/// string em cada consulta é como um campo novo acaba faltando em uma delas.
const _pedidoCompleto = '''
  *,
  restaurants(name, logo_url, phone),
  order_items(*, order_item_addons(*)),
  payments(*),
  deliveries(*)
''';

class Pedidos {
  /// Fecha o carrinho e devolve o pedido criado.
  ///
  /// Manda o que a pessoa escolheu — jamais quanto custa. O preço é recalculado
  /// pelo banco a partir do cardápio daquele instante.
  static Future<Pedido> fechar({
    required String carrinhoId,
    required TipoDeEntrega tipo,
    required FormaDePagamento forma,
    required MomentoDoPagamento momento,
    String? enderecoId,
    int? trocoParaCentavos,
    String? cupom,
    String? observacao,
    /// Código do QR da mesa, quando o pedido é feito no salão.
    String? mesa,
    DateTime? agendadoPara,
  }) =>
      executar(() async {
        final id = await banco.rpc('fechar_pedido', params: {
          'p_cart_id': carrinhoId,
          'p_fulfillment': tipo.noBanco,
          'p_payment_method': forma.noBanco,
          'p_payment_timing': momento.noBanco,
          'p_address_id': enderecoId,
          'p_change_for_cents': trocoParaCentavos,
          'p_coupon_code': cupom,
          'p_notes': observacao,
          'p_scheduled_for': agendadoPara?.toUtc().toIso8601String(),
          // O código do QR da mesa. Vem da leitura da câmera, nunca de uma
          // lista na tela: lista de mesas deixaria qualquer um lançar na mesa
          // do vizinho.
          'p_mesa': mesa,
        }) as String;

        return porId(id);
      });

  /// Quanto um cupom abate, antes de fechar. Devolve null quando não vale, com
  /// a razão na exceção — que a tela mostra como está, porque o banco já
  /// escreve em português.
  static Future<int> simularCupom({
    required String codigo,
    required String restauranteId,
    required int subtotalCentavos,
    required int taxaDeEntregaCentavos,
  }) =>
      executar(() async {
        final r = await banco.rpc('simular_cupom', params: {
          'p_code': codigo,
          'p_restaurant': restauranteId,
          'p_subtotal_cents': subtotalCentavos,
          'p_delivery_fee_cents': taxaDeEntregaCentavos,
        }) as Map<String, dynamic>;
        return (r['discount_cents'] as num).round();
      });

  static Future<Pedido> porId(String id) => executar(() async {
        final linha =
            await banco.from('orders').select(_pedidoCompleto).eq('id', id).single();
        return Pedido.deMapa(linha);
      });

  static Future<List<Pedido>> meus({int limite = 30}) => executar(() async {
        final id = usuarioId;
        if (id == null) return <Pedido>[];
        final linhas = await banco
            .from('orders')
            .select(_pedidoCompleto)
            .eq('customer_id', id)
            .order('created_at', ascending: false)
            .limit(limite);
        return linhas.map((l) => Pedido.deMapa(l)).toList();
      });

  /// O pedido que ainda está andando, se houver. É ele que vira a faixa fixa no
  /// topo da vitrine — quem tem comida a caminho abre o aplicativo para ver
  /// isso, não para escolher outro restaurante.
  static Future<Pedido?> emAndamento() => executar(() async {
        final id = usuarioId;
        if (id == null) return null;
        final linhas = await banco
            .from('orders')
            .select(_pedidoCompleto)
            .eq('customer_id', id)
            .inFilter('status', const [
              'awaiting_payment',
              'received',
              'confirmed',
              'preparing',
              'ready',
              'out_for_delivery',
            ])
            .order('created_at', ascending: false)
            .limit(1);
        return linhas.isEmpty ? null : Pedido.deMapa(linhas.first);
      });

  /// Cancelamento pelo cliente.
  ///
  /// Só até o restaurante aceitar. Depois disso a comida já está sendo feita, e
  /// cancelar deixa de ser um botão para virar uma conversa — por isso a tela
  /// manda ligar em vez de oferecer o botão.
  static Future<void> cancelar(String id, {String? motivo}) =>
      executar(() => banco.from('orders').update({
            'status': StatusDoPedido.cancelado.noBanco,
            'cancellation_reason': motivo ?? 'Cancelado pelo cliente',
          }).eq('id', id));

  static bool clientePodeCancelar(StatusDoPedido status) =>
      status == StatusDoPedido.aguardandoPagamento ||
      status == StatusDoPedido.recebido;

  /// Avisa sempre que este pedido mudar no banco.
  ///
  /// Devolve o canal para que a tela o feche em `dispose`. Canal esquecido
  /// aberto é conexão viva consumindo bateria de quem já fechou a tela.
  static RealtimeChannel acompanhar(
    String pedidoId,
    void Function() aoMudar,
  ) {
    final canal = banco.channel('pedido:$pedidoId');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: pedidoId,
          ),
          callback: (_) => aoMudar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'deliveries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: pedidoId,
          ),
          callback: (_) => aoMudar(),
        )
        .subscribe();
    return canal;
  }

  /// Onde está o entregador deste pedido, agora.
  ///
  /// Consulta, e não Realtime, de propósito: assinar mudanças em `couriers`
  /// exigiria abrir a tabela ao cliente por RLS, e o Realtime passaria a
  /// transmitir a linha inteira do entregador — documento, reputação, cadastro.
  /// A função do banco devolve três campos e nada mais.
  ///
  /// Devolve nulo quando a corrida acabou, quando ninguém a pegou ainda, ou
  /// quando o entregador ainda não publicou nenhuma medida.
  static Future<PosicaoDoEntregador?> ondeEstaOEntregador(String pedidoId) =>
      executar(() async {
        final r = await banco.rpc('onde_esta_o_entregador',
            params: {'p_order': pedidoId});
        if (r == null) return null;
        return PosicaoDoEntregador.deMapa(r as Map<String, dynamic>);
      });

  static Future<void> avaliar({
    required String pedidoId,
    required String restauranteId,
    required int nota,
    String? comentario,
  }) =>
      executar(() => banco.from('reviews').insert({
            'order_id': pedidoId,
            'restaurant_id': restauranteId,
            'customer_id': usuarioId,
            'rating': nota,
            'comment': (comentario?.isEmpty ?? true) ? null : comentario,
          }));
}
