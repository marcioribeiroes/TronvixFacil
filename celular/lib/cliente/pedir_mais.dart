/// Pedir mais, sentado na mesa.
///
/// As escolhas juntam aqui e vão para a cozinha de uma vez, no mesmo pedido e
/// na mesma conta. Nada vai antes de "Enviar": quem escolheu duas sobremesas e
/// desistiu de uma não incomoda a cozinha duas vezes.
library;

import 'package:flutter/material.dart';

import '../comum/escolher_do_cardapio.dart';
import '../comum/widgets.dart';
import '../dados/edicao.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../tema.dart';

class TelaPedirMais extends StatefulWidget {
  const TelaPedirMais({super.key, required this.pedido});
  final Pedido pedido;

  @override
  State<TelaPedirMais> createState() => _TelaPedirMaisState();
}

class _TelaPedirMaisState extends State<TelaPedirMais> {
  final List<EscolhaDoProduto> _escolhas = [];
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    // Abre direto no cardápio: quem tocou em "Pedir mais" já sabe o que quer.
    WidgetsBinding.instance.addPostFrameCallback((_) => _acrescentar());
  }

  Future<void> _acrescentar() async {
    final escolha = await Navigator.of(context).push<EscolhaDoProduto>(
      MaterialPageRoute(
        builder: (_) =>
            TelaEscolherDoCardapio(restauranteId: widget.pedido.restauranteId),
      ),
    );
    if (escolha != null && mounted) setState(() => _escolhas.add(escolha));
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    try {
      await EdicaoDoPedido.pedirMais(widget.pedido.id, _escolhas);
      if (!mounted) return;
      avisar(context, 'Enviado para a cozinha.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _escolhas.fold<int>(0, (s, e) => s + e.totalCentavos);
    final p = widget.pedido;

    return Scaffold(
      appBar: AppBar(title: const Text('Pedir mais')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '${p.rotuloDaMesa ?? 'Mesa'} · pedido nº ${p.numero}. '
              'O que você escolher entra no mesmo pedido e na mesma conta.',
              style: const TextStyle(color: Cores.textoSuave),
            ),
          ),
          if (_escolhas.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Vazio(
                icone: Icons.restaurant_menu,
                titulo: 'Nada escolhido ainda',
                detalhe: 'Toque em "Escolher item" para ver o cardápio.',
              ),
            ),
          for (final e in _escolhas)
            ListTile(
              title: Text(
                '${e.quantidade}× ${e.produto.nome}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                [
                  for (final a in e.adicionais) '+ ${a.adicional.nome}',
                  if (e.observacao.trim().isNotEmpty)
                    '“${e.observacao.trim()}”',
                ].join('\n'),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emReais(e.totalCentavos)),
                  IconButton(
                    tooltip: 'Tirar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _escolhas.remove(e)),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _enviando ? null : _acrescentar,
              icon: const Icon(Icons.add),
              label: const Text('Escolher item'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _escolhas.isEmpty
          ? null
          : BarraDeAcao(
              filho: FilledButton(
                onPressed: _enviando ? null : _enviar,
                child: Text(
                  _enviando
                      ? 'Enviando…'
                      : 'Enviar para a cozinha · ${emReais(total)}',
                ),
              ),
            ),
    );
  }
}
