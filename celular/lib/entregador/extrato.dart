/// O que o entregador levou, e quanto rendeu.
///
/// Espelho de src/app/(entregador)/entregas/historico/page.tsx. O ganho vem de
/// `courier_fee_cents` da própria corrida, congelado quando ela nasceu — a tela
/// tem de concordar com o acerto. E o acerto é com cada estabelecimento: quem
/// paga o entregador é a loja, então o extrato separa quanto cada uma deve.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/corridas.dart';
import '../formato.dart';
import '../tema.dart';

class TelaExtrato extends StatefulWidget {
  const TelaExtrato({super.key, required this.entregadorId});

  final String entregadorId;

  @override
  State<TelaExtrato> createState() => _TelaExtratoState();
}

class _TelaExtratoState extends State<TelaExtrato> {
  List<Corrida> _corridas = const [];
  bool _carregando = true;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final lista =
          await Corridas.minhasEntregues(widget.entregadorId, limite: 300);
      if (!mounted) return;
      setState(() {
        _corridas = lista;
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

  int _desde(DateTime inicio) => _corridas
      .where((c) => c.entrega.entregueEm?.isAfter(inicio) ?? false)
      .fold(0, (s, c) => s + c.entrega.taxaDoEntregadorCentavos);

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Scaffold(body: Carregando());
    if (_erro != null) {
      return Scaffold(body: Falhou(erro: _erro!, aoTentarDeNovo: _carregar));
    }

    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final semana = hoje.subtract(const Duration(days: 6));
    final mes = hoje.subtract(const Duration(days: 29));

    final porLoja = <String, (int, int)>{};
    for (final c in _corridas) {
      if (!(c.entrega.entregueEm?.isAfter(semana) ?? false)) continue;
      final (n, total) = porLoja[c.nomeDoRestaurante] ?? (0, 0);
      porLoja[c.nomeDoRestaurante] =
          (n + 1, total + c.entrega.taxaDoEntregadorCentavos);
    }
    final lojas = porLoja.entries.toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));

    return Scaffold(
      appBar: AppBar(title: const Text('Extrato')),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                for (final (rotulo, valor) in [
                  ('Hoje', _desde(hoje)),
                  ('7 dias', _desde(semana)),
                  ('30 dias', _desde(mes)),
                ])
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          children: [
                            Text(rotulo,
                                style: const TextStyle(
                                    fontSize: 12, color: Cores.textoSuave)),
                            const SizedBox(height: 4),
                            Text(emReais(valor),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (lojas.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('A receber de cada estabelecimento (7 dias)',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              for (final l in lojas)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.key),
                  subtitle: Text(
                      '${l.value.$1} ${l.value.$1 == 1 ? 'entrega' : 'entregas'}'),
                  trailing: Text(emReais(l.value.$2),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
            ],
            const SizedBox(height: 16),
            const Text('Corridas',
                style: TextStyle(fontWeight: FontWeight.w800)),
            if (_corridas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Nenhuma entrega ainda.',
                    style: TextStyle(color: Cores.textoSuave)),
              ),
            for (final c in _corridas.take(60))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c.nomeDoRestaurante),
                subtitle: Text('#${c.numeroDoPedido} · ${c.nomeDoCliente}'),
                trailing: Text(emReais(c.entrega.taxaDoEntregadorCentavos),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }
}
