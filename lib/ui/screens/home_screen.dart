import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/ai/audio_pipeline.dart';
import '../../core/ai/inference_engine.dart';
import '../../core/ai/model_manager.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/models.dart';

class HomeScreen extends StatefulWidget {
  final int sessionId;
  final String sessionTitle;

  const HomeScreen({
    super.key, 
    required this.sessionId, 
    required this.sessionTitle
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  late InferenceEngine _engine;
  late AudioPipeline _pipeline;
  late ModelManager _modelManager;
  
  final List<TranslationMessage> _messages = [];
  final List<String> _logs = [];
  bool _isListening = false;
  bool _isInitializing = true;
  String? _activeSessionId; // Unique ID for the current mic session

  @override
  void initState() {
    super.initState();
    _setupEngine();
  }

  Future<void> _setupEngine() async {
    _modelManager = ModelManager();
    _engine = InferenceEngine();
    
    final whisperPath = await _modelManager.getModelPath(ModelManager.whisperFileName);
    final gemmaPath = await _modelManager.getModelPath(ModelManager.gemmaFileName);
    _engine.init(whisperPath, gemmaPath);
    
    final savedMessages = await _dbHelper.getMessagesForSession(widget.sessionId);
    setState(() {
      _messages.addAll(savedMessages.reversed);
    });

    _pipeline = AudioPipeline(_engine);
    _pipeline.conversationStream.listen((info) async {
      setState(() {
        // If we have an active session, update the top bubble
        if (_activeSessionId != null && _messages.isNotEmpty) {
          _messages[0] = TranslationMessage(
            id: _messages[0].id,
            sessionId: widget.sessionId,
            speakerId: info.id,
            originalText: info.originalText,
            translatedText: info.translatedText,
            timestamp: info.timestamp,
          );
        } else {
          // This case should only happen if a message arrives right after stop
          // or if it's the very first message of a session
          final msg = TranslationMessage(
            sessionId: widget.sessionId,
            speakerId: info.id,
            originalText: info.originalText,
            translatedText: info.translatedText,
            timestamp: info.timestamp,
          );
          _messages.insert(0, msg);
          _dbHelper.addMessage(msg);
        }
      });
      
      if (info.translatedText.isNotEmpty && !info.translatedText.startsWith("Translating...")) {
        // Removed automatic _speak(info.translatedText);
      }
    });

    _pipeline.logStream.listen((msg) {
      if (mounted) {
        setState(() {
          _logs.add("${DateTime.now().second}.${DateTime.now().millisecond}s - $msg");
          if (_logs.length > 6) _logs.removeAt(0); // Keep last 6 logs
        });
      }
    });

    setState(() {
      _isInitializing = false;
    });
  }

  Future<void> _speak(String text) async {
    await _flutterTts.setLanguage("hi-IN");
    await _flutterTts.speak(text);
  }

  void _showExportMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.description_outlined, color: Colors.white),
            title: const Text("Export as Text", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _exportAsText();
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined, color: Colors.greenAccent),
            title: const Text("Export to Excel (CSV)", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _exportAsExcel();
            },
          ),
          const Divider(color: Colors.white10),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text("Delete Chat", style: TextStyle(color: Colors.redAccent)),
            onTap: () {
              Navigator.pop(context);
              _deleteChat();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _exportAsText() {
    if (_messages.isEmpty) return;
    String exportText = "--- ${widget.sessionTitle} ---\n\n";
    for (var m in _messages.reversed) {
      exportText += "Speaker ${m.speakerId}:\nOriginal: ${m.originalText}\nTranslated: ${m.translatedText}\n\n";
    }
    Share.share(exportText);
  }

  Future<void> _exportAsExcel() async {
    if (_messages.isEmpty) return;

    List<List<dynamic>> rows = [
      ["Speaker ID", "Timestamp", "Original Text", "Translated Text"],
    ];

    for (var m in _messages.reversed) {
      rows.add([
        m.speakerId,
        m.timestamp.toIso8601String(),
        m.originalText,
        m.translatedText,
      ]);
    }

    // Robust manual CSV generation (Excel compatible)
    String csvData = rows.map((row) {
      return row.map((cell) {
        String str = cell.toString().replaceAll('"', '""');
        return '"$str"'; // Wrap in quotes to handle commas in text
      }).join(",");
    }).join("\n");

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/${widget.sessionTitle.replaceAll(" ", "_")}.csv');
    await file.writeAsString(csvData);

    await Share.shareXFiles([XFile(file.path)], text: "Excel Export: ${widget.sessionTitle}");
  }

  void _deleteChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Delete Chat?", style: TextStyle(color: Colors.white)),
        content: const Text("This will permanently remove this session and all its messages.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirm == true) {
      await _dbHelper.deleteSession(widget.sessionId);
      if (mounted) Navigator.pop(context);
    }
  }

  void _toggleListening() async {
    if (_isListening) {
      await _pipeline.stopListening();
      _activeSessionId = null; // Clear session on stop
    } else {
      _activeSessionId = DateTime.now().millisecondsSinceEpoch.toString(); // Start new session
      await _pipeline.startListening();
    }
    setState(() {
      _isListening = !_isListening;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Image.asset('assets/logo.png', width: 24, height: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.sessionTitle,
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _engine.hasError ? Colors.orangeAccent : Colors.greenAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _engine.hasError ? "ENGINE FALLBACK" : "AI CONNECTED",
                      style: TextStyle(
                        fontSize: 9, 
                        color: _engine.hasError ? Colors.orangeAccent : Colors.greenAccent, 
                        fontWeight: FontWeight.w800, 
                        letterSpacing: 1
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white70, size: 22),
            onPressed: _showExportMenu,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isInitializing 
        ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
        : Column(
            children: [
              Expanded(
                child: ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(20, 120, 20, 20),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    return _buildMessageBubble(msg);
                  },
                ),
              ),
              _buildControlPanel(),
            ],
          ),
    );
  }

  Widget _buildMessageBubble(TranslationMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "SPEAKER ${msg.speakerId}",
                  style: const TextStyle(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'sans-serif'),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "${msg.timestamp.hour}:${msg.timestamp.minute}",
                style: const TextStyle(color: Colors.white10, fontSize: 10, fontFamily: 'sans-serif'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            msg.originalText,
            style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5, fontFamily: 'sans-serif'),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    msg.translatedText,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                ),
                if (!msg.translatedText.startsWith("Translating..."))
                  IconButton(
                    icon: const Icon(Icons.volume_up_rounded, color: Colors.blueAccent, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _speak(msg.translatedText),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 0, 30, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isListening) ...[
              Text(
                "LISTENING...",
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  fontFamily: 'sans-serif',
                ),
              ),
              const SizedBox(height: 16),
            ],
            _buildConsole(),
            GestureDetector(
              onTap: _toggleListening,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening ? Colors.redAccent : Colors.blueAccent,
                  boxShadow: [
                    BoxShadow(
                      color: (_isListening ? Colors.redAccent : Colors.blueAccent).withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildConsole() {
    if (_logs.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 100,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
      ),
      child: ListView.builder(
        reverse: true, // Show newest at bottom (wait, reverse shows newest at top if we don't reverse the list)
        itemCount: _logs.length,
        itemBuilder: (context, index) {
          final log = _logs[_logs.length - 1 - index];
          return Text(
            "> $log",
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          );
        },
      ),
    );
  }
}
