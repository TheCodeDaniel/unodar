import '../ir/ir.dart';
import 'unodar_spi_header.dart';
import 'unodar_widgets_header.dart';

/// The fixed runtime files the compiler can put next to a sketch, by file name (docs/DECISIONS.md, PRD §13.2): the
/// widget runtime, and the shim headers of library wrappers (docs/SUBSET.md "First-party libraries"). A binding whose
/// `@CppHeader` names one of them gets it written next to the `.ino` and included as `#include "…"`.
const runtimeFiles = {'unodar_widgets.h': unodarWidgetsHeader, 'unodar_spi.h': unodarSpiHeader};

/// The files [program]'s sketch-local includes need. A local include without a runtime file is a compiler bug:
/// lowering only adds includes it knows, so this throws instead of producing a sketch that cannot build.
Map<String, String> runtimeFilesFor(IrProgram program) => {
      for (final header in program.localIncludes)
        header: runtimeFiles[header] ?? (throw StateError('no runtime file for local include "$header"')),
    };
