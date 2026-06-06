/// Serial-NMEA location provider — a real GPS data path.
///
/// Implements [LocationProvider] by reading bytes from a serial port (a USB or
/// UART GPS receiver), splitting them into NMEA lines, parsing the RMC/GGA
/// position sentences via [NmeaParser], and emitting [GeoPosition] fixes on the
/// [positions] stream. It is the concrete inner provider you wrap in a
/// [DeadReckoningProvider] and feed to a [LocationBloc] — the same shape as
/// [GeoClueLocationProvider], but sourcing the OS-independent NMEA stream a
/// plain serial GPS puck speaks.
///
/// ## Opening by name (not by enumeration)
///
/// The port is opened by an **explicit name** (`/dev/ttyUSB0`, `/dev/ttyAMA0`,
/// `/dev/ttyS0`, or a `tty0tty` virtual pair like `/dev/tnt0`). It deliberately
/// does NOT call `SerialPort.availablePorts` and pick one: that enumeration
/// walks `/sys/class/tty` and does NOT list `socat` UNIX98 ptys, so an
/// availablePorts-driven open would silently miss a virtual test port. Opening
/// the named device directly is the portable path for both real hardware and a
/// `tty0tty` kernel-virtual port.
///
/// ## Injectable byte source (for tests)
///
/// The byte source is **injectable** via the optional [byteSource] constructor
/// argument. When supplied, the provider reads NMEA bytes from that stream
/// instead of opening the serial port — so the full
/// serial → parse → kalman_dr → bloc → scene chain can be integration-tested
/// without any hardware or virtual port. When [byteSource] is `null` (the
/// production path) the named serial port is opened and read.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:kalman_dr/kalman_dr.dart';

import 'nmea_parser.dart';

/// A [LocationProvider] backed by a serial NMEA stream.
class SerialNmeaLocationProvider implements LocationProvider {
  /// The serial device to open, e.g. `/dev/ttyUSB0`. Ignored when [byteSource]
  /// is supplied.
  final String portName;

  /// Serial baud rate. NMEA receivers are commonly 4800 or 9600; default 9600.
  final int baudRate;

  /// Optional injected byte source. When non-null, the provider reads NMEA
  /// bytes from this stream instead of opening [portName] — used by tests and
  /// by any caller that already has a byte stream (e.g. a replay file).
  final Stream<List<int>>? byteSource;

  final NmeaParser _parser;
  final _controller = StreamController<GeoPosition>.broadcast();

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<List<int>>? _byteSub;

  // Accumulates partial bytes until a full `\n`-terminated line is available.
  final StringBuffer _lineBuffer = StringBuffer();

  bool _started = false;
  bool _disposed = false;

  SerialNmeaLocationProvider({
    required this.portName,
    this.baudRate = 9600,
    this.byteSource,
    NmeaParser? parser,
  }) : _parser = parser ?? NmeaParser();

  @override
  Stream<GeoPosition> get positions => _controller.stream;

  /// Whether the provider is currently reading.
  bool get isRunning => _started;

  @override
  Future<void> start() async {
    if (_disposed) {
      throw StateError('SerialNmeaLocationProvider has already been disposed');
    }
    if (_started) return;

    final injected = byteSource;
    if (injected != null) {
      // Test / replay path: read bytes from the injected stream.
      _byteSub = injected.listen(
        _onBytes,
        onError: _onSourceError,
        cancelOnError: false,
      );
      _started = true;
      return;
    }

    // Production path: open the named serial port and stream its bytes.
    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final err = SerialPort.lastError;
      throw SerialPortError(
        'Failed to open serial port "$portName"'
        '${err != null ? ': ${err.message}' : ''}',
      );
    }
    _port = port;

    final config = SerialPortConfig()
      ..baudRate = baudRate
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 1;
    port.config = config;

    final reader = SerialPortReader(port);
    _reader = reader;
    _byteSub = reader.stream.listen(
      _onBytes,
      onError: _onSourceError,
      cancelOnError: false,
    );
    _started = true;
  }

  @override
  Future<void> stop() async {
    _started = false;
    await _byteSub?.cancel();
    _byteSub = null;
    _reader?.close();
    _reader = null;
    if (_port != null) {
      try {
        _port!.close();
      } catch (_) {}
      _port = null;
    }
    _lineBuffer.clear();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    _port?.dispose();
    _port = null;
    await _controller.close();
  }

  /// Buffer incoming bytes, split on newlines, parse each complete line.
  void _onBytes(List<int> bytes) {
    if (_controller.isClosed) return;
    // NMEA is ASCII; latin1 is a lossless byte→char map that never throws on
    // stray non-UTF-8 bytes from a noisy serial line.
    _lineBuffer.write(latin1.decode(bytes, allowInvalid: true));

    var buffered = _lineBuffer.toString();
    // A line is complete once we see CR or LF. Process every complete line and
    // keep the trailing partial fragment in the buffer.
    final lines = buffered.split(RegExp(r'[\r\n]+'));
    // The last element is the (possibly empty) incomplete tail.
    final tail = lines.removeLast();
    for (final line in lines) {
      if (line.isEmpty) continue;
      _emitFromLine(line);
    }
    _lineBuffer
      ..clear()
      ..write(tail);
  }

  void _emitFromLine(String line) {
    if (_controller.isClosed) return;
    try {
      final pos = _parser.parseLine(line);
      if (pos != null) _controller.add(pos);
    } catch (_) {
      // A single malformed sentence must never tear down the stream.
    }
  }

  void _onSourceError(Object error, StackTrace stackTrace) {
    if (!_controller.isClosed) {
      _controller.addError(error, stackTrace);
    }
  }
}
