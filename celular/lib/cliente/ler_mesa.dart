/// Ler o QR da mesa.
///
/// A câmera é o caminho previsto, mas não é o único que funciona: luz baixa,
/// etiqueta riscada e celular velho existem. Por isso a mesma tela aceita o
/// código digitado — é o que está impresso embaixo do QR, e foi escolhido sem
/// i, l, o, 0 e 1 justamente para ser ditado por telefone sem confusão.
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../dados/mesa.dart';

class LerMesa extends StatefulWidget {
  const LerMesa({super.key});

  @override
  State<LerMesa> createState() => _LerMesaState();
}

class _LerMesaState extends State<LerMesa> {
  final _controle = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  final _digitado = TextEditingController();

  bool _ocupado = false;
  String? _erro;

  @override
  void dispose() {
    _controle.dispose();
    _digitado.dispose();
    super.dispose();
  }

  /// Resolve o código e devolve a mesa a quem abriu esta tela.
  ///
  /// O `_ocupado` não é só para o botão: a câmera dispara a leitura várias
  /// vezes por segundo, e sem ele a mesma mesa seria buscada dez vezes antes da
  /// primeira resposta voltar.
  Future<void> _resolver(String leitura) async {
    if (_ocupado) return;

    final codigo = Mesas.codigoDe(leitura);
    if (codigo == null) {
      setState(() => _erro = 'Esse QR Code não é de uma mesa.');
      return;
    }

    setState(() {
      _ocupado = true;
      _erro = null;
    });

    try {
      final mesa = await Mesas.porCodigo(codigo);
      if (!mounted) return;

      if (mesa == null) {
        setState(() {
          _ocupado = false;
          _erro = 'Não achei essa mesa. Chame alguém do salão.';
        });
        return;
      }

      Navigator.of(context).pop(mesa);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _erro = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ler o QR da mesa')),
      // Rolagem: com o teclado aberto para digitar o código, uma coluna de
      // altura fixa estoura e o campo some atrás do teclado.
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            // A câmera numa caixa de tamanho conhecido, e não ocupando o que
            // sobrar: assim o que vem depois — o código digitado, que é a saída
            // quando a câmera falha — existe de qualquer jeito.
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 320,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.black),
                    MobileScanner(
                      controller: _controle,
                      fit: BoxFit.cover,
                      onDetect: (captura) {
                        final valor = captura.barcodes.firstOrNull?.rawValue;
                        if (valor != null) _resolver(valor);
                      },
                      errorBuilder: (context, erro) => _SemCamera(erro: erro),
                    ),

                    // A mira. Não recorta nada — o leitor enxerga o quadro
                    // inteiro —, mas diz onde pôr o celular.
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white70, width: 3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),

                    if (_ocupado)
                      const ColoredBox(
                        color: Colors.black54,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              // Sem crossAxisAlignment.stretch: dentro de uma rolagem, uma
              // coluna esticada com uma Row dentro fazia a tela inteira parar
              // de pintar no Android — sem exceção, sem aviso, só branco.
              // Descoberto por bissecção: cada peça sozinha funcionava.
              child: Column(
                children: [
                  const Text(
                    'Aponte para o QR Code colado na mesa.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Ou digite o código impresso embaixo do QR',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('codigo-da-mesa'),
                    controller: _digitado,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      hintText: 'ex.: 6cxb9enb',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: _resolver,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _ocupado ? null : () => _resolver(_digitado.text),
                      child: const Text('Entrar na mesa'),
                    ),
                  ),
                  if (_erro != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _erro!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sem câmera não é o fim: o código digitado continua ali embaixo.
class _SemCamera extends StatelessWidget {
  const _SemCamera({required this.erro});

  final MobileScannerException erro;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.no_photography_outlined,
                    color: Colors.white54, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Não consegui usar a câmera.',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Digite o código impresso embaixo do QR Code.',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
}
