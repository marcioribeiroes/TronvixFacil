/// A primeira tela: onde pedir.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/pedidos.dart';
import '../dados/vitrine.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../sessao.dart';
import '../tema.dart';
import 'acompanhar.dart';
import 'restaurante.dart';

class TelaVitrine extends StatefulWidget {
  const TelaVitrine({super.key});

  @override
  State<TelaVitrine> createState() => _TelaVitrineState();
}

class _TelaVitrineState extends State<TelaVitrine> {
  final _busca = TextEditingController();

  List<CategoriaDaPlataforma> _categorias = const [];
  List<Restaurante> _restaurantes = const [];
  Pedido? _andando;
  String? _categoriaEscolhida;
  bool _carregando = true;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final resultados = await Future.wait([
        Vitrine.categorias(),
        Vitrine.restaurantes(
          busca: _busca.text,
          categoriaId: _categoriaEscolhida,
        ),
        // Um pedido a caminho é o motivo mais provável de alguém abrir o
        // aplicativo. Ele vem junto da vitrine e fica no topo.
        Pedidos.emAndamento(),
      ]);

      if (!mounted) return;
      setState(() {
        _categorias = resultados[0] as List<CategoriaDaPlataforma>;
        _restaurantes = resultados[1] as List<Restaurante>;
        _andando = resultados[2] as Pedido?;
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
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _carregar,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _cabecalho()),
                if (_andando != null)
                  SliverToBoxAdapter(child: _faixaDoPedido(_andando!)),
                if (_categorias.isNotEmpty)
                  SliverToBoxAdapter(child: _filtros()),
                if (_carregando)
                  const SliverFillRemaining(child: Carregando())
                else if (_erro != null)
                  SliverFillRemaining(
                      child: Falhou(erro: _erro!, aoTentarDeNovo: _carregar))
                else if (_restaurantes.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Vazio(
                      icone: Icons.storefront_outlined,
                      titulo: 'Nada por aqui ainda',
                      detalhe:
                          'Nenhum estabelecimento aprovado corresponde a essa busca.',
                    ),
                  )
                else
                  SliverList.separated(
                    itemCount: _restaurantes.length,
                    separatorBuilder: (_, _) => const Divider(indent: 16),
                    itemBuilder: (_, i) => _CartaoDeRestaurante(
                      restaurante: _restaurantes[i],
                      aoTocar: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              TelaRestaurante(restaurante: _restaurantes[i]),
                        ),
                      ).then((_) => _carregar()),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
      );

  Widget _cabecalho() {
    final nome = Sessao.instancia.perfil?.primeiroNome;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nome == null ? 'O que você quer comer?' : 'Boa, $nome. Bateu a fome?',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _busca,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _carregar(),
            decoration: InputDecoration(
              hintText: 'Buscar restaurantes',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _busca.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _busca.clear();
                        _carregar();
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtros() => SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          itemCount: _categorias.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            if (i == 0) {
              return ChoiceChip(
                label: const Text('Tudo'),
                selected: _categoriaEscolhida == null,
                onSelected: (_) {
                  setState(() => _categoriaEscolhida = null);
                  _carregar();
                },
              );
            }
            final c = _categorias[i - 1];
            return ChoiceChip(
              label: Text(c.nome),
              selected: _categoriaEscolhida == c.id,
              onSelected: (escolhida) {
                setState(() => _categoriaEscolhida = escolhida ? c.id : null);
                _carregar();
              },
            );
          },
        ),
      );

  Widget _faixaDoPedido(Pedido pedido) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Material(
          color: Cores.realce,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(
                    builder: (_) => TelaAcompanhar(pedidoId: pedido.id)))
                .then((_) => _carregar()),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.delivery_dining, color: Cores.marcaEscura),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pedido.status.paraOCliente,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Cores.marcaEscura)),
                        Text(
                          '${pedido.nomeDoRestaurante ?? 'Pedido'} · nº ${pedido.numero}',
                          style: const TextStyle(
                              fontSize: 13, color: Cores.marcaEscura),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Cores.marcaEscura),
                ],
              ),
            ),
          ),
        ),
      );
}

class _CartaoDeRestaurante extends StatelessWidget {
  const _CartaoDeRestaurante({required this.restaurante, required this.aoTocar});

  final Restaurante restaurante;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final r = restaurante;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      onTap: aoTocar,
      leading: Opacity(
        // Loja fechada continua na lista, mas apagada: o cliente precisa saber
        // que ela existe e voltar amanhã, sem achar que pode pedir agora.
        opacity: r.aberto ? 1 : 0.45,
        child: Foto(url: r.logoUrl, largura: 60, altura: 60, icone: Icons.storefront),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(r.nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          if (!r.aberto) ...[
            const SizedBox(width: 8),
            const Etiqueta('Fechado'),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            if (r.temNota) ...[
              const Icon(Icons.star, size: 14, color: Cores.atencao),
              const SizedBox(width: 3),
              Text(r.notaMedia.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const _Ponto(),
            ],
            Text(faixaDeMinutos(r.minutosDePreparo, r.minutosDeEntrega),
                style: const TextStyle(fontSize: 13, color: Cores.textoSuave)),
            const _Ponto(),
            Text(
              r.taxaDeEntregaCentavos == 0
                  ? 'Entrega grátis'
                  : emReais(r.taxaDeEntregaCentavos),
              style: TextStyle(
                fontSize: 13,
                color: r.taxaDeEntregaCentavos == 0
                    ? Cores.sucesso
                    : Cores.textoSuave,
                fontWeight: r.taxaDeEntregaCentavos == 0
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ponto extends StatelessWidget {
  const _Ponto();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text('·', style: TextStyle(color: Cores.borda)),
      );
}
