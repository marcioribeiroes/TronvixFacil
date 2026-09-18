/// O que a busca de CEP tem de acertar sem depender de rede.
///
/// A chamada HTTP em si não é testada aqui de propósito: testar que o ViaCEP
/// responde é testar o ViaCEP. O que este arquivo cobre é a leitura da
/// resposta e a formatação — que é onde os erros ficam escondidos.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tronvix_facil/dados/cep.dart';

void main() {
  group('formatação', () {
    test('põe o hífen depois do quinto dígito', () {
      expect(cepFormatado('74210'), '74210');
      expect(cepFormatado('742100'), '74210-0');
      expect(cepFormatado('74210000'), '74210-000');
    });

    test('ignora o que não é dígito e não passa de oito', () {
      expect(cepFormatado('74.210-000'), '74210-000');
      expect(cepFormatado('742100001234'), '74210-000');
      expect(cepFormatado('abc'), '');
    });

    test('só está completo com oito dígitos', () {
      expect(cepCompleto('74210-000'), isTrue);
      expect(cepCompleto('7421000'), isFalse);
      expect(cepCompleto(''), isFalse);
    });
  });

  group('ViaCEP', () {
    test('lê o endereço', () {
      final e = EnderecoDoCep.deViaCep({
        'cep': '74210-000',
        'logradouro': 'Rua das Palmeiras',
        'bairro': 'Setor Bueno',
        'localidade': 'Goiânia',
        'uf': 'GO',
      });
      expect(e, isNotNull);
      expect(e!.cep, '74210000');
      expect(e.rua, 'Rua das Palmeiras');
      expect(e.cidade, 'Goiânia');
      expect(e.uf, 'GO');
      expect(e.temRua, isTrue);
    });

    test('CEP inexistente devolve nulo', () {
      expect(EnderecoDoCep.deViaCep({'erro': true}), isNull);
      // O ViaCEP já respondeu com a string "true" nesse campo.
      expect(EnderecoDoCep.deViaCep({'erro': 'true'}), isNull);
    });

    test('resposta sem UF é resposta imprestável', () {
      expect(EnderecoDoCep.deViaCep({'localidade': 'Goiânia'}), isNull);
    });

    test('CEP de cidade inteira chega sem rua, e isso não é erro', () {
      final e = EnderecoDoCep.deViaCep({
        'cep': '74000-000',
        'logradouro': '',
        'bairro': '',
        'localidade': 'Goiânia',
        'uf': 'GO',
      });
      expect(e, isNotNull);
      expect(e!.temRua, isFalse);
      expect(e.cidade, 'Goiânia');
    });
  });

  group('BrasilAPI', () {
    test('lê o endereço no formato dela', () {
      final e = EnderecoDoCep.deBrasilApi({
        'cep': '74210000',
        'street': 'Rua das Palmeiras',
        'neighborhood': 'Setor Bueno',
        'city': 'Goiânia',
        'state': 'GO',
      });
      expect(e, isNotNull);
      expect(e!.rua, 'Rua das Palmeiras');
      expect(e.bairro, 'Setor Bueno');
      expect(e.uf, 'GO');
    });

    test('resposta de erro devolve nulo', () {
      expect(EnderecoDoCep.deBrasilApi({'message': 'Todos os serviços de CEP retornaram erro.'}),
          isNull);
    });
  });
}
