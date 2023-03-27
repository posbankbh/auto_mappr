import 'package:analyzer/dart/element/type.dart';
import 'package:auto_mappr/extensions/expression_extension.dart';
import 'package:auto_mappr/models/auto_mappr_config.dart';
import 'package:auto_mappr/models/type_mapping.dart';
import 'package:code_builder/code_builder.dart';

/// Builds main `convert` method
class ConvertMethodBuilder {
  static const sourceKey = 'SOURCE';
  static const sourceTypeReference = Reference(sourceKey);
  static const nullableSourceTypeReference = Reference('$sourceKey?');
  static const targetKey = 'TARGET';
  static const targetTypeReference = Reference(targetKey);

  final Set<TypeMapping> _nullableMappings;

  ConvertMethodBuilder() : _nullableMappings = {};

  static String concreteConvertMethodName(DartType source, DartType target) =>
      '_map${source.getDisplayString(withNullability: false)}To${target.getDisplayString(withNullability: false)}';

  static String concreteNullableConvertMethodName(DartType source, DartType target) =>
      '${concreteConvertMethodName(source, target)}__Nullable';

  bool shouldGenerateNullableMappingMethod(TypeMapping mapping) {
    return _nullableMappings.contains(mapping);
  }

  void usedNullableMappingMethod(TypeMapping? mapping) {
    if (mapping == null) return;

    final _ = _nullableMappings.add(mapping);
  }

  Method buildCanConvert(AutoMapprConfig config) {
    return Method(
      (b) => b
        ..name = 'canConvert'
        ..types.addAll([sourceTypeReference, targetTypeReference])
        ..returns = refer('bool')
        ..body = _buildCanConvertBody(config.mappers),
    );
  }

  Method buildConvertMethod() {
    return Method(
      (b) => b
        ..name = 'convert'
        ..types.addAll([sourceTypeReference, targetTypeReference])
        ..requiredParameters.add(
          Parameter(
            (p) => p
              ..name = 'model'
              ..type = nullableSourceTypeReference,
          ),
        )
        ..returns = targetTypeReference
        ..lambda = false
        ..body = refer('_convert(model)').returned.statement,
    );
  }

  Method buildInternalConvertMethod(AutoMapprConfig config) {
    return Method(
      (b) => b
        ..name = '_convert'
        ..types.addAll([sourceTypeReference, targetTypeReference])
        ..requiredParameters.add(
          Parameter(
            (p) => p
              ..name = 'model'
              ..type = nullableSourceTypeReference,
          ),
        )
        ..returns = targetTypeReference
        ..body = _buildConvertMethodBody(config.mappers),
    );
  }

  Method buildTypeOfHelperMethod() {
    return Method(
      (b) => b
        ..name = '_typeOf'
        ..types.add(refer('T'))
        ..returns = refer('Type')
        ..lambda = true
        ..body = const Code('T'),
    );
  }

  Code? _buildConvertMethodBody(List<TypeMapping> mappings) {
    final block = BlockBuilder();

    for (final mapping in mappings) {
      final sourceName = mapping.source.getDisplayString(withNullability: false);
      final targetName = mapping.target.getDisplayString(withNullability: false);

      final modelIsTypeExpression = refer('_typeOf<$sourceKey>()')
          .equalTo(refer('_typeOf<$sourceName>()'))
          .or(refer('_typeOf<$sourceKey>()').equalTo(refer('_typeOf<$sourceName?>()')));

      final outputExpression = refer('_typeOf<$targetKey>()')
          .equalTo(refer('_typeOf<$targetName>()'))
          .or(refer('_typeOf<$targetKey>()').equalTo(refer('_typeOf<$targetName?>()')));

      final ifConditionExpression = modelIsTypeExpression.bracketed().and(outputExpression.bracketed());

      final inIfExpression = refer(mapping.mappingMethodName)
          .call(
            [
              refer('model').asA(refer('${mapping.source.getDisplayString(withNullability: false)}?')),
            ],
          )
          .asA(targetTypeReference)
          .returned
          .statement;

      final ifStatementExpression = ifConditionExpression.ifStatement(ifBody: inIfExpression);

      // Generates code like:
      //
      // if ((_typeOf<SOURCE>() == _typeOf<UserDto>() ||
      //     _typeOf<SOURCE>() == _typeOf<UserDto?>()) &&
      //     (_typeOf<TARGET>() == _typeOf<User>() ||
      //         _typeOf<TARGET>() == _typeOf<User?>())) {
      //   return _mapUserDtoToUser(model as UserDto?);
      // }
      block.statements.add(ifStatementExpression.code);
    }

    block.addExpression(
      refer('Exception')
          .newInstance([refer("'No mapping from \${model.runtimeType} -> \${_typeOf<$targetKey>()}'")]).thrown,
    );

    return block.build();
  }

  Code? _buildCanConvertBody(List<TypeMapping> mappings) {
    final block = BlockBuilder();

    for (final mapping in mappings) {
      final outputExpression =
          refer('_typeOf<$targetKey>()').equalTo(refer(mapping.target.getDisplayString(withNullability: false)));

      final ifConditionExpression = refer('_typeOf<$sourceKey>()')
          .equalTo(refer(mapping.source.getDisplayString(withNullability: false)))
          .and(outputExpression);

      final ifStatement = ifConditionExpression.ifStatement(ifBody: literalTrue.returned.statement);

      block.statements.add(ifStatement.code);
    }

    block.statements.add(literalFalse.returned.statement);

    return block.build();
  }
}
