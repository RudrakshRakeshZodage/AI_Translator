import 'dart:async';
import 'package:record/record.dart';
import 'inference_engine.dart';

class SpeakerInfo {
  final int id;
  final String originalText;
  final String translatedText;
  final DateTime timestamp;

  SpeakerInfo({
    required this.id,
    required this.originalText,
    required this.translatedText,
    required this.timestamp,
  });
}

class AudioPipeline {
  final AudioRecorder _recorder = AudioRecorder();
  final InferenceEngine _engine;
  
  bool _isListening = false;
  StreamController<SpeakerInfo> _streamController = StreamController.broadcast();

  AudioPipeline(this._engine);

  Stream<SpeakerInfo> get conversationStream => _streamController.stream;

  Future<void> startListening() async {
    if (await _recorder.hasPermission()) {
      _isListening = true;
      
      // Start recording to a stream
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));

      _processAudioStream(stream);
    }
  }

  Stream<String> get logStream => _logController.stream;
  StreamController<String> _logController = StreamController.broadcast();

  void _log(String msg) {
    print("PIPELINE LOG: $msg");
    _logController.add(msg);
  }

  void _processAudioStream(Stream<List<int>> stream) async {
    List<double> buffer = [];
    _log("Microphone Stream Opened.");
    
    await for (final chunk in stream) {
      if (!_isListening) {
        _log("Listening Stopped. Flushing final buffer...");
        break;
      }

      // Convert PCM16 to Float32 for Whisper and check volume
      double maxAmplitude = 0;
      for (int i = 0; i < chunk.length; i += 2) {
        int sample = (chunk[i] | (chunk[i + 1] << 8));
        if (sample > 32767) sample -= 65536;
        double floatSample = sample / 32768.0;
        buffer.add(floatSample);
        if (floatSample.abs() > maxAmplitude) maxAmplitude = floatSample.abs();
      }

      if (maxAmplitude > 0.01) {
        _log("Mic Activity: Peak Amplitude = ${(maxAmplitude * 100).toStringAsFixed(1)}%");
      }

      // Process every 3.0 seconds for better Whisper accuracy
      if (buffer.length >= 48000) {
        final samplesToProcess = List<double>.from(buffer);
        buffer.clear();
        _log("Buffer filled (48000 samples). Sending to Inference Engine...");
        _processChunk(samplesToProcess);
      }
    }
    
    // FLUSH FINAL BUFFER: Ensure short speeches are never dropped!
    if (buffer.isNotEmpty) {
      _log("Flushing remaining ${buffer.length} samples to engine...");
      _processChunk(buffer);
    }
  }

  Future<void> _processChunk(List<double> samples) async {
    _log("Whisper Transcribing...");
    // 1. Transcribe
    final text = await _engine.transcribe(samples);
    if (text.trim().isEmpty) {
      _log("Transcribe resulted in empty string. Ignoring.");
      return;
    }
    _log("Transcription: '$text'");

    // 2. Detect Language (Simple logic or let Gemma do it)
    String sourceLang = _detectLanguage(text);
    String targetLang = sourceLang == "Hindi" ? "English" : "Hindi";
    _log("Whisper Finished. Detected: $sourceLang. Now Translating with Gemma...");

    // 3. Translate using Gemma with real-time streaming
    String translated = "";
    await for (final token in _engine.translate(text, targetLang)) {
      translated += token;
      
      // Emit to UI for every token for that "Real-Time" look
      _streamController.add(SpeakerInfo(
        id: 1, 
        originalText: text,
        translatedText: translated,
        timestamp: DateTime.now(),
      ));
    }
    _log("Gemma completed: '$translated'");
  }

  String _detectLanguage(String text) {
    // Simple heuristic: check for Devanagari characters
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) >= 0x0900 && text.codeUnitAt(i) <= 0x097F) {
        return "Hindi";
      }
    }
    return "English";
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _recorder.stop();
  }
}
