/// Meus pedidos.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/pedidos.dart';
import '../formato.dart';
import '../main.dart';
import '../modelos/modelos.dart';
import '../sessao.dart';
import '../tema.dart';
import 'acompanhar.dart';

class TelaMeusPedidos extends StatefulWidget {
  const TelaMeusPedidos({super.key});

  @override
  State<TelaMeusPedidos> createState() => _TelaMeusPedidosState();
}

class _TelaMeusPedidosState extends State<TelaMeusPedidos> {
  List<Pedido> _pedidos = const [];
  bool _carregando = true;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (!Sessao.instancia.autenticado) {
      setState(() => _carregando = false);
      return;
    }
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final pedidos = await Pedidos.meus();
      if (!mounted) return;
      setState(() {
        _pedidos = pedidos;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e;
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Seus pedidos')),
        body: ListenableBuilder(
          listenable: Sessao.instancia,
          builder: (context, _) {
            if (!Sessao.instancia.autenticado) {
              return Vazio(
                icone: Icons.receipt_long_outlined,
                titulo: 'Entre para ver seus pedidos',
                detalhe: 'Seu histórico fica na sua conta, não no aparelho.',
                acao: FilledButton(
                  onPressed: () async {
                    if (await exigirConta(context)) _carregar();
                  },
                  child: const Text('Entrar'),
                ),
              );
            }

            if (_carregando) return const Carregando();
            if (_erro != null) {
              return Falhou(erro: _erro!, aoTentarDeNovo: _carregar);
            }
            if (_pedidos.isEmpty) {
              return const Vazio(
                icone: Icons.receipt_long_outlined,
                titulo: 'Nenhum pedido ainda',
                detalhe: 'Quando você pedir, o histórico aparece aqui.',
              );
            }

            return RefreshIndicator(
              onRefresh: _carregar,
              child: ListView.separated(
                itemCount: _pedidos.length,
                separatorBuilder: (_, _) => const Divider(indent: 16),
                itemBuilder: (_, i) => _linha(_pedidos[i]),
              ),
            );
          },
        ),
      );

  Widget _linha(Pedido p) {
    final cor = switch (p.status) {
      StatusDoPedido.entregue => Cores.sucesso,
      StatusDoPedido.cancelado || StatusDoPedido.recusado => Cores.perigo,
      _ => Cores.marca,
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Foto(
          url: p.logoDoRestaurante,
          largura: 48,
          altura: 48,
          icone: Icons.storefront),
      title: Text(p.nomeDoRestaurante ?? 'Pedido nº ${p.numero}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'nº ${p.numero} · ${p.quantidadeDeItens} item(ns) · ${haQuantoTempo(p.criadoEm)}',
              style: const TextStyle(fontSize: 12.5, color: Cores.textoSuave),
            ),
            const SizedBox(height: 6),
            Etiqueta(p.status.paraOCliente, cor: cor),
          ],
        ),
      ),
      trailing: Text(emReais(p.totalCentavos),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (_) => TelaAcompanhar(pedidoId: p.id)))
          .then((_) => _carregar()),
    );
  }
}
