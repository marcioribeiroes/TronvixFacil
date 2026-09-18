/// O cardápio visto pelo balcão.
///
/// Uma coisa só, e a mais usada no meio do movimento: tirar e repor item.
/// "Acabou o hambúrguer" precisa de um toque, não de um formulário.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/balcao.dart';
import '../dados/cardapio.dart';
import '../formato.dart';
import '../sessao.dart';
import '../tema.dart';

class TelaCardapioDoBalcao extends StatefulWidget {
  const TelaCardapioDoBalcao({super.key});

  @override
  State<TelaCardapioDoBalcao> createState() => _TelaCardapioDoBalcaoState();
}

class _TelaCardapioDoBalcaoState extends State<TelaCardapioDoBalcao> {
  List<SecaoDoCardapio> _secoes = const [];
  bool _carregando = true;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final id = Sessao.instancia.vinculo?.restauranteId;
    if (id == null) return;
    try {
      final secoes = await Cardapio.secoes(id);
      if (!mounted) return;
      setState(() {
        _secoes = secoes;
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

  @override
  Widget build(BuildContext context) {
    final podeGerenciar =
        Sessao.instancia.vinculo?.papel.gerencia ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Cardápio')),
      body: _carregando
          ? const Carregando()
          : _erro != null
              ? Falhou(erro: _erro!, aoTentarDeNovo: _carregar)
              : ListView(
                  children: [
                    if (!podeGerenciar)
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Cores.suave,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Seu papel é de atendente: você vê o cardápio, mas quem '
                          'tira e repõe item é a gerência.',
                          style: TextStyle(fontSize: 13, color: Cores.textoSuave),
                        ),
                      ),
                    for (final secao in _secoes) ...[
                      Container(
                        width: double.infinity,
                        color: Cores.suave,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Text(secao.categoria.nome.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: Cores.textoSuave)),
                      ),
                      for (final p in secao.produtos)
                        SwitchListTile(
                          value: p.disponivel,
                          onChanged: podeGerenciar
                              ? (v) async {
                                  try {
                                    await Balcao.mudarDisponibilidade(p.id, v);
                                    await _carregar();
                                  } catch (e) {
                                    if (context.mounted) {
                                      avisar(context, e.toString(), erro: true);
                                    }
                                  }
                                }
                              : null,
                          title: Text(p.nome),
                          subtitle: Text(
                            p.esgotado
                                ? 'Sem estoque'
                                : '${emReais(p.precoQueVale)}'
                                    '${p.emPromocao ? ' · em promoção' : ''}',
                            style: TextStyle(
                                color: p.esgotado
                                    ? Cores.perigo
                                    : Cores.textoSuave),
                          ),
                          secondary:
                              Foto(url: p.imagemUrl, largura: 44, altura: 44),
                        ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }
}
