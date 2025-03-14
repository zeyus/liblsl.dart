import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:liblsl/liblsl.dart';
import 'src/types.dart';

enum LSLContentType {
  /// EEG (for Electroencephalogram)
  eeg("EEG"),

  /// MoCap (for Motion Capture)
  mocap("MoCap"),

  /// NIRS (Near-Infrared Spectroscopy)
  nirs("NIRS"),

  /// Gaze (for gaze / eye tracking parameters)
  gaze("Gaze"),

  /// VideoRaw (for uncompressed video)
  videoRaw("VideoRaw"),

  /// VideoCompressed (for compressed video)
  videoCompressed("VideoCompressed"),

  /// Audio (for PCM-encoded audio)
  audio("Audio"),

  /// Markers (for event marker streams)
  markers("Markers");

  final String value;

  const LSLContentType(this.value);

  Pointer<Char> get charPtr => value.toNativeUtf8() as Pointer<Char>;
}

/// Further bits of meta-data that can be associated with a stream are the following:

// Human-Subject Information
// Recording Environment Information
// Experiment Information
// Synchronization Information

// need to implement full data types later
class LSL {
  Pointer<lsl_streaminfo_struct_>? _streamInfo;
  Pointer<lsl_outlet_struct_>? _streamOutlet;
  LSL();

  Future<void> createStreamInfo(
      {String streamName = "DartLSLStream",
      LSLContentType streamType = LSLContentType.eeg,
      int channelCount = 16,
      double sampleRate = 250.0,
      lsl_channel_format_t channelFormat = lsl_channel_format_t.cft_float32,
      String sourceId = "DartLSL"}) async {
    _streamInfo = lsl_create_streaminfo(
        streamName.toNativeUtf8() as Pointer<Char>,
        streamType.charPtr,
        channelCount,
        sampleRate,
        channelFormat,
        sourceId.toNativeUtf8() as Pointer<Char>);
  }

  int get version => lsl_library_version();

  Future<void> createOutlet({int chunkSize = 0, int maxBuffer = 1}) async {
    if (_streamInfo == null) {
      throw LSLException('StreamInfo not created');
    }
    _streamOutlet = lsl_create_outlet(_streamInfo!, chunkSize, maxBuffer);
  }

  Future<void> waitForConsumer({double timeout = 60}) async {
    final consumerFound = lsl_wait_for_consumers(_streamOutlet!, timeout);
    if (consumerFound == 0) {
      throw TimeoutException('No consumer found within $timeout seconds');
    }
  }
}
