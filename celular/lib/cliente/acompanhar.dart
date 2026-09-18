/// Acompanhar um pedido.
///
/// A tela não tem botão de atualizar: um canal de Realtime avisa quando a
/// cozinha ou o entregador mexem no pedido, e ela se redesenha sozinha. Quem
/// está esperando comida não deve precisar puxar a lista para descobrir que já
/// saiu para entrega.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../comum/mapa.dart';
import '../comum/sons.dart';
import '../comum/widgets.dart';
import '../dados/localizacao.dart';
import '../dados/pedidos.dart';
import '../dados/supabase.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../tema.dart';

class TelaAcompanhar extends StatefulWidget {
  const TelaAcompanhar({
    super.key,
    required this.pedidoId,
    this.recemFeito = false,
  });

  final String pedidoId;

  /// Acabou de ser feito nesta sessão — a tela abre comemorando em vez de
  /// abrir como consulta.
  final bool recemFeito;

  @override
  State<TelaAcompanhar> createState() => _TelaAcompanharState();
}

class _TelaAcompanharState extends State<TelaAcompanhar> {
  Pedido? _pedido;

  /// Em que passo o pedido estava na última vez que esta tela olhou.
  ///
  /// É a comparação que diz se ALGO ANDOU. Sem ela o sino tocaria a cada
  /// recarga — inclusive quando só a posição do entregador mudou — e a pessoa
  /// aprenderia a ignorar o som.
  StatusDoPedido? _passoAnterior;

  RealtimeChannel? _canal;
  Timer? _relogioDoRastreio;
  PosicaoDoEntregador? _entregador;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
    _canal = Pedidos.acompanhar(widget.pedidoId, _carregar);

    // A posição do entregador é consultada, não recebida por Realtime: assinar
    // `couriers` exigiria abrir a linha inteira dele ao cliente. Oito segundos
    // é rápido o bastante para a bolinha parecer viva e devagar o bastante
    // para não pesar.
    _relogioDoRastreio = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _buscarEntregador(),
    );
    _buscarEntregador();
  }

  @override
  void dispose() {
    // Canal esquecido aberto é conexão viva gastando bateria de quem já saiu
    // da tela.
    final canal = _canal;
    if (canal != null) banco.removeChannel(canal);
    _relogioDoRastreio?.cancel();
    super.dispose();
  }

  Future<void> _buscarEntregador() async {
    try {
      final onde = await Pedidos.ondeEstaOEntregador(widget.pedidoId);
      // Nulo é resposta legítima: a corrida acabou, ninguém pegou ainda, ou o
      // entregador não publicou medida nenhuma. Some o alfinete, sem alarde.
      if (mounted) setState(() => _entregador = onde);
    } catch (_) {
      // Rastreio é enfeite do acompanhamento: se falhar, o resto da tela
      // continua servindo.
    }
  }

  Future<void> _carregar() async {
    try {
      final pedido = await Pedidos.porId(widget.pedidoId);
      if (!mounted) return;

      final andou = _passoAnterior != null && _passoAnterior != pedido.status;
      _passoAnterior = pedido.status;

      setState(() => _pedido = pedido);

      if (andou) {
        // Entregue merece o sino inteiro: é o fim da espera, e o único passo
        // em que a pessoa pode estar longe do celular.
        unawaited(Sons.tocar(
          pedido.status == StatusDoPedido.entregue ? Toque.cheio : Toque.curto,
        ));
      }
    } catch (e) {
      if (mounted) setState(() => _erro = e);
    }
  }

  /// As etapas que o cliente vê. Não são todos os estados do banco: "aguardando
  /// pagamento" e os finais negativos têm tela própria, e listar nove caixinhas
  /// não ajudaria ninguém a saber quanto falta.
  static const _etapasDeEntrega = [
    'Pedido enviado',
    'Restaurante aceitou',
    'Em preparo',
    'Pronto',
    'Saiu para entrega',
    'Entregue',
  ];

  static const _etapasDeRetirada = [
    'Pedido enviado',
    'Restaurante aceitou',
    'Em preparo',
    'Pronto para retirar',
    'Retirado',
  ];

  int _etapaAtual(Pedido p) {
    if (p.tipo == TipoDeEntrega.retirada) {
      return switch (p.status) {
        StatusDoPedido.aguardandoPagamento || StatusDoPedido.recebido => 0,
        StatusDoPedido.confirmado => 1,
        StatusDoPedido.emPreparo => 2,
        StatusDoPedido.pronto => 3,
        _ => 4,
      };
    }
    return switch (p.status) {
      StatusDoPedido.aguardandoPagamento || StatusDoPedido.recebido => 0,
      StatusDoPedido.confirmado => 1,
      StatusDoPedido.emPreparo => 2,
      StatusDoPedido.pronto => 3,
      StatusDoPedido.saiuParaEntrega => 4,
      _ => 5,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_erro != null) {
      return Scaffold(
          appBar: AppBar(), body: Falhou(erro: _erro!, aoTentarDeNovo: _carregar));
    }
    final p = _pedido;
    if (p == null) {
      return const Scaffold(body: Carregando(mensagem: 'Buscando seu pedido…'));
    }

    final encerradoMal = p.status == StatusDoPedido.cancelado ||
        p.status == StatusDoPedido.recusado;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido nº ${p.numero}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          if (widget.recemFeito) _recemFeito(p),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.status.paraOCliente,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  encerradoMal
                      ? (p.motivoDoCancelamento ?? 'Pedido encerrado.')
                      : p.status == StatusDoPedido.entregue
                          ? 'Bom apetite.'
                          : 'Previsão de ${faixaDeMinutos(20, 20)} a partir do aceite.',
                  style: const TextStyle(color: Cores.textoSuave, height: 1.4),
                ),
              ],
            ),
          ),
          ?_mapaDoRastreio(encerradoMal ? null : p),
          if (!encerradoMal)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Trilha(
                etapas: p.tipo == TipoDeEntrega.retirada
                    ? _etapasDeRetirada
                    : _etapasDeEntrega,
                atual: _etapaAtual(p),
              ),
            ),
          if (p.pagamento?.momento == MomentoDoPagamento.noApp &&
              p.pagamento?.status == StatusDoPagamento.pendente)
            _aguardandoPagamento(p),
          const Divider(),
          ListTile(
            leading: Foto(
                url: p.logoDoRestaurante,
                largura: 44,
                altura: 44,
                icone: Icons.storefront),
            title: Text(p.nomeDoRestaurante ?? 'Restaurante',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(haQuantoTempo(p.criadoEm)),
          ),
          if (p.tipo == TipoDeEntrega.entrega && p.resumoDoEndereco != null)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Entregar em'),
              subtitle: Text(
                  '${p.resumoDoEndereco}, ${p.bairroDoEndereco ?? ''}'),
            ),
          if (p.entrega != null)
            ListTile(
              leading: const Icon(Icons.two_wheeler_outlined),
              title: const Text('Entrega'),
              subtitle: Text(p.entrega!.status.rotulo),
            ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(p.pagamento?.forma.rotulo ?? 'Pagamento'),
            subtitle: Text(
              p.pagamento?.momento == MomentoDoPagamento.naEntrega
                  ? 'Pagar na entrega'
                  : 'Pago pelo aplicativo',
            ),
            trailing: p.pagamento?.trocoParaCentavos == null
                ? null
                : Text('Troco de ${emReais(p.pagamento!.trocoCentavos)}',
                    style: const TextStyle(fontSize: 12.5)),
          ),
          const Divider(),
          _titulo('Itens'),
          for (final i in p.itens)
            ListTile(
              dense: true,
              leading: Text('${i.quantidade}×',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Cores.marca)),
              title: Text(i.nomeDoProduto),
              subtitle: i.adicionais.isEmpty && i.observacao == null
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final a in i.adicionais)
                          Text('+ ${a.nome}',
                              style: const TextStyle(fontSize: 12.5)),
                        if (i.observacao != null)
                          Text('“${i.observacao}”',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontStyle: FontStyle.italic)),
                      ],
                    ),
              trailing: Text(emReais(i.totalCentavos)),
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
      bottomNavigationBar: Pedidos.clientePodeCancelar(p.status)
          ? BarraDeAcao(
              filho: OutlinedButton(
                onPressed: () => _cancelar(p),
                style: OutlinedButton.styleFrom(foregroundColor: Cores.perigo),
                child: const Text('Cancelar pedido'),
              ),
            )
          : null,
    );
  }

  /// O mapa da entrega.
  ///
  /// Só aparece quando há o que mostrar: entrega (não retirada), e ao menos um
  /// ponto conhecido. Mapa vazio numa tela de espera é ansiedade de graça.
  Widget? _mapaDoRastreio(Pedido? p) {
    if (p == null || p.tipo != TipoDeEntrega.entrega) return null;

    final entregador = _entregador;
    final destino = (p.latitudeDoEndereco != null && p.longitudeDoEndereco != null)
        ? Ponto(p.latitudeDoEndereco!, p.longitudeDoEndereco!)
        : null;

    if (entregador == null && destino == null) return null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Mapa(
              altura: 220,
              alfinetes: [
                if (destino != null)
                  Alfinete(
                      ponto: destino,
                      icone: Icons.home,
                      cor: Cores.texto),
                if (entregador != null)
                  Alfinete(
                    ponto: entregador.onde,
                    icone: Icons.two_wheeler,
                    cor: entregador.velha ? Cores.textoSuave : Cores.marca,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                entregador == null
                    ? Icons.schedule
                    : entregador.velha
                        ? Icons.signal_wifi_off
                        : Icons.two_wheeler,
                size: 15,
                color: Cores.textoSuave,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entregador == null
                      ? 'O mapa mostra onde a comida vai chegar. Quando um '
                          'entregador pegar o pedido, ele aparece aqui.'
                      : entregador.velha
                          // Dizer que a medida é velha é melhor que mostrar um
                          // alfinete parado e deixar o cliente concluir que o
                          // entregador sumiu.
                          ? 'Última posição de ${haQuantoTempo(entregador.medidoEm)}. '
                              'O sinal dele pode ter caído.'
                          : destino == null
                              ? 'Entregador a caminho.'
                              : 'Entregador a '
                                  '${distanciaKm(Localizacao.distanciaKm(entregador.onde, destino))} '
                                  'de você, em linha reta.',
                  style: const TextStyle(
                      fontSize: 12.5, color: Cores.textoSuave, height: 1.35),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recemFeito(Pedido p) => Container(
        width: double.infinity,
        color: Cores.realce,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Cores.marca, size: 40),
            const SizedBox(height: 10),
            const Text('Pedido enviado',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Cores.marcaEscura)),
            const SizedBox(height: 4),
            Text(
              'O ${p.nomeDoRestaurante ?? 'restaurante'} já recebeu. '
              'Você acompanha tudo por aqui.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Cores.marcaEscura, fontSize: 13.5),
            ),
          ],
        ),
      );

  /// Pagamento pelo aplicativo, com o provedor ainda simulado.
  ///
  /// O `.env.example` do projeto já prevê `PAGAMENTO_PROVEDOR=simulado`: até a
  /// integração real entrar, esta tela diz a verdade em vez de fingir um QR
  /// Code que ninguém consegue pagar.
  Widget _aguardandoPagamento(Pedido p) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Cores.atencao.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.hourglass_empty, color: Cores.atencao),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                p.pagamento?.pixQrCode == null
                    ? 'O pagamento pelo aplicativo ainda não está ligado a um provedor real. '
                        'Enquanto isso, combine com o restaurante ou escolha pagar na entrega.'
                    : 'Aguardando a confirmação do pagamento.',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      );

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(texto,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Future<void> _cancelar(Pedido p) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancelar o pedido?'),
        content: const Text(
            'Dá para cancelar enquanto o restaurante não aceitou. Depois disso, '
            'a comida já está sendo feita e o jeito é falar com eles.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Manter')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Cores.perigo),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    try {
      await Pedidos.cancelar(p.id);
      await _carregar();
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    }
  }
}
