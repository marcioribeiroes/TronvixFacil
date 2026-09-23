/// O cardápio de um estabelecimento.
library;

import 'package:flutter/material.dart';

import '../comum/barra_do_carrinho.dart';
import '../comum/widgets.dart';
import '../dados/cardapio.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../tema.dart';
import 'produto.dart';

class TelaRestaurante extends StatefulWidget {
  /// Chegou pela vitrine: o estabelecimento já veio pronto.
  const TelaRestaurante({super.key, required Restaurante this.restaurante})
      : slug = null,
        raiz = false;

  /// Modo único: o aplicativo *é* deste estabelecimento e o busca pelo slug.
  /// `raiz` tira o botão de voltar — não há para onde voltar.
  const TelaRestaurante.porSlug(this.slug, {super.key})
      : restaurante = null,
        raiz = true;

  final Restaurante? restaurante;
  final String? slug;
  final bool raiz;

  @override
  State<TelaRestaurante> createState() => _TelaRestauranteState();
}

class _TelaRestauranteState extends State<TelaRestaurante> {
  List<SecaoDoCardapio> _secoes = const [];
  Restaurante? _restaurante;
  bool _carregando = true;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _restaurante = widget.restaurante;
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = _restaurante ??
          await Cardapio.restaurantePorSlug(widget.slug!);
      final secoes = await Cardapio.secoes(r.id);
      if (!mounted) return;
      setState(() {
        _restaurante = r;
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
    final r = _restaurante;

    if (r == null) {
      return Scaffold(
        body: _carregando
            ? const Carregando()
            : Falhou(
                erro: _erro ?? 'Estabelecimento não encontrado.',
                aoTentarDeNovo: _carregar,
              ),
      );
    }

    return Scaffold(
      // A barra do carrinho vive AQUI também, e não só nas telas de aba: este
      // é o único lugar onde se adiciona item, e sem ela o "Adicionar ao
      // carrinho" não produzia nenhum sinal na tela.
      bottomNavigationBar: const BarraDoCarrinho(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            automaticallyImplyLeading: !widget.raiz,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(r.nome,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Foto(
                    url: r.capaUrl ?? r.logoUrl,
                    largura: double.infinity,
                    altura: 180,
                    raio: 0,
                    icone: Icons.storefront,
                  ),
                  // Véu por baixo do nome. Sem ele o texto some dentro da foto
                  // — e capa de restaurante é justamente onde há tijolo, prato
                  // e letreiro. O escuro entra só na metade de baixo, para não
                  // apagar a foto que a loja escolheu.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x99000000)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: _informacoes(r)),
          if (_carregando)
            const SliverFillRemaining(child: Carregando())
          else if (_erro != null)
            SliverFillRemaining(
                child: Falhou(erro: _erro!, aoTentarDeNovo: _carregar))
          else if (_secoes.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Vazio(
                icone: Icons.menu_book_outlined,
                titulo: 'Cardápio vazio',
                detalhe: 'Este estabelecimento ainda não publicou produtos.',
              ),
            )
          else
            for (final secao in _secoes) ...[
              SliverToBoxAdapter(child: _tituloDaSecao(secao.categoria)),
              SliverList.separated(
                itemCount: secao.produtos.length,
                separatorBuilder: (_, _) => const Divider(indent: 16),
                itemBuilder: (_, i) => _LinhaDeProduto(
                  produto: secao.produtos[i],
                  restaurante: r,
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _informacoes(Restaurante r) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Cores.borda)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!r.aberto)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Cores.realce,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Fechado agora. Você pode olhar o cardápio, mas o pedido só sai quando abrir.',
                  style: TextStyle(color: Cores.marcaEscura, fontSize: 13.5),
                ),
              ),
            if (r.descricao != null && r.descricao!.isNotEmpty) ...[
              Text(r.descricao!,
                  style: const TextStyle(color: Cores.textoSuave, height: 1.4)),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                if (r.temNota)
                  _info(Icons.star, '${r.notaMedia.toStringAsFixed(1)} '
                      '(${r.quantidadeDeNotas})'),
                _info(Icons.schedule,
                    faixaDeMinutos(r.minutosDePreparo, r.minutosDeEntrega)),
                _info(
                  Icons.delivery_dining,
                  r.taxaDeEntregaCentavos == 0
                      ? 'Entrega grátis'
                      : emReais(r.taxaDeEntregaCentavos),
                ),
                if (r.pedidoMinimoCentavos > 0)
                  _info(Icons.shopping_basket_outlined,
                      'Mínimo ${emReais(r.pedidoMinimoCentavos)}'),
              ],
            ),
            if (r.entregaGratisAcimaDeCentavos != null) ...[
              const SizedBox(height: 10),
              Text(
                'Entrega grátis acima de ${emReais(r.entregaGratisAcimaDeCentavos!)}',
                style: const TextStyle(
                    color: Cores.sucesso,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ],
          ],
        ),
      );

  Widget _info(IconData icone, String texto) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 16, color: Cores.textoSuave),
          const SizedBox(width: 5),
          Text(texto,
              style: const TextStyle(fontSize: 13, color: Cores.textoSuave)),
        ],
      );

  Widget _tituloDaSecao(Categoria c) => Container(
        width: double.infinity,
        color: Cores.suave,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Text(c.nome.toUpperCase(),
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Cores.textoSuave)),
      );
}

class _LinhaDeProduto extends StatelessWidget {
  const _LinhaDeProduto({required this.produto, required this.restaurante});

  final Produto produto;
  final Restaurante restaurante;

  @override
  Widget build(BuildContext context) {
    final p = produto;
    final indisponivel = !p.podeSerPedido;

    return Opacity(
      opacity: indisponivel ? 0.5 : 1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        onTap: indisponivel
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        TelaProduto(produto: p, restaurante: restaurante),
                  ),
                ),
        title: Text(p.nome,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.descricao != null && p.descricao!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(p.descricao!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, color: Cores.textoSuave, height: 1.35)),
            ],
            const SizedBox(height: 7),
            Row(
              children: [
                Text(emReais(p.precoQueVale),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Cores.texto)),
                if (p.emPromocao) ...[
                  const SizedBox(width: 7),
                  Text(
                    emReais(p.precoCentavos),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Cores.textoSuave,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
                if (p.esgotado) ...[
                  const SizedBox(width: 8),
                  const Etiqueta('Esgotado', cor: Cores.perigo),
                ] else if (!p.disponivel) ...[
                  const SizedBox(width: 8),
                  const Etiqueta('Indisponível'),
                ],
              ],
            ),
          ],
        ),
        trailing: Foto(url: p.imagemUrl, largura: 78, altura: 78),
      ),
    );
  }
}
