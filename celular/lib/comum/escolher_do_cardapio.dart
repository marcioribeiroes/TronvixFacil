/// O cardápio da loja para escolher um item que vai para um pedido já feito.
///
/// Abre a mesma tela de produto do cliente — adicionais, observação,
/// quantidade —, e devolve a [EscolhaDoProduto] para quem chamou.
library;

import 'package:flutter/material.dart';

import '../cliente/produto.dart';
import '../dados/cardapio.dart';
import '../dados/edicao.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../tema.dart';
import 'widgets.dart';

class TelaEscolherDoCardapio extends StatefulWidget {
  const TelaEscolherDoCardapio({super.key, required this.restauranteId});

  final String restauranteId;

  @override
  State<TelaEscolherDoCardapio> createState() => _TelaEscolherDoCardapioState();
}

class _TelaEscolherDoCardapioState extends State<TelaEscolherDoCardapio> {
  Restaurante? _restaurante;
  List<SecaoDoCardapio> _secoes = const [];
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final resultados = await Future.wait([
        Cardapio.restaurante(widget.restauranteId),
        Cardapio.secoes(widget.restauranteId),
      ]);
      if (!mounted) return;
      setState(() {
        _restaurante = resultados[0] as Restaurante;
        _secoes = resultados[1] as List<SecaoDoCardapio>;
        _erro = null;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = e);
    }
  }

  Future<void> _escolher(Produto p) async {
    final escolha = await Navigator.of(context).push<EscolhaDoProduto>(
      MaterialPageRoute(
        builder: (_) => TelaProduto(
          produto: p,
          restaurante: _restaurante!,
          paraOPedido: true,
        ),
      ),
    );
    if (escolha != null && mounted) Navigator.of(context).pop(escolha);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escolher item')),
      body: _erro != null
          ? Falhou(erro: _erro!, aoTentarDeNovo: _carregar)
          : _restaurante == null
          ? const Carregando()
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final s in _secoes) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                    child: Text(
                      s.categoria.nome,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Cores.textoSuave,
                      ),
                    ),
                  ),
                  for (final p in s.produtos)
                    Opacity(
                      opacity: p.podeSerPedido ? 1 : 0.45,
                      child: ListTile(
                        title: Text(
                          p.nome,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: p.podeSerPedido
                            ? null
                            : const Text('Indisponível'),
                        trailing: Text(
                          emReais(p.precoQueVale),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onTap: p.podeSerPedido ? () => _escolher(p) : null,
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
