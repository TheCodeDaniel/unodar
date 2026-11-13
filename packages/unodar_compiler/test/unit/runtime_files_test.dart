import 'package:test/test.dart';
import 'package:unodar_compiler/src/ir/ir.dart';
import 'package:unodar_compiler/src/runtime/runtime_files.dart';
import 'package:unodar_compiler/src/runtime/unodar_widgets_header.dart';

/// A program's sketch-local includes decide which runtime files `unodar build` writes next to the `.ino`.
void main() {
  IrProgram program(List<String> localIncludes) =>
      IrProgram(sourceName: 'main.dart', localIncludes: localIncludes, functions: const []);

  test('a program without local includes needs no files', () {
    expect(runtimeFilesFor(program(const [])), isEmpty);
  });

  test('unodar_widgets.h is the embedded runtime header', () {
    expect(runtimeFilesFor(program(const ['unodar_widgets.h'])), {'unodar_widgets.h': unodarWidgetsHeader});
  });

  test('an include with no runtime file is a compiler bug, not a missing file at build time', () {
    expect(() => runtimeFilesFor(program(const ['nope.h'])), throwsStateError);
  });
}
