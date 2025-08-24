import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const VoiceNotesApp());
}

class VoiceNotesApp extends StatelessWidget {
  const VoiceNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NOTES',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color.fromARGB(255, 3, 64, 219),
      ),
      home: const VoiceNotesHomePage(),
    );
  }
}

class VoiceNotesHomePage extends StatefulWidget {
  const VoiceNotesHomePage({super.key});

  @override
  State<VoiceNotesHomePage> createState() => _VoiceNotesHomePageState();
}

class _VoiceNotesHomePageState extends State<VoiceNotesHomePage> {
  List<Map<String, String>> _notes = [];
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _transcript = "";

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _loadNotes();
  }

  @override
  void dispose() {
    _player.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString("notes") ?? "[]";
    final List decoded = json.decode(jsonString);
    setState(() {
      _notes = decoded.map((e) => Map<String, String>.from(e)).toList();
    });
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("notes", json.encode(_notes));
  }

  void _addTextNote() {
    if (_textController.text.trim().isEmpty) return;
    setState(() {
      _notes.insert(0, {
        "title": "Text Note",
        "text": _textController.text.trim(),
        "transcript": "",
        "audioPath": "",
      });
      _textController.clear();
    });
    _saveNotes();
  }

  Future<void> _addVoiceNote(String transcript, String? audioPath) async {
    String defaultTitle =
        "Voice Note - ${DateTime.now().toString().substring(0, 16)}";

    final controller = TextEditingController();

    // ask user for name
    final noteTitle = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Name your voice note"),
          content: TextField(
            controller: controller,
            decoration:
                const InputDecoration(hintText: "Enter a title (optional)"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text("Skip"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    setState(() {
      _notes.insert(0, {
        "title": noteTitle?.isNotEmpty == true ? noteTitle! : defaultTitle,
        "text": "",
        "transcript": transcript,
        "audioPath": audioPath ?? "",
      });
    });
    _saveNotes();
  }

  Future<void> _startListening() async {
    final sttAvailable = await _speech.initialize();
    final hasRecordPermission = await _recorder.hasPermission();

    if (sttAvailable && hasRecordPermission) {
      setState(() {
        _isListening = true;
        _transcript = "";
      });

      final dir = await getApplicationDocumentsDirectory();
      final filePath =
          '${dir.path}/note_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
        ),
        path: filePath,
      );

      _speech.listen(onResult: (result) {
        setState(() {
          _transcript = result.recognizedWords;
        });
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission or STT unavailable'),
        ),
      );
    }
  }

  Future<void> _stopListening() async {
    _speech.stop();
    final recordedPath = await _recorder.stop();

    setState(() {
      _isListening = false;
    });

    if (_transcript.isNotEmpty || (recordedPath?.isNotEmpty ?? false)) {
      _addVoiceNote(_transcript, recordedPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.toLowerCase();
    final filtered = _notes.where((note) {
      final title = note["title"]?.toLowerCase() ?? "";
      final text = note["text"]?.toLowerCase() ?? "";
      final transcript = note["transcript"]?.toLowerCase() ?? "";
      return title.contains(query) ||
          text.contains(query) ||
          transcript.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Voice Notes"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              showSearch(
                context: context,
                delegate: NotesSearchDelegate(_notes),
              );
            },
          )
        ],
      ),
      body: Column(
        children: [
          if (_isListening || _transcript.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _isListening ? Icons.mic : Icons.text_snippet,
                    color: const Color.fromARGB(255, 58, 85, 183),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isListening ? "Listening..." : "Heard: $_transcript",
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      "No notes yet",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final note = filtered[index];
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 3,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          leading: Icon(
                            note["audioPath"]!.isNotEmpty
                                ? Icons.mic
                                : Icons.note,
                            color: const Color.fromARGB(255, 2, 6, 67),
                          ),
                          title: Text(
                            note["title"] ?? "(Untitled)",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (note["text"]!.isNotEmpty)
                                Text(note["text"]!,
                                    style:
                                        const TextStyle(color: Colors.black87)),
                              if (note["transcript"]!.isNotEmpty)
                                Text("Transcript: ${note["transcript"]}",
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.grey)),
                              if (note["audioPath"]!.isNotEmpty)
                                TextButton.icon(
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text("Play Audio"),
                                  onPressed: () async {
                                    final p = note["audioPath"]!;
                                    if (File(p).existsSync()) {
                                      await _player.play(DeviceFileSource(p));
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('Audio file missing')),
                                      );
                                    }
                                  },
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              if (note["audioPath"]!.isNotEmpty) {
                                final file = File(note["audioPath"]!);
                                if (file.existsSync()) {
                                  await file.delete();
                                }
                              }
                              setState(() {
                                _notes.removeAt(index);
                              });
                              _saveNotes();
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    hintText: "Type a note...",
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color.fromARGB(255, 2, 6, 67),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _addTextNote,
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _isListening ? Colors.red : Colors.deepPurple,
        onPressed: () {
          if (_isListening) {
            _stopListening();
          } else {
            _startListening();
          }
        },
        child: Icon(_isListening ? Icons.stop : Icons.mic, color: Colors.white),
      ),
    );
  }
}

/// Search delegate for notes
class NotesSearchDelegate extends SearchDelegate {
  final List<Map<String, String>> notes;
  NotesSearchDelegate(this.notes);

  @override
  List<Widget> buildActions(BuildContext context) => [
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = "",
        ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) {
    final results = notes.where((note) {
      final title = note["title"]?.toLowerCase() ?? "";
      final text = note["text"]?.toLowerCase() ?? "";
      final transcript = note["transcript"]?.toLowerCase() ?? "";
      return title.contains(query.toLowerCase()) ||
          text.contains(query.toLowerCase()) ||
          transcript.contains(query.toLowerCase());
    }).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final note = results[index];
        return Card(
          child: ListTile(
            title: Text(note["title"] ?? "(Untitled)"),
            subtitle: Text(note["text"]!.isNotEmpty
                ? note["text"]!
                : note["transcript"] ?? ""),
          ),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) => buildResults(context);
}
