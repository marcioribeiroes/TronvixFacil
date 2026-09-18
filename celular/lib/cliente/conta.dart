/// A conta: quem eu sou, meus endereços, e — quando for o caso — a troca de
/// fluxo.
///
/// A troca de fluxo só aparece para quem tem mais de um papel. Um cliente
/// comum nunca vê a palavra "restaurante" aqui; um dono que também pede comida
/// vê, porque para ele os dois aplicativos são o mesmo aparelho.
library;

import 'package:flutter/material.dart';

import '../ambiente.dart';
import '../dados/supabase.dart';
import '../comum/widgets.dart';
import '../main.dart';
import '../sessao.dart';
import '../tema.dart';
import 'enderecos.dart';

class TelaConta extends StatelessWidget {
  const TelaConta({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Sessao.instancia,
        builder: (context, _) {
          final sessao = Sessao.instancia;
          final perfil = sessao.perfil;

          return Scaffold(
            appBar: AppBar(title: const Text('Sua conta')),
            body: perfil == null
                ? Vazio(
                    icone: Icons.person_outline,
                    titulo: 'Você não está conectado',
                    detalhe:
                        'Entre para salvar endereços, acompanhar pedidos e pedir mais rápido da próxima vez.',
                    acao: FilledButton(
                      onPressed: () => exigirConta(context),
                      child: const Text('Entrar ou criar conta'),
                    ),
                  )
                : ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: Cores.realce,
                              child: Text(
                                perfil.primeiroNome.isEmpty
                                    ? '?'
                                    : perfil.primeiroNome[0].toUpperCase(),
                                style: const TextStyle(
                                    color: Cores.marca,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(perfil.nome,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800)),
                                  if (perfil.email != null)
                                    Text(perfil.email!,
                                        style: const TextStyle(
                                            color: Cores.textoSuave,
                                            fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: const Text('Meus endereços'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const TelaEnderecos()),
                        ),
                      ),
                      if (sessao.fluxosDisponiveis.length > 1) ...[
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                          child: Text('Você também usa',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: Cores.textoSuave)),
                        ),
                        for (final f in sessao.fluxosDisponiveis)
                          if (f != Fluxo.cliente)
                            ListTile(
                              leading: Icon(f == Fluxo.restaurante
                                  ? Icons.storefront
                                  : Icons.two_wheeler),
                              title: Text(f == Fluxo.restaurante
                                  ? (sessao.vinculo?.nomeDoRestaurante ??
                                      'Meu estabelecimento')
                                  : 'Sou entregador'),
                              subtitle: Text(f == Fluxo.restaurante
                                  ? 'Abrir o balcão'
                                  : 'Abrir as corridas'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => sessao.trocarDeFluxo(f),
                            ),
                      ],
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.logout, color: Cores.perigo),
                        title: const Text('Sair',
                            style: TextStyle(color: Cores.perigo)),
                        onTap: () => sessao.sair(),
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_forever_outlined,
                            color: Cores.textoSuave),
                        title: const Text('Apagar minha conta',
                            style: TextStyle(color: Cores.textoSuave)),
                        subtitle: const Text('Isso não tem volta',
                            style: TextStyle(fontSize: 12)),
                        onTap: () => _apagarConta(context, sessao),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Text(Ambiente.nomeDaMarca,
                            style: const TextStyle(
                                color: Cores.borda,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
          );
        },
      );
}

/// Pergunta, e só então apaga.
///
/// Duas frases antes do botão vermelho: o que sai e o que fica. A segunda é a
/// que evita a pergunta seguinte — "e o pedido que eu já paguei?". O pedido
/// fica, sem apontar para ninguém: ele é a venda de um restaurante, que tem
/// obrigação fiscal sobre ela.
Future<void> _apagarConta(BuildContext context, Sessao sessao) async {
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: const Text('Apagar sua conta?'),
      content: const Text(
        'Somem o seu acesso, o seu cadastro e os seus endereços. Não dá para '
        'desfazer.\n\n'
        'Os pedidos que você já fez continuam no registro de vendas dos '
        'restaurantes, sem o seu nome e sem o seu contato.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogo).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogo).pop(true),
          style: TextButton.styleFrom(foregroundColor: Cores.perigo),
          child: const Text('Apagar'),
        ),
      ],
    ),
  );

  if (confirmou != true || !context.mounted) return;

  try {
    await sessao.apagarConta();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conta apagada.')),
    );
  } on ErroDeDados catch (e) {
    // O banco recusa por motivo que a pessoa resolve: pedido em andamento,
    // conta de loja, conta de entregador. A mensagem dele já explica o quê.
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.mensagem)),
    );
  }
}
