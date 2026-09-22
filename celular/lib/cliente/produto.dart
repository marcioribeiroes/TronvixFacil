/// Um item do cardápio, com os adicionais.
///
/// É aqui que a maior parte das regras do cardápio aparece para a pessoa:
/// grupo obrigatório, mínimo, máximo. A tela obedece a todas — mas quem obriga
/// de verdade é `fechar_pedido`, no banco. Se as duas discordarem, o pedido é
/// recusado no fechamento, e o certo é o banco.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/cardapio.dart';
import '../dados/carrinho.dart';
import '../formato.dart';
import '../main.dart';
import '../modelos/modelos.dart';
import '../tema.dart';

class TelaProduto extends StatefulWidget {
  const TelaProduto({super.key, required this.produto, required this.restaurante});

  final Produto produto;
  final Restaurante restaurante;

  @override
  State<TelaProduto> createState() => _TelaProdutoState();
}

class _TelaProdutoState extends State<TelaProduto> {
  final _observacao = TextEditingController();

  List<GrupoDeAdicionais> _grupos = const [];
  final Map<String, int> _escolhidos = {}; // adicional.id -> quantidade
  int _quantidade = 1;
  bool _carregando = true;
  bool _enviando = false;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _observacao.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final grupos = await Cardapio.adicionais(widget.produto.id);
      if (!mounted) return;
      setState(() {
        _grupos = grupos;
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

  List<AdicionalEscolhido> get _selecao => [
        for (final g in _grupos)
          for (final a in g.adicionais)
            if ((_escolhidos[a.id] ?? 0) > 0)
              AdicionalEscolhido(adicional: a, quantidade: _escolhidos[a.id]!),
      ];

  int get _adicionaisCentavos =>
      _selecao.fold(0, (s, a) => s + a.totalCentavos);

  int get _totalCentavos =>
      (widget.produto.precoQueVale + _adicionaisCentavos) * _quantidade;

  /// O primeiro grupo obrigatório ainda sem escolha suficiente, se houver.
  GrupoDeAdicionais? get _grupoPendente {
    for (final g in _grupos) {
      final escolhidos = g.adicionais
          .fold<int>(0, (s, a) => s + (_escolhidos[a.id] ?? 0));
      if (escolhidos < g.minimo) return g;
    }
    return null;
  }

  int _escolhidosNoGrupo(GrupoDeAdicionais g) =>
      g.adicionais.fold(0, (s, a) => s + (_escolhidos[a.id] ?? 0));

  Future<void> _adicionar() async {
    final pendente = _grupoPendente;
    if (pendente != null) {
      avisar(context, 'Escolha em "${pendente.nome}" antes de continuar.',
          erro: true);
      return;
    }

    if (!await exigirConta(context)) return;
    if (!mounted) return;

    // Carrinho é de um estabelecimento só — é assim no schema, porque um
    // pedido pertence a um restaurante. Perguntar antes de descartar é o
    // mínimo: a pessoa pode ter montado o outro carrinho inteiro.
    final carrinho = Carrinho.instancia;
    if (carrinho.ehDeOutro(widget.restaurante.id)) {
      final trocar = await showDialog<bool>(
        context: context,
        builder: (contexto) => AlertDialog(
          title: const Text('Começar outro pedido?'),
          content: Text(
            'Seu carrinho tem itens de ${carrinho.restaurante?.nome}. '
            'Cada pedido é de um estabelecimento só — continuar aqui descarta o outro.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(contexto, false),
                child: const Text('Manter o outro')),
            FilledButton(
                onPressed: () => Navigator.pop(contexto, true),
                child: const Text('Começar aqui')),
          ],
        ),
      );
      if (trocar != true) return;
    }

    setState(() => _enviando = true);
    try {
      await Carrinho.instancia.adicionar(
        restaurante: widget.restaurante,
        produto: widget.produto,
        quantidade: _quantidade,
        adicionais: _selecao,
        observacao: _observacao.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.produto;

    return Scaffold(
      appBar: AppBar(title: Text(p.nome, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _erro != null
          ? Falhou(erro: _erro!)
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                if (p.imagemUrl != null && p.imagemUrl!.isNotEmpty)
                  Foto(url: p.imagemUrl, largura: double.infinity, altura: 220, raio: 0),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.nome,
                          style: const TextStyle(
                              fontSize: 21, fontWeight: FontWeight.w800)),
                      if (p.descricao != null && p.descricao!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(p.descricao!,
                            style: const TextStyle(
                                color: Cores.textoSuave, height: 1.45)),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(emReais(p.precoQueVale),
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800)),
                          if (p.emPromocao) ...[
                            const SizedBox(width: 8),
                            Text(emReais(p.precoCentavos),
                                style: const TextStyle(
                                  color: Cores.textoSuave,
                                  decoration: TextDecoration.lineThrough,
                                )),
                            const SizedBox(width: 8),
                            const Etiqueta('Promoção', cor: Cores.sucesso),
                          ],
                        ],
                      ),
                      if (p.serveQuantasPessoas != null) ...[
                        const SizedBox(height: 8),
                        Text('Serve ${p.serveQuantasPessoas} pessoa(s)',
                            style: const TextStyle(
                                fontSize: 13, color: Cores.textoSuave)),
                      ],
                    ],
                  ),
                ),
                if (_carregando)
                  const Padding(
                      padding: EdgeInsets.all(32), child: Carregando())
                else
                  for (final g in _grupos) _grupo(g),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _observacao,
                    maxLines: 3,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Alguma observação?',
                      hintText: 'Ex.: sem cebola, ponto da carne, embalar separado',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
      bottomNavigationBar: _erro != null
          ? null
          : BarraDeAcao(
              acima: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Quantidade(
                    valor: _quantidade,
                    aoMudar: (v) => setState(() => _quantidade = v),
                  ),
                  Text(emReais(_totalCentavos),
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800)),
                ],
              ),
              filho: FilledButton(
                onPressed: _enviando ? null : _adicionar,
                child: Text(_enviando ? 'Adicionando…' : 'Adicionar ao carrinho'),
              ),
            ),
    );
  }

  Widget _grupo(GrupoDeAdicionais g) {
    final escolhidos = _escolhidosNoGrupo(g);
    final cheio = escolhidos >= g.maximo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: Cores.suave,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.nome,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    if (g.descricao != null && g.descricao!.isNotEmpty)
                      Text(g.descricao!,
                          style: const TextStyle(
                              fontSize: 12.5, color: Cores.textoSuave)),
                  ],
                ),
              ),
              if (g.obrigatorio)
                Etiqueta(
                  escolhidos >= g.minimo ? 'ok' : 'obrigatório',
                  cor: escolhidos >= g.minimo ? Cores.sucesso : Cores.marca,
                )
              else
                Etiqueta(g.regra),
            ],
          ),
        ),
        if (g.escolhaUnica)
          // Escolha única, mas feita à mão em vez de `RadioGroup`: num grupo
          // OPCIONAL, tocar de novo no que já está marcado precisa desmarcar,
          // e rádio não volta para "nenhum" sozinho. Sem isso, quem tocasse
          // sem querer em "Molho Mostarda" levava o molho para casa — a única
          // saída era sair da tela e montar o item de novo.
          //
          // Em grupo obrigatório o toque repetido não faz nada: ali "nenhum"
          // não é resposta válida, e apagar a escolha só deixaria a pessoa
          // presa no botão desligado.
          Column(
            children: [
              for (final a in g.adicionais)
                Builder(builder: (_) {
                  final marcado = (_escolhidos[a.id] ?? 0) > 0;
                  return ListTile(
                    leading: Icon(
                      marcado
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: marcado ? Cores.marca : Cores.textoSuave,
                    ),
                    title: Text(a.nome),
                    subtitle: a.precoCentavos == 0
                        ? null
                        : Text('+ ${emReais(a.precoCentavos)}',
                            style: const TextStyle(color: Cores.textoSuave)),
                    onTap: () => setState(() {
                      if (marcado) {
                        if (!g.obrigatorio) _escolhidos.remove(a.id);
                        return;
                      }
                      for (final x in g.adicionais) {
                        _escolhidos.remove(x.id);
                      }
                      _escolhidos[a.id] = 1;
                    }),
                  );
                }),
            ],
          )
        else
          for (final a in g.adicionais)
            ListTile(
                  title: Text(a.nome),
                  subtitle: a.precoCentavos == 0
                      ? null
                      : Text('+ ${emReais(a.precoCentavos)}',
                          style: const TextStyle(color: Cores.textoSuave)),
                  trailing: (_escolhidos[a.id] ?? 0) > 0 || !cheio
                      ? Quantidade(
                          compacto: true,
                          minimo: 0,
                          maximo: a.quantidadeMaxima,
                          valor: _escolhidos[a.id] ?? 0,
                          aoMudar: (v) => setState(() {
                            if (v <= 0) {
                              _escolhidos.remove(a.id);
                            } else if (escolhidos - (_escolhidos[a.id] ?? 0) + v <=
                                g.maximo) {
                              _escolhidos[a.id] = v;
                            }
                          }),
                        )
                      : null,
                ),
        const Divider(height: 1),
      ],
    );
  }
}
