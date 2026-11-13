import 'package:unodar/unodar.dart';

// Parameters make main() unsupported even when its body is a valid runDevice call.
void main(List<String> arguments) {
  runDevice(Device(board: Uno(), children: []));
}
