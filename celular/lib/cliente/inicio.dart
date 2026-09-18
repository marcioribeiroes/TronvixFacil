/// O aplicativo de quem pede.
///
/// Três abas e uma barra de carrinho que acompanha a pessoa por todas elas —
/// sair do carrinho para olhar outra coisa não pode significar perder o pedido
/// pela metade.
library;

import 'package:flutter/material.dart';

import '../ambiente.dart';
import '../comum/widgets.dart';
import '../dados/carrinho.dart';
import '../formato.dart';
import '../sessao.dart';
import '../tema.dart';
import '../dados/mesa.dart';
import 'carrinho.dart';
import 'faixa_da_mesa.dart';
import 'ler_mesa.dart';
import 'conta.dart';
import 'pedidos.dart';
import 'restaurante.dart';
import 'vitrine.dart';

class InicioDoCliente extends StatefulWidget {
  const InicioDoCliente({super.key});

  @override
  State<InicioDoCliente> createState() => _InicioDoClienteState();
}

class _InicioDoClienteState extends State<InicioDoCliente> {
  int _aba = 0;

  /// Abre a câmera e, se a leitura for boa, senta a pessoa na mesa e leva ao
  /// cardápio daquele restaurante — que é o que ela quer ver depois de sentar.
  Future<void> _lerMesa() async {
    final mesa = await Navigator.of(
      context,
    ).push<Mesa>(MaterialPageRoute(builder: (_) => const LerMesa()));
    if (mesa == null || !mounted) return;

    MesaAtual.instancia.sentar(mesa);
    if (!Ambiente.unico) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TelaRestaurante.porSlug(mesa.restauranteSlug),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const FaixaDaMesa(),
        Expanded(
          child: IndexedStack(
            index: _aba,
            children: [
              // No modo único não há vitrine: a primeira tela é o cardápio da
              // loja. Quem instalou o aplicativo do restaurante não quer escolher
              // restaurante.
              if (!Ambiente.unico)
                TelaVitrine(aoLerMesa: _lerMesa)
              else if (Ambiente.coerente)
                TelaRestaurante.porSlug(Ambiente.estabelecimento)
              else
                const Vazio(
                  icone: Icons.storefront_outlined,
                  titulo: 'Falta dizer de quem é este aplicativo',
                  detalhe: Ambiente.instrucaoDoModoUnico,
                ),
              const TelaMeusPedidos(),
              const TelaConta(),
            ],
          ),
        ),
      ],
    ),
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BarraDoCarrinho(),
        NavigationBar(
          selectedIndex: _aba,
          onDestinationSelected: (i) => setState(() => _aba = i),
          backgroundColor: Cores.fundo,
          indicatorColor: Cores.realce,
          destinations: [
            NavigationDestination(
              icon: Icon(Ambiente.unico ? Icons.restaurant_menu : Icons.search),
              label: Ambiente.unico ? 'Cardápio' : 'Descobrir',
            ),
            const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Pedidos',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Conta',
            ),
          ],
        ),
      ],
    ),
  );
}

/// A faixa que aparece acima da barra de abas quando há carrinho aberto.
class _BarraDoCarrinho extends StatelessWidget {
  const _BarraDoCarrinho();

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
        child: InkWell(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TelaCarrinho())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        ),
      );
    },
  );
}
