import 'dart:async';

Future nextTick() {
  return new Future.delayed(new Duration(milliseconds: 1));
}
