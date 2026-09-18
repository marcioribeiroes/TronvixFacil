/// O aplicativo de quem prepara.
///
/// A fila é a tela: pedido que chega aparece sozinho, sem ninguém puxar. Num
/// balcão, o atraso entre o pedido entrar no banco e alguém vê-lo é comida
/// esfriando e cliente ligando.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/balcao.dart';
import '../dados/supabase.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../sessao.dart';
import '../tema.dart';
import 'cardapio.dart';
import 'entregadores.dart';
import 'pedido.dart';

class InicioDoRestaurante extends StatefulWidget {
  const InicioDoRestaurante({super.key});

  @override
  State<InicioDoRestaurante> createState() => _InicioDoRestauranteState();
}

class _InicioDoRestauranteState extends State<InicioDoRestaurante> {
  List<Pedido> _fila = const [];
  Restaurante? _restaurante;
  ResumoDoDia? _resumo;
  RealtimeChannel? _canal;
  bool _carregando = true;
  Object? _erro;

  String? get _restauranteId => Sessao.instancia.vinculo?.restauranteId;

  @override
  void initState() {
    super.initState();
    _carregar();
    final id = _restauranteId;
    if (id != null) _canal = Balcao.acompanharFila(id, _carregar);
  }

  @override
  void dispose() {
    final canal = _canal;
    if (canal != null) banco.removeChannel(canal);
    super.dispose();
  }

  Future<void> _carregar() async {
    final id = _restauranteId;
    if (id == null) return;

    try {
      final resultados = await Future.wait([
        Balcao.fila(id),
        Balcao.meuRestaurante(id),
        Balcao.resumoDoDia(id),
      ]);
      if (!mounted) return;
      setState(() {
        _fila = resultados[0] as List<Pedido>;
        _restaurante = resultados[1] as Restaurante;
        _resumo = resultados[2] as ResumoDoDia;
        _carregando = false;
        _erro = null;
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
  Widget build(BuildContext context) {
    final vinculo = Sessao.instancia.vinculo;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(vinculo?.nomeDoRestaurante ?? 'Balcão',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (_restaurante != null)
              Text(
                _restaurante!.aberto ? 'Aberto agora' : 'Fechado',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _restaurante!.aberto ? Cores.sucesso : Cores.perigo,
                ),
              ),
          ],
        ),
        actions: [
          if (_restaurante != null && vinculo?.papel.gerencia == true)
            Switch(
              value: _restaurante!.aberto,
              onChanged: (aberto) async {
                try {
                  await Balcao.abrirOuFechar(_restaurante!.id, aberto);
                  await _carregar();
                } catch (e) {
                  if (context.mounted) {
                    avisar(context, e.toString(), erro: true);
                  }
                }
              },
            ),
          PopupMenuButton<String>(
            onSelected: (acao) {
              if (acao == 'cardapio') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const TelaCardapioDoBalcao()));
              } else if (acao == 'entregadores') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const TelaEntregadores()));
              } else if (acao == 'cliente') {
                Sessao.instancia.trocarDeFluxo(Fluxo.cliente);
              } else if (acao == 'sair') {
                Sessao.instancia.sair();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'cardapio', child: Text('Cardápio')),
              const PopupMenuItem(
                  value: 'entregadores', child: Text('Entregadores')),
              if (Sessao.instancia.fluxosDisponiveis.contains(Fluxo.cliente))
                const PopupMenuItem(
                    value: 'cliente', child: Text('Abrir como cliente')),
              const PopupMenuItem(value: 'sair', child: Text('Sair')),
            ],
          ),
        ],
      ),
      body: _carregando
          ? const Carregando()
          : _erro != null
              ? Falhou(erro: _erro!, aoTentarDeNovo: _carregar)
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    children: [
                      if (_resumo != null) _placar(_resumo!),
                      if (_fila.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 60),
                          child: Vazio(
                            icone: Icons.check_circle_outline,
                            titulo: 'Nenhum pedido em aberto',
                            detalhe:
                                'Quando entrar um pedido, ele aparece aqui sozinho.',
                          ),
                        )
                      else
                        for (final p in _fila) _cartao(p),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _placar(ResumoDoDia r) => Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Cores.suave,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _numero('Hoje', '${r.pedidos}'),
            _numero('Faturado', emReais(r.totalCentavos)),
            _numero('Ticket', emReais(r.ticketMedioCentavos)),
          ],
        ),
      );

  Widget _numero(String rotulo, String valor) => Expanded(
        child: Column(
          children: [
            Text(valor,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(rotulo,
                style: const TextStyle(
                    fontSize: 11.5,
                    color: Cores.textoSuave,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _cartao(Pedido p) {
    final novo = p.status == StatusDoPedido.recebido;
    // Minutos parado é o número que dói no cliente, então é o que a cozinha vê
    // em destaque — não a hora em que o pedido nasceu.
    final esperando = p.esperando.inMinutes;
    final atrasado = novo && esperando >= 5;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: atrasado ? Cores.perigo : Cores.borda),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => TelaPedidoDoBalcao(pedido: p)))
            .then((_) => _carregar()),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('nº ${p.numero}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 10),
                  Etiqueta(
                    p.status.paraORestaurante,
                    cor: novo ? Cores.marca : Cores.textoSuave,
                    forte: novo,
                  ),
                  const Spacer(),
                  Text(
                    esperando == 0 ? 'agora' : 'há $esperando min',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: atrasado ? FontWeight.w800 : FontWeight.w500,
                      color: atrasado ? Cores.perigo : Cores.textoSuave,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(p.nomeDoCliente,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                '${p.quantidadeDeItens} item(ns) · ${p.tipo.rotulo}'
                '${p.tipo == TipoDeEntrega.entrega && p.bairroDoEndereco != null ? ' · ${p.bairroDoEndereco}' : ''}',
                style: const TextStyle(fontSize: 13, color: Cores.textoSuave),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    p.pagamento?.momento == MomentoDoPagamento.naEntrega
                        ? 'Receber ${emReais(p.totalCentavos)} na entrega'
                        : 'Pago · ${emReais(p.totalCentavos)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (Balcao.proximoPasso(p) != null)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        textStyle: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => _avancar(p),
                      child:
                          Text(Balcao.rotuloDoPasso(Balcao.proximoPasso(p)!)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _avancar(Pedido p) async {
    final destino = Balcao.proximoPasso(p);
    if (destino == null) return;
    try {
      await Balcao.avancar(p, destino);
      await _carregar();
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    }
  }
}
