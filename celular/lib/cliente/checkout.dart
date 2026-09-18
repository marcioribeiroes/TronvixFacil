/// Fechar o pedido.
///
/// A tela pergunta quatro coisas — onde entregar, como pagar, cupom,
/// observação — e manda só isso. O total que ela mostra é estimativa; o total
/// que vale é o que `fechar_pedido` devolve, recalculado do cardápio.
///
/// Por isso, depois de fechar, a tela seguinte mostra o pedido como o banco o
/// gravou, e não como a tela o imaginou.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/cardapio.dart';
import '../dados/carrinho.dart';
import '../dados/mesa.dart';
import '../dados/enderecos.dart';
import '../dados/pedidos.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../tema.dart';
import 'acompanhar.dart';
import 'enderecos.dart';

class TelaCheckout extends StatefulWidget {
  const TelaCheckout({super.key});

  @override
  State<TelaCheckout> createState() => _TelaCheckoutState();
}

class _TelaCheckoutState extends State<TelaCheckout> {
  final _cupom = TextEditingController();
  final _observacao = TextEditingController();
  final _troco = TextEditingController();

  List<Endereco> _enderecos = const [];
  List<FormaDePagamento> _formasAceitas = const [];
  Endereco? _endereco;
  /// A mesa lida no QR, se for desta loja. Quem escaneou já começa nela:
  /// perguntar "onde você quer receber?" a quem acabou de escanear a mesa é
  /// perguntar o que a pessoa já respondeu.
  Mesa? get _mesa {
    final atual = MesaAtual.instancia.mesa;
    final loja = Carrinho.instancia.restaurante?.id;
    if (atual == null || loja == null || atual.restauranteId != loja) return null;
    return atual;
  }

  late TipoDeEntrega _tipo =
      _mesa != null ? TipoDeEntrega.mesa : TipoDeEntrega.entrega;
  FormaDePagamento? _forma;
  int _descontoCentavos = 0;
  String? _cupomAplicado;
  bool _carregando = true;
  bool _fechando = false;
  bool _conferindoCupom = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _cupom.dispose();
    _observacao.dispose();
    _troco.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final restaurante = Carrinho.instancia.restaurante;
    if (restaurante == null) return;

    try {
      final resultados = await Future.wait([
        Enderecos.meus(),
        Cardapio.formasAceitas(restaurante.id),
      ]);

      if (!mounted) return;
      final enderecos = resultados[0] as List<Endereco>;
      final formas = resultados[1] as List<FormaDePagamento>;

      setState(() {
        _enderecos = enderecos;
        _endereco = enderecos.where((e) => e.padrao).firstOrNull ??
            enderecos.firstOrNull;
        // Sem forma cadastrada, o estabelecimento ainda não configurou nada;
        // dinheiro na entrega é o padrão que nunca depende de integração.
        _formasAceitas =
            formas.isEmpty ? const [FormaDePagamento.dinheiro] : formas;

        // O padrão é uma forma que se paga na entrega, mesmo que a loja aceite
        // Pix. Enquanto PAGAMENTO_PROVEDOR for "simulado", um pedido pago pelo
        // aplicativo nasce em "aguardando pagamento" e nunca sai de lá: o
        // balcão só enxerga a fila a partir de "recebido". Escolher por
        // omissão o caminho que funciona hoje evita entregar ao cliente um
        // pedido que morre esperando um gateway que ainda não existe.
        //
        // Quando o provedor real entrar, esta preferência sai e o padrão volta
        // a ser a primeira forma que o estabelecimento cadastrou.
        _forma = _formasAceitas.firstWhere(
          (f) => f != FormaDePagamento.pix && f != FormaDePagamento.credito,
          orElse: () => _formasAceitas.first,
        );
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      if (mounted) avisar(context, e.toString(), erro: true);
    }
  }

  int get _subtotal => Carrinho.instancia.subtotalCentavos;

  int get _taxa => !_tipo.vaiParaRua
      ? 0
      : (Carrinho.instancia.restaurante?.taxaPara(_subtotal) ?? 0);

  int get _total => _subtotal + _taxa - _descontoCentavos;

  /// Pagar pelo aplicativo só faz sentido nas formas que um gateway processa.
  /// Dinheiro é sempre na entrega, e o banco recusaria o contrário.
  MomentoDoPagamento get _momento =>
      (_forma == FormaDePagamento.pix || _forma == FormaDePagamento.credito)
          ? MomentoDoPagamento.noApp
          : MomentoDoPagamento.naEntrega;

  Future<void> _aplicarCupom() async {
    final restaurante = Carrinho.instancia.restaurante;
    if (restaurante == null || _cupom.text.trim().isEmpty) return;

    setState(() => _conferindoCupom = true);
    try {
      final desconto = await Pedidos.simularCupom(
        codigo: _cupom.text.trim(),
        restauranteId: restaurante.id,
        subtotalCentavos: _subtotal,
        taxaDeEntregaCentavos: _taxa,
      );
      if (!mounted) return;
      setState(() {
        _descontoCentavos = desconto;
        _cupomAplicado = _cupom.text.trim().toUpperCase();
      });
      if (mounted) avisar(context, 'Cupom aplicado: −${emReais(desconto)}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _descontoCentavos = 0;
        _cupomAplicado = null;
      });
      // A mensagem vem do banco, já em português: "Este cupom venceu",
      // "Voce ja usou este cupom".
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _conferindoCupom = false);
    }
  }

  Future<void> _fechar() async {
    final carrinho = Carrinho.instancia;
    final carrinhoId = carrinho.id;
    if (carrinhoId == null || _forma == null) return;

    if (_tipo == TipoDeEntrega.entrega && _endereco == null) {
      avisar(context, 'Escolha onde entregar.', erro: true);
      return;
    }

    int? trocoCentavos;
    if (_forma == FormaDePagamento.dinheiro && _troco.text.trim().isNotEmpty) {
      final valor = double.tryParse(
          _troco.text.replaceAll('.', '').replaceAll(',', '.'));
      if (valor != null) trocoCentavos = (valor * 100).round();
      if (trocoCentavos != null && trocoCentavos < _total) {
        avisar(context, 'O troco precisa cobrir o total do pedido.', erro: true);
        return;
      }
    }

    setState(() => _fechando = true);
    try {
      final pedido = await Pedidos.fechar(
        carrinhoId: carrinhoId,
        tipo: _tipo,
        forma: _forma!,
        momento: _momento,
        enderecoId: _tipo == TipoDeEntrega.entrega ? _endereco?.id : null,
        trocoParaCentavos: trocoCentavos,
        cupom: _cupomAplicado,
        observacao: _observacao.text,
        mesa: _tipo == TipoDeEntrega.mesa ? _mesa?.codigo : null,
      );

      // A linha do carrinho já foi apagada pelo próprio fechamento.
      carrinho.esquecer();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TelaAcompanhar(pedidoId: pedido.id, recemFeito: true),
        ),
      );
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _fechando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Carregando(mensagem: 'Preparando…'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Fechar pedido')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _titulo('Como você quer receber'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<TipoDeEntrega>(
              segments: [
                // "Mesa" só aparece para quem escaneou uma. Oferecer a opção a
                // quem está em casa produziria pedido de salão sem ninguém
                // sentado — e um prato levado a uma mesa vazia.
                if (_mesa != null)
                  ButtonSegment(
                      value: TipoDeEntrega.mesa,
                      icon: const Icon(Icons.restaurant),
                      label: Text(_mesa!.rotulo)),
                const ButtonSegment(
                    value: TipoDeEntrega.entrega,
                    icon: Icon(Icons.delivery_dining),
                    label: Text('Entrega')),
                const ButtonSegment(
                    value: TipoDeEntrega.retirada,
                    icon: Icon(Icons.storefront),
                    label: Text('Retirar')),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() => _tipo = s.first),
            ),
          ),
          if (_tipo == TipoDeEntrega.entrega) ...[
            _titulo('Onde entregar'),
            if (_enderecos.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Cadastrar endereço'),
                  onPressed: _novoEndereco,
                ),
              )
            else ...[
              RadioGroup<String>(
                groupValue: _endereco?.id,
                onChanged: (id) => setState(() => _endereco =
                    _enderecos.where((e) => e.id == id).firstOrNull),
                child: Column(
                  children: [
                    for (final e in _enderecos)
                      RadioListTile<String>(
                        value: e.id,
                        title: Text(e.rotulo,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle:
                            Text(e.resumo, style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Outro endereço'),
                  onPressed: _novoEndereco,
                ),
              ),
            ],
          ],
          _titulo('Como pagar'),
          RadioGroup<FormaDePagamento>(
            groupValue: _forma,
            onChanged: (v) => setState(() => _forma = v),
            child: Column(
              children: [
                for (final f in _formasAceitas)
                  RadioListTile<FormaDePagamento>(
                    value: f,
                    title: Text(f.rotulo),
                    subtitle: Text(
                      (f == FormaDePagamento.pix ||
                              f == FormaDePagamento.credito)
                          ? 'Pelo aplicativo'
                          : 'Na entrega',
                      style: const TextStyle(
                          fontSize: 12.5, color: Cores.textoSuave),
                    ),
                  ),
              ],
            ),
          ),
          if (_forma?.aceitaTroco == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _troco,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Precisa de troco para quanto?',
                  hintText: 'Deixe vazio se tiver o valor certo',
                  prefixText: 'R\$ ',
                ),
              ),
            ),
          _titulo('Cupom'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cupom,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(hintText: 'Tem um código?'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _conferindoCupom ? null : _aplicarCupom,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(96, 52)),
                  child: Text(_conferindoCupom ? '…' : 'Aplicar'),
                ),
              ],
            ),
          ),
          _titulo('Observação para o restaurante'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _observacao,
              maxLines: 2,
              maxLength: 200,
              decoration: const InputDecoration(
                  hintText: 'Ex.: interfone quebrado, ligar ao chegar'),
            ),
          ),
          const Divider(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                LinhaDeValor(rotulo: 'Subtotal', centavos: _subtotal),
                LinhaDeValor(
                  rotulo: _tipo == TipoDeEntrega.retirada
                      ? 'Retirada no balcão'
                      : 'Entrega',
                  centavos: _taxa,
                  gratis: _taxa == 0,
                ),
                if (_descontoCentavos > 0)
                  LinhaDeValor(
                    rotulo: 'Cupom $_cupomAplicado',
                    centavos: _descontoCentavos,
                    desconto: true,
                  ),
                const Divider(height: 20),
                LinhaDeValor(rotulo: 'Total', centavos: _total, forte: true),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BarraDeAcao(
        filho: FilledButton(
          onPressed: _fechando ? null : _fechar,
          child: Text(_fechando
              ? 'Enviando…'
              : 'Fazer pedido · ${emReais(_total)}'),
        ),
      ),
    );
  }

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
        child: Text(texto,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Future<void> _novoEndereco() async {
    final criado = await Navigator.of(context).push<Endereco>(
      MaterialPageRoute(builder: (_) => const TelaEnderecoFormulario()),
    );
    if (criado != null) {
      setState(() {
        _enderecos = [..._enderecos, criado];
        _endereco = criado;
      });
    }
  }
}
