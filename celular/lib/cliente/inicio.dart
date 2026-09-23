/// O aplicativo de quem pede.
///
/// Três abas e uma barra de carrinho que acompanha a pessoa por todas elas —
/// sair do carrinho para olhar outra coisa não pode significar perder o pedido
/// pela metade.
library;

import 'package:flutter/material.dart';

import '../comum/barra_do_carrinho.dart';

import '../ambiente.dart';
import '../comum/widgets.dart';
import '../tema.dart';
import '../dados/mesa.dart';
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
        const BarraDoCarrinho(),
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

