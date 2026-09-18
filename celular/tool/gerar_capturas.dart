/// Monta as capturas de tela que vao para a Play Store.
///
/// A loja aceita a foto crua da tela, e quase ninguem usa: o que aparece na
/// listagem e uma composicao — fundo da marca, uma frase dizendo o que aquela
/// tela resolve, e o aparelho no meio. Quem rola a lista de aplicativos le a
/// frase, nao a tela.
///
/// A materia-prima sao PNGs em `loja/telas/`, capturados do aparelho de
/// verdade:
///
/// ```sh
/// adb -s emulator-5554 exec-out screencap -p > celular/loja/telas/1-inicio.png
/// flutter test tool/gerar_capturas.dart
/// ```
///
/// Roda como teste pelo mesmo motivo de `gerar_icones.dart`: e o jeito de ter
/// um `Canvas` de verdade sem dependencia nova.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tronvix_facil/tema.dart';

/// A tela de cada captura, e a frase que a acompanha.
///
/// A frase e um beneficio, nao o nome do menu: "Peça da mesa pelo seu celular"
/// diz o que muda para quem le; "Tela de leitura de QR" nao diz nada.
const _capturas = <(String, String, String)>[
  ('1-inicio', 'Delivery e mesa', 'O restaurante perto de você, ou o QR da mesa onde você já está'),
  ('2-mesa', 'Peça da mesa', 'Leia o QR, monte o pedido e ele cai direto na cozinha'),
  ('3-cardapio', 'Cardápio de verdade', 'Preço, descrição e promoção, como a loja cadastrou hoje'),
  ('4-pagamento', 'Pague como quiser', 'Pix na hora, cartão ou dinheiro na entrega'),
  ('5-carrinho', 'Sem surpresa no total', 'Entrega e desconto na conta antes de você confirmar'),
];

/// Os tamanhos que cada loja quer.
///
/// A Play aceita de 16:9 a 9:16 e nao exige medida exata. A Apple exige: a
/// ficha de hoje pede a tela de 6,9 polegadas, que e 1320x2868 — o pixel certo
/// ou o envio e recusado.
/// `(nome, largura, altura, pasta do fastlane)`. A captura e escrita duas
/// vezes: em `loja/`, para olhar, e direto onde o `fastlane` vai busca-la — se
/// fossem lugares diferentes, um dia a loja subiria a captura do mes passado.
const _formatos = <(String, int, int, String)>[
  ('play', 1080, 1920,
      'android/fastlane/metadata/android/pt-BR/images/phoneScreenshots'),
  ('apple', 1320, 2868, 'ios/fastlane/screenshots/pt-BR'),
];

/// Quanto cortar do topo da captura crua.
///
/// A barra de status do aparelho — relogio, sinal, bateria — nao e o
/// aplicativo, e entrega de qual aparelho saiu a foto. Na captura de 1080x2400
/// que o `screencap` produz, ela ocupa estes 90 pixels.
const _barraDeStatus = 90.0;

void main() {
  test('gera as capturas da loja', () async {
    await _carregarAFonte();

    for (final (arquivo, titulo, frase) in _capturas) {
      final origem = File('loja/telas/$arquivo.png');
      expect(origem.existsSync(), isTrue,
          reason: 'falta a captura crua ${origem.path}');

      for (final (loja, largura, altura, pasta) in _formatos) {
        final png = await _compor(origem, titulo, frase, largura, altura);

        File('loja/$loja-captura-$arquivo.png').writeAsBytesSync(png);

        final destino = Directory(pasta)..createSync(recursive: true);
        File('${destino.path}/$arquivo.png').writeAsBytesSync(png);
      }
    }
  });
}

Future<Uint8List> _compor(
  File origem,
  String titulo,
  String frase,
  int largura,
  int altura,
) async {
  final tela = await _abrir(origem);

  // A tela sem a barra de status do aparelho.
  final recorte = Rect.fromLTWH(0, _barraDeStatus, tela.width.toDouble(),
      tela.height - _barraDeStatus);

  final gravador = ui.PictureRecorder();
  final canvas = Canvas(gravador);
  final quadro = Rect.fromLTWH(0, 0, largura.toDouble(), altura.toDouble());
  final marca = Cores.marca;

  // O fundo: o mesmo carvao do icone e do painel de login.
  canvas.drawRect(
    quadro,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF26262C), Color(0xFF121214), Color(0xFF09090B)],
        stops: [0, 0.55, 1],
      ).createShader(quadro),
  );

  final brilho = Offset(largura * 0.5, altura * 0.22);
  canvas.drawCircle(
    brilho,
    largura * 0.8,
    Paint()
      ..shader = RadialGradient(
        colors: [marca.withValues(alpha: 0.22), Colors.transparent],
      ).createShader(Rect.fromCircle(center: brilho, radius: largura * 0.8)),
  );

  // O risco da marca, atras do aparelho.
  canvas.save();
  canvas.clipRect(quadro);
  canvas.translate(largura / 2, altura * 0.33);
  canvas.rotate(-9 * math.pi / 180);
  final faixa =
      Rect.fromLTWH(-largura.toDouble(), -5, largura * 2.0, 10);
  canvas.drawRect(
    faixa,
    Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, marca, marca.withValues(alpha: 0.1)],
      ).createShader(faixa),
  );
  canvas.restore();

  // Tudo escala com a largura: o mesmo desenho, no tamanho de cada loja.
  final k = largura / 1080;

  _escrever(canvas, titulo,
      tamanho: 72 * k,
      fonte: 'Roboto Black',
      cor: Colors.white,
      topo: 96 * k,
      largura: largura - 120 * k,
      quadroDaLargura: largura);

  _escrever(canvas, frase,
      tamanho: 38 * k,
      fonte: 'Roboto Medium',
      cor: Colors.white.withValues(alpha: 0.66),
      topo: 190 * k,
      largura: largura - 160 * k,
      quadroDaLargura: largura);

  // O aparelho. A tela crua entra inteira, com canto arredondado e sombra —
  // recortar pedaco da tela para "caber melhor" e mostrar um aplicativo que
  // nao existe.
  // Cabe pela largura OU pela altura, o que for mais apertado. Escalar so
  // pela largura cortava o rodape do aplicativo — e a barra de baixo, com o
  // preco e o botao, e justamente o que prova que da para concluir o pedido.
  final margem = 96.0 * k;
  final topo = 360.0 * k;
  final rodape = 72.0 * k;
  final escala = math.min(
    (largura - margem * 2) / recorte.width,
    (altura - topo - rodape) / recorte.height,
  );
  final larguraDaTela = recorte.width * escala;
  final alturaDaTela = recorte.height * escala;
  final alvo = Rect.fromLTWH(
      (largura - larguraDaTela) / 2, topo, larguraDaTela, alturaDaTela);
  final cantos = RRect.fromRectAndRadius(alvo, Radius.circular(36 * k));

  canvas.drawRRect(
    cantos.shift(Offset(0, 18 * k)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 36 * k),
  );

  canvas.save();
  canvas.clipRRect(cantos);
  canvas.drawImageRect(
    tela,
    recorte,
    alvo,
    Paint()..filterQuality = FilterQuality.high,
  );
  canvas.restore();

  canvas.drawRRect(
    cantos,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * k
      ..color = Colors.white.withValues(alpha: 0.12),
  );

  final imagem = await gravador.endRecording().toImage(largura, altura);
  final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

void _escrever(
  Canvas canvas,
  String texto, {
  required double tamanho,
  required String fonte,
  required Color cor,
  required double topo,
  required double largura,
  required int quadroDaLargura,
}) {
  final pintor = TextPainter(
    text: TextSpan(
      text: texto,
      style: TextStyle(
        color: cor,
        fontSize: tamanho,
        fontFamily: fonte,
        height: 1.22,
        letterSpacing: -tamanho * 0.015,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: largura);

  pintor.paint(canvas, Offset((quadroDaLargura - pintor.width) / 2, topo));
}

Future<ui.Image> _abrir(File arquivo) async {
  final codec = await ui.instantiateImageCodec(arquivo.readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

/// A mesma Roboto que a faixa da loja usa. Sem isto o `flutter test` desenha
/// texto com a fonte de teste, que e feita de retangulos.
Future<void> _carregarAFonte() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  var pasta = Directory(Platform.resolvedExecutable).parent;
  while (pasta.path != pasta.parent.path) {
    final fontes = Directory('${pasta.path}/artifacts/material_fonts');
    if (fontes.existsSync()) {
      for (final peso in const ['Black', 'Medium']) {
        final arquivo = File('${fontes.path}/Roboto-$peso.ttf');
        await (FontLoader('Roboto $peso')
              ..addFont(
                  Future.value(arquivo.readAsBytesSync().buffer.asByteData())))
            .load();
      }
      return;
    }
    pasta = pasta.parent;
  }
  fail('nao achei as fontes do Flutter a partir de '
      '${Platform.resolvedExecutable}');
}
