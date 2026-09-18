/// O carrinho — que mora no servidor, não no celular.
///
/// A tabela `carts` existe justamente para isso: quem monta o pedido no ônibus
/// e fecha em casa encontra o carrinho como deixou. E, mais importante, é do
/// carrinho do servidor que `fechar_pedido` lê para recalcular os preços. Um
/// carrinho só local obrigaria o aplicativo a mandar o que custa, que é
/// exatamente o que o banco não aceita.
///
/// O preço que esta classe soma serve para *mostrar*. Quem cobra é o banco.
library;

import 'package:flutter/foundation.dart';

import '../modelos/modelos.dart';
import 'supabase.dart';

class AdicionalEscolhido {
  const AdicionalEscolhido({required this.adicional, this.quantidade = 1});
  final Adicional adicional;
  final int quantidade;

  int get totalCentavos => adicional.precoCentavos * quantidade;
}

class ItemDoCarrinho {
  const ItemDoCarrinho({
    required this.id,
    required this.produto,
    required this.quantidade,
    required this.adicionais,
    this.observacao,
  });

  final String id;
  final Produto produto;
  final int quantidade;
  final List<AdicionalEscolhido> adicionais;
  final String? observacao;

  int get adicionaisCentavos =>
      adicionais.fold(0, (s, a) => s + a.totalCentavos);

  int get totalCentavos =>
      (produto.precoQueVale + adicionaisCentavos) * quantidade;
}

class Carrinho extends ChangeNotifier {
  Carrinho._();
  static final Carrinho instancia = Carrinho._();

  String? _id;
  Restaurante? _restaurante;
  List<ItemDoCarrinho> _itens = const [];
  bool _carregando = false;

  String? get id => _id;
  Restaurante? get restaurante => _restaurante;
  List<ItemDoCarrinho> get itens => _itens;
  bool get carregando => _carregando;
  bool get vazio => _itens.isEmpty;

  int get quantidadeDeItens => _itens.fold(0, (s, i) => s + i.quantidade);
  int get subtotalCentavos => _itens.fold(0, (s, i) => s + i.totalCentavos);

  /// Quanto falta para o pedido mínimo. Zero quando já dá.
  int faltaParaOMinimo() {
    final minimo = _restaurante?.pedidoMinimoCentavos ?? 0;
    final falta = minimo - subtotalCentavos;
    return falta > 0 ? falta : 0;
  }

  /// Lê o carrinho aberto da pessoa, se houver.
  ///
  /// O índice `carts_open_per_restaurant_idx` garante um carrinho por
  /// estabelecimento; na prática o aplicativo trabalha com um de cada vez, e
  /// trocar de restaurante troca o carrinho.
  Future<void> carregar() async {
    if (usuarioId == null) {
      _id = null;
      _restaurante = null;
      _itens = const [];
      notifyListeners();
      return;
    }

    _carregando = true;
    notifyListeners();

    try {
      final linhas = await executar(() => banco
          .from('carts')
          .select('id, restaurant_id, restaurants(*)')
          .order('updated_at', ascending: false)
          .limit(1));

      if (linhas.isEmpty) {
        _id = null;
        _restaurante = null;
        _itens = const [];
        return;
      }

      _id = linhas.first['id'] as String;
      _restaurante =
          Restaurante.deMapa(linhas.first['restaurants'] as Map<String, dynamic>);
      await _lerItens();
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> _lerItens() async {
    final id = _id;
    if (id == null) {
      _itens = const [];
      return;
    }

    final linhas = await executar(() => banco
        .from('cart_items')
        .select('*, products(*), cart_item_addons(quantity, addons(*))')
        .eq('cart_id', id)
        .order('created_at'));

    _itens = linhas.map((l) {
      final adicionais = ((l['cart_item_addons'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map((a) => AdicionalEscolhido(
                adicional: Adicional.deMapa(a['addons'] as Map<String, dynamic>),
                quantidade: (a['quantity'] as int?) ?? 1,
              ))
          .toList();

      return ItemDoCarrinho(
        id: l['id'] as String,
        produto: Produto.deMapa(l['products'] as Map<String, dynamic>),
        quantidade: l['quantity'] as int,
        observacao: l['notes'] as String?,
        adicionais: adicionais,
      );
    }).toList();
  }

  /// Abre (ou reabre) o carrinho de um estabelecimento.
  ///
  /// Trocar de restaurante apaga o carrinho anterior. É a regra do schema — um
  /// pedido pertence a um estabelecimento — e quem confirma isso com o cliente
  /// é a tela, antes de chamar aqui.
  Future<void> abrirEm(Restaurante restaurante) async {
    if (usuarioId == null) {
      throw ErroDeDados('Entre na sua conta para montar o pedido.');
    }
    if (_id != null && _restaurante?.id == restaurante.id) return;

    await executar(() async {
      if (_id != null) await banco.from('carts').delete().eq('id', _id!);

      final linha = await banco
          .from('carts')
          .insert({'user_id': usuarioId, 'restaurant_id': restaurante.id})
          .select('id')
          .single();

      _id = linha['id'] as String;
    });

    _restaurante = restaurante;
    _itens = const [];
    notifyListeners();
  }

  /// O carrinho aberto é de outro estabelecimento?
  bool ehDeOutro(String restauranteId) =>
      _id != null && !vazio && _restaurante?.id != restauranteId;

  Future<void> adicionar({
    required Restaurante restaurante,
    required Produto produto,
    required int quantidade,
    List<AdicionalEscolhido> adicionais = const [],
    String? observacao,
  }) async {
    await abrirEm(restaurante);

    await executar(() async {
      final item = await banco
          .from('cart_items')
          .insert({
            'cart_id': _id,
            'product_id': produto.id,
            'quantity': quantidade,
            'notes': (observacao?.isEmpty ?? true) ? null : observacao,
          })
          .select('id')
          .single();

      if (adicionais.isNotEmpty) {
        await banco.from('cart_item_addons').insert([
          for (final a in adicionais)
            {
              'cart_item_id': item['id'],
              'addon_id': a.adicional.id,
              'quantity': a.quantidade,
            }
        ]);
      }
    });

    await _lerItens();
    notifyListeners();
  }

  Future<void> alterarQuantidade(String itemId, int quantidade) async {
    if (quantidade <= 0) return remover(itemId);

    await executar(() => banco
        .from('cart_items')
        .update({'quantity': quantidade}).eq('id', itemId));

    await _lerItens();
    notifyListeners();
  }

  Future<void> remover(String itemId) async {
    await executar(() => banco.from('cart_items').delete().eq('id', itemId));
    await _lerItens();
    if (_itens.isEmpty) await esvaziar();
    notifyListeners();
  }

  Future<void> esvaziar() async {
    final id = _id;
    if (id == null) return;
    await executar(() => banco.from('carts').delete().eq('id', id));
    _id = null;
    _restaurante = null;
    _itens = const [];
    notifyListeners();
  }

  /// Esquece o carrinho sem apagar nada — usado depois do fechamento, quando o
  /// próprio `fechar_pedido` já removeu a linha no banco.
  void esquecer() {
    _id = null;
    _restaurante = null;
    _itens = const [];
    notifyListeners();
  }
}
