/// Um pedido visto do balcão: o que fazer, e o que dizer ao cliente.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/balcao.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../tema.dart';

class TelaPedidoDoBalcao extends StatefulWidget {
  const TelaPedidoDoBalcao({super.key, required this.pedido});
  final Pedido pedido;

  @override
  State<TelaPedidoDoBalcao> createState() => _TelaPedidoDoBalcaoState();
}

class _TelaPedidoDoBalcaoState extends State<TelaPedidoDoBalcao> {
  late final Pedido _pedido = widget.pedido;
  bool _ocupado = false;

  @override
  Widget build(BuildContext context) {
    final p = _pedido;
    final destino = Balcao.proximoPasso(p);

    return Scaffold(
      appBar: AppBar(title: Text('Pedido nº ${p.numero}')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Container(
            width: double.infinity,
            color: Cores.suave,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Etiqueta(p.status.paraORestaurante, cor: Cores.marca, forte: true),
                    const SizedBox(width: 10),
                    Text(haQuantoTempo(p.criadoEm),
                        style: const TextStyle(
                            fontSize: 12.5, color: Cores.textoSuave)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(p.nomeDoCliente,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800)),
                if (p.telefoneDoCliente != null)
                  Text(telefone(p.telefoneDoCliente),
                      style: const TextStyle(color: Cores.textoSuave)),
              ],
            ),
          ),
          ListTile(
            leading: Icon(p.tipo == TipoDeEntrega.entrega
                ? Icons.delivery_dining
                : Icons.storefront),
            title: Text(p.tipo.rotulo),
            subtitle: p.tipo == TipoDeEntrega.entrega
                ? Text('${p.resumoDoEndereco ?? ''}\n'
                    '${p.bairroDoEndereco ?? ''} · ${p.cidadeDoEndereco ?? ''}')
                : const Text('O cliente vem buscar'),
            isThreeLine: p.tipo == TipoDeEntrega.entrega,
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(p.pagamento?.forma.rotulo ?? 'Pagamento'),
            subtitle: Text(
              p.pagamento?.momento == MomentoDoPagamento.naEntrega
                  ? 'Receber na entrega'
                  : 'Pago pelo aplicativo',
            ),
            // Troco é informação de operação: quem monta a sacola precisa
            // separar o dinheiro antes de o entregador sair.
            trailing: p.pagamento?.trocoParaCentavos == null
                ? null
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Troco',
                          style: TextStyle(fontSize: 11, color: Cores.textoSuave)),
                      Text(emReais(p.pagamento!.trocoCentavos),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
          ),
          if (p.observacao != null && p.observacao!.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Cores.realce,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: Cores.marcaEscura),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p.observacao!,
                        style: const TextStyle(
                            color: Cores.marcaEscura, height: 1.4)),
                  ),
                ],
              ),
            ),
          const Divider(),
          for (final i in p.itens)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Cores.realce,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${i.quantidade}×',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Cores.marca,
                            fontSize: 13)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.nomeDoProduto,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        for (final a in i.adicionais)
                          Text('+ ${a.nome}',
                              style: const TextStyle(
                                  fontSize: 13, color: Cores.textoSuave)),
                        if (i.observacao != null && i.observacao!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('“${i.observacao}”',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Cores.marcaEscura)),
                          ),
                      ],
                    ),
                  ),
                  Text(emReais(i.totalCentavos),
                      style: const TextStyle(color: Cores.textoSuave)),
                ],
              ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                LinhaDeValor(rotulo: 'Subtotal', centavos: p.subtotalCentavos),
                LinhaDeValor(
                    rotulo: 'Entrega',
                    centavos: p.taxaDeEntregaCentavos,
                    gratis: p.taxaDeEntregaCentavos == 0),
                if (p.descontoCentavos > 0)
                  LinhaDeValor(
                      rotulo: 'Cupom ${p.codigoDoCupom ?? ''}',
                      centavos: p.descontoCentavos,
                      desconto: true),
                const Divider(height: 20),
                LinhaDeValor(
                    rotulo: 'Total', centavos: p.totalCentavos, forte: true),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: destino == null
          ? null
          : BarraDeAcao(
              acima: p.status == StatusDoPedido.recebido
                  ? OutlinedButton(
                      onPressed: _ocupado ? null : _recusar,
                      style:
                          OutlinedButton.styleFrom(foregroundColor: Cores.perigo),
                      child: const Text('Recusar pedido'),
                    )
                  : null,
              filho: FilledButton(
                onPressed: _ocupado ? null : () => _avancar(destino),
                child: Text(Balcao.rotuloDoPasso(destino)),
              ),
            ),
    );
  }

  Future<void> _avancar(StatusDoPedido destino) async {
    setState(() => _ocupado = true);
    try {
      await Balcao.avancar(_pedido, destino);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Recusar exige motivo.
  ///
  /// O motivo vai para `cancellation_reason`, o gatilho o copia para o
  /// histórico, e é ele que o cliente lê na tela de acompanhamento. Recusa sem
  /// explicação é a reclamação do dia seguinte.
  Future<void> _recusar() async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (contexto) {
        final campo = TextEditingController();
        return AlertDialog(
          title: const Text('Recusar o pedido'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'O cliente vê esta mensagem. Diga o motivo — acabou o item, '
                'fora da área, fechando a cozinha.',
                style: TextStyle(fontSize: 13.5, color: Cores.textoSuave),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: campo,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Motivo'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(contexto),
                child: const Text('Voltar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Cores.perigo),
              onPressed: () => Navigator.pop(contexto, campo.text.trim()),
              child: const Text('Recusar'),
            ),
          ],
        );
      },
    );

    if (motivo == null || motivo.isEmpty) return;

    setState(() => _ocupado = true);
    try {
      await Balcao.recusar(_pedido.id, motivo);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }
}
