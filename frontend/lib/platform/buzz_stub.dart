import 'package:flutter/services.dart';

/// Buzzes the phone: a heavy haptic tap, whatever [length].
void buzz(Duration length) => HapticFeedback.heavyImpact();
