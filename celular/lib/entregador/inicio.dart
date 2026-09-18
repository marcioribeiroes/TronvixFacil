/// O aplicativo de quem leva.
///
/// Mapa em primeiro plano, e o resto por cima dele. Quem dirige não navega por
/// menu: a tela precisa responder "onde eu estou, o que tem para mim, e qual é
/// o próximo passo" sem nenhum toque.
///
/// Duas situações, e só duas: ou a pessoa está em uma corrida — e então a folha
/// de baixo é aquela corrida — ou está livre, e a folha é a fila.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../comum/mapa.dart';
import '../comum/widgets.dart';
import '../dados/corridas.dart';
import '../dados/localizacao.dart';
import '../dados/supabase.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../sessao.dart';
import '../tema.dart';
import 'cadastro.dart';
import 'corrida.dart';

class InicioDoEntregador extends StatefulWidget {
  const InicioDoEntregador({super.key});

  @override
  State<InicioDoEntregador> createState() => _InicioDoEntregadorState();
}

class _InicioDoEntregadorState extends State<InicioDoEntregador> {
  List<Corrida> _disponiveis = const [];
  Corrida? _minha;
  Ponto? _eu;
  RealtimeChannel? _canal;
  StreamSubscription<Ponto>? _rastro;
  bool _carregando = true;
  Object? _erro;

  Entregador? get _eu_ => Sessao.instancia.entregador;

  @override
  void initState() {
    super.initState();
    _carregar();
    _localizar();
    _canal = Corridas.acompanharFila(_carregar);
  }

  @override
  void dispose() {
    final canal = _canal;
    if (canal != null) banco.removeChannel(canal);
    _rastro?.cancel();
    super.dispose();
  }

  /// Publica a posição enquanto houver corrida em andamento — e só então.
  ///
  /// Fora de uma entrega o aplicativo não acompanha ninguém: ficar emitindo a
  /// posição de quem está livre é vigiar, não rastrear um pedido. O
  /// `geolocator` só emite a cada 25 metros, então uma moto parada no sinal
  /// não gera trânsito nem gasta bateria.
  void _ajustarRastro() {
    final emCorrida = _minha != null;

    if (!emCorrida) {
      _rastro?.cancel();
      _rastro = null;
      return;
    }
    if (_rastro != null) return;

    _rastro = Localizacao.acompanhar().listen((onde) {
      Corridas.publicarPosicao(onde);
      if (mounted) setState(() => _eu = onde);
    });
  }

  Future<void> _localizar() async {
    final onde = await Localizacao.onde();
    if (mounted && onde != null) setState(() => _eu = onde);
  }

  Future<void> _carregar() async {
    final eu = _eu_;
    if (eu == null) return;
    try {
      final resultados = await Future.wait([
        Corridas.minhaCorrida(eu.id),
        Corridas.disponiveis(),
      ]);
      if (!mounted) return;
      setState(() {
        _minha = resultados[0] as Corrida?;
        _disponiveis = resultados[1] as List<Corrida>;
        _carregando = false;
        _erro = null;
      });
      _ajustarRastro();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e;
        _carregando = false;
      });
    }
  }

  /// O que aparece no mapa: a corrida em andamento, se houver; senão, de onde
  /// sairia cada corrida disponível.
  List<Alfinete> get _alfinetes {
    final minha = _minha;
    if (minha != null) {
      return [
        if (minha.ondeRetirar != null)
          Alfinete(ponto: minha.ondeRetirar!, icone: Icons.storefront),
        if (minha.ondeEntregar != null)
          Alfinete(
              ponto: minha.ondeEntregar!,
              icone: Icons.place,
              cor: Cores.sucesso),
      ];
    }
    return [
      for (final c in _disponiveis)
        if (c.ondeRetirar != null)
          Alfinete(ponto: c.ondeRetirar!, icone: Icons.storefront),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Sessao.instancia,
        builder: (context, _) {
          final eu = _eu_;

          if (eu == null) return const TelaCadastroDeEntregador();
          if (!eu.podeTrabalhar) {
            return Scaffold(
              appBar: AppBar(title: const Text('Entregas'), actions: [_menu()]),
              body: _aguardandoAprovacao(eu),
            );
          }

          return Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Mapa(alfinetes: _alfinetes, eu: _eu),
                ),
                _chapeu(eu),
                if (_erro != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: MediaQuery.of(context).padding.top + 76,
                    child: Material(
                      borderRadius: BorderRadius.circular(12),
                      color: Cores.perigo,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('$_erro',
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
                Positioned(
                  right: 16,
                  bottom: MediaQuery.of(context).size.height * 0.34 + 16,
                  child: FloatingActionButton.small(
                    heroTag: 'centralizar',
                    backgroundColor: Cores.fundo,
                    foregroundColor: Cores.marca,
                    onPressed: _localizar,
                    child: const Icon(Icons.my_location),
                  ),
                ),
                _folha(eu),
              ],
            ),
          );
        },
      );

  /// A faixa do topo: quem sou, se estou disponível, e o menu.
  Widget _chapeu(Entregador eu) {
    final online = eu.disponibilidade != DisponibilidadeDoEntregador.offline;
    final emEntrega =
        eu.disponibilidade == DisponibilidadeDoEntregador.emEntrega;

    return Positioned(
      left: 12,
      right: 12,
      top: MediaQuery.of(context).padding.top + 8,
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(28),
        color: Cores.fundo,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Cores.realce,
                child: Text(
                  (Sessao.instancia.perfil?.primeiroNome ?? '?')
                      .characters
                      .first
                      .toUpperCase(),
                  style: const TextStyle(
                      color: Cores.marca, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  // Em entrega o botão não alterna: sair do ar no meio de uma
                  // corrida deixaria um pedido sem dono.
                  onTap: emEntrega ? null : () => _alternar(eu, !online),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: emEntrega
                          ? Cores.marca
                          : online
                              ? Cores.sucesso
                              : Cores.suave,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      emEntrega
                          ? 'Em coleta'
                          : online
                              ? 'Disponível'
                              : 'Fora do ar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: online || emEntrega ? Colors.white : Cores.textoSuave,
                      ),
                    ),
                  ),
                ),
              ),
              _menu(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu() => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (acao) {
          if (acao == 'cliente') {
            Sessao.instancia.trocarDeFluxo(Fluxo.cliente);
          } else if (acao == 'sair') {
            Sessao.instancia.sair();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
              value: 'cliente', child: Text('Abrir como cliente')),
          const PopupMenuItem(value: 'sair', child: Text('Sair')),
        ],
      );

  Future<void> _alternar(Entregador eu, bool online) async {
    try {
      await Corridas.mudarDisponibilidade(
        eu.id,
        online
            ? DisponibilidadeDoEntregador.online
            : DisponibilidadeDoEntregador.offline,
      );
      await Sessao.instancia.carregar();
      await _carregar();
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    }
  }

  /// A folha de baixo, sobre o mapa.
  Widget _folha(Entregador eu) {
    final minha = _minha;

    return DraggableScrollableSheet(
      initialChildSize: 0.34,
      minChildSize: 0.18,
      maxChildSize: 0.82,
      builder: (context, rolagem) => Container(
        decoration: const BoxDecoration(
          color: Cores.fundo,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(color: Color(0x22000000), blurRadius: 16, offset: Offset(0, -4)),
          ],
        ),
        child: ListView(
          controller: rolagem,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Cores.borda,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (_carregando)
              const Padding(padding: EdgeInsets.all(28), child: Carregando())
            else if (minha != null) ...[
              _tituloDaFolha('Sua corrida', eu),
              _cartao(minha, emAndamento: true),
            ] else ...[
              _tituloDaFolha(
                eu.disponibilidade == DisponibilidadeDoEntregador.offline
                    ? 'Você está fora do ar'
                    : '${_disponiveis.length} corrida(s) disponível(is)',
                eu,
              ),
              if (eu.disponibilidade == DisponibilidadeDoEntregador.offline)
                const _Recado(
                  icone: Icons.power_settings_new,
                  texto: 'Toque em "Fora do ar" ali em cima para começar a '
                      'receber corridas.',
                )
              else if (_disponiveis.isEmpty)
                _Recado(
                  icone: Icons.inbox_outlined,
                  texto:
                      'Nenhuma corrida agora. Quando ${eu.nomeDoRestaurante ?? 'o estabelecimento'} '
                      'despachar um pedido, ele aparece aqui.',
                )
              else
                for (final c in _disponiveis) _cartao(c),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tituloDaFolha(String texto, Entregador eu) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(texto,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            Text('${eu.entregasFeitas} entregas',
                style:
                    const TextStyle(fontSize: 12.5, color: Cores.textoSuave)),
          ],
        ),
      );

  Widget _cartao(Corrida c, {bool emAndamento = false}) {
    // A distância só aparece quando dá para calculá-la de verdade. Número
    // inventado num aplicativo de entrega vira corrida aceita por engano.
    final distancia = (_eu != null && c.ondeRetirar != null)
        ? Localizacao.distanciaKm(_eu!, c.ondeRetirar!)
        : c.entrega.distanciaKm;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: emAndamento ? Cores.marca : Cores.borda),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => TelaCorrida(corrida: c)))
            .then((_) {
          Sessao.instancia.carregar();
          _carregar();
        }),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(c.nomeDoRestaurante,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  Text(emReais(c.entrega.taxaDoEntregadorCentavos),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Cores.sucesso)),
                ],
              ),
              if (emAndamento) ...[
                const SizedBox(height: 6),
                Etiqueta(c.entrega.status.rotulo, cor: Cores.marca, forte: true),
              ],
              const SizedBox(height: 10),
              _etapa(Icons.storefront, 'Retirar', c.enderecoDoRestaurante),
              const SizedBox(height: 6),
              _etapa(Icons.place_outlined, 'Entregar',
                  '${c.enderecoDeEntrega ?? ''} · ${c.bairroDeEntrega ?? ''}'),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (distancia != null) ...[
                    const Icon(Icons.straighten, size: 15, color: Cores.textoSuave),
                    const SizedBox(width: 5),
                    Text('${distanciaKm(distancia)} até a loja',
                        style: const TextStyle(
                            fontSize: 12.5, color: Cores.textoSuave)),
                    const SizedBox(width: 14),
                  ],
                  if (c.recebeNaPorta) ...[
                    const Icon(Icons.payments_outlined,
                        size: 15, color: Cores.atencao),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Receber ${emReais(c.totalDoPedidoCentavos)}',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Cores.atencao),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _etapa(IconData icone, String rotulo, String? endereco) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 16, color: Cores.textoSuave),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: Cores.texto),
                children: [
                  TextSpan(
                      text: '$rotulo  ',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Cores.textoSuave,
                          fontSize: 12)),
                  TextSpan(text: endereco ?? '—'),
                ],
              ),
            ),
          ),
        ],
      );

  /// Entregador não aprovado não pode nem ficar disponível — é o gatilho
  /// `app.guard_courier_platform_fields` que recusa. A tela diz isso em vez de
  /// oferecer um botão que o banco vai negar.
  Widget _aguardandoAprovacao(Entregador eu) => Vazio(
        icone: Icons.hourglass_top,
        titulo: eu.status == StatusDoEntregador.suspenso
            ? 'Seu cadastro está suspenso'
            : 'Cadastro em análise',
        detalhe: eu.status == StatusDoEntregador.suspenso
            ? 'Fale com ${eu.nomeDoRestaurante ?? 'o estabelecimento'} para '
                'voltar a receber corridas.'
            : 'Assim que ${eu.nomeDoRestaurante ?? 'o estabelecimento'} '
                'aprovar, as corridas aparecem aqui.',
      );
}

class _Recado extends StatelessWidget {
  const _Recado({required this.icone, required this.texto});
  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: Cores.borda),
            const SizedBox(width: 12),
            Expanded(
              child: Text(texto,
                  style: const TextStyle(
                      color: Cores.textoSuave, height: 1.45, fontSize: 13.5)),
            ),
          ],
        ),
      );
}
