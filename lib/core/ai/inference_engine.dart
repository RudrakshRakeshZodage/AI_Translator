import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:isolate';
import 'package:ffi/ffi.dart';

typedef InitWhisperNative = Pointer<Void> Function(Pointer<Utf8> modelPath);
typedef InitWhisper = Pointer<Void> Function(Pointer<Utf8> modelPath);

typedef InitLlamaNative = Pointer<Void> Function(Pointer<Utf8> modelPath);
typedef InitLlama = Pointer<Void> Function(Pointer<Utf8> modelPath);

typedef TranscribeNative = Pointer<Utf8> Function(Pointer<Void> ctx, Pointer<Double> audioData, Int32 sampleCount);
typedef Transcribe = Pointer<Utf8> Function(Pointer<Void> ctx, Pointer<Double> audioData, int sampleCount);

typedef TranslateNative = Pointer<Utf8> Function(Pointer<Void> ctx, Pointer<Utf8> text, Pointer<Utf8> targetLang);
typedef Translate = Pointer<Utf8> Function(Pointer<Void> ctx, Pointer<Utf8> text, Pointer<Utf8> targetLang);

class InferenceEngine {
  DynamicLibrary? _lib;
  InitWhisper? _initWhisper;
  InitLlama? _initLlama;
  Transcribe? _whisperTranscribe;
  Translate? _llamaTranslate;

  Pointer<Void>? _whisperCtx;
  Pointer<Void>? _llamaCtx;

  String? errorMessage; 

  bool get hasError => errorMessage != null;

  InferenceEngine() {
    try {
      _lib = Platform.isAndroid
          ? DynamicLibrary.open("libnative_bridge.so")
          : DynamicLibrary.process();

      _initWhisper = _lib!.lookupFunction<InitWhisperNative, InitWhisper>("init_whisper");
      _initLlama = _lib!.lookupFunction<InitLlamaNative, InitLlama>("init_llama");
      _whisperTranscribe = _lib!.lookupFunction<TranscribeNative, Transcribe>("whisper_transcribe");
      _llamaTranslate = _lib!.lookupFunction<TranslateNative, Translate>("llama_translate");
      print("AI ENGINE: Native Library Loaded Successfully.");
    } catch (e) {
      errorMessage = "Native Library Load Failed: $e";
    }
  }

  void init(String whisperModelPath, String gemmaModelPath) {
    if (_lib == null) return;
    try {
      _whisperCtx = _initWhisper!(whisperModelPath.toNativeUtf8());
      _llamaCtx = _initLlama!(gemmaModelPath.toNativeUtf8());
    } catch (e) {
      errorMessage = "Context Init Failed: $e";
    }
  }

  Future<String> transcribe(List<double> samples) async {
    if (_whisperCtx == null || _whisperCtx!.address == 0) {
      return "Whisper Not Ready";
    }
    
    final ctxAddress = _whisperCtx!.address;
    
    return await Isolate.run(() {
      final lib = Platform.isAndroid ? DynamicLibrary.open("libnative_bridge.so") : DynamicLibrary.process();
      final whisperTranscribe = lib.lookupFunction<TranscribeNative, Transcribe>("whisper_transcribe");
      final freeString = lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>("free_string");
      
      // Use Double to match C++ signature
      final pointer = calloc<Double>(samples.length);
      for (var i = 0; i < samples.length; i++) {
        pointer[i] = samples[i];
      }
      
      final ctxPointer = Pointer<Void>.fromAddress(ctxAddress);
      final resultPointer = whisperTranscribe(ctxPointer, pointer, samples.length);
      
      String text = "";
      if (resultPointer.address != 0) {
        text = resultPointer.toDartString();
        freeString(resultPointer);
      }
      
      calloc.free(pointer);
      return text;
    });
  }

  Stream<String> translate(String text, String targetLang) async* {
    if (_llamaCtx == null || _llamaCtx!.address == 0) {
      yield "Translation engine not ready.";
      return;
    }

    final textPtr = text.toNativeUtf8();
    final langPtr = targetLang.toNativeUtf8();
    
    try {
      final resultPtr = _llamaTranslate!(
        _llamaCtx!,
        textPtr,
        langPtr,
      );
      
      if (resultPtr.address != 0) {
        final translated = resultPtr.toDartString();
        yield translated;
        
        // Clean up native string
        final lib = Platform.isAndroid ? DynamicLibrary.open("libnative_bridge.so") : DynamicLibrary.process();
        final freeString = lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>("free_string");
        freeString(resultPtr);
      }
    } finally {
      malloc.free(textPtr);
      malloc.free(langPtr);
    }
  }
}
