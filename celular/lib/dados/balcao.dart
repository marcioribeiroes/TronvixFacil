/// O que a equipe do estabelecimento faz.
///
/// Uma consulta e um canal de Realtime sustentam a tela toda: a fila de pedidos
/// abertos. Num balcão, pedido que demora a aparecer é pedido que esfria — por
/// isso a lista não espera a pessoa puxar para atualizar.
library;

import '../modelos/modelos.dart';
import 'supabase.dart';

const _pedidoDoBalcao = '''
  *,
  order_items(*, order_item_addons(*)),
  payments(*),
  deliveries(*)
''';

/// Os estados que ainda pedem alguma coisa de alguém.
const _abertos = [
  'received',
  'confirmed',
  'preparing',
  'ready',
  'out_for_delivery',
];

class Balcao {
  static Future<List<Pedido>> fila(String restauranteId) => executar(() async {
        final linhas = await banco
            .from('orders')
            .select(_pedidoDoBalcao)
            .eq('restaurant_id', restauranteId)
            .inFilter('status', _abertos)
            .order('created_at');
        return linhas.map((l) => Pedido.deMapa(l)).toList();
      });

  static Future<List<Pedido>> doDia(String restauranteId) => executar(() async {
        final inicio = DateTime.now();
        final meiaNoite = DateTime(inicio.year, inicio.month, inicio.day);
        final linhas = await banco
            .from('orders')
            .select(_pedidoDoBalcao)
            .eq('restaurant_id', restauranteId)
            .gte('created_at', meiaNoite.toUtc().toIso8601String())
            .order('created_at', ascending: false);
        return linhas.map((l) => Pedido.deMapa(l)).toList();
      });

  static RealtimeChannel acompanharFila(
    String restauranteId,
    void Function() aoMudar,
  ) {
    final canal = banco.channel('balcao:$restauranteId');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: restauranteId,
          ),
          callback: (_) => aoMudar(),
        )
        .subscribe();
    return canal;
  }

  /// O próximo passo natural de um pedido, ou null quando não há.
  ///
  /// A cozinha não escolhe entre nove estados: aperta um botão que diz o que
  /// vem agora. Retirada pula "saiu para entrega" — não há rua no caminho, e o
  /// banco recusaria.
  static StatusDoPedido? proximoPasso(Pedido pedido) => switch (pedido.status) {
        StatusDoPedido.recebido => StatusDoPedido.confirmado,
        StatusDoPedido.confirmado => StatusDoPedido.emPreparo,
        StatusDoPedido.emPreparo => StatusDoPedido.pronto,
        StatusDoPedido.pronto => pedido.tipo == TipoDeEntrega.entrega
            ? StatusDoPedido.saiuParaEntrega
            : StatusDoPedido.entregue,
        StatusDoPedido.saiuParaEntrega => StatusDoPedido.entregue,
        _ => null,
      };

  static String rotuloDoPasso(StatusDoPedido destino) => switch (destino) {
        StatusDoPedido.confirmado => 'Aceitar pedido',
        StatusDoPedido.emPreparo => 'Começar o preparo',
        StatusDoPedido.pronto => 'Marcar como pronto',
        StatusDoPedido.saiuParaEntrega => 'Despachar',
        StatusDoPedido.entregue => 'Concluir',
        _ => 'Avançar',
      };

  static Future<void> avancar(Pedido pedido, StatusDoPedido destino) =>
      executar(() async {
        if (!transicaoPermitida(pedido.status, destino)) {
          throw ErroDeDados('Esse passo não é possível agora.');
        }
        await banco
            .from('orders')
            .update({'status': destino.noBanco}).eq('id', pedido.id);

        // Despachar o pedido põe a corrida na fila dos entregadores. Sem isto,
        // "saiu para entrega" seria só uma etiqueta e ninguém seria chamado.
        if (destino == StatusDoPedido.saiuParaEntrega) {
          await banco
              .from('deliveries')
              .update({'status': StatusDaEntrega.procurandoEntregador.noBanco})
              .eq('order_id', pedido.id)
              .eq('status', StatusDaEntrega.pendente.noBanco);
        }
      });

  static Future<void> recusar(String pedidoId, String motivo) =>
      executar(() => banco.from('orders').update({
            'status': StatusDoPedido.recusado.noBanco,
            'cancellation_reason': motivo,
          }).eq('id', pedidoId));

  /// A equipe de entrega do estabelecimento.
  ///
  /// A RLS já recorta: `cadastro de entregador visivel a quem o emprega`
  /// devolve só os deste estabelecimento. Não há `where restaurant_id` aqui de
  /// propósito — se aparecer gente de fora, o conserto é no banco.
  static Future<List<Entregador>> entregadores() =>
      executar(() async {
        final linhas = await banco
            .from('couriers')
            .select('*, profiles(full_name)')
            .isFilter('deleted_at', null)
            .order('status')
            .order('created_at');
        return linhas.map((l) => Entregador.deMapa(l)).toList();
      });

  static Future<void> decidirSobreEntregador(
    String entregadorId,
    StatusDoEntregador novo,
  ) =>
      executar(() => banco.from('couriers').update({
            'status': novo.noBanco,
            // Suspender alguém em serviço não pode deixá-lo "disponível" na
            // fila; o banco recusaria na próxima mudança, e a tela mentiria
            // até lá.
            if (novo != StatusDoEntregador.aprovado)
              'availability': DisponibilidadeDoEntregador.offline.noBanco,
          }).eq('id', entregadorId));

  static Future<void> aceitarEntregadorDaPlataforma(
    String restauranteId,
    bool aceita,
  ) =>
      executar(() => banco
          .from('restaurants')
          .update({'accepts_platform_couriers': aceita}).eq('id', restauranteId));

  static Future<void> abrirOuFechar(String restauranteId, bool aberto) =>
      executar(() => banco
          .from('restaurants')
          .update({'is_open': aberto}).eq('id', restauranteId));

  static Future<Restaurante> meuRestaurante(String id) => executar(() async {
        final linha =
            await banco.from('restaurants').select().eq('id', id).single();
        return Restaurante.deMapa(linha);
      });

  /// Tirar um item do ar no meio do movimento é a operação mais usada de um
  /// balcão: acabou o hambúrguer, some do cardápio agora.
  static Future<void> mudarDisponibilidade(String produtoId, bool disponivel) =>
      executar(() => banco
          .from('products')
          .update({'is_available': disponivel}).eq('id', produtoId));

  /// Um resumo honesto do dia: o que entrou, quanto foi, quanto ainda espera.
  static Future<ResumoDoDia> resumoDoDia(String restauranteId) async {
    final pedidos = await doDia(restauranteId);
    final valendo = pedidos
        .where((p) =>
            p.status != StatusDoPedido.cancelado &&
            p.status != StatusDoPedido.recusado)
        .toList();

    return ResumoDoDia(
      pedidos: valendo.length,
      totalCentavos: valendo.fold(0, (s, p) => s + p.totalCentavos),
      esperando: pedidos.where((p) => p.status == StatusDoPedido.recebido).length,
      emPreparo:
          pedidos.where((p) => p.status == StatusDoPedido.emPreparo).length,
    );
  }
}

class ResumoDoDia {
  const ResumoDoDia({
    required this.pedidos,
    required this.totalCentavos,
    required this.esperando,
    required this.emPreparo,
  });

  final int pedidos;
  final int totalCentavos;
  final int esperando;
  final int emPreparo;

  int get ticketMedioCentavos =>
      pedidos == 0 ? 0 : (totalCentavos / pedidos).round();
}
