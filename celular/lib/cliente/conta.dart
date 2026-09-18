/// A conta: quem eu sou, meus endereços, e — quando for o caso — a troca de
/// fluxo.
///
/// A troca de fluxo só aparece para quem tem mais de um papel. Um cliente
/// comum nunca vê a palavra "restaurante" aqui; um dono que também pede comida
/// vê, porque para ele os dois aplicativos são o mesmo aparelho.
library;

import 'package:flutter/material.dart';

import '../ambiente.dart';
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
