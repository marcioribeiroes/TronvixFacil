/// "Você está na Mesa 3."
///
/// Existe porque a mesa vive na memória, e memória é invisível. Sem esta faixa,
/// quem escaneou e depois foi olhar outra coisa faria um pedido para o salão
/// sem perceber — e alguém levaria um prato para uma mesa vazia.
///
/// Por isso a saída fica aqui do lado, e não escondida em configurações.
library;

import 'package:flutter/material.dart';

import '../dados/mesa.dart';
import '../tema.dart';

class FaixaDaMesa extends StatelessWidget {
  const FaixaDaMesa({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: MesaAtual.instancia,
        builder: (context, _) {
          final mesa = MesaAtual.instancia.mesa;
          if (mesa == null) return const SizedBox.shrink();

          return Material(
            color: Cores.marca.withValues(alpha: 0.10),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.restaurant, size: 18, color: Cores.marcaEscura),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Você está na '),
                            TextSpan(
                              text: mesa.rotulo,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextSpan(text: ' · ${mesa.restauranteNome}'),
                          ],
                        ),
                        style: TextStyle(fontSize: 13, color: Cores.marcaEscura),
                      ),
                    ),
                    TextButton(
                      onPressed: MesaAtual.instancia.levantar,
                      style: TextButton.styleFrom(
                        foregroundColor: Cores.marcaEscura,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Sair', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
