/// A equipe de entrega do estabelecimento.
///
/// Quem aprova é daqui. O sistema não leiloa a corrida para uma plataforma de
/// entregadores: quem leva a comida é gente do restaurante, e quem diz que ela
/// pode levar é o restaurante.
///
/// A chave no fim da tela abre exceção a isso, para quem quiser — e ela é
/// desligada por omissão de propósito.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/balcao.dart';
import '../modelos/modelos.dart';
import '../sessao.dart';
import '../tema.dart';

class TelaEntregadores extends StatefulWidget {
  const TelaEntregadores({super.key});

  @override
  State<TelaEntregadores> createState() => _TelaEntregadoresState();
}

class _TelaEntregadoresState extends State<TelaEntregadores> {
  List<Entregador> _entregadores = const [];
  Restaurante? _restaurante;
  bool _carregando = true;
  Object? _erro;

  String? get _restauranteId => Sessao.instancia.vinculo?.restauranteId;
  bool get _podeGerenciar =>
      Sessao.instancia.vinculo?.papel.gerencia ?? false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final id = _restauranteId;
    if (id == null) return;
    try {
      final resultados = await Future.wait([
        Balcao.entregadores(),
        Balcao.meuRestaurante(id),
      ]);
      if (!mounted) return;
      setState(() {
        _entregadores = resultados[0] as List<Entregador>;
        _restaurante = resultados[1] as Restaurante;
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

  Future<void> _decidir(Entregador e, StatusDoEntregador novo) async {
    try {
      await Balcao.decidirSobreEntregador(e.id, novo);
      await _carregar();
    } catch (erro) {
      if (mounted) avisar(context, erro.toString(), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendentes = _entregadores
        .where((e) => e.status == StatusDoEntregador.pendente)
        .toList();
    final resto = _entregadores
        .where((e) => e.status != StatusDoEntregador.pendente)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Entregadores')),
      body: _carregando
          ? const Carregando()
          : _erro != null
              ? Falhou(erro: _erro!, aoTentarDeNovo: _carregar)
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    children: [
                      if (pendentes.isNotEmpty) ...[
                        _titulo('Esperando sua aprovação'),
                        for (final e in pendentes) _linha(e),
                      ],
                      _titulo('Sua equipe'),
                      if (resto.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                          child: Text(
                            'Ninguém aprovado ainda. Quem quiser entregar para '
                            'você se cadastra pelo aplicativo e aparece aqui.',
                            style: TextStyle(
                                color: Cores.textoSuave, height: 1.45),
                          ),
                        )
                      else
                        for (final e in resto) _linha(e),
                      const Divider(height: 32),
                      _chaveDaPlataforma(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(texto,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _linha(Entregador e) {
    final cor = switch (e.status) {
      StatusDoEntregador.aprovado => Cores.sucesso,
      StatusDoEntregador.suspenso => Cores.perigo,
      StatusDoEntregador.pendente => Cores.atencao,
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: Cores.suave,
        child: Icon(
          e.tipoDeVeiculo == 'bicycle'
              ? Icons.pedal_bike
              : e.tipoDeVeiculo == 'car'
                  ? Icons.directions_car
                  : e.tipoDeVeiculo == 'foot'
                      ? Icons.directions_walk
                      : Icons.two_wheeler,
          color: Cores.textoSuave,
        ),
      ),
      title: Text(e.nome ?? 'Entregador',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Etiqueta(
              switch (e.status) {
                StatusDoEntregador.aprovado => e.disponibilidade.rotulo,
                StatusDoEntregador.pendente => 'Pendente',
                StatusDoEntregador.suspenso => 'Suspenso',
              },
              cor: cor,
            ),
            const SizedBox(width: 8),
            Text('${e.veiculo} · ${e.entregasFeitas} entregas',
                style:
                    const TextStyle(fontSize: 12.5, color: Cores.textoSuave)),
          ],
        ),
      ),
      trailing: !_podeGerenciar
          ? null
          : e.status == StatusDoEntregador.pendente
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () =>
                          _decidir(e, StatusDoEntregador.suspenso),
                      child: const Text('Recusar'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 14)),
                      onPressed: () =>
                          _decidir(e, StatusDoEntregador.aprovado),
                      child: const Text('Aprovar'),
                    ),
                  ],
                )
              : PopupMenuButton<StatusDoEntregador>(
                  onSelected: (novo) => _decidir(e, novo),
                  itemBuilder: (_) => [
                    if (e.status != StatusDoEntregador.aprovado)
                      const PopupMenuItem(
                          value: StatusDoEntregador.aprovado,
                          child: Text('Reativar')),
                    if (e.status == StatusDoEntregador.aprovado)
                      const PopupMenuItem(
                          value: StatusDoEntregador.suspenso,
                          child: Text('Suspender')),
                  ],
                ),
    );
  }

  Widget _chaveDaPlataforma() {
    final r = _restaurante;
    if (r == null) return const SizedBox.shrink();

    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      value: r.aceitaEntregadorDaPlataforma,
      onChanged: !_podeGerenciar
          ? null
          : (v) async {
              try {
                await Balcao.aceitarEntregadorDaPlataforma(r.id, v);
                await _carregar();
              } catch (e) {
                if (mounted) avisar(context, e.toString(), erro: true);
              }
            },
      title: const Text('Aceitar entregador de fora',
          style: TextStyle(fontWeight: FontWeight.w700)),
      subtitle: const Text(
        'Desligado, suas corridas só aparecem para a sua equipe. Ligado, '
        'entregadores autônomos da plataforma também podem pegá-las.',
        style: TextStyle(fontSize: 13, height: 1.4),
      ),
    );
  }
}
