/// Lançar um pedido do zero, pelo balcão: o que chega pelo telefone, pelo
/// garçom ou por quem está de pé na frente do caixa.
///
/// Nada vai para o banco até "Lançar pedido". O total é prévia; frete e preço
/// de verdade são os que `lancar_pedido` calcula.
library;

import 'package:flutter/material.dart';

import '../comum/escolher_do_cardapio.dart';
import '../comum/widgets.dart';
import '../dados/edicao.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../tema.dart';

class TelaLancarPedido extends StatefulWidget {
  const TelaLancarPedido({super.key, required this.restaurante});
  final Restaurante restaurante;

  @override
  State<TelaLancarPedido> createState() => _TelaLancarPedidoState();
}

class _TelaLancarPedidoState extends State<TelaLancarPedido> {
  final _cliente = TextEditingController();
  final _telefone = TextEditingController();
  final _mesa = TextEditingController();
  final _rua = TextEditingController();
  final _numero = TextEditingController();
  final _complemento = TextEditingController();
  final _bairro = TextEditingController();
  final _troco = TextEditingController();
  final _observacao = TextEditingController();

  TipoDeEntrega _tipo = TipoDeEntrega.retirada;
  FormaDePagamento _forma = FormaDePagamento.dinheiro;
  bool _receberAgora = false;
  List<({String id, String rotulo})> _mesas = const [];
  String? _mesaId;
  final List<EscolhaDoProduto> _itens = [];
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    Lancamento.mesas(widget.restaurante.id)
        .then((mesas) {
          if (!mounted) return;
          setState(() {
            _mesas = mesas;
            _mesaId = mesas.isEmpty ? null : mesas.first.id;
          });
        })
        .catchError((_) {
          // Sem a lista, o garçom escreve o nome da mesa.
        });
  }

  @override
  void dispose() {
    for (final c in [
      _cliente,
      _telefone,
      _mesa,
      _rua,
      _numero,
      _complemento,
      _bairro,
      _troco,
      _observacao,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _subtotal => _itens.fold(0, (s, i) => s + i.totalCentavos);

  int get _frete {
    if (_tipo != TipoDeEntrega.entrega) return 0;
    final gratis = widget.restaurante.entregaGratisAcimaDeCentavos;
    if (gratis != null && _subtotal >= gratis) return 0;
    return widget.restaurante.taxaDeEntregaCentavos;
  }

  Future<void> _acrescentar() async {
    final escolha = await Navigator.of(context).push<EscolhaDoProduto>(
      MaterialPageRoute(
        builder: (_) =>
            TelaEscolherDoCardapio(restauranteId: widget.restaurante.id),
      ),
    );
    if (escolha != null) setState(() => _itens.add(escolha));
  }

  Future<void> _lancar() async {
    setState(() => _enviando = true);
    try {
      final troco = _forma == FormaDePagamento.dinheiro && !_receberAgora
          ? paraCentavos(_troco.text)
          : null;
      await Lancamento.lancar(
        widget.restaurante.id,
        tipo: _tipo,
        itens: _itens,
        forma: _forma,
        cliente: _cliente.text,
        telefone: _telefone.text,
        mesaId: _tipo == TipoDeEntrega.mesa ? _mesaId : null,
        mesa: _mesa.text,
        endereco: _tipo == TipoDeEntrega.entrega
            ? {
                'rua': _rua.text.trim(),
                'numero': _numero.text.trim(),
                'complemento': _complemento.text.trim(),
                'bairro': _bairro.text.trim(),
              }
            : const {},
        trocoParaCentavos: troco != null && troco > 0 ? troco : null,
        receberAgora: _receberAgora,
        observacao: _observacao.text,
      );
      if (!mounted) return;
      avisar(context, 'Pedido lançado.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Widget _campo(
    TextEditingController c,
    String rotulo, {
    TextInputType? teclado,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: TextField(
      controller: c,
      keyboardType: teclado,
      decoration: InputDecoration(labelText: rotulo),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo pedido')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: SegmentedButton<TipoDeEntrega>(
              segments: const [
                ButtonSegment(
                  value: TipoDeEntrega.retirada,
                  label: Text('Balcão'),
                  icon: Icon(Icons.storefront),
                ),
                ButtonSegment(
                  value: TipoDeEntrega.mesa,
                  label: Text('Mesa'),
                  icon: Icon(Icons.table_restaurant),
                ),
                ButtonSegment(
                  value: TipoDeEntrega.entrega,
                  label: Text('Entrega'),
                  icon: Icon(Icons.delivery_dining),
                ),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() => _tipo = s.first),
            ),
          ),
          _campo(_cliente, 'Cliente'),
          _campo(
            _telefone,
            _tipo == TipoDeEntrega.entrega ? 'Telefone' : 'Telefone (opcional)',
            teclado: TextInputType.phone,
          ),
          if (_tipo == TipoDeEntrega.mesa)
            _mesas.isEmpty
                ? _campo(_mesa, 'Mesa')
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: DropdownButtonFormField<String>(
                      initialValue: _mesaId,
                      decoration: const InputDecoration(labelText: 'Mesa'),
                      items: [
                        for (final m in _mesas)
                          DropdownMenuItem(value: m.id, child: Text(m.rotulo)),
                      ],
                      onChanged: (v) => setState(() => _mesaId = v),
                    ),
                  ),
          if (_tipo == TipoDeEntrega.entrega) ...[
            _campo(_rua, 'Rua'),
            _campo(_numero, 'Número'),
            _campo(_complemento, 'Complemento'),
            _campo(_bairro, 'Bairro'),
          ],
          _campo(_observacao, 'Observação do pedido'),
          const Divider(height: 28),
          for (final i in _itens)
            ListTile(
              title: Text(
                '${i.quantidade}× ${i.produto.nome}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: i.adicionais.isEmpty && i.observacao.trim().isEmpty
                  ? null
                  : Text(
                      [
                        for (final a in i.adicionais) '+ ${a.adicional.nome}',
                        if (i.observacao.trim().isNotEmpty)
                          '“${i.observacao.trim()}”',
                      ].join('\n'),
                    ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emReais(i.totalCentavos)),
                  IconButton(
                    tooltip: 'Tirar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _itens.remove(i)),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _enviando ? null : _acrescentar,
              icon: const Icon(Icons.add),
              label: const Text('Escolher item'),
            ),
          ),
          const Divider(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<FormaDePagamento>(
              initialValue: _forma,
              decoration: const InputDecoration(labelText: 'Pagamento'),
              items: [
                for (final f in FormaDePagamento.values)
                  DropdownMenuItem(value: f, child: Text(f.rotulo)),
              ],
              onChanged: (v) => setState(() => _forma = v ?? _forma),
            ),
          ),
          if (_forma == FormaDePagamento.dinheiro && !_receberAgora)
            _campo(
              _troco,
              'Troco para (opcional)',
              teclado: const TextInputType.numberWithOptions(decimal: true),
            ),
          SwitchListTile(
            title: const Text('Já recebido'),
            subtitle: const Text('O cliente pagou agora, no balcão'),
            value: _receberAgora,
            onChanged: (v) => setState(() => _receberAgora = v),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                LinhaDeValor(rotulo: 'Subtotal', centavos: _subtotal),
                if (_tipo == TipoDeEntrega.entrega)
                  LinhaDeValor(
                    rotulo: 'Entrega',
                    centavos: _frete,
                    gratis: _frete == 0,
                  ),
                const Divider(height: 20),
                LinhaDeValor(
                  rotulo: 'Total',
                  centavos: _subtotal + _frete,
                  forte: true,
                ),
              ],
            ),
          ),
          if (_itens.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Escolha ao menos um item para lançar.',
                style: TextStyle(color: Cores.textoSuave),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BarraDeAcao(
        filho: FilledButton(
          onPressed: _enviando || _itens.isEmpty ? null : _lancar,
          child: Text(_enviando ? 'Lançando…' : 'Lançar pedido'),
        ),
      ),
    );
  }
}
