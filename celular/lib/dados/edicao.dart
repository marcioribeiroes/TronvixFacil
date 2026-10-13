/// Editar o pedido (a loja) e pedir mais na mesa (o cliente).
///
/// A conta não é feita aqui: a tela manda o que mudou, e `editar_pedido` ou
/// `pedir_mais_na_mesa` refazem preço, estoque e valor a receber no banco —
/// as mesmas funções que o painel web usa.
library;

import '../modelos/modelos.dart';
import 'carrinho.dart';
import 'supabase.dart';

/// O que sai da tela de produto quando a escolha é para um pedido, e não para
/// o carrinho.
class EscolhaDoProduto {
  const EscolhaDoProduto({
    required this.produto,
    required this.quantidade,
    required this.adicionais,
    this.observacao = '',
  });

  final Produto produto;
  final int quantidade;
  final List<AdicionalEscolhido> adicionais;
  final String observacao;

  /// Prévia, para a tela. O valor que vale é o que o banco calcula.
  int get totalCentavos =>
      (produto.precoQueVale +
          adicionais.fold<int>(0, (s, a) => s + a.totalCentavos)) *
      quantidade;

  Map<String, dynamic> paraOBanco() => {
    'produto_id': produto.id,
    'quantidade': quantidade,
    'observacao': observacao.trim(),
    'adicionais': [
      for (final a in adicionais)
        {'id': a.adicional.id, 'quantidade': a.quantidade},
    ],
  };
}

class EdicaoDoPedido {
  /// Espelho de `app.conferir_pedido_editavel`: aqui decide o botão; quem
  /// decide de verdade é o banco.
  static bool podeMudar(Pedido p) {
    const abertos = {
      StatusDoPedido.recebido,
      StatusDoPedido.confirmado,
      StatusDoPedido.emPreparo,
      StatusDoPedido.pronto,
    };
    if (!abertos.contains(p.status)) return false;
    final pagamento = p.pagamento;
    if (pagamento == null) return true;
    // Pago pelo app, ou já recebido no caixa: o valor foi acertado.
    return pagamento.momento == MomentoDoPagamento.naEntrega &&
        pagamento.status == StatusDoPagamento.pendente;
  }

  /// Na mesa, enquanto a conta está aberta, o cliente pede mais.
  static bool clientePodePedirMais(Pedido p) =>
      p.tipo == TipoDeEntrega.mesa && podeMudar(p);

  /// A loja muda quantidades (0 remove), e acrescenta itens. Tudo numa
  /// transação: a cozinha nunca vê o pedido pela metade.
  static Future<void> editar(
    String pedidoId, {
    required Map<String, int> quantidades,
    required List<EscolhaDoProduto> novos,
  }) => executar(
    () => banco.rpc(
      'editar_pedido',
      params: {
        'p_pedido': pedidoId,
        'p_alteracoes': {
          'itens': [
            for (final e in quantidades.entries)
              {'id': e.key, 'quantidade': e.value},
          ],
          'novos': [for (final n in novos) n.paraOBanco()],
        },
      },
    ),
  );

  static Future<void> pedirMais(
    String pedidoId,
    List<EscolhaDoProduto> itens,
  ) => executar(
    () => banco.rpc(
      'pedir_mais_na_mesa',
      params: {
        'p_pedido': pedidoId,
        'p_itens': [for (final n in itens) n.paraOBanco()],
      },
    ),
  );
}

/// A loja lança um pedido do zero: balcão, mesa ou entrega por telefone.
///
/// Nasce aceito, sem comissão, com a conta feita por `lancar_pedido` — a
/// mesma função do painel web.
class Lancamento {
  static Future<List<({String id, String rotulo})>> mesas(String restauranteId) =>
      executar(() async {
        final linhas = await banco
            .from('restaurant_tables')
            .select('id, label')
            .eq('restaurant_id', restauranteId)
            .eq('is_active', true)
            .isFilter('deleted_at', null)
            .order('label');
        return [
          for (final l in linhas)
            (id: l['id'] as String, rotulo: l['label'] as String),
        ];
      });

  static Future<String> lancar(
    String restauranteId, {
    required TipoDeEntrega tipo,
    required List<EscolhaDoProduto> itens,
    required FormaDePagamento forma,
    String cliente = '',
    String telefone = '',
    String? mesaId,
    String mesa = '',
    Map<String, String> endereco = const {},
    int? trocoParaCentavos,
    bool receberAgora = false,
    String observacao = '',
  }) =>
      executar(() async {
        final id = await banco.rpc('lancar_pedido', params: {
          'p_restaurante': restauranteId,
          'p_dados': {
            'tipo': tipo.noBanco,
            'cliente': cliente.trim(),
            'telefone': telefone.trim(),
            'mesa_id': mesaId,
            'mesa': mesa.trim(),
            'endereco': endereco,
            'forma': forma.noBanco,
            'troco_para_cents': trocoParaCentavos,
            'receber_agora': receberAgora,
            'observacao': observacao.trim(),
            'itens': [for (final i in itens) i.paraOBanco()],
          },
        });
        return id as String;
      });
}
