/// Cadastro de entregador, em dois caminhos.
///
/// Para um estabelecimento: a pessoa escolhe para qual quer levar comida, e o
/// cadastro nasce pendente. Quem aprova é o estabelecimento — está no banco, em
/// `app.guard_courier_platform_fields`, e a razão é simples: é ele quem conhece
/// a pessoa e é o dinheiro dele que vai na mochila.
///
/// Autônomo: entrega para vários estabelecimentos, manda documentos, e quem
/// aprova é a plataforma (cadastro_autonomo.dart).
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/corridas.dart';
import '../modelos/modelos.dart';
import '../sessao.dart';
import '../tema.dart';
import 'cadastro_autonomo.dart';

const _veiculos = {
  'motorcycle': 'Moto',
  'bicycle': 'Bicicleta',
  'car': 'Carro',
  'foot': 'A pé',
};

/// Depois de enviar: volta para a primeira tela e abre o fluxo do entregador,
/// que mostra o "em análise". Vale para os dois caminhos.
void cadastroEnviado(BuildContext context) {
  avisar(context, 'Cadastro enviado. Aguarde a aprovação.');
  Navigator.of(context).popUntil((rota) => rota.isFirst);
  Sessao.instancia.trocarDeFluxo(Fluxo.entregador);
}

/// A escolha do caminho.
class TelaCadastroDeEntregador extends StatelessWidget {
  const TelaCadastroDeEntregador({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Entregar pelo Tronvix Fácil')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Como você quer trabalhar?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            _Caminho(
              icone: Icons.storefront,
              titulo: 'Para um estabelecimento',
              detalhe: 'Você entrega para um restaurante específico. Ele '
                  'aprova seu cadastro.',
              aoTocar: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const TelaCadastroParaEstabelecimento())),
            ),
            const SizedBox(height: 12),
            _Caminho(
              icone: Icons.two_wheeler,
              titulo: 'Autônomo',
              detalhe: 'Entrega para vários estabelecimentos da sua cidade. '
                  'Pede CNH, documento do veículo e selfie; a plataforma '
                  'aprova.',
              aoTocar: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const TelaCadastroAutonomo())),
            ),
          ],
        ),
      );
}

class _Caminho extends StatelessWidget {
  const _Caminho({
    required this.icone,
    required this.titulo,
    required this.detalhe,
    required this.aoTocar,
  });

  final IconData icone;
  final String titulo;
  final String detalhe;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          leading: Icon(icone, size: 32, color: Cores.marca),
          title: Text(titulo,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(detalhe, style: const TextStyle(height: 1.4)),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: aoTocar,
        ),
      );
}

class TelaCadastroParaEstabelecimento extends StatefulWidget {
  const TelaCadastroParaEstabelecimento({super.key});

  @override
  State<TelaCadastroParaEstabelecimento> createState() =>
      _TelaCadastroParaEstabelecimentoState();
}

class _TelaCadastroParaEstabelecimentoState
    extends State<TelaCadastroParaEstabelecimento> {
  final _placa = TextEditingController();

  List<Restaurante> _estabelecimentos = const [];
  String? _escolhido;
  String _veiculo = 'motorcycle';
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
    _placa.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final lista = await Corridas.estabelecimentosParaCadastro();
      if (!mounted) return;
      setState(() {
        _estabelecimentos = lista;
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

  Future<void> _enviar() async {
    if (_escolhido == null) {
      avisar(context, 'Escolha para onde você quer entregar.', erro: true);
      return;
    }

    setState(() => _enviando = true);
    try {
      await Corridas.cadastrar(
        restauranteId: _escolhido!,
        tipoDeVeiculo: _veiculo,
        placa: _placa.text,
      );
      await Sessao.instancia.carregar();
      if (mounted) cadastroEnviado(context);
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Scaffold(body: Carregando());
    if (_erro != null) {
      return Scaffold(body: Falhou(erro: _erro!, aoTentarDeNovo: _carregar));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Entregar pelo Tronvix Fácil')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Você entrega para um estabelecimento. É ele que aprova seu '
              'cadastro e é dele que vêm as corridas.',
              style: TextStyle(color: Cores.textoSuave, height: 1.45),
            ),
          ),
          _titulo('Para onde você quer entregar'),
          if (_estabelecimentos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhum estabelecimento aprovado ainda.',
                  style: TextStyle(color: Cores.textoSuave)),
            )
          else
            RadioGroup<String>(
              groupValue: _escolhido,
              onChanged: (v) => setState(() => _escolhido = v),
              child: Column(
                children: [
                  for (final r in _estabelecimentos)
                    RadioListTile<String>(
                      value: r.id,
                      title: Text(r.nome,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        [r.bairro, r.cidade].whereType<String>().join(', '),
                        style: const TextStyle(fontSize: 13),
                      ),
                      secondary: Foto(
                          url: r.logoUrl,
                          largura: 40,
                          altura: 40,
                          icone: Icons.storefront),
                    ),
                ],
              ),
            ),
          _titulo('Como você entrega'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final v in _veiculos.entries)
                  ChoiceChip(
                    label: Text(v.value),
                    selected: _veiculo == v.key,
                    onSelected: (_) => setState(() => _veiculo = v.key),
                  ),
              ],
            ),
          ),
          if (_veiculo == 'motorcycle' || _veiculo == 'car')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _placa,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Placa', hintText: 'ABC1D23'),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BarraDeAcao(
        filho: FilledButton(
          onPressed: _enviando ? null : _enviar,
          child: Text(_enviando ? 'Enviando…' : 'Enviar cadastro'),
        ),
      ),
    );
  }

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(texto,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );
}
