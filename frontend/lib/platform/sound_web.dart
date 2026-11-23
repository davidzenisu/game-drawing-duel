import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// Sound through the Web Audio API. Browsers keep sound off until the page
/// is tapped: the audio context is woken on every tap and key press, so
/// sound turned on at an earlier visit starts with the first tap.
class SoundOutput {
  /// Not under `LocalCache`'s prefix, so signing out keeps the settings.
  static const _prefix = 'drawing-duel-sound-';

  web.AudioContext? _context;
  final _buffers = <String, Future<web.AudioBuffer?>>{};

  /// A sound that isn't ready this long after it was asked for is skipped:
  /// late, it would no longer match what it goes with.
  static const _maxLate = Duration(milliseconds: 150);

  bool savedOn(String key) {
    try {
      return web.window.localStorage.getItem('$_prefix$key') == 'on';
    } catch (_) {
      return false;
    }
  }

  void save(String key, bool on) {
    try {
      web.window.localStorage.setItem('$_prefix$key', on ? 'on' : 'off');
    } catch (_) {
      // Not kept: sound is off again next visit.
    }
  }

  web.AudioContext? get _audio {
    if (_context case final context?) return context;
    try {
      final context = _context = web.AudioContext();
      void wake(web.Event _) => _resume(context);
      web.document.addEventListener('pointerdown', wake.toJS);
      web.document.addEventListener('keydown', wake.toJS);
      return context;
    } catch (_) {
      return null; // No Web Audio here.
    }
  }

  void _resume(web.AudioContext context) {
    try {
      if (context.state != 'running') context.resume();
    } catch (_) {
      // Still not allowed: the next tap tries again.
    }
  }

  void wake() {
    if (_audio case final context?) _resume(context);
  }

  Future<web.AudioBuffer?> _load(web.AudioContext context, String file) => _buffers.putIfAbsent(file, () async {
    try {
      final data = await rootBundle.load('assets/sounds/$file');
      final bytes = Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      return await context.decodeAudioData(bytes.buffer.toJS).toDart;
    } catch (_) {
      return null;
    }
  });

  void preload(Iterable<String> files) {
    final context = _audio;
    if (context == null) return;
    for (final file in files) {
      _load(context, file);
    }
  }

  /// A source for [file] through a gain at [volume], or nothing if it can't play.
  Future<(web.AudioBufferSourceNode, web.GainNode)?> _source(String file, double volume) async {
    final context = _audio;
    if (context == null) return null;
    final buffer = await _load(context, file);
    if (buffer == null) return null;
    final gain = context.createGain()..gain.value = volume;
    gain.connect(context.destination);
    final source = context.createBufferSource()..buffer = buffer;
    source.connect(gain);
    return (source, gain);
  }

  void play(String file, {double volume = 1}) async {
    final asked = DateTime.now();
    try {
      final (source, _) = await _source(file, volume) ?? (null, null);
      if (DateTime.now().difference(asked) > _maxLate) return;
      source?.start();
    } catch (_) {
      // Not played.
    }
  }

  SoundLoop loop(String file, {double volume = 1}) {
    final loop = SoundLoop._(this, volume);
    _source(file, volume)
        .then((nodes) {
          if (nodes == null || loop._stopped) return;
          final (source, gain) = nodes;
          loop
            .._source = source
            .._gain = gain;
          gain.gain.value = loop._volume;
          source
            ..loop = true
            ..start();
        })
        .catchError((_) {});
    return loop;
  }
}

/// A sound playing over and over.
class SoundLoop {
  SoundLoop._(this._output, this._volume);

  final SoundOutput _output;
  double _volume;
  bool _stopped = false;
  web.AudioBufferSourceNode? _source;
  web.GainNode? _gain;

  set volume(double value) {
    _volume = value;
    final gain = _gain;
    final context = _output._context;
    if (gain == null || context == null) return;
    try {
      gain.gain.setTargetAtTime(value, context.currentTime, 0.08);
    } catch (_) {
      gain.gain.value = value;
    }
  }

  void stop() {
    _stopped = true;
    try {
      _source?.stop();
    } catch (_) {
      // Already stopped.
    }
    _source = null;
  }
}
