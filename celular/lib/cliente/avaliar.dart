/// A nota do pedido que chegou.
///
/// Espelho de src/components/cliente/avaliar-pedido.tsx. O estabelecimento
/// sempre; o entregador quando houve entrega. Avaliar de novo corrige — quem
/// deu 2 no calor da fome e pensou melhor depois não fica preso à primeira
/// nota.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/pedidos.dart';
import '../tema.dart';

class AvaliarPedido extends StatefulWidget {
  const AvaliarPedido({
    super.key,
    required this.pedidoId,
    required this.comEntregador,
  });

  final String pedidoId;
  final bool comEntregador;

  @override
  State<AvaliarPedido> createState() => _AvaliarPedidoState();
}

class _AvaliarPedidoState extends State<AvaliarPedido> {
  final _comentario = TextEditingController();
  int _loja = 0;
  int _entregador = 0;
  bool _jaAvaliou = false;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final r = await Pedidos.minhaAvaliacao(widget.pedidoId);
      if (!mounted || r == null) return;
      setState(() {
        _jaAvaliou = true;
        _loja = (r['restaurant_rating'] as int?) ?? 0;
        _entregador = (r['courier_rating'] as int?) ?? 0;
        _comentario.text = (r['comment'] as String?) ?? '';
      });
    } catch (_) {
      // Sem a avaliação anterior, a tela começa em branco: dá para avaliar
      // do mesmo jeito.
    }
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    try {
      await Pedidos.avaliar(
        pedidoId: widget.pedidoId,
        notaDaLoja: _loja,
        notaDoEntregador:
            widget.comEntregador && _entregador > 0 ? _entregador : null,
        comentario: _comentario.text,
      );
      if (!mounted) return;
      setState(() => _jaAvaliou = true);
      avisar(context, 'Obrigado pela avaliação!');
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Widget _estrelas(String rotulo, int nota, ValueChanged<int> aoEscolher) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, style: const TextStyle(fontWeight: FontWeight.w700)),
          Row(
            children: [
              for (var n = 1; n <= 5; n++)
                IconButton(
                  tooltip: '$n ${n == 1 ? 'estrela' : 'estrelas'}',
                  onPressed: () => aoEscolher(n),
                  icon: Icon(
                    n <= nota ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 32,
                    color: n <= nota ? Cores.atencao : Cores.borda,
                  ),
                ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_jaAvaliou ? 'Sua avaliação' : 'Como foi o pedido?',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _estrelas('Estabelecimento', _loja, (n) => setState(() => _loja = n)),
            if (widget.comEntregador)
              _estrelas(
                  'Entregador', _entregador, (n) => setState(() => _entregador = n)),
            TextField(
              controller: _comentario,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(
                  hintText: 'Quer contar mais? (opcional)'),
            ),
            FilledButton(
              onPressed: _enviando || _loja == 0 ? null : _enviar,
              child: Text(_enviando
                  ? 'Enviando…'
                  : _jaAvaliou
                      ? 'Atualizar avaliação'
                      : 'Enviar avaliação'),
            ),
          ],
        ),
      );
}
