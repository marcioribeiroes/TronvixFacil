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

/// Densidades do Android.
const _android = <String, int>{
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

void main() {
  test('gera os ícones', () async {
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

    // O de 1024 é o que vai para a App Store e o que se olha para conferir.
    expect(File('ios/Runner/Assets.xcassets/AppIcon.appiconset/'
            'Icon-App-1024x1024@1x.png')
        .existsSync(), isTrue);
  });
}

Future<void> _escrever(String caminho, int lado) async {
  final gravador = ui.PictureRecorder();
  final canvas = Canvas(gravador);
  _desenhar(canvas, lado.toDouble());

  final imagem = await gravador.endRecording().toImage(lado, lado);
  final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);

  final arquivo = File(caminho);
  arquivo.parent.createSync(recursive: true);
  arquivo.writeAsBytesSync(bytes!.buffer.asUint8List());
}

void _desenhar(Canvas canvas, double lado) {
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
