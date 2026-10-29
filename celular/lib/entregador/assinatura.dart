/// A assinatura do autônomo: se está em dia, até quando, e o Pix para pagar.
///
/// Espelho de src/components/entregador/assinatura-do-entregador.tsx. O
/// copia-e-cola vem pronto do banco (`minha_assinatura`), o mesmo que o site
/// mostra. Quem confirma o pagamento é a plataforma, ao ver o Pix cair — a tela
/// diz isso, para o motoboy não achar que pagou e nada aconteceu.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../comum/widgets.dart';
import '../dados/corridas.dart';
import '../formato.dart';
import '../tema.dart';

class TelaAssinatura extends StatefulWidget {
  const TelaAssinatura({super.key});

  @override
  State<TelaAssinatura> createState() => _TelaAssinaturaState();
}

class _TelaAssinaturaState extends State<TelaAssinatura> {
  Map<String, dynamic>? _a;
  bool _carregando = true;
  bool _gerando = false;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final a = await Corridas.minhaAssinatura();
      if (!mounted) return;
      setState(() {
        _a = a;
        _carregando = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e;
        _carregando = false;
      });
    }
  }

  Future<void> _gerar() async {
    setState(() => _gerando = true);
    try {
      await Corridas.gerarPagamentoDaAssinatura();
      await _carregar();
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  /// "2026-11-28" para "28/11/2026", sem passar pelo fuso.
  String _dia(Object? iso) {
    final p = iso.toString().split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : '—';
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Scaffold(body: Carregando());
    if (_erro != null) {
      return Scaffold(body: Falhou(erro: _erro!, aoTentarDeNovo: _carregar));
    }

    final a = _a!;
    final cobrando = a['cobrando'] == true;
    final emDia = a['em_dia'] == true;
    final preco = (a['preco_centavos'] as num?)?.toInt() ?? 0;
    final pendente = a['pendente'] as Map<String, dynamic>?;

    final situacao = !cobrando
        ? (a['inicio'] != null
            ? 'Grátis até ${_dia(a['inicio'])}. Depois, ${emReais(preco)} por mês.'
            : 'Grátis no lançamento. Avisaremos antes de começar a cobrar.')
        : emDia
            ? 'Em dia até ${_dia(a['vence'])}.'
            : 'Vencida desde ${_dia(a['vence'])}. Pague para voltar a receber corridas.';

    return Scaffold(
      appBar: AppBar(title: const Text('Assinatura')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(situacao,
              style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: cobrando && !emDia ? Cores.perigo : Cores.texto)),
          const SizedBox(height: 20),
          if (cobrando && pendente != null) ...[
            Text(
              'Pague ${emReais((pendente['valor_centavos'] as num).toInt())} com '
              'o Pix copia e cola. A confirmação é feita pela equipe quando o '
              'dinheiro cair — pode levar algumas horas.',
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Cores.suave, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(pendente['copia_e_cola'] as String,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: pendente['copia_e_cola'] as String));
                if (context.mounted) avisar(context, 'Código Pix copiado.');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copiar código Pix'),
            ),
            const SizedBox(height: 8),
            Text('Referência: ${pendente['referencia']}',
                style: const TextStyle(color: Cores.textoSuave, fontSize: 12)),
          ] else if (cobrando)
            FilledButton(
              onPressed: _gerando ? null : _gerar,
              child: Text(emDia
                  ? 'Pagar o próximo mês'
                  : 'Pagar ${emReais(preco)} por Pix'),
            ),
        ],
      ),
    );
  }
}
