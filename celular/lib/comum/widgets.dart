/// Peças que se repetem nas três frentes do aplicativo.
library;

import 'package:flutter/material.dart';

import '../formato.dart';
import '../tema.dart';

/// Estado vazio com voz — "nenhum pedido ainda" diz mais que uma lista em
/// branco, e evita que a pessoa ache que o aplicativo quebrou.
class Vazio extends StatelessWidget {
  const Vazio({super.key, required this.titulo, this.detalhe, this.icone, this.acao});

  final String titulo;
  final String? detalhe;
  final IconData? icone;
  final Widget? acao;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone ?? Icons.inbox_outlined, size: 48, color: Cores.borda),
              const SizedBox(height: 16),
              Text(titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: Cores.texto)),
              if (detalhe != null) ...[
                const SizedBox(height: 8),
                Text(detalhe!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Cores.textoSuave, height: 1.4)),
              ],
              if (acao != null) ...[const SizedBox(height: 20), acao!],
            ],
          ),
        ),
      );
}

class Carregando extends StatelessWidget {
  const Carregando({super.key, this.mensagem});
  final String? mensagem;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            if (mensagem != null) ...[
              const SizedBox(height: 14),
              Text(mensagem!, style: const TextStyle(color: Cores.textoSuave)),
            ],
          ],
        ),
      );
}

/// Falha na tela inteira, com a chance de tentar de novo.
///
/// A mensagem vem pronta de `ErroDeDados` — inclusive as que o próprio banco
/// escreveu nos gatilhos, que já estão em português e dizem a coisa certa.
class Falhou extends StatelessWidget {
  const Falhou({super.key, required this.erro, this.aoTentarDeNovo});
  final Object erro;
  final VoidCallback? aoTentarDeNovo;

  @override
  Widget build(BuildContext context) => Vazio(
        icone: Icons.error_outline,
        titulo: 'Não deu certo',
        detalhe: erro.toString(),
        acao: aoTentarDeNovo == null
            ? null
            : OutlinedButton(
                onPressed: aoTentarDeNovo,
                child: const Text('Tentar de novo'),
              ),
      );
}

void avisar(BuildContext context, String texto, {bool erro = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? Cores.perigo : Cores.texto,
    ));
}

/// Etiqueta curta e colorida: situação do pedido, "aberto", "esgotado".
class Etiqueta extends StatelessWidget {
  const Etiqueta(this.texto, {super.key, this.cor = Cores.textoSuave, this.forte = false});

  final String texto;
  final Color cor;
  final bool forte;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: forte ? cor : cor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          texto.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: forte ? Colors.white : cor,
          ),
        ),
      );
}

/// Imagem de produto ou de loja que não quebra a tela quando não existe —
/// cardápio recém-cadastrado quase nunca tem foto em tudo.
class Foto extends StatelessWidget {
  const Foto({
    super.key,
    this.url,
    this.largura = 88,
    this.altura = 88,
    this.raio = 12,
    this.icone = Icons.restaurant_menu,
  });

  final String? url;
  final double largura;
  final double altura;
  final double raio;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final vazia = Container(
      width: largura,
      height: altura,
      color: Cores.suave,
      child: Icon(icone, color: Cores.borda, size: altura * 0.36),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(raio),
      child: url == null || url!.isEmpty
          ? vazia
          : Image.network(
              url!,
              width: largura,
              height: altura,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => vazia,
              loadingBuilder: (c, filho, progresso) =>
                  progresso == null ? filho : vazia,
            ),
    );
  }
}

/// O seletor de quantidade, igual em toda parte: produto, carrinho, adicional.
class Quantidade extends StatelessWidget {
  const Quantidade({
    super.key,
    required this.valor,
    required this.aoMudar,
    this.minimo = 1,
    this.maximo = 99,
    this.compacto = false,
  });

  final int valor;
  final ValueChanged<int> aoMudar;
  final int minimo;
  final int maximo;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final tamanho = compacto ? 30.0 : 38.0;

    Widget botao(IconData icone, VoidCallback? acao) => SizedBox(
          width: tamanho,
          height: tamanho,
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: acao,
            icon: Icon(icone, size: compacto ? 16 : 20),
            color: acao == null ? Cores.borda : Cores.marca,
          ),
        );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Cores.borda),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          botao(valor <= minimo ? Icons.delete_outline : Icons.remove,
              valor > minimo || minimo == 0 ? () => aoMudar(valor - 1) : null),
          SizedBox(
            width: compacto ? 22 : 28,
            child: Text('$valor',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: compacto ? 13 : 15)),
          ),
          botao(Icons.add, valor < maximo ? () => aoMudar(valor + 1) : null),
        ],
      ),
    );
  }
}

/// Uma linha de conta: rótulo à esquerda, valor à direita. Usada no resumo do
/// carrinho, no checkout e no pedido pronto — sempre com os mesmos nomes, para
/// que o cliente reconheça a mesma conta nas três telas.
class LinhaDeValor extends StatelessWidget {
  const LinhaDeValor({
    super.key,
    required this.rotulo,
    required this.centavos,
    this.forte = false,
    this.desconto = false,
    this.gratis = false,
  });

  final String rotulo;
  final int centavos;
  final bool forte;
  final bool desconto;
  final bool gratis;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontSize: forte ? 17 : 14,
      fontWeight: forte ? FontWeight.w800 : FontWeight.w500,
      color: desconto ? Cores.sucesso : Cores.texto,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rotulo,
              style: estilo.copyWith(
                  color: forte ? Cores.texto : Cores.textoSuave)),
          Text(
            gratis
                ? 'Grátis'
                : '${desconto ? '− ' : ''}${emReais(centavos)}',
            style: estilo.copyWith(color: gratis ? Cores.sucesso : estilo.color),
          ),
        ],
      ),
    );
  }
}

/// Barra fixa no rodapé com uma ação grande. É o padrão de todo aplicativo de
/// comida, e por um bom motivo: o polegar chega lá sem a mão mudar de posição.
class BarraDeAcao extends StatelessWidget {
  const BarraDeAcao({
    super.key,
    required this.filho,
    this.acima,
  });

  final Widget filho;
  final Widget? acima;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(
          color: Cores.fundo,
          border: Border(top: BorderSide(color: Cores.borda)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (acima != null) ...[acima!, const SizedBox(height: 10)],
            filho,
          ],
        ),
      );
}

/// Linha do tempo vertical do pedido — o que já aconteceu, o que falta.
class Trilha extends StatelessWidget {
  const Trilha({super.key, required this.etapas, required this.atual});

  final List<String> etapas;
  final int atual;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < etapas.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= atual ? Cores.marca : Cores.fundo,
                          border: Border.all(
                            color: i <= atual ? Cores.marca : Cores.borda,
                            width: 2,
                          ),
                        ),
                        child: i < atual
                            ? const Icon(Icons.check, size: 11, color: Colors.white)
                            : null,
                      ),
                      if (i < etapas.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: i < atual ? Cores.marca : Cores.borda,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: i < etapas.length - 1 ? 22 : 0, top: 0),
                    child: Text(
                      etapas[i],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            i == atual ? FontWeight.w800 : FontWeight.w500,
                        color: i <= atual ? Cores.texto : Cores.textoSuave,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
}
