/// O que o entregador faz.
///
/// A fila de corridas é pública entre os entregadores aprovados: a primeira
/// pessoa que aceitar leva. Quem garante que duas não levem a mesma é o
/// `eq('status', 'searching_courier')` no UPDATE — se a linha já mudou, o
/// update não pega nada e a tela avisa que a corrida saiu.
library;

import '../modelos/modelos.dart';
import 'localizacao.dart';
import 'supabase.dart';

const _corridaCompleta = '''
  *,
  orders(
    id, number, status, fulfillment, total_cents, customer_name, customer_phone,
    ready_forecast_at,
    address_summary, address_district, address_city, notes, created_at,
    address_latitude, address_longitude,
    restaurant_id, subtotal_cents, delivery_fee_cents, discount_cents,
    restaurants(name, logo_url, phone, street, number, district, city,
                latitude, longitude),
    payments(method, timing, status, amount_cents, change_for_cents)
  )
''';

/// O mesmo que `_quando` em modelos.dart, que é privado daquele arquivo.
///
/// Vem do Postgres em UTC; sem `toLocal()` a previsão apareceria três horas
/// fora no Brasil, e o entregador sairia na hora errada.
DateTime? _horario(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// Uma corrida com o pedido e o restaurante juntos — é o que a tela mostra:
/// de onde buscar, para onde levar, quanto recebe.
class Corrida {
  const Corrida({
    required this.entrega,
    required this.numeroDoPedido,
    required this.nomeDoCliente,
    required this.totalDoPedidoCentavos,
    required this.nomeDoRestaurante,
    required this.situacaoDoPedido,
    this.prontoEm,
    this.telefoneDoCliente,
    this.enderecoDeEntrega,
    this.bairroDeEntrega,
    this.enderecoDoRestaurante,
    this.telefoneDoRestaurante,
    this.observacao,
    this.formaDePagamento,
    this.momentoDoPagamento,
    this.ondeRetirar,
    this.ondeEntregar,
  });

  final Entrega entrega;
  final int numeroDoPedido;
  final String nomeDoCliente;
  final int totalDoPedidoCentavos;
  final String nomeDoRestaurante;

  /// Em que pé está a comida. A corrida agora é aceita durante o preparo, então
  /// o entregador chega antes dela: é esta situação que diz se já dá para pegar.
  final StatusDoPedido situacaoDoPedido;

  /// Quando a loja prometeu que a comida fica pronta. Nulo em corrida chamada
  /// do jeito antigo, em que ninguém prometia nada.
  final DateTime? prontoEm;

  final String? telefoneDoCliente;
  final String? enderecoDeEntrega;
  final String? bairroDeEntrega;
  final String? enderecoDoRestaurante;
  final String? telefoneDoRestaurante;
  final String? observacao;
  final FormaDePagamento? formaDePagamento;
  final MomentoDoPagamento? momentoDoPagamento;

  /// Coordenadas, quando existem. O estabelecimento tem as dele no cadastro; o
  /// endereço do cliente só tem se ele deixou o aplicativo marcar. Nulo é
  /// normal, e o mapa desenha o que tiver.
  final Ponto? ondeRetirar;
  final Ponto? ondeEntregar;

  /// O entregador precisa saber disto antes de sair: vai receber dinheiro na
  /// porta ou o pedido já está pago?
  bool get recebeNaPorta => momentoDoPagamento == MomentoDoPagamento.naEntrega;

  factory Corrida.deMapa(Map<String, dynamic> m) {
    // Mesmo cuidado de Pedido.deMapa: o PostgREST devolve objeto numa relação
    // um-para-um e lista numa um-para-muitos.
    final pedido = aninhado(m['orders']) ?? const <String, dynamic>{};
    final restaurante =
        aninhado(pedido['restaurants']) ?? const <String, dynamic>{};
    final pagamento = aninhado(pedido['payments']);

    Ponto? ponto(Object? lat, Object? lon) => (lat == null || lon == null)
        ? null
        : Ponto(
            double.parse(lat.toString()),
            double.parse(lon.toString()),
          );

    return Corrida(
      entrega: Entrega.deMapa(m),
      ondeRetirar: ponto(restaurante['latitude'], restaurante['longitude']),
      ondeEntregar:
          ponto(pedido['address_latitude'], pedido['address_longitude']),
      numeroDoPedido: (pedido['number'] as int?) ?? 0,
      nomeDoCliente: (pedido['customer_name'] as String?) ?? '',
      totalDoPedidoCentavos:
          ((pedido['total_cents'] as num?) ?? 0).round(),
      nomeDoRestaurante: (restaurante['name'] as String?) ?? '',
      situacaoDoPedido: StatusDoPedido.de(
        (pedido['status'] as String?) ?? StatusDoPedido.recebido.noBanco,
      ),
      prontoEm: _horario(pedido['ready_forecast_at']),
      telefoneDoCliente: pedido['customer_phone'] as String?,
      enderecoDeEntrega: pedido['address_summary'] as String?,
      bairroDeEntrega: pedido['address_district'] as String?,
      enderecoDoRestaurante: [
        restaurante['street'],
        restaurante['number'],
        restaurante['district'],
      ].whereType<String>().join(', '),
      telefoneDoRestaurante: restaurante['phone'] as String?,
      observacao: pedido['notes'] as String?,
      formaDePagamento: pagamento == null
          ? null
          : FormaDePagamento.de(pagamento['method'] as String),
      momentoDoPagamento: pagamento == null
          ? null
          : MomentoDoPagamento.de(pagamento['timing'] as String),
    );
  }
}

class Corridas {
  /// Os estabelecimentos onde dá para se cadastrar como entregador.
  ///
  /// Lista os aprovados: é de um deles que a pessoa vai levar comida, e é ele
  /// quem vai aprovar o cadastro. Autônomo da plataforma existe no banco, mas
  /// não se cadastra por aqui — quem opera assim é exceção, e a plataforma
  /// resolve fora do aplicativo.
  static Future<List<Restaurante>> estabelecimentosParaCadastro() =>
      executar(() async {
        final linhas = await banco
            .from('restaurants')
            .select()
            .eq('status', 'approved')
            .order('name');
        return linhas.map((l) => Restaurante.deMapa(l)).toList();
      });

  /// Cadastro do entregador, que nasce pendente.
  ///
  /// Quem aprova é o estabelecimento escolhido — `app.guard_courier_platform_fields`
  /// recusa qualquer outra pessoa, inclusive o próprio entregador.
  static Future<void> cadastrar({
    required String restauranteId,
    required String tipoDeVeiculo,
    String? placa,
  }) =>
      executar(() => banco.from('couriers').insert({
            'user_id': usuarioId,
            'restaurant_id': restauranteId,
            'vehicle_type': tipoDeVeiculo,
            'vehicle_plate': (placa?.isEmpty ?? true) ? null : placa,
            'status': StatusDoEntregador.pendente.noBanco,
          }));

  /// As corridas esperando entregador.
  static Future<List<Corrida>> disponiveis() => executar(() async {
        final linhas = await banco
            .from('deliveries')
            .select(_corridaCompleta)
            .eq('status', StatusDaEntrega.procurandoEntregador.noBanco)
            .order('created_at');
        return linhas.map((l) => Corrida.deMapa(l)).toList();
      });

  /// A corrida que este entregador está fazendo agora, se houver. Uma de cada
  /// vez: quem está com comida na mochila não escolhe outra.
  static Future<Corrida?> minhaCorrida(String entregadorId) =>
      executar(() async {
        final linhas = await banco
            .from('deliveries')
            .select(_corridaCompleta)
            .eq('courier_id', entregadorId)
            .inFilter('status', const [
              'assigned',
              'heading_to_restaurant',
              'picked_up',
              'heading_to_customer',
            ])
            .limit(1);
        return linhas.isEmpty ? null : Corrida.deMapa(linhas.first);
      });

  static Future<List<Corrida>> minhasEntregues(String entregadorId,
          {int limite = 30}) =>
      executar(() async {
        final linhas = await banco
            .from('deliveries')
            .select(_corridaCompleta)
            .eq('courier_id', entregadorId)
            .eq('status', StatusDaEntrega.entregue.noBanco)
            .order('delivered_at', ascending: false)
            .limit(limite);
        return linhas.map((l) => Corrida.deMapa(l)).toList();
      });

  static RealtimeChannel acompanharFila(void Function() aoMudar) {
    final canal = banco.channel('corridas');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'deliveries',
          callback: (_) => aoMudar(),
        )
        .subscribe();
    return canal;
  }

  /// Aceita a corrida — se ela ainda estiver na fila.
  ///
  /// O filtro por status no próprio UPDATE é a trava contra dois entregadores
  /// aceitando ao mesmo tempo: o segundo não encontra a linha e recebe o aviso
  /// em vez de sair para uma entrega que já é de outro.
  static Future<void> aceitar(String entregaId, String entregadorId) =>
      executar(() async {
        final linhas = await banco
            .from('deliveries')
            .update({
              'courier_id': entregadorId,
              'status': StatusDaEntrega.designada.noBanco,
            })
            .eq('id', entregaId)
            .eq('status', StatusDaEntrega.procurandoEntregador.noBanco)
            .select('id');

        if (linhas.isEmpty) {
          throw ErroDeDados('Outro entregador pegou esta corrida.');
        }

        await banco
            .from('couriers')
            .update({'availability': DisponibilidadeDoEntregador.emEntrega.noBanco})
            .eq('id', entregadorId);
      });

  /// Em que situação do pedido a comida pode ser retirada.
  ///
  /// `pronto` é o caso que passa a existir: a corrida é aceita durante o
  /// preparo, e o entregador chega antes da comida. `saiuParaEntrega` é o
  /// caminho antigo, em que o balcão marcava o pedido como saído antes de
  /// existir entregador — esse continua valendo.
  static const _permitemRetirar = {
    StatusDoPedido.pronto,
    StatusDoPedido.saiuParaEntrega,
  };

  /// Espelho de `app.guard_delivery_status`.
  ///
  /// Devolve `null` quando a comida ainda não está pronta: a tela mostra a
  /// espera em vez de um botão que o banco recusaria. Quem está de capacete não
  /// deve descobrir a regra levando erro na cara.
  static StatusDaEntrega? proximoPasso(
    StatusDaEntrega atual, {
    StatusDoPedido? situacaoDoPedido,
  }) =>
      switch (atual) {
        StatusDaEntrega.designada => StatusDaEntrega.indoAoRestaurante,
        StatusDaEntrega.indoAoRestaurante =>
          situacaoDoPedido == null || _permitemRetirar.contains(situacaoDoPedido)
              ? StatusDaEntrega.retirada
              : null,
        StatusDaEntrega.retirada => StatusDaEntrega.indoAoCliente,
        StatusDaEntrega.indoAoCliente => StatusDaEntrega.entregue,
        _ => null,
      };

  static String rotuloDoPasso(StatusDaEntrega destino) => switch (destino) {
        StatusDaEntrega.indoAoRestaurante => 'Estou a caminho da loja',
        StatusDaEntrega.retirada => 'Peguei o pedido',
        StatusDaEntrega.indoAoCliente => 'Saí para o cliente',
        StatusDaEntrega.entregue => 'Entreguei',
        _ => 'Avançar',
      };

  static Future<void> avancar(
    Corrida corrida,
    StatusDaEntrega destino,
    String entregadorId,
  ) =>
      executar(() async {
        await banco
            .from('deliveries')
            .update({'status': destino.noBanco}).eq('id', corrida.entrega.id);

        // A entrega concluída fecha o pedido e devolve o entregador à fila.
        if (destino == StatusDaEntrega.entregue) {
          await banco
              .from('orders')
              .update({'status': StatusDoPedido.entregue.noBanco})
              .eq('id', corrida.entrega.pedidoId);

          // Só a disponibilidade: o contador de entregas é do banco.
          // `app.guard_courier_platform_fields` devolve deliveries_count ao
          // valor antigo se o entregador tentar escrevê-lo, e quem o avança é
          // o gatilho app.count_delivery.
          await banco
              .from('couriers')
              .update({'availability': DisponibilidadeDoEntregador.online.noBanco})
              .eq('id', entregadorId);
        }
      });

  /// Desistir devolve a corrida à fila. O gatilho do banco limpa o entregador
  /// da linha — está escrito lá, em `app.guard_delivery_status`.
  static Future<void> desistir(String entregaId, String entregadorId) =>
      executar(() async {
        await banco
            .from('deliveries')
            .update({'status': StatusDaEntrega.procurandoEntregador.noBanco})
            .eq('id', entregaId);
        await banco
            .from('couriers')
            .update({'availability': DisponibilidadeDoEntregador.online.noBanco})
            .eq('id', entregadorId);
      });

  /// Publica onde o entregador está.
  ///
  /// Silencia o erro de propósito: isto roda de fundo, a cada movimento, e uma
  /// falha de rede não pode interromper a entrega nem encher a tela de avisos.
  /// A consequência de perder uma medida é o alfinete do cliente ficar alguns
  /// segundos atrasado — e ele mostra a idade da medida justamente por isso.
  static Future<void> publicarPosicao(Ponto onde) async {
    try {
      await banco.rpc('publicar_posicao', params: {
        'p_latitude': onde.latitude,
        'p_longitude': onde.longitude,
      });
    } catch (_) {
      // Segue a viagem.
    }
  }

  static Future<void> mudarDisponibilidade(
    String entregadorId,
    DisponibilidadeDoEntregador nova,
  ) =>
      executar(() => banco
          .from('couriers')
          .update({'availability': nova.noBanco}).eq('id', entregadorId));
}
