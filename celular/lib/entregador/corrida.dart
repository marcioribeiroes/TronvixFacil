/// Uma corrida: aceitar, ou tocá-la até a porta do cliente.
library;

import 'package:flutter/material.dart';

import '../comum/mapa.dart';
import '../comum/widgets.dart';
import '../dados/corridas.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../sessao.dart';
import '../tema.dart';

class TelaCorrida extends StatefulWidget {
  const TelaCorrida({super.key, required this.corrida});
  final Corrida corrida;

  @override
  State<TelaCorrida> createState() => _TelaCorridaState();
}

class _TelaCorridaState extends State<TelaCorrida> {
  late Corrida _corrida = widget.corrida;
  bool _ocupado = false;

  Entregador? get _eu => Sessao.instancia.entregador;

  bool get _minha => _corrida.entrega.entregadorId == _eu?.id;

  static const _etapas = [
    'Corrida aceita',
    'A caminho da loja',
    'Pedido retirado',
    'A caminho do cliente',
    'Entregue',
  ];

  int get _etapaAtual => switch (_corrida.entrega.status) {
        StatusDaEntrega.designada => 0,
        StatusDaEntrega.indoAoRestaurante => 1,
        StatusDaEntrega.retirada => 2,
        StatusDaEntrega.indoAoCliente => 3,
        _ => 4,
      };

  @override
  Widget build(BuildContext context) {
    final c = _corrida;
    final destino = _minha
        ? Corridas.proximoPasso(
            c.entrega.status,
            situacaoDoPedido: c.situacaoDoPedido,
          )
        : null;

    // Chegou antes da comida. Sem isto o botão sumiria sem explicação, e quem
    // está parado na porta da loja não saberia se é para esperar ou ir embora.
    final esperandoAComida = _minha &&
        destino == null &&
        c.entrega.status == StatusDaEntrega.indoAoRestaurante;

    return Scaffold(
      appBar: AppBar(title: Text('Pedido nº ${c.numeroDoPedido}')),
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
                const Text('Você recebe',
                    style: TextStyle(fontSize: 12.5, color: Cores.textoSuave)),
                Text(emReais(c.entrega.taxaDoEntregadorCentavos),
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Cores.sucesso)),
                if (c.entrega.distanciaKm != null)
                  Text('${distanciaKm(c.entrega.distanciaKm!)} de percurso',
                      style: const TextStyle(color: Cores.textoSuave)),
              ],
            ),
          ),
          // O mapa da coleta: de onde sai e para onde vai. Sem coordenada
          // nenhuma não há o que desenhar, e a tela vale mais sem ele do que
          // com um retângulo cinza.
          if (c.ondeRetirar != null || c.ondeEntregar != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Mapa(
                  altura: 200,
                  interativo: false,
                  alfinetes: [
                    if (c.ondeRetirar != null)
                      Alfinete(ponto: c.ondeRetirar!, icone: Icons.storefront),
                    if (c.ondeEntregar != null)
                      Alfinete(
                          ponto: c.ondeEntregar!,
                          icone: Icons.place,
                          cor: Cores.sucesso),
                  ],
                ),
              ),
            ),
          if (_minha)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Trilha(etapas: _etapas, atual: _etapaAtual),
            ),
          const Divider(),
          _local(
            icone: Icons.storefront,
            titulo: 'Retirar em',
            nome: c.nomeDoRestaurante,
            endereco: c.enderecoDoRestaurante,
            fone: c.telefoneDoRestaurante,
          ),
          const Divider(),
          _local(
            icone: Icons.place,
            titulo: 'Entregar para',
            nome: c.nomeDoCliente,
            endereco:
                '${c.enderecoDeEntrega ?? ''} · ${c.bairroDeEntrega ?? ''}',
            fone: c.telefoneDoCliente,
          ),
          if (c.observacao != null && c.observacao!.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Cores.realce,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(c.observacao!,
                  style: const TextStyle(
                      color: Cores.marcaEscura, height: 1.4, fontSize: 13.5)),
            ),
          // O que o entregador precisa saber antes de bater na porta: vai
          // receber dinheiro ali, ou o pedido já está pago?
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(
                  color: c.recebeNaPorta ? Cores.atencao : Cores.borda),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  c.recebeNaPorta
                      ? Icons.account_balance_wallet_outlined
                      : Icons.check_circle_outline,
                  color: c.recebeNaPorta ? Cores.atencao : Cores.sucesso,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    c.recebeNaPorta
                        ? 'Receber ${emReais(c.totalDoPedidoCentavos)} '
                            'em ${c.formaDePagamento?.rotulo.toLowerCase() ?? 'dinheiro'} na entrega.'
                        : 'Pedido já pago pelo aplicativo. Não cobre nada na porta.',
                    style: const TextStyle(fontSize: 13.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BarraDeAcao(
        acima: _minha && _corrida.entrega.status != StatusDaEntrega.entregue
            ? OutlinedButton(
                onPressed: _ocupado ? null : _desistir,
                style: OutlinedButton.styleFrom(foregroundColor: Cores.perigo),
                child: const Text('Não vou conseguir'),
              )
            : null,
        filho: FilledButton(
          onPressed: _ocupado
              ? null
              : _minha
                  ? (destino == null ? null : () => _avancar(destino))
                  : _aceitar,
          child: Text(
            _minha
                ? (destino != null
                    ? Corridas.rotuloDoPasso(destino)
                    : esperandoAComida
                        ? 'A cozinha ainda está fazendo'
                        : 'Corrida concluída')
                : 'Aceitar corrida',
          ),
        ),
      ),
    );
  }

  Widget _local({
    required IconData icone,
    required String titulo,
    required String nome,
    String? endereco,
    String? fone,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: Cores.marca),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: Cores.textoSuave)),
                  const SizedBox(height: 3),
                  Text(nome,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  if (endereco != null && endereco.trim().isNotEmpty)
                    Text(endereco,
                        style: const TextStyle(
                            color: Cores.textoSuave, height: 1.35)),
                ],
              ),
            ),
            if (fone != null && fone.isNotEmpty)
              Text(telefone(fone),
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Future<void> _aceitar() async {
    final eu = _eu;
    if (eu == null) return;

    // Aceitar é compromisso: a corrida sai da fila e alguém está esperando
    // comida. Uma pergunta antes evita o toque sem querer com o celular no
    // suporte da moto.
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Você quer mesmo aceitar?'),
        content: Text(
          'A corrida sai da fila e passa a ser sua. '
          '${_corrida.nomeDoRestaurante} vai contar com você.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(contexto, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(contexto, true),
              child: const Text('Aceitar')),
        ],
      ),
    );
    if (confirmou != true) return;

    setState(() => _ocupado = true);
    try {
      await Corridas.aceitar(_corrida.entrega.id, eu.id);
      final atualizada = await Corridas.minhaCorrida(eu.id);
      if (!mounted) return;
      setState(() => _corrida = atualizada ?? _corrida);
      await Sessao.instancia.carregar();
    } catch (e) {
      if (mounted) {
        avisar(context, e.toString(), erro: true);
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _avancar(StatusDaEntrega destino) async {
    final eu = _eu;
    if (eu == null) return;
    setState(() => _ocupado = true);
    try {
      await Corridas.avancar(_corrida, destino, eu.id);
      if (destino == StatusDaEntrega.entregue) {
        await Sessao.instancia.carregar();
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final atualizada = await Corridas.minhaCorrida(eu.id);
      if (mounted) setState(() => _corrida = atualizada ?? _corrida);
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _desistir() async {
    final eu = _eu;
    if (eu == null) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Devolver a corrida?'),
        content: const Text(
            'Ela volta para a fila e outro entregador pode pegar. O pedido do '
            'cliente continua de pé.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Continuar com ela')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Cores.perigo),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Devolver'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    try {
      await Corridas.desistir(_corrida.entrega.id, eu.id);
      await Sessao.instancia.carregar();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    }
  }
}
