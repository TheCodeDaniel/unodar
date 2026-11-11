import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../api/api_resolution.dart';
import '../ir/ir.dart';

/// Maps Dart static types to IR types (docs/SUBSET.md "Types"). Shared by the validator (E009) and lowering, so
/// that "which types are supported" is defined exactly once.
///
/// Returns null for every unsupported type, including nullable ones; see [isNullable].
IrType? irTypeOf(DartType? type) {
  if (type == null) return null;
  if (type is VoidType) return IrType.void_;
  if (isNullable(type)) return null;
  if (type.isDartCoreInt) return IrType.int32;
  if (type.isDartCoreDouble) return IrType.float32;
  if (type.isDartCoreBool) return IrType.bool_;
  return sizedTypeOf(type);
}

/// `Uint8`/`Uint16`/`Int16` from `package:unodar`, matched by declaring element, never by spelling.
IrType? sizedTypeOf(DartType type) {
  if (type is! InterfaceType || isNullable(type)) return null;
  final element = type.element;
  if (element is! ExtensionTypeElement || !isUnodarElement(element)) return null;
  return switch (element.name) {
    'Uint8' => IrType.uint8,
    'Uint16' => IrType.uint16,
    'Int16' => IrType.int16,
    _ => null,
  };
}

bool isNullable(DartType type) => type.nullabilitySuffix == NullabilitySuffix.question;

/// The Dart spelling of [type] for messages, e.g. `int?`, `num`.
String displayType(DartType type) => type.getDisplayString();
