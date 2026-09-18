/// Gera o ícone do aplicativo, para iOS e Android.
///
/// Roda como teste porque é o jeito de ter um `Canvas` de verdade sem
/// dependência nova: `flutter test tool/gerar_icones.dart`. O mesmo comando
/// com outras cores gera o ícone de outra marca — é o que sustenta a promessa
/// de "coloque sua marca":
///
/// ```sh
/// flutter test tool/gerar_icones.dart \
///   --dart-define=COR_DA_MARCA=0xFF1D4ED8
/// ```
///
/// **Por que não copiar o painel da marca aqui.** O painel é largo: marca
/// escrita por extenso, riscos de um pixel, malha de pontos. Num ícone de 60pt
/// a palavra vira borrão, o risco some e a malha vira ruído. O que sobrevive
/// nesse tamanho é figura, fundo e um gesto — e é isso que este arquivo
/// desenha: o carvão em gradiente, um risco vermelho e o símbolo do produto.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tronvix_facil/tema.dart';

/// Os tamanhos que o Xcode espera, com o nome de cada arquivo.
const _ios = <String, int>{
  'Icon-App-20x20@1x': 20,
  'Icon-App-20x20@2x': 40,
  'Icon-App-20x20@3x': 60,
  'Icon-App-29x29@1x': 29,
  'Icon-App-29x29@2x': 58,
  'Icon-App-29x29@3x': 87,
  'Icon-App-40x40@1x': 40,
  'Icon-App-40x40@2x': 80,
  'Icon-App-40x40@3x': 120,
  'Icon-App-60x60@2x': 120,
  'Icon-App-60x60@3x': 180,
  'Icon-App-76x76@1x': 76,
  'Icon-App-76x76@2x': 152,
  'Icon-App-83.5x83.5@2x': 167,
  'Icon-App-1024x1024@1x': 1024,
};

/// Densidades do Android, para o ícone antigo (quadrado inteiro).
const _android = <String, int>{
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

/// Densidades do ícone ADAPTATIVO, que é o que o Android 8+ usa de verdade.
///
/// A tela é de 108dp e o launcher recorta a forma que quiser — círculo,
/// quadrado arredondado, gota. Só os 72dp centrais são garantidos; o resto
/// existe para o recorte e para a animação de parallax.
///
/// Sem estas camadas, o Android pega o ícone antigo, encolhe e põe dentro de
/// um círculo branco. Foi o que aconteceu aqui: o alfinete aparecia pequeno,
/// boiando num disco branco, sem nada a ver com o do iPhone.
const _adaptativo = <String, int>{
  'mipmap-mdpi': 108,
  'mipmap-hdpi': 162,
  'mipmap-xhdpi': 216,
  'mipmap-xxhdpi': 324,
  'mipmap-xxxhdpi': 432,
};

/// A fração da tela de 108dp que é seguramente visível: 72/108.
const _zonaSegura = 72 / 108;

/// Carrega a Roboto de verdade para desenhar o nome na faixa da loja.
///
/// Sem isto o `flutter test` desenha texto com a fonte de teste, que é feita
/// de retângulos: a faixa saiu uma vez com o nome em tijolinhos brancos. A
/// fonte vem do próprio cache do Flutter (Roboto, Apache 2.0) — a mesma que o
/// aplicativo usa no Android, então a faixa fica com a letra do produto.
Future<void> _carregarAFonte() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // .../flutter/bin/cache/dart-sdk/bin/dart -> .../flutter/bin/cache
  var pasta = Directory(Platform.resolvedExecutable).parent;
  while (pasta.path != pasta.parent.path) {
    final fontes = Directory('${pasta.path}/artifacts/material_fonts');
    if (fontes.existsSync()) {
      for (final peso in const ['Black', 'Medium']) {
        final arquivo = File('${fontes.path}/Roboto-$peso.ttf');
        await (FontLoader('Roboto $peso')
              ..addFont(Future.value(
                  arquivo.readAsBytesSync().buffer.asByteData())))
            .load();
      }
      return;
    }
    pasta = pasta.parent;
  }
  fail('não achei as fontes do Flutter a partir de '
      '${Platform.resolvedExecutable}');
}

void main() {
  test('gera os ícones', () async {
    await _carregarAFonte();

    for (final e in _ios.entries) {
      await _escrever(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/${e.key}.png',
        e.value,
      );
    }
    for (final e in _android.entries) {
      await _escrever(
        'android/app/src/main/res/${e.key}/ic_launcher.png',
        e.value,
      );
    }

    // As duas camadas do adaptativo, e o XML que as costura.
    for (final e in _adaptativo.entries) {
      await _escrever(
        'android/app/src/main/res/${e.key}/ic_launcher_background.png',
        e.value,
        desenhar: _desenharFundo,
      );
      await _escrever(
        'android/app/src/main/res/${e.key}/ic_launcher_foreground.png',
        e.value,
        desenhar: _desenharFiguraAdaptativa,
      );
    }
    _escreverXmlDoAdaptativo();

    // A Play Store pede o ícone em 512 e uma faixa de 1024x500. As duas saem
    // do mesmo desenho: manter uma arte separada para a loja é garantir que um
    // dia ela fique diferente do aplicativo instalado.
    await _escrever('loja/play-icone-512.png', 512);
    await _escreverRetangulo('loja/play-faixa-1024x500.png', 1024, 500);

    // O de 1024 é o que vai para a App Store e o que se olha para conferir.
    expect(File('ios/Runner/Assets.xcassets/AppIcon.appiconset/'
            'Icon-App-1024x1024@1x.png')
        .existsSync(), isTrue);
  });
}

Future<void> _escrever(
  String caminho,
  int lado, {
  void Function(Canvas, double) desenhar = _desenhar,
}) async {
  final gravador = ui.PictureRecorder();
  final canvas = Canvas(gravador);
  desenhar(canvas, lado.toDouble());

  final imagem = await gravador.endRecording().toImage(lado, lado);
  final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);

  final arquivo = File(caminho);
  arquivo.parent.createSync(recursive: true);
  arquivo.writeAsBytesSync(bytes!.buffer.asUint8List());
}

void _desenhar(Canvas canvas, double lado) {
  _desenharFundo(canvas, lado);
  _desenharFigura(canvas, lado);
}

/// A camada de baixo do adaptativo: só o fundo, sem figura.
///
/// Sangra até a borda de propósito. É ela que o launcher recorta, e um fundo
/// que parasse antes deixaria um anel transparente na forma escolhida.
void _desenharFundo(Canvas canvas, double lado) {
  final quadro = Rect.fromLTWH(0, 0, lado, lado);
  final marca = Cores.marca;

  // --- fundo: o carvão em gradiente, como na faixa da tela de entrar --------
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

  // Brilho da marca, atrás do símbolo.
  canvas.drawCircle(
    Offset(lado * 0.34, lado * 0.42),
    lado * 0.5,
    Paint()
      ..shader = RadialGradient(
        colors: [marca.withValues(alpha: 0.32), Colors.transparent],
      ).createShader(Rect.fromCircle(
        center: Offset(lado * 0.34, lado * 0.42),
        radius: lado * 0.5,
      )),
  );

  // --- o gesto: um risco só, grosso o bastante para existir a 40px ---------
  canvas.save();
  canvas.clipRect(quadro);
  // Logo abaixo da ponta do alfinete: a figura fica APOIADA na linha, em vez
  // de cortada por ela. Cortada, parecia colisão; apoiada, vira chão.
  canvas.translate(lado / 2, lado * 0.905);
  canvas.rotate(-17 * math.pi / 180);
  final faixa = Rect.fromLTWH(-lado * 0.75, -lado * 0.022, lado * 1.5, lado * 0.044);
  canvas.drawRect(
    faixa,
    Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, marca, marca.withValues(alpha: 0.1)],
      ).createShader(faixa),
  );
  canvas.restore();
}

/// A camada de cima do adaptativo: a figura, encolhida para a zona segura.
///
/// Os 72dp do meio são o que todo launcher mostra. Desenhar do tamanho cheio
/// faria a ponta do alfinete ser cortada num aparelho de ícone redondo — e
/// cortada num, inteira noutro, é pior do que menor em todos.
void _desenharFiguraAdaptativa(Canvas canvas, double lado) {
  final sobra = lado * (1 - _zonaSegura) / 2;
  canvas.translate(sobra, sobra);
  _desenharFigura(canvas, lado * _zonaSegura);
}

void _desenharFigura(Canvas canvas, double lado) {
  final marca = Cores.marca;

  // --- a figura: alfinete de mapa com a cúpula do prato --------------------
  // Mesma construção do símbolo da web: a entrega (alfinete) carregando a
  // comida (cúpula). Aqui redesenhado em primitivas, não em caminho de SVG —
  // num ícone o que importa é a silhueta, e ela precisa aguentar 20 pixels.
  // Grande de propósito. Na tela inicial o ladrilho tem ~60pt: figura tímida
  // vira mancha escura no meio de ícones cheios. Confirmado olhando o
  // simulador — a primeira versão, menor, sumia ao lado dos vizinhos.
  final centro = Offset(lado * 0.5, lado * 0.40);
  final raio = lado * 0.285;
  final pontaY = lado * 0.855;

  final cabeca = Path()..addOval(Rect.fromCircle(center: centro, radius: raio));
  final rabo = Path()
    ..moveTo(centro.dx - raio * 0.84, centro.dy + raio * 0.54)
    ..lineTo(centro.dx, pontaY)
    ..lineTo(centro.dx + raio * 0.84, centro.dy + raio * 0.54)
    ..close();
  final alfinete = Path.combine(PathOperation.union, cabeca, rabo);

  // Sombra: separa a figura do fundo escuro sem precisar de contorno.
  canvas.drawPath(
    alfinete.shift(Offset(0, lado * 0.012)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, lado * 0.02),
  );
  canvas.drawPath(alfinete, Paint()..color = marca);

  // A cúpula, vazada em branco.
  final branco = Paint()..color = Colors.white;
  final larguraDaCupula = raio * 1.2;
  final baseDaCupula = centro.dy + raio * 0.18;

  canvas.drawPath(
    Path()
      ..moveTo(centro.dx - larguraDaCupula / 2, baseDaCupula)
      ..arcToPoint(
        Offset(centro.dx + larguraDaCupula / 2, baseDaCupula),
        radius: Radius.circular(larguraDaCupula * 0.62),
      )
      ..close(),
    branco,
  );

  // A bandeja.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centro.dx, baseDaCupula + raio * 0.2),
        width: larguraDaCupula * 1.24,
        height: raio * 0.26,
      ),
      Radius.circular(raio * 0.11),
    ),
    branco,
  );

  // O pegador.
  canvas.drawCircle(
    Offset(centro.dx, baseDaCupula - larguraDaCupula * 0.52),
    raio * 0.115,
    branco,
  );
}

/// O XML que diz ao Android quais são as duas camadas.
///
/// `mipmap-anydpi-v26` só é lido no Android 8 e acima; abaixo disso o sistema
/// continua pegando o `ic_launcher.png` de sempre. Por isso os dois convivem.
///
/// O `monochrome` é o ícone temático do Android 13: quando a pessoa liga
/// "ícones temáticos", o sistema pinta a silhueta com a cor do papel de parede.
/// Sem ele, o Tronvix seria o único colorido no meio de uma tela inteira
/// tingida — e pareceria defeito, não destaque.
void _escreverXmlDoAdaptativo() {
  final xml = [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">',
    '    <background android:drawable="@mipmap/ic_launcher_background" />',
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />',
    '    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />',
    '</adaptive-icon>',
    '',
  ].join('\n');

  for (final nome in ['ic_launcher.xml', 'ic_launcher_round.xml']) {
    final arquivo = File('android/app/src/main/res/mipmap-anydpi-v26/$nome');
    arquivo.parent.createSync(recursive: true);
    arquivo.writeAsStringSync(xml);
  }
}

/// A faixa da loja: larga, com o símbolo à esquerda e o nome ao lado.
///
/// O ícone quadrado esticado para 1024x500 ficaria com a figura minúscula no
/// meio de um deserto. Aqui o mesmo fundo e o mesmo alfinete, recompostos para
/// a proporção que a loja pede.
Future<void> _escreverRetangulo(String caminho, int largura, int altura) async {
  final gravador = ui.PictureRecorder();
  final canvas = Canvas(gravador);
  final quadro = Rect.fromLTWH(0, 0, largura.toDouble(), altura.toDouble());
  final marca = Cores.marca;

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

  // O brilho da marca atrás do símbolo, como no ícone.
  canvas.drawCircle(
    Offset(altura * 0.62, altura * 0.5),
    altura * 0.75,
    Paint()
      ..shader = RadialGradient(
        colors: [marca.withValues(alpha: 0.30), Colors.transparent],
      ).createShader(Rect.fromCircle(
        center: Offset(altura * 0.62, altura * 0.5),
        radius: altura * 0.75,
      )),
  );

  // O risco da marca, atravessando a faixa.
  canvas.save();
  canvas.clipRect(quadro);
  canvas.translate(largura / 2, altura * 0.93);
  canvas.rotate(-9 * math.pi / 180);
  final faixa = Rect.fromLTWH(-largura.toDouble(), -altura * 0.015, largura * 2, altura * 0.03);
  canvas.drawRect(
    faixa,
    Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, marca, marca.withValues(alpha: 0.1)],
      ).createShader(faixa),
  );
  canvas.restore();

  // O alfinete, à esquerda, no tamanho da faixa.
  canvas.save();
  final lado = altura * 0.66;
  canvas.translate(altura * 0.30, (altura - lado) / 2);
  _desenharFigura(canvas, lado);
  canvas.restore();

  // O nome, ao lado. Duas linhas: "Tronvix" em branco e "Fácil" na cor da
  // marca — o mesmo tratamento do logotipo da web.
  void escrever(String texto, double tamanho, Color cor, double y) {
    final pintor = TextPainter(
      text: TextSpan(
        text: texto,
        style: TextStyle(
          color: cor,
          fontSize: tamanho,
          fontFamily: 'Roboto Black',
          letterSpacing: -tamanho * 0.02,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    pintor.paint(canvas, Offset(altura * 1.05, y));
  }

  escrever('Tronvix', altura * 0.20, Colors.white, altura * 0.26);
  escrever('Fácil', altura * 0.20, marca, altura * 0.48);

  final pintor = TextPainter(
    text: TextSpan(
      text: 'Delivery e pedido na mesa',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.62),
        fontSize: altura * 0.068,
        fontFamily: 'Roboto Medium',
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  pintor.paint(canvas, Offset(altura * 1.06, altura * 0.72));

  final imagem = await gravador.endRecording().toImage(largura, altura);
  final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);

  final arquivo = File(caminho);
  arquivo.parent.createSync(recursive: true);
  arquivo.writeAsBytesSync(bytes!.buffer.asUint8List());
}
