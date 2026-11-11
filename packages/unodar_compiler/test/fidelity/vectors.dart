/// Source-level fidelity vectors. Every top-level `const` below goes through the whole compiler; its value according
/// to Dart (the analyzer's constant evaluator) is then checked against avr-gcc with `static_assert`
/// (test/fidelity_test.dart). Add a vector here for every operator or conversion whose C++ meaning could drift.
library;

// Literal conditions such as `true ? 60 : 30` are deliberate vectors.
// ignore_for_file: dead_code

import 'package:unodar/unodar.dart';

// Operands of each type.
const int seven = 7;
const int minusTwo = -2;
const int intMin = -2147483647 - 1;
const Uint8 small = Uint8(200);
const Uint16 u16Max = Uint16(65535);
const Uint16 u16One = Uint16(1);
const Int16 i16Min = Int16(-32768);
const double half = 0.5;

// `%`: Dart's result is never negative.
const int modNegPos = -7 % 2;
const int modPosNeg = 7 % -2;
const int modNegNeg = -7 % -2;
const int modVariables = -seven % 3;
const int modByMin = -5 % intMin;
const int modMinByMax = intMin % 2147483647;

// `~/` truncates toward zero; `/` is always a double.
const int divNegPos = -7 ~/ 2;
const int divPosNeg = seven ~/ minusTwo;
const int divNegNeg = -7 ~/ -2;
const double slashInts = seven / 2;
const double slashNegative = -seven / 4;
const double slashMixed = half / 4;

// Precedence and associativity.
const int precSubRight = 10 - (4 - 3);
const int precSubLeft = 10 - 4 - 3;
const int precProduct = (2 + 3) * 4;
const int precSum = 2 + 3 * 4;
const int precNegSum = -(2 + 3);
const int precNegNeg = -(-seven);
const int precMinusNeg = 1 - -seven;
const int precDivRight = 100 ~/ (20 ~/ 3);
const int precModProduct = seven % 4 * 3;
const int precTernaryElse = seven > 5
    ? 1
    : seven > 2
        ? 2
        : 3;
const int precTernarySum = (seven > 5 ? 1 : 2) + 10;
const bool logicNotAnd = !(true && false);
const bool logicOrAnd = false || true && false;
const bool logicAndOr = (false || true) && false;
const bool compareChain = (seven < 2) == false;
const bool compareMixed = half < seven;

// 32-bit arithmetic on the 16-bit-int Uno.
const int wideLiterals = 60 * 1000;
const int wideChain = 60 * 60 * 1000;
const int wideEdge = 32767 + 1;
const int wideTernaries = (true ? 60 : 30) * (false ? 2000 : 1000);
const int wideMacro = HIGH + 32767;
const int wideU16Sum = u16Max + u16One;
const int wideU8Product = small * small;
const int wideNegI16 = -i16Min;
const int wideNegU16 = -u16One;
const bool wideU16LessThanNeg = u16One < -1;
const Uint8 convU8Sum = Uint8(small + small);

// Sized conversions wrap like package:unodar defines them.
const int convU8 = Uint8(300);
const Int16 convI16 = Int16(40000);
const Uint16 convU16 = Uint16(-1);

// Doubles.
const double doubleContext = 1;
const double floatMath = half * 3 + 0.25;

void setup() {}

void loop() {}
