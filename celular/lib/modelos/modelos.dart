/// Os registros do banco, do jeito que o aplicativo os usa.
///
/// Todos imutáveis e todos construídos por `deMapa`, nunca por atribuição campo
/// a campo depois. Um modelo meio preenchido é a origem clássica do "por que a
/// tela mostra R$ 0,00" — aqui, ou o registro chega inteiro, ou estoura na
/// borda, onde ainda dá para entender o que faltou.
///
/// Dinheiro é `int` de centavos em todos eles. A regra vem do schema e não se
/// negocia: nenhum `double` toca em preço neste aplicativo.
library;

import 'enums.dart';

export 'enums.dart';

int _centavos(Object? v) => v == null ? 0 : (v as num).round();
double? _decimal(Object? v) =>
    v == null ? null : double.parse(v.toString());
DateTime? _quando(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

/// Uma relação aninhada do PostgREST, normalizada.
///
/// O PostgREST devolve **objeto** quando a relação é um-para-um e **lista**
/// quando é um-para-muitos. `orders.deliveries` é um-para-um — `deliveries.order_id`
/// é único — e `orders.payments` é lista. Tratar os dois como lista quebrava na
/// primeira leitura de pedido com entrega; tratar pelo tipo, não pelo palpite,
/// é o que resolve.
Map<String, dynamic>? aninhado(Object? v) {
  if (v == null) return null;
  if (v is Map<String, dynamic>) return v;
  if (v is List) {
    return v.isEmpty ? null : (v.first as Map<String, dynamic>);
  }
  return null;
}

class Perfil {
  const Perfil({
    required this.id,
    required this.nome,
    required this.papel,
    this.email,
    this.telefone,
    this.avatarUrl,
    this.ativo = true,
  });

  final String id;
  final String nome;
  final PapelNaPlataforma papel;
  final String? email;
  final String? telefone;
  final String? avatarUrl;
  final bool ativo;

  factory Perfil.deMapa(Map<String, dynamic> m) => Perfil(
        id: m['id'] as String,
        nome: (m['full_name'] as String?) ?? '',
        papel: PapelNaPlataforma.de(m['platform_role'] as String),
        email: m['email'] as String?,
        telefone: m['phone'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        ativo: (m['is_active'] as bool?) ?? true,
      );

  /// O primeiro nome basta para cumprimentar; o nome inteiro cabe mal no topo
  /// de uma tela de celular.
  String get primeiroNome => nome.trim().split(' ').first;
}

class Restaurante {
  const Restaurante({
    required this.id,
    required this.slug,
    required this.nome,
    required this.aberto,
    required this.taxaDeEntregaCentavos,
    required this.pedidoMinimoCentavos,
    required this.minutosDePreparo,
    required this.minutosDeEntrega,
    required this.notaMedia,
    required this.quantidadeDeNotas,
    this.descricao,
    this.logoUrl,
    this.capaUrl,
    this.telefone,
    this.entregaGratisAcimaDeCentavos,
    this.bairro,
    this.cidade,
    this.raioKm = 5,
    this.aceitaAgendamento = false,
    this.aceitaEntregadorDaPlataforma = false,
  });

  final String id;
  final String slug;
  final String nome;
  /// Vende agora? É a chave da mão E o horário de funcionamento, as duas
  /// concordando — o banco calcula em `aberto_agora`, para a vitrine não ter
  /// de buscar o horário de trinta lojas e cruzar no celular.
  ///
  /// Sem a coluna calculada no `select`, cai em `is_open`: melhor errar para o
  /// lado de uma tela que ainda funciona do que quebrar.
  final bool aberto;
  final int taxaDeEntregaCentavos;
  final int pedidoMinimoCentavos;
  final int minutosDePreparo;
  final int minutosDeEntrega;
  final double notaMedia;
  final int quantidadeDeNotas;
  final String? descricao;
  final String? logoUrl;
  final String? capaUrl;
  final String? telefone;
  final int? entregaGratisAcimaDeCentavos;
  final String? bairro;
  final String? cidade;
  final double raioKm;
  final bool aceitaAgendamento;

  /// Falso por omissão: o estabelecimento entrega com gente própria. Ligar isto
  /// abre a corrida aos autônomos da plataforma.
  final bool aceitaEntregadorDaPlataforma;

  factory Restaurante.deMapa(Map<String, dynamic> m) => Restaurante(
        id: m['id'] as String,
        slug: m['slug'] as String,
        nome: m['name'] as String,
        aberto: (m['aberto_agora'] as bool?) ?? (m['is_open'] as bool?) ?? false,
        taxaDeEntregaCentavos: _centavos(m['delivery_fee_cents']),
        pedidoMinimoCentavos: _centavos(m['min_order_cents']),
        minutosDePreparo: (m['avg_prep_minutes'] as int?) ?? 30,
        minutosDeEntrega: (m['avg_delivery_minutes'] as int?) ?? 20,
        notaMedia: _decimal(m['rating_avg']) ?? 0,
        quantidadeDeNotas: (m['rating_count'] as int?) ?? 0,
        descricao: m['description'] as String?,
        logoUrl: m['logo_url'] as String?,
        capaUrl: m['cover_url'] as String?,
        telefone: m['phone'] as String?,
        entregaGratisAcimaDeCentavos: m['free_delivery_above_cents'] == null
            ? null
            : _centavos(m['free_delivery_above_cents']),
        bairro: m['district'] as String?,
        cidade: m['city'] as String?,
        raioKm: _decimal(m['delivery_radius_km']) ?? 5,
        aceitaAgendamento: (m['accepts_scheduled_orders'] as bool?) ?? false,
        aceitaEntregadorDaPlataforma:
            (m['accepts_platform_couriers'] as bool?) ?? false,
      );

  /// A taxa que vale para um carrinho deste tamanho.
  ///
  /// Serve para *mostrar* ao cliente. Quem cobra é `fechar_pedido`, no banco —
  /// se as duas contas divergirem, quem está errada é esta.
  int taxaPara(int subtotalCentavos) {
    final gratisAcima = entregaGratisAcimaDeCentavos;
    if (gratisAcima != null && subtotalCentavos >= gratisAcima) return 0;
    return taxaDeEntregaCentavos;
  }

  bool get temNota => quantidadeDeNotas > 0;
}

class Categoria {
  const Categoria({
    required this.id,
    required this.restauranteId,
    required this.nome,
    required this.posicao,
    this.descricao,
  });

  final String id;
  final String restauranteId;
  final String nome;
  final int posicao;
  final String? descricao;

  factory Categoria.deMapa(Map<String, dynamic> m) => Categoria(
        id: m['id'] as String,
        restauranteId: m['restaurant_id'] as String,
        nome: m['name'] as String,
        posicao: (m['position'] as int?) ?? 0,
        descricao: m['description'] as String?,
      );
}

class Produto {
  const Produto({
    required this.id,
    required this.restauranteId,
    required this.categoriaId,
    required this.nome,
    required this.precoCentavos,
    required this.disponivel,
    required this.destaque,
    this.descricao,
    this.imagemUrl,
    this.precoPromocionalCentavos,
    this.promocaoComecaEm,
    this.promocaoTerminaEm,
    this.serveQuantasPessoas,
    this.minutosDePreparo,
    this.controlaEstoque = false,
    this.quantidadeEmEstoque = 0,
  });

  final String id;
  final String restauranteId;
  final String categoriaId;
  final String nome;
  final int precoCentavos;
  final bool disponivel;
  final bool destaque;
  final String? descricao;
  final String? imagemUrl;
  final int? precoPromocionalCentavos;
  final DateTime? promocaoComecaEm;
  final DateTime? promocaoTerminaEm;
  final int? serveQuantasPessoas;
  final int? minutosDePreparo;
  final bool controlaEstoque;
  final int quantidadeEmEstoque;

  factory Produto.deMapa(Map<String, dynamic> m) => Produto(
        id: m['id'] as String,
        restauranteId: m['restaurant_id'] as String,
        categoriaId: m['category_id'] as String,
        nome: m['name'] as String,
        precoCentavos: _centavos(m['price_cents']),
        disponivel: (m['is_available'] as bool?) ?? true,
        destaque: (m['is_featured'] as bool?) ?? false,
        descricao: m['description'] as String?,
        imagemUrl: m['image_url'] as String?,
        precoPromocionalCentavos: m['promo_price_cents'] == null
            ? null
            : _centavos(m['promo_price_cents']),
        promocaoComecaEm: _quando(m['promo_starts_at']),
        promocaoTerminaEm: _quando(m['promo_ends_at']),
        serveQuantasPessoas: m['serves_people'] as int?,
        minutosDePreparo: m['prep_minutes'] as int?,
        controlaEstoque: (m['track_stock'] as bool?) ?? false,
        quantidadeEmEstoque: (m['stock_quantity'] as int?) ?? 0,
      );

  /// A promoção só vale dentro da janela cadastrada.
  ///
  /// A mesma conta terá de existir em `fechar_pedido`: o preço que o cliente
  /// viu e o preço que o banco cobra precisam ser o mesmo, e quem decide é a
  /// janela, não a tela.
  bool get emPromocao {
    if (precoPromocionalCentavos == null) return false;
    final agora = DateTime.now();
    final inicio = promocaoComecaEm;
    final fim = promocaoTerminaEm;
    if (inicio != null && agora.isBefore(inicio)) return false;
    if (fim != null && agora.isAfter(fim)) return false;
    return true;
  }

  int get precoQueVale =>
      emPromocao ? precoPromocionalCentavos! : precoCentavos;

  /// Esgotado é diferente de indisponível: um é do estoque, o outro é escolha
  /// do restaurante. A tela diz coisas diferentes para cada caso.
  bool get esgotado => controlaEstoque && quantidadeEmEstoque <= 0;
  bool get podeSerPedido => disponivel && !esgotado;
}

class GrupoDeAdicionais {
  const GrupoDeAdicionais({
    required this.id,
    required this.produtoId,
    required this.nome,
    required this.obrigatorio,
    required this.minimo,
    required this.maximo,
    required this.posicao,
    required this.adicionais,
    this.descricao,
  });

  final String id;
  final String produtoId;
  final String nome;
  final bool obrigatorio;
  final int minimo;
  final int maximo;
  final int posicao;
  final List<Adicional> adicionais;
  final String? descricao;

  factory GrupoDeAdicionais.deMapa(Map<String, dynamic> m) =>
      GrupoDeAdicionais(
        id: m['id'] as String,
        produtoId: m['product_id'] as String,
        nome: m['name'] as String,
        obrigatorio: (m['is_required'] as bool?) ?? false,
        minimo: (m['min_select'] as int?) ?? 0,
        maximo: (m['max_select'] as int?) ?? 1,
        posicao: (m['position'] as int?) ?? 0,
        descricao: m['description'] as String?,
        adicionais: ((m['addons'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Adicional.deMapa)
            .where((a) => a.disponivel)
            .toList()
          ..sort((a, b) => a.posicao.compareTo(b.posicao)),
      );

  /// Um grupo de escolha única vira botão de rádio; de múltipla, caixas.
  bool get escolhaUnica => maximo == 1;

  String get regra {
    if (obrigatorio && escolhaUnica) return 'Escolha 1';
    if (obrigatorio) return 'Escolha de $minimo a $maximo';
    if (escolhaUnica) return 'Opcional';
    return 'Até $maximo';
  }
}

class Adicional {
  const Adicional({
    required this.id,
    required this.grupoId,
    required this.nome,
    required this.precoCentavos,
    required this.disponivel,
    required this.posicao,
    required this.quantidadeMaxima,
    this.descricao,
  });

  final String id;
  final String grupoId;
  final String nome;
  final int precoCentavos;
  final bool disponivel;
  final int posicao;
  final int quantidadeMaxima;
  final String? descricao;

  factory Adicional.deMapa(Map<String, dynamic> m) => Adicional(
        id: m['id'] as String,
        grupoId: m['group_id'] as String,
        nome: m['name'] as String,
        precoCentavos: _centavos(m['price_cents']),
        disponivel: (m['is_available'] as bool?) ?? true,
        posicao: (m['position'] as int?) ?? 0,
        quantidadeMaxima: (m['max_quantity'] as int?) ?? 1,
        descricao: m['description'] as String?,
      );
}

class Endereco {
  const Endereco({
    required this.id,
    required this.rotulo,
    required this.rua,
    required this.numero,
    required this.bairro,
    required this.cidade,
    required this.uf,
    required this.cep,
    required this.padrao,
    this.complemento,
    this.referencia,
    this.destinatario,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String rotulo;
  final String rua;
  final String numero;
  final String bairro;
  final String cidade;
  final String uf;
  final String cep;
  final bool padrao;
  final String? complemento;
  final String? referencia;
  final String? destinatario;
  final double? latitude;
  final double? longitude;

  factory Endereco.deMapa(Map<String, dynamic> m) => Endereco(
        id: m['id'] as String,
        rotulo: (m['label'] as String?) ?? 'Casa',
        rua: m['street'] as String,
        numero: m['number'] as String,
        bairro: m['district'] as String,
        cidade: m['city'] as String,
        uf: m['state'] as String,
        cep: m['postal_code'] as String,
        padrao: (m['is_default'] as bool?) ?? false,
        complemento: m['complement'] as String?,
        referencia: m['reference_point'] as String?,
        destinatario: m['recipient'] as String?,
        latitude: _decimal(m['latitude']),
        longitude: _decimal(m['longitude']),
      );

  String get linha1 =>
      [rua, numero].join(', ') + (complemento?.isNotEmpty == true ? ' — $complemento' : '');
  String get linha2 => '$bairro, $cidade-$uf';
  String get resumo => '$linha1, $linha2';

  String get cepFormatado =>
      cep.length == 8 ? '${cep.substring(0, 5)}-${cep.substring(5)}' : cep;
}

class ItemDoPedido {
  const ItemDoPedido({
    required this.id,
    required this.nomeDoProduto,
    required this.precoUnitarioCentavos,
    required this.quantidade,
    required this.totalDosAdicionaisCentavos,
    required this.totalCentavos,
    required this.adicionais,
    this.produtoId,
    this.imagemUrl,
    this.observacao,
  });

  final String id;
  final String nomeDoProduto;
  final int precoUnitarioCentavos;
  final int quantidade;
  final int totalDosAdicionaisCentavos;
  final int totalCentavos;
  final List<AdicionalDoPedido> adicionais;
  final String? produtoId;
  final String? imagemUrl;
  final String? observacao;

  factory ItemDoPedido.deMapa(Map<String, dynamic> m) => ItemDoPedido(
        id: m['id'] as String,
        nomeDoProduto: m['product_name'] as String,
        precoUnitarioCentavos: _centavos(m['unit_price_cents']),
        quantidade: m['quantity'] as int,
        totalDosAdicionaisCentavos: _centavos(m['addons_total_cents']),
        totalCentavos: _centavos(m['total_cents']),
        produtoId: m['product_id'] as String?,
        imagemUrl: m['product_image_url'] as String?,
        observacao: m['notes'] as String?,
        adicionais: ((m['order_item_addons'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(AdicionalDoPedido.deMapa)
            .toList(),
      );
}

class AdicionalDoPedido {
  const AdicionalDoPedido({
    required this.nome,
    required this.quantidade,
    required this.totalCentavos,
    this.grupo,
  });

  final String nome;
  final int quantidade;
  final int totalCentavos;
  final String? grupo;

  factory AdicionalDoPedido.deMapa(Map<String, dynamic> m) => AdicionalDoPedido(
        nome: m['addon_name'] as String,
        quantidade: (m['quantity'] as int?) ?? 1,
        totalCentavos: _centavos(m['total_cents']),
        grupo: m['group_name'] as String?,
      );
}

class Pedido {
  const Pedido({
    required this.id,
    required this.numero,
    required this.restauranteId,
    required this.nomeDoCliente,
    required this.status,
    required this.tipo,
    required this.subtotalCentavos,
    required this.taxaDeEntregaCentavos,
    required this.descontoCentavos,
    required this.totalCentavos,
    required this.criadoEm,
    required this.itens,
    this.telefoneDoCliente,
    this.clienteId,
    this.resumoDoEndereco,
    this.bairroDoEndereco,
    this.cidadeDoEndereco,
    this.rotuloDaMesa,
    this.latitudeDoEndereco,
    this.longitudeDoEndereco,
    this.observacao,
    this.codigoDoCupom,
    this.confirmadoEm,
    this.prontoEm,
    this.entregueEm,
    this.canceladoEm,
    this.motivoDoCancelamento,
    this.nomeDoRestaurante,
    this.logoDoRestaurante,
    this.pagamento,
    this.entrega,
  });

  final String id;
  final int numero;
  final String restauranteId;
  final String nomeDoCliente;
  final StatusDoPedido status;
  final TipoDeEntrega tipo;
  final int subtotalCentavos;
  final int taxaDeEntregaCentavos;
  final int descontoCentavos;
  final int totalCentavos;
  final DateTime criadoEm;
  final List<ItemDoPedido> itens;
  final String? telefoneDoCliente;
  final String? clienteId;
  final String? resumoDoEndereco;
  final String? bairroDoEndereco;
  final String? cidadeDoEndereco;

  /// Em qual mesa servir. Cópia, não referência: a mesa pode ser renomeada ou
  /// removida amanhã, e o pedido de hoje precisa continuar dizendo onde foi
  /// servido — é o mesmo cuidado do endereço.
  final String? rotuloDaMesa;

  /// Onde o pedido vai chegar. Nulo quando o endereço foi cadastrado sem GPS —
  /// o mapa então mostra só o entregador.
  final double? latitudeDoEndereco;
  final double? longitudeDoEndereco;
  final String? observacao;
  final String? codigoDoCupom;
  final DateTime? confirmadoEm;
  final DateTime? prontoEm;
  final DateTime? entregueEm;
  final DateTime? canceladoEm;
  final String? motivoDoCancelamento;
  final String? nomeDoRestaurante;
  final String? logoDoRestaurante;
  final Pagamento? pagamento;
  final Entrega? entrega;

  factory Pedido.deMapa(Map<String, dynamic> m) {
    final restaurante = aninhado(m['restaurants']);
    final pagamento = aninhado(m['payments']);
    final entrega = aninhado(m['deliveries']);

    return Pedido(
      id: m['id'] as String,
      numero: m['number'] as int,
      restauranteId: m['restaurant_id'] as String,
      nomeDoCliente: m['customer_name'] as String,
      status: StatusDoPedido.de(m['status'] as String),
      tipo: TipoDeEntrega.de(m['fulfillment'] as String),
      subtotalCentavos: _centavos(m['subtotal_cents']),
      taxaDeEntregaCentavos: _centavos(m['delivery_fee_cents']),
      descontoCentavos: _centavos(m['discount_cents']),
      totalCentavos: _centavos(m['total_cents']),
      criadoEm: _quando(m['created_at'])!,
      telefoneDoCliente: m['customer_phone'] as String?,
      clienteId: m['customer_id'] as String?,
      resumoDoEndereco: m['address_summary'] as String?,
      bairroDoEndereco: m['address_district'] as String?,
      rotuloDaMesa: m['table_label'] as String?,
      cidadeDoEndereco: m['address_city'] as String?,
      latitudeDoEndereco: _decimal(m['address_latitude']),
      longitudeDoEndereco: _decimal(m['address_longitude']),
      observacao: m['notes'] as String?,
      codigoDoCupom: m['coupon_code'] as String?,
      confirmadoEm: _quando(m['confirmed_at']),
      prontoEm: _quando(m['ready_at']),
      entregueEm: _quando(m['delivered_at']),
      canceladoEm: _quando(m['cancelled_at']),
      motivoDoCancelamento: m['cancellation_reason'] as String?,
      nomeDoRestaurante: restaurante?['name'] as String?,
      logoDoRestaurante: restaurante?['logo_url'] as String?,
      itens: ((m['order_items'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ItemDoPedido.deMapa)
          .toList(),
      pagamento: pagamento == null ? null : Pagamento.deMapa(pagamento),
      entrega: entrega == null ? null : Entrega.deMapa(entrega),
    );
  }

  int get quantidadeDeItens =>
      itens.fold(0, (soma, i) => soma + i.quantidade);

  /// Quanto tempo o balcão deixou o pedido parado antes de aceitar. É o número
  /// que mais dói no cliente, e por isso ele aparece na fila da cozinha.
  Duration get esperando => DateTime.now().difference(criadoEm);
}

class Pagamento {
  const Pagamento({
    required this.id,
    required this.forma,
    required this.momento,
    required this.status,
    required this.valorCentavos,
    this.trocoParaCentavos,
    this.pixQrCode,
    this.pagoEm,
  });

  final String id;
  final FormaDePagamento forma;
  final MomentoDoPagamento momento;
  final StatusDoPagamento status;
  final int valorCentavos;
  final int? trocoParaCentavos;
  final String? pixQrCode;
  final DateTime? pagoEm;

  factory Pagamento.deMapa(Map<String, dynamic> m) => Pagamento(
        id: m['id'] as String,
        forma: FormaDePagamento.de(m['method'] as String),
        momento: MomentoDoPagamento.de(m['timing'] as String),
        status: StatusDoPagamento.de(m['status'] as String),
        valorCentavos: _centavos(m['amount_cents']),
        trocoParaCentavos: m['change_for_cents'] == null
            ? null
            : _centavos(m['change_for_cents']),
        pixQrCode: m['pix_qr_code'] as String?,
        pagoEm: _quando(m['paid_at']),
      );

  int get trocoCentavos =>
      trocoParaCentavos == null ? 0 : trocoParaCentavos! - valorCentavos;
}

class Entrega {
  const Entrega({
    required this.id,
    required this.pedidoId,
    required this.restauranteId,
    required this.status,
    required this.taxaDoEntregadorCentavos,
    this.entregadorId,
    this.distanciaKm,
    this.designadaEm,
    this.retiradaEm,
    this.entregueEm,
  });

  final String id;
  final String pedidoId;
  final String restauranteId;
  final StatusDaEntrega status;
  final int taxaDoEntregadorCentavos;
  final String? entregadorId;
  final double? distanciaKm;
  final DateTime? designadaEm;
  final DateTime? retiradaEm;
  final DateTime? entregueEm;

  factory Entrega.deMapa(Map<String, dynamic> m) => Entrega(
        id: m['id'] as String,
        pedidoId: m['order_id'] as String,
        restauranteId: m['restaurant_id'] as String,
        status: StatusDaEntrega.de(m['status'] as String),
        taxaDoEntregadorCentavos: _centavos(m['courier_fee_cents']),
        entregadorId: m['courier_id'] as String?,
        distanciaKm: _decimal(m['distance_km']),
        designadaEm: _quando(m['assigned_at']),
        retiradaEm: _quando(m['picked_up_at']),
        entregueEm: _quando(m['delivered_at']),
      );
}

class Entregador {
  const Entregador({
    required this.id,
    required this.usuarioId,
    required this.status,
    required this.disponibilidade,
    required this.tipoDeVeiculo,
    required this.notaMedia,
    required this.entregasFeitas,
    this.placa,
    this.restauranteId,
    this.nomeDoRestaurante,
    this.nome,
  });

  final String id;
  final String usuarioId;
  final StatusDoEntregador status;
  final DisponibilidadeDoEntregador disponibilidade;
  final String tipoDeVeiculo;
  final double notaMedia;
  final int entregasFeitas;
  final String? placa;

  /// De qual estabelecimento este entregador é. Nulo = autônomo da plataforma,
  /// que só enxerga corrida de quem aceita gente de fora.
  final String? restauranteId;
  final String? nomeDoRestaurante;

  /// Só vem preenchido na lista que o balcão enxerga.
  final String? nome;

  factory Entregador.deMapa(Map<String, dynamic> m) => Entregador(
        id: m['id'] as String,
        usuarioId: m['user_id'] as String,
        status: StatusDoEntregador.de(m['status'] as String),
        disponibilidade:
            DisponibilidadeDoEntregador.de(m['availability'] as String),
        tipoDeVeiculo: (m['vehicle_type'] as String?) ?? 'motorcycle',
        notaMedia: _decimal(m['rating_avg']) ?? 0,
        entregasFeitas: (m['deliveries_count'] as int?) ?? 0,
        placa: m['vehicle_plate'] as String?,
        restauranteId: m['restaurant_id'] as String?,
        nomeDoRestaurante:
            aninhado(m['restaurants'])?['name'] as String?,
        nome: aninhado(m['profiles'])?['full_name'] as String?,
      );

  bool get podeTrabalhar => status == StatusDoEntregador.aprovado;

  bool get autonomo => restauranteId == null;

  String get veiculo => switch (tipoDeVeiculo) {
        'bicycle' => 'Bicicleta',
        'car' => 'Carro',
        'scooter' => 'Patinete',
        'foot' => 'A pé',
        _ => 'Moto',
      };
}

/// O vínculo de uma pessoa com um estabelecimento. É por ele que o aplicativo
/// sabe se deve abrir no fluxo do restaurante.
class VinculoComRestaurante {
  const VinculoComRestaurante({
    required this.restauranteId,
    required this.papel,
    required this.nomeDoRestaurante,
  });

  final String restauranteId;
  final PapelNoRestaurante papel;
  final String nomeDoRestaurante;

  factory VinculoComRestaurante.deMapa(Map<String, dynamic> m) =>
      VinculoComRestaurante(
        restauranteId: m['restaurant_id'] as String,
        papel: PapelNoRestaurante.de(m['role'] as String),
        nomeDoRestaurante:
            (m['restaurants'] as Map<String, dynamic>?)?['name'] as String? ??
                'Meu estabelecimento',
      );
}
