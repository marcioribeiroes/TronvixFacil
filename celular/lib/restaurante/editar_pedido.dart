/// O pedido aberto na mão do balcão: mudar quantidades, tirar e acrescentar.
///
/// Nada vai para o banco até "Salvar". O total da tela é prévia; a conta que
/// vale é a que `editar_pedido` refaz.
library;

import 'package:flutter/material.dart';

import '../comum/escolher_do_cardapio.dart';
import '../comum/widgets.dart';
import '../dados/edicao.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../tema.dart';

class TelaEditarPedido extends StatefulWidget {
  const TelaEditarPedido({super.key, required this.pedido});
  final Pedido pedido;

  @override
  State<TelaEditarPedido> createState() => _TelaEditarPedidoState();
}

class _TelaEditarPedidoState extends State<TelaEditarPedido> {
  late final Map<String, int> _quantidades = {
    for (final i in widget.pedido.itens) i.id: i.quantidade,
  };
  final List<EscolhaDoProduto> _novos = [];
  bool _salvando = false;

  Pedido get _p => widget.pedido;

  int get _subtotal =>
      _p.itens.fold<int>(
        0,
        (s, i) =>
            s +
            (i.precoUnitarioCentavos + i.totalDosAdicionaisCentavos) *
                (_quantidades[i.id] ?? 0),
      ) +
      _novos.fold<int>(0, (s, n) => s + n.totalCentavos);

  int get _total {
    final desconto = _p.descontoCentavos.clamp(
      0,
      _subtotal + _p.taxaDeEntregaCentavos,
    );
    return _subtotal + _p.taxaDeEntregaCentavos - desconto;
  }

  Map<String, int> get _mudados => {
    for (final i in _p.itens)
      if (_quantidades[i.id] != i.quantidade) i.id: _quantidades[i.id]!,
  };

  bool get _nadaMudou => _mudados.isEmpty && _novos.isEmpty;

  Future<void> _acrescentar() async {
    final escolha = await Navigator.of(context).push<EscolhaDoProduto>(
      MaterialPageRoute(
        builder: (_) => TelaEscolherDoCardapio(restauranteId: _p.restauranteId),
      ),
    );
    if (escolha != null) setState(() => _novos.add(escolha));
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      await EdicaoDoPedido.editar(_p.id, quantidades: _mudados, novos: _novos);
      if (!mounted) return;
      avisar(context, 'Pedido nº ${_p.numero} atualizado.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Editar pedido nº ${_p.numero}')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final i in _p.itens) _itemExistente(i),
          for (final n in _novos) _itemNovo(n),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: OutlinedButton.icon(
              onPressed: _salvando ? null : _acrescentar,
              icon: const Icon(Icons.add),
              label: const Text('Acrescentar item'),
            ),
          ),
          const Divider(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                LinhaDeValor(rotulo: 'Subtotal', centavos: _subtotal),
                if (_p.taxaDeEntregaCentavos > 0)
                  LinhaDeValor(
                    rotulo: 'Entrega',
                    centavos: _p.taxaDeEntregaCentavos,
                  ),
                const Divider(height: 20),
                LinhaDeValor(
                  rotulo: 'Novo total',
                  centavos: _total,
                  forte: true,
                ),
              ],
            ),
          ),
          if (_subtotal == 0)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'O pedido não pode ficar sem itens. Para desistir de tudo, '
                'recuse ou cancele o pedido.',
                style: TextStyle(color: Cores.textoSuave),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BarraDeAcao(
        filho: FilledButton(
          onPressed: _salvando || _nadaMudou || _subtotal == 0 ? null : _salvar,
          child: Text(_salvando ? 'Salvando…' : 'Salvar alterações'),
        ),
      ),
    );
  }

  Widget _itemExistente(ItemDoPedido i) {
    final q = _quantidades[i.id] ?? 0;
    return Opacity(
      opacity: q == 0 ? 0.45 : 1,
      child: ListTile(
        title: Text(
          i.nomeDoProduto,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            decoration: q == 0 ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          [
            for (final a in i.adicionais) '+ ${a.nome}',
            if (i.observacao != null && i.observacao!.isNotEmpty)
              '“${i.observacao}”',
            emReais(
              (i.precoUnitarioCentavos + i.totalDosAdicionaisCentavos) * q,
            ),
          ].join('\n'),
        ),
        isThreeLine: i.adicionais.isNotEmpty || i.observacao != null,
        trailing: Quantidade(
          compacto: true,
          minimo: 0,
          maximo: 99,
          valor: q,
          aoMudar: (v) => setState(() => _quantidades[i.id] = v),
        ),
      ),
    );
  }

  Widget _itemNovo(EscolhaDoProduto n) => Container(
    color: Cores.realce,
    child: ListTile(
      title: Row(
        children: [
          Flexible(
            child: Text(
              '${n.quantidade}× ${n.produto.nome}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          const Etiqueta('novo', cor: Cores.marca),
        ],
      ),
      subtitle: Text(
        [
          for (final a in n.adicionais)
            '+ ${a.quantidade > 1 ? '${a.quantidade}× ' : ''}${a.adicional.nome}',
          if (n.observacao.trim().isNotEmpty) '“${n.observacao.trim()}”',
          emReais(n.totalCentavos),
        ].join('\n'),
      ),
      trailing: IconButton(
        tooltip: 'Tirar',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => setState(() => _novos.remove(n)),
      ),
    ),
  );
}
