/// O fundo escuro da marca — o mesmo tratamento do login do TronvixERP e da
/// tela de entrar da web: gradiente em camadas, malha de pontos e dois riscos
/// diagonais.
///
/// Tudo derivado de [Cores.marca], que vem da configuração. O aplicativo de um
/// cliente cuja marca é azul ganha o mesmo gesto em azul — copiar o vermelho do
/// ERP aqui desfaria a configuração de marca inteira.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tema.dart';

class FundoDaMarca extends StatelessWidget {
  const FundoDaMarca({super.key, required this.filho, this.altura});

  final Widget filho;
  final double? altura;

  @override
  Widget build(BuildContext context) => Container(
        height: altura,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            // 158° no CSS da web; aqui a diagonal equivalente.
            colors: [Color(0xFF1D1D21), Color(0xFF121214), Color(0xFF0B0B0D)],
            stops: [0, 0.52, 1],
          ),
        ),
        // Recorta: o risco diagonal e a malha são desenhados de propósito para
        // fora dos limites — é o que dá o corte na borda. Sem o recorte eles
        // vazam para o formulário branco embaixo.
        child: ClipRect(
          child: CustomPaint(
            painter: _Gestos(),
            child: filho,
          ),
        ),
      );
}

class _Gestos extends CustomPainter {
  /// Os dois riscos, inclinados como no original, e a malha de pontos.
  ///
  /// Desenhados, não montados com widgets: são decoração pura, não devem
  /// aparecer para leitor de tela nem participar do layout.
  @override
  void paint(Canvas canvas, Size size) {
    final marca = Cores.marca;

    // Brilho atrás do texto.
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.5),
      size.width * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [marca.withValues(alpha: 0.26), Colors.transparent],
        ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.2, size.height * 0.5),
          radius: size.width * 0.55,
        )),
    );

    // Facetas claras, que dão o volume de vidro do original.
    final faceta = Paint()..color = Colors.white.withValues(alpha: 0.035);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.52, 0)
        ..lineTo(size.width * 0.78, 0)
        ..lineTo(size.width * 0.34, size.height)
        ..lineTo(size.width * 0.12, size.height)
        ..close(),
      faceta,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.86, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height * 0.5)
        ..close(),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );

    // Embaixo e à direita, longe do texto: na referência os gestos emolduram
    // a chamada, não passam por cima dela.
    _malhaDePontos(canvas, size, marca);
    _risco(canvas, size, 0.92, 2.2, marca, 0.85);
    _risco(canvas, size, 1.01, 1.1, marca, 0.3);
  }

  void _malhaDePontos(Canvas canvas, Size size, Color marca) {
    const passo = 20.0;
    final esquerda = size.width * 0.72;
    final topo = size.height * 0.46;
    final largura = size.width * 0.22;
    final alturaDaMalha = size.height * 0.3;

    final vermelho = Paint()..color = marca.withValues(alpha: 0.32);
    final branco = Paint()..color = Colors.white.withValues(alpha: 0.09);

    for (var x = 0.0; x < largura; x += passo) {
      for (var y = 0.0; y < alturaDaMalha; y += passo) {
        canvas.drawCircle(Offset(esquerda + x, topo + y), 1.4, vermelho);
        canvas.drawCircle(
            Offset(esquerda + x + 10, topo + y + 10), 1.4, branco);
      }
    }
  }

  void _risco(
    Canvas canvas,
    Size size,
    double alturaRelativa,
    double espessura,
    Color marca,
    double forca,
  ) {
    // Gira pelo CENTRO, não pela borda: girando a partir de x = 0, a ponta
    // direita sobe width·sen(17°) — mais de cem pixels numa faixa de celular —
    // e o risco acaba atravessando a chamada. Pelo centro, a subida de um lado
    // é a descida do outro e a altura pedida é respeitada.
    canvas.save();
    canvas.translate(size.width / 2, size.height * alturaRelativa);
    canvas.rotate(-17 * math.pi / 180);

    final faixa = Rect.fromLTWH(
      -size.width * 0.75,
      -espessura / 2,
      size.width * 1.5,
      espessura,
    );

    canvas.drawRect(
      faixa,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            marca.withValues(alpha: forca),
            Colors.transparent,
          ],
        ).createShader(faixa)
        ..maskFilter = MaskFilter.blur(BlurStyle.solid, espessura * 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Gestos oldDelegate) => false;
}

/// A assinatura: nome em caixa alta, subtítulo espaçado e o risco curto.
///
/// É o bloco `TRONVIX / ERP` da referência, com o nome que vier da
/// configuração.
class AssinaturaDaMarca extends StatelessWidget {
  const AssinaturaDaMarca({super.key, required this.nome, this.legenda});

  final String nome;
  final String? legenda;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nome.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
              height: 1,
              shadows: [
                Shadow(color: Color(0x59000000), blurRadius: 12, offset: Offset(0, 2)),
              ],
            ),
          ),
          if (legenda != null) ...[
            const SizedBox(height: 8),
            Text(
              legenda!.toUpperCase(),
              style: TextStyle(
                color: Cores.marca,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 5,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            height: 3,
            width: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Cores.marca, Cores.marca.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
      );
}
