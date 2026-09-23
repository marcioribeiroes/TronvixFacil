/// A faixa do carrinho aberto.
///
/// Morava dentro de `inicio.dart`, privada, e aparecia acima da barra de abas
/// — ou seja, só nas telas de aba. O cardápio da loja é empilhado por cima
/// delas, então quem adicionava um item **ali** não via nada acontecer: a tela
/// voltava ao cardápio, sem contador, sem aviso e sem caminho para frente. A
/// barra reaparecia só depois de sair da loja.
///
/// Era o pior lugar possível para faltar, porque o cardápio é a única tela em
/// que se adiciona alguma coisa. Por isso ela mora aqui agora, e as duas telas
/// usam a mesma.
library;

import 'package:flutter/material.dart';

import '../cliente/carrinho.dart';
import '../dados/carrinho.dart';
import '../sessao.dart';
import '../formato.dart';
import '../tema.dart';

class BarraDoCarrinho extends StatelessWidget {
  const BarraDoCarrinho({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Carrinho.instancia,
        builder: (context, _) {
          final carrinho = Carrinho.instancia;
          if (carrinho.vazio || !Sessao.instancia.autenticado) {
            return const SizedBox.shrink();
          }

          return Material(
            // A chave existe para o passeio de capturas conseguir tocar a
            // barra: ela é a única coisa na tela sem texto próprio estável.
            key: const Key('barra-do-carrinho'),
            color: Cores.marca,
            child: SafeArea(
              top: false,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TelaCarrinho()),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Empurraozinho(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${carrinho.quantidadeDeItens}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              carrinho.restaurante?.nome ?? 'Seu pedido',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            emReais(carrinho.subtotalCentavos),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

/// A linha de cima: o que falta para o pedido andar, ou para o frete sumir.
///
/// A loja já guarda os dois números — `min_order_cents` e
/// `free_delivery_above_cents` — e até aqui ninguém ligava os pontos: o
/// cardápio dizia "Mínimo R$ 30,00" numa tela, o carrinho somava R$ 22,00 em
/// outra, e a conta ficava por conta do cliente.
///
/// O mínimo vem antes do frete grátis quando os dois faltam: um impede o
/// pedido de existir, o outro é só uma economia. Dizer da economia primeiro
/// seria esconder o que trava.
class _Empurraozinho extends StatelessWidget {
  const _Empurraozinho();

  @override
  Widget build(BuildContext context) {
    final carrinho = Carrinho.instancia;
    final faltaMinimo = carrinho.faltaParaOMinimo();
    final faltaFrete = carrinho.faltaParaEntregaGratis();

    final (texto, icone) = switch ((faltaMinimo, faltaFrete)) {
      (> 0, _) => ('Faltam ${emReais(faltaMinimo)} para o pedido mínimo', Icons.remove_shopping_cart_outlined),
      (_, > 0) => ('Faltam ${emReais(faltaFrete)} para a entrega sair de graça', Icons.local_shipping_outlined),
      _ when carrinho.restaurante?.entregaGratisAcimaDeCentavos != null =>
        ('Entrega grátis garantida', Icons.check_circle_outline),
      _ => (null, Icons.check),
    };

    if (texto == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Colors.black.withValues(alpha: 0.16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          Icon(icone, size: 15, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
