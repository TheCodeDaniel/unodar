# Decisions log

Choices made where the PRD was silent or ambiguous. Format: date — decision — reason.
Open decisions from PRD §13 are **not** decided here; they are asked of the maintainer.

| Date | Decision | Reason |
|---|---|---|
| 2026-11-10 | API functions are declared `external`; constants are plain `const int` with Arduino.h values. | `external` gives analyzable signatures with no fake bodies to maintain. Plain `int` (vs. distinct extension types per kind) is the simpler option and matches Arduino's own typing; stricter typing can come later without breaking user code. |
| 2026-11-10 | Arduino spelling is kept (`INPUT_PULLUP`, `digitalWrite`); `constant_identifier_names` is ignored in `arduino_core.dart` only. | Code reads the same in Dart, tutorials, and generated C++. Scoping the ignore to one file keeps the lint active everywhere else. |
