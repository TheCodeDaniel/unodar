# Runtime headers

Hand-written C++ that generated sketches include. The compiler never generates this code; it copies it.

- `unodar_widgets.h` (Phase 4): `unodar::Led`, `unodar::Button` (pull-up, 50 ms debounce, press edge) and
  `unodar::Every` (drift-free, wrap-safe, one tick per call), each with a `constexpr` constructor. `unodar build`
  writes a copy next to every widget program. The compiler embeds the text: after editing the header, run
  `tool/embed_runtime.sh` (`test/unit/runtime_header_test.dart` fails until you do). The logic is tested on its own
  in avr8js by `runtime_fidelity_test.dart` (`test/runtime/widgets/widgets.ino`), with negative controls.
