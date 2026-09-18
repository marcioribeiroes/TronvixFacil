/// O carrinho, antes de virar pedido.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/carrinho.dart';
import '../formato.dart';
import '../tema.dart';
import 'checkout.dart';

class TelaCarrinho extends StatelessWidget {
  const TelaCarrinho({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Carrinho.instancia,
        builder: (context, _) {
          final carrinho = Carrinho.instancia;
          final restaurante = carrinho.restaurante;

          if (carrinho.vazio || restaurante == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Seu pedido')),
              body: const Vazio(
                icone: Icons.shopping_basket_outlined,
                titulo: 'Carrinho vazio',
                detalhe: 'Escolha um restaurante e monte seu pedido.',
              ),
            );
          }

          final falta = carrinho.faltaParaOMinimo();
          final taxa = restaurante.taxaPara(carrinho.subtotalCentavos);

          return Scaffold(
            appBar: AppBar(
              title: const Text('Seu pedido'),
              actions: [
                IconButton(
                  tooltip: 'Esvaziar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final confirmou = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Esvaziar o carrinho?'),
                        content: const Text('Os itens escolhidos são descartados.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Não')),
                          FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Esvaziar')),
                        ],
                      ),
                    );
                    if (confirmou == true) {
                      await carrinho.esvaziar();
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            ),
            body: ListView(
              children: [
                ListTile(
                  leading: Foto(
                      url: restaurante.logoUrl,
                      largura: 44,
                      altura: 44,
                      icone: Icons.storefront),
                  title: Text(restaurante.nome,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(faixaDeMinutos(
                      restaurante.minutosDePreparo, restaurante.minutosDeEntrega)),
                ),
                const Divider(),
                for (final item in carrinho.itens)
                  _LinhaDoItem(item: item, carrinho: carrinho),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Column(
                    children: [
                      LinhaDeValor(
                          rotulo: 'Subtotal',
                          centavos: carrinho.subtotalCentavos),
                      LinhaDeValor(
                        rotulo: 'Entrega',
                        centavos: taxa,
                        gratis: taxa == 0,
                      ),
                    ],
                  ),
                ),
                // O total final sai do banco no fechamento. Aqui é estimativa,
                // e a tela diz isso em vez de fingir precisão.
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'Cupom e forma de pagamento na próxima tela.',
                    style: TextStyle(fontSize: 12.5, color: Cores.textoSuave),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: BarraDeAcao(
              acima: falta > 0
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Cores.realce,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Faltam ${emReais(falta)} para o pedido mínimo deste estabelecimento.',
                        style: const TextStyle(
                            color: Cores.marcaEscura, fontSize: 13),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total parcial',
                            style: TextStyle(color: Cores.textoSuave)),
                        Text(emReais(carrinho.subtotalCentavos + taxa),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                      ],
                    ),
              filho: FilledButton(
                onPressed: falta > 0
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const TelaCheckout()),
                        ),
                child: const Text('Continuar'),
              ),
            ),
          );
        },
      );
}

class _LinhaDoItem extends StatelessWidget {
  const _LinhaDoItem({required this.item, required this.carrinho});

  final ItemDoCarrinho item;
  final Carrinho carrinho;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Foto(url: item.produto.imagemUrl, largura: 56, altura: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.produto.nome,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  for (final a in item.adicionais)
                    Text(
                      '+ ${a.quantidade > 1 ? '${a.quantidade}× ' : ''}${a.adicional.nome}',
                      style: const TextStyle(
                          fontSize: 12.5, color: Cores.textoSuave),
                    ),
                  if (item.observacao != null && item.observacao!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('“${item.observacao}”',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                              color: Cores.textoSuave)),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Quantidade(
                        compacto: true,
                        minimo: 0,
                        valor: item.quantidade,
                        aoMudar: (v) => carrinho.alterarQuantidade(item.id, v),
                      ),
                      Text(emReais(item.totalCentavos),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
