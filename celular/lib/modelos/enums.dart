/// Os enums do Postgres, espelhados em Dart.
///
/// O banco é a fonte da verdade: cada valor aqui é exatamente a string que o
/// tipo correspondente aceita em `20260917100000_fundacao.sql`. Por isso a
/// conversão passa por `porNome`, que falha alto se o banco ganhar um estado
/// novo e este arquivo ficar para trás — silêncio aqui viraria um pedido em
/// estado desconhecido aparecendo como "recebido" na tela do balcão.
library;

T _porNome<T>(List<T> valores, String Function(T) nome, String bruto, String tipo) {
  for (final v in valores) {
    if (nome(v) == bruto) return v;
  }
  throw ArgumentError('Valor desconhecido de $tipo vindo do banco: "$bruto"');
}

enum PapelNaPlataforma {
  cliente('customer'),
  entregador('courier'),
  administrador('platform_admin');

  const PapelNaPlataforma(this.noBanco);
  final String noBanco;

  static PapelNaPlataforma de(String v) =>
      _porNome(values, (e) => e.noBanco, v, 'platform_role');
}

enum PapelNoRestaurante {
  dono('owner'),
  gerente('manager'),
  atendente('staff');

  const PapelNoRestaurante(this.noBanco);
  final String noBanco;

  static PapelNoRestaurante de(String v) =>
      _porNome(values, (e) => e.noBanco, v, 'restaurant_role');

  /// Quem pode mexer no cardápio e nos dados da loja. Espelha `app.can_manage`.
  bool get gerencia => this != atendente;
}

enum TipoDeEntrega {
  entrega('delivery'),
  retirada('pickup');

  const TipoDeEntrega(this.noBanco);
  final String noBanco;

  static TipoDeEntrega de(String v) =>
      _porNome(values, (e) => e.noBanco, v, 'fulfillment_type');

  String get rotulo => this == entrega ? 'Entrega' : 'Retirada no balcão';
}

enum StatusDoPedido {
  aguardandoPagamento('awaiting_payment'),
  recebido('received'),
  confirmado('confirmed'),
  emPreparo('preparing'),
  pronto('ready'),
  saiuParaEntrega('out_for_delivery'),
  entregue('delivered'),
  cancelado('cancelled'),
  recusado('rejected');

  const StatusDoPedido(this.noBanco);
  final String noBanco;

  static StatusDoPedido de(String v) =>
      _porNome(values, (e) => e.noBanco, v, 'order_status');

  bool get encerrado =>
      this == entregue || this == cancelado || this == recusado;

  /// O que o cliente lê enquanto acompanha.
  String get paraOCliente => switch (this) {
        aguardandoPagamento => 'Aguardando pagamento',
        recebido => 'Enviado ao restaurante',
        confirmado => 'Pedido aceito',
        emPreparo => 'Em preparo',
        pronto => 'Pronto',
        saiuParaEntrega => 'Saiu para entrega',
        entregue => 'Entregue',
        cancelado => 'Cancelado',
        recusado => 'Recusado pelo restaurante',
      };

  /// O que o balcão lê. É outra frase de propósito: "recebido" para o cliente
  /// significa que saiu do celular dele; para a cozinha significa que chegou.
  String get paraORestaurante => switch (this) {
        aguardandoPagamento => 'Aguardando pagamento',
        recebido => 'Novo pedido',
        confirmado => 'Aceito',
        emPreparo => 'Em preparo',
        pronto => 'Pronto para sair',
        saiuParaEntrega => 'Com o entregador',
        entregue => 'Entregue',
        cancelado => 'Cancelado',
        recusado => 'Recusado',
      };
}

/// Espelho de `app.order_transition_allowed`.
///
/// Existe no aplicativo para que a tela não ofereça um botão que o banco vai
/// recusar — mas quem manda continua sendo o gatilho. Se os dois discordarem,
/// o certo é o do banco, e este mapa é que está errado.
const Map<StatusDoPedido, List<StatusDoPedido>> transicoesPermitidas = {
  StatusDoPedido.aguardandoPagamento: [
    StatusDoPedido.recebido,
    StatusDoPedido.cancelado,
  ],
  StatusDoPedido.recebido: [
    StatusDoPedido.confirmado,
    StatusDoPedido.recusado,
    StatusDoPedido.cancelado,
  ],
  StatusDoPedido.confirmado: [
    StatusDoPedido.emPreparo,
    StatusDoPedido.cancelado,
  ],
  StatusDoPedido.emPreparo: [StatusDoPedido.pronto, StatusDoPedido.cancelado],
  StatusDoPedido.pronto: [
    StatusDoPedido.saiuParaEntrega,
    StatusDoPedido.entregue,
    StatusDoPedido.cancelado,
  ],
  StatusDoPedido.saiuParaEntrega: [
    StatusDoPedido.entregue,
    StatusDoPedido.cancelado,
  ],
  StatusDoPedido.entregue: [],
  StatusDoPedido.cancelado: [],
  StatusDoPedido.recusado: [],
};

bool transicaoPermitida(StatusDoPedido de, StatusDoPedido para) =>
    transicoesPermitidas[de]?.contains(para) ?? false;

enum StatusDoPagamento {
  pendente('pending'),
  pago('paid'),
  falhou('failed'),
  estornado('refunded'),
  cancelado('cancelled');

  const StatusDoPagamento(this.noBanco);
  final String noBanco;

  static StatusDoPagamento de(String v) =>
      _porNome(values, (e) => e.noBanco, v, 'payment_status');
}

enum FormaDePagamento {
  pix('pix', 'Pix'),
  credito('credit_card', 'Cartão de crédito'),
  debito('debit_card', 'Cartão de débito'),
  dinheiro('cash', 'Dinheiro'),
  valeRefeicao('meal_voucher', 'Vale-refeição');

  const FormaDePagamento(this.noBanco, this.rotulo);
  final String noBanco;
  final String rotulo;

  static FormaDePagamento de(String v) =>
      _porNome(values, (e) => e.noBanco, v, 'payment_method');

  /// Só dinheiro aceita troco — é a mesma restrição do check
  /// `payments_change_only_for_cash`.
  bool get aceitaTroco => this == dinheiro;
}

enum MomentoDoPagamento {
  noApp('online', 'Pagar pelo aplicativo'),
  naEntrega('on_delivery', 'Pagar na entrega');

  const MomentoDoPagamento(this.noBanco, this.rotulo);
  final String noBanco;
  final String rotulo;

  static MomentoDoPagamento de(String v) =>
      _porNome(values, (e) => e.noBanco, v, 'payment_timing');
}

enum StatusDaEntrega {
  pendente('pending'),
  procurandoEntregador('searching_courier'),
  designada('assigned'),
  indoAoRestaurante('heading_to_restaurant'),
  retirada('picked_up'),
  indoAoCliente('heading_to_customer'),
  entregue('delivered'),
  cancelada('cancelled');

  const StatusDaEntrega(this.noBanco);
  final String noBanco;

  static StatusDaEntrega de(String v) =>
      _porNome(values, (e) => e.noBanco, v, 'delivery_status');

  String get rotulo => switch (this) {
        pendente => 'Aguardando',
        procurandoEntregador => 'Procurando entregador',
        designada => 'Entregador a caminho da loja',
        indoAoRestaurante => 'Indo buscar',
        retirada => 'Pedido retirado',
        indoAoCliente => 'A caminho do cliente',
        entregue => 'Entregue',
        cancelada => 'Cancelada',
      };
}

enum DisponibilidadeDoEntregador {
  offline('offline', 'Fora do ar'),
  online('online', 'Disponível'),
  emEntrega('on_delivery', 'Em entrega');

  const DisponibilidadeDoEntregador(this.noBanco, this.rotulo);
  final String noBanco;
  final String rotulo;

  static DisponibilidadeDoEntregador de(String v) =>
      _porNome(values, (e) => e.noBanco, v, 'courier_availability');
}

enum StatusDoEntregador {
  pendente('pending'),
  aprovado('approved'),
  suspenso('suspended');

  const StatusDoEntregador(this.noBanco);
  final String noBanco;

  static StatusDoEntregador de(String v) =>
      _porNome(values, (e) => e.noBanco, v, 'courier_status');
}
