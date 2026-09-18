/// Gera os sons do aplicativo.
///
/// Sintetizados aqui, e não baixados: efeito sonoro publicado na internet tem
/// dono, e embutir um num produto que se vende é problema de licença que
/// aparece tarde. Um sino de recepção é um fenômeno físico — metal batido —, e
/// reproduzir a física dele não copia o arquivo de ninguém.
///
/// Rodar:  flutter test tool/gerar_sons.dart
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

const _taxa = 44100;

/// O timbre do sino, em números.
///
/// Sino é paramétrico: mudar a fundamental muda o tamanho aparente do sino, e
/// mudar as batidas muda o gesto. Guardar isto como dado — e não espalhado
/// pelo código — é o que permite provar variações sem reescrever nada.
class Timbre {
  const Timbre({
    required this.nome,
    required this.fundamental,
    required this.duracao,
    this.batidas = 1,
    this.intervaloEntreBatidas = 0.0,
  });

  final String nome;

  /// Quanto mais alta, menor o sino parece.
  final double fundamental;
  final double duracao;

  /// Quantas vezes o martelo bate.
  final int batidas;
  final double intervaloEntreBatidas;
}

/// As variações, para escolher de ouvido.
const timbres = <Timbre>[
  // O de agora: sino pequeno de balcão, um toque.
  Timbre(nome: 'claro', fundamental: 1760, duracao: 1.9),
  // Sino maior: mais grave, soa mais "caro" e menos estridente no celular.
  Timbre(nome: 'grave', fundamental: 1174, duracao: 2.2),
  // Dois toques, como quem bate duas vezes no balcão.
  Timbre(nome: 'duplo', fundamental: 1760, duracao: 2.0, batidas: 2, intervaloEntreBatidas: 0.22),
  // Curto e seco: chama atenção sem ocupar a sala.
  Timbre(nome: 'seco', fundamental: 2093, duracao: 0.9),
];

void main() {
  test('gera os sons', () {
    final escolhido = timbres.firstWhere(
      (t) => t.nome == (Platform.environment['TIMBRE'] ?? 'claro'),
      orElse: () => timbres.first,
    );

    _escrever('assets/sons/sino.wav', _sino(escolhido, forca: 1));
    // O mesmo sino, mais curto e mais discreto: toca a cada passo do pedido, e
    // um toque longo repetido cinco vezes cansa antes de a comida chegar.
    _escrever(
      'assets/sons/sino-curto.wav',
      _sino(
        Timbre(
          nome: escolhido.nome,
          fundamental: escolhido.fundamental,
          duracao: escolhido.duracao * 0.58,
          batidas: escolhido.batidas,
          intervaloEntreBatidas: escolhido.intervaloEntreBatidas,
        ),
        forca: 0.72,
      ),
    );

    // Uma amostra de cada variação, para ouvir lado a lado sem mexer no
    // aplicativo. Lido do ambiente, e não por --dart-define: dart-define é
    // constante de COMPILAÇÃO, e um caminho decidido na hora de rodar não
    // chega lá.
    final pasta = Platform.environment['AMOSTRAS'] ?? '';
    if (pasta.isNotEmpty) {
      for (final t in timbres) {
        _escrever('$pasta/sino-${t.nome}.wav', _sino(t, forca: 1));
      }
    }

    expect(File('assets/sons/sino.wav').lengthSync(), greaterThan(1000));
  });
}

/// Um sino de recepção.
///
/// Sino não é harmônico: as parciais dele não são múltiplos inteiros da
/// fundamental — é isso que separa o som de um sino do som de uma flauta. As
/// razões abaixo (2,76 · 5,40 · 8,93) são as clássicas de um corpo metálico
/// circular, e cada parcial decai mais rápido que a anterior, que é por que o
/// sino "escurece" enquanto some.
Uint8List _sino(Timbre timbre, {required double forca}) {
  final fundamental = timbre.fundamental;

  const parciais = <(double, double, double)>[
    // (razão, amplitude, tempo de decaimento em segundos)
    (1.00, 1.00, 1.70),
    (2.76, 0.62, 1.10),
    (5.40, 0.38, 0.65),
    (8.93, 0.22, 0.38),
  ];

  final amostras = (timbre.duracao * _taxa).round();
  final onda = Float64List(amostras);

  // Cada batida é o mesmo sino começando de novo, somado ao que ainda está
  // soando — é o que acontece de verdade quando alguém bate duas vezes: a
  // segunda pancada encontra o metal ainda vibrando.
  for (var batida = 0; batida < timbre.batidas; batida++) {
    final comeco = (batida * timbre.intervaloEntreBatidas * _taxa).round();
    // A segunda pancada é sempre mais fraca que a primeira.
    final peso = math.pow(0.78, batida).toDouble();

    for (var i = comeco; i < amostras; i++) {
      final t = (i - comeco) / _taxa;
      var valor = 0.0;

      for (final (razao, amplitude, decaimento) in parciais) {
        // Duas parciais quase iguais batendo entre si: é o leve tremor que
        // todo sino de verdade tem, e cuja falta faz um sino sintetizado soar
        // morto.
        final f = fundamental * razao;
        valor += amplitude *
            math.exp(-t / decaimento) *
            (math.sin(2 * math.pi * f * t) +
                0.35 * math.sin(2 * math.pi * (f * 1.003) * t));
      }

      // A batida do martelo: um estalo curtíssimo antes do sino falar. Sem ele
      // o som "aparece" em vez de ser golpeado.
      if (t < 0.006) {
        final estalo = math.exp(-t / 0.0015);
        valor += 0.9 * estalo * (math.Random(i).nextDouble() * 2 - 1);
      }

      // Ataque de 1,5 ms: instantâneo para o ouvido, mas evita o clique que um
      // início abrupto de onda produz no alto-falante.
      final ataque = t < 0.0015 ? t / 0.0015 : 1.0;

      onda[i] += valor * ataque * forca * peso;
    }
  }

  return _paraWav(onda);
}

/// Normaliza e embala em WAV de 16 bits, mono.
Uint8List _paraWav(Float64List onda) {
  var pico = 0.0;
  for (final v in onda) {
    if (v.abs() > pico) pico = v.abs();
  }
  // Deixa uma folga: som normalizado até o talo distorce no alto-falante
  // pequeno de celular, que é onde este som vai tocar.
  final ganho = pico == 0 ? 0.0 : 0.82 / pico;

  final dados = ByteData(onda.length * 2);
  for (var i = 0; i < onda.length; i++) {
    final v = (onda[i] * ganho * 32767).clamp(-32768, 32767).round();
    dados.setInt16(i * 2, v, Endian.little);
  }

  final corpo = dados.buffer.asUint8List();
  final cabecalho = ByteData(44);

  void texto(int posicao, String s) {
    for (var i = 0; i < s.length; i++) {
      cabecalho.setUint8(posicao + i, s.codeUnitAt(i));
    }
  }

  texto(0, 'RIFF');
  cabecalho.setUint32(4, 36 + corpo.length, Endian.little);
  texto(8, 'WAVE');
  texto(12, 'fmt ');
  cabecalho.setUint32(16, 16, Endian.little); // tamanho do bloco fmt
  cabecalho.setUint16(20, 1, Endian.little); // PCM
  cabecalho.setUint16(22, 1, Endian.little); // mono
  cabecalho.setUint32(24, _taxa, Endian.little);
  cabecalho.setUint32(28, _taxa * 2, Endian.little); // bytes por segundo
  cabecalho.setUint16(32, 2, Endian.little); // alinhamento do bloco
  cabecalho.setUint16(34, 16, Endian.little); // bits por amostra
  texto(36, 'data');
  cabecalho.setUint32(40, corpo.length, Endian.little);

  return Uint8List.fromList([...cabecalho.buffer.asUint8List(), ...corpo]);
}

void _escrever(String caminho, Uint8List bytes) {
  final arquivo = File(caminho);
  arquivo.parent.createSync(recursive: true);
  arquivo.writeAsBytesSync(bytes);
}
