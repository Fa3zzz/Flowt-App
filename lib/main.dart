import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
part 'main.g.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(NoteAdapter());
  await Hive.openBox<Note>('notesBox_v2');

  final notesBox = Hive.box<Note>('notesBox_v2');
  await notesBox.clear();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF4B0082),
          foregroundColor: Colors.white54,
        ),
      ),
      home: const NotesHome(),
    );
  }
}

@HiveType(typeId: 0)
class Note extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  String? description;

  @HiveField(2)
  final List<Map<String, String>> links;

  @HiveField(3)
  List<String> imagePaths;

  @HiveField(4)
  List<Map<String, String>> contentBlocks;

  Note({
    required this.title,
    this.description,
    List<Map<String, String>>? links,
    this.imagePaths = const [],
    List<Map<String, String>>? contentBlocks,
  })  : links = links ?? [],
        contentBlocks = contentBlocks ?? [];
}



class NotesHome extends StatefulWidget {
  const NotesHome({super.key});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  final notesBox = Hive.box<Note>('notesBox_v2');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        // backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text("Flowt"),
      ),
      body: ValueListenableBuilder(
        valueListenable: notesBox.listenable(),
        builder: (context, Box<Note> box, _) {
          if (box.isEmpty) {
            return const Center(
              child: Text("No notes yet",
                  style: TextStyle(color: Colors.white54, fontSize: 18)),
            );
          }

          return ListView.builder(
            itemCount: box.length,
            itemBuilder: (context, index) {
              final note = box.getAt(index)!;

              return Dismissible(
                key: Key(note.key.toString()),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => note.delete(),
                child: Card(
                  margin:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  color: Colors.grey[900],
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    title: Text(
                      note.title,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () async {
                      final updatedNote = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NoteDetailScreen(note: note),
                        ),
                      );

                      if (updatedNote != null) {
                        note.title = updatedNote.title;
                        note.description = updatedNote.description;
                        note.save();
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF4B0082),
        onPressed: () async {
          final newNote = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddNotesScreen()),
          );

          if (newNote != null) {
            notesBox.add(newNote);
          }
        },
        child: const Icon(
          Icons.add,
          color: Colors.white54,
        )
      ),
    );
  }
}

class AddNotesScreen extends StatefulWidget {
  const AddNotesScreen({super.key});

  @override
  State<AddNotesScreen> createState() => _AddNotesScreenState();
}

class _AddNotesScreenState extends State<AddNotesScreen> {
  final titleController = TextEditingController();
  final scrollController = ScrollController();

  List<Map<String, dynamic>> blocks = [
    {"type": "text", "content": "", "controller": null}
  ];

  String? selectedText;

  // ✅ links must match Note model: List<Map<String, String>>
  final List<Map<String, String>> links = [];

  // ✅ track the exact selection to persist ranges
  int? selectedBlockIndex;
  int? selectedStart;
  int? selectedEnd;

  @override
  void dispose() {
    titleController.dispose();
    for (final b in blocks) {
      if (b['type'] == 'text' && b['controller'] is TextEditingController) {
        (b['controller'] as TextEditingController).dispose();
      }
    }
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        // Add image block at end
        blocks.add({"type": "image", "path": pickedFile.path});
        // Followed by a new empty text block
        blocks.add({"type": "text", "content": "", "controller": null});
      });

      // Scroll to bottom
      await Future.delayed(const Duration(milliseconds: 200));
      scrollController.animateTo(
        scrollController.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.white54),
            title: const Text("Take Photo", style: TextStyle(color: Colors.white54)),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo, color: Colors.white54),
            title: const Text("Choose from Gallery", style: TextStyle(color: Colors.white54)),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  void _openFullScreen(File file) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => GestureDetector(
        onVerticalDragEnd: (_) => Navigator.pop(context),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: InteractiveViewer(child: Image.file(file))),
        ),
      ),
    );
  }

  Future<void> _showLinkOptions(String selected) async {
    // must have a concrete selection range & block
    if (selectedBlockIndex == null || selectedStart == null || selectedEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select text to link')),
      );
      return;
    }

    // find by text safely
    final existingIndex = links.indexWhere((l) =>
        l["text"] == selected &&
        l["block"] == selectedBlockIndex.toString() &&
        l["start"] == selectedStart.toString() &&
        l["end"] == selectedEnd.toString());

    final hasExisting = existingIndex != -1;
    final existingLink = hasExisting ? links[existingIndex] : null;

    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) {
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!hasExisting) ...[
              ListTile(
                title: const Text("Link to existing note", style: TextStyle(color: Colors.white54)),
                onTap: () {
                  Navigator.pop(context);
                  _pickNoteToLink(selected);
                },
              ),
              ListTile(
                title: const Text("Create new linked note", style: TextStyle(color: Colors.white54)),
                onTap: () async {
                  Navigator.pop(context);
                  final newNote = Note(
                    title: selected,
                    description: "",
                    contentBlocks: [
                      {"type": "text", "content": ""}
                    ],
                    links: const [],
                  );
                  final key = await Hive.box<Note>('notesBox_v2').add(newNote);
                  setState(() {
                    links.add({
                      "id": const Uuid().v4(),
                      "text": selected,
                      "noteId": key.toString(),
                      // ✅ store position
                      "block": selectedBlockIndex.toString(),
                      "start": selectedStart.toString(),
                      "end": selectedEnd.toString(),
                    });
                  });
                },
              ),
            ] else ...[
              ListTile(
                title: const Text("Unlink", style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    if (existingLink != null) {
                      links.removeWhere((l) => l["id"] == existingLink["id"]);
                    }
                  });
                },
              ),
            ]
          ]),
        );
      },
    );
  }

  void _pickNoteToLink(String selected) {
    final notesBox = Hive.box<Note>('notesBox_v2');
    final others = notesBox.values.toList();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Select Note to Link"),
        content: SizedBox(
          width: double.maxFinite,
          child: others.isEmpty
              ? const Text("No other notes available")
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: others.length,
                  itemBuilder: (context, i) {
                    final n = others[i];
                    return ListTile(
                      title: Text(n.title),
                      onTap: () {
                        if (selectedBlockIndex == null || selectedStart == null || selectedEnd == null) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Select text to link')),
                          );
                          return;
                        }
                        setState(() {
                          links.add({
                            "id": const Uuid().v4(),
                            "text": selected,
                            "noteId": n.key.toString(),
                            // ✅ store position
                            "block": selectedBlockIndex.toString(),
                            "start": selectedStart.toString(),
                            "end": selectedEnd.toString(),
                          });
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Add Note"),
        actions: [
          if (selectedText != null)
            IconButton(
              icon: const Icon(Icons.link, color: Colors.white54),
              onPressed: () async => await _showLinkOptions(selectedText!),
            )
          else
            IconButton(
              icon: const Icon(Icons.image_outlined, color: Colors.white54),
              onPressed: _showImageOptions,
            ),
        ],
      ),
      body: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white54),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[900],
                hintText: "Title",
                border: const OutlineInputBorder(),
                hintStyle: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            ...blocks.asMap().entries.map((entry) {
              final index = entry.key;
              final b = entry.value;

              if (b["type"] == "text") {
                if (b["controller"] == null) {
                  final c = TextEditingController(text: b["content"] ?? "");
                  c.addListener(() {
                    b["content"] = c.text;

                    final sel = c.selection;
                    if (sel.start != sel.end &&
                        sel.start >= 0 &&
                        sel.end <= c.text.length) {
                      final s = c.text.substring(sel.start, sel.end);
                      if (s.trim().isNotEmpty) {
                        setState(() {
                          selectedText = s;
                          selectedBlockIndex = index;     // ✅ capture block
                          selectedStart = sel.start;      // ✅ capture start
                          selectedEnd = sel.end;          // ✅ capture end
                        });
                      }
                    } else {
                      if (selectedText != null) {
                        setState(() {
                          selectedText = null;
                          selectedBlockIndex = null;
                          selectedStart = null;
                          selectedEnd = null;
                        });
                      }
                    }
                  });
                  b["controller"] = c;
                }
                final c = b["controller"] as TextEditingController;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: c,
                    style: const TextStyle(color: Colors.white54, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: index == 0 ? "Description……" : "",
                      hintStyle: const TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                    keyboardType: TextInputType.multiline,
                    maxLines: null,
                  ),
                );
              } else if (b["type"] == "image") {
                final file = File(b["path"]);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      GestureDetector(
                        onTap: () => _openFullScreen(file),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(file, width: double.infinity, fit: BoxFit.cover),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            blocks.removeAt(index);
                          });
                        },
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF4B0082),
        onPressed: () {
          final imagePaths = blocks
              .where((b) => b["type"] == "image")
              .map<String>((b) => (b["path"] ?? "").toString())
              .toList();

          final contentBlocks = blocks.map<Map<String, String>>((b) {
            final type = (b['type'] ?? '').toString();
            if (type == 'text') {
              return {
                "type": "text",
                "content": (b["content"] ?? "").toString(),
              };
            } else if (type == 'image') {
              return {
                "type": "image",
                "path": (b["path"] ?? "").toString(),
              };
            }
            return {"type": "text", "content": ""};
          }).toList();

          final description = contentBlocks
              .where((b) => b["type"] == "text")
              .map((b) => b["content"] ?? "")
              .join("\n");

          // 🧹 Keep only valid links (with block/start/end)
          final cleanLinks = links.where((l) =>
            l.containsKey("block") &&
            l.containsKey("start") &&
            l.containsKey("end")
          ).toList();

          final newNote = Note(
            title: titleController.text,
            description: description.isNotEmpty ? description : null,
            imagePaths: imagePaths,
            contentBlocks: contentBlocks,
            links: cleanLinks.cast<Map<String, String>>(), // ✅ sanitized links
          );

          Navigator.pop(context, newNote);
        },
        child: const Icon(Icons.check, color: Colors.white54),
      ),
    );
  }
}

class NoteDetailScreen extends StatefulWidget {
  final Note note;
  const NoteDetailScreen({super.key, required this.note});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late TextEditingController titleController;
  bool isEditingTitle = false;
  bool isEditingDescription = false;

  String? selectedText;
  int? selectedBlockIndex;
  int? selectedStart;
  int? selectedEnd;

  List<Map<String, dynamic>> blocks = [];

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.note.title);

    // Load or fallback
    if (widget.note.contentBlocks.isNotEmpty) {
      blocks = widget.note.contentBlocks
          .map((b) => Map<String, dynamic>.from(b))
          .toList();
    } else {
      blocks = [
        {"type": "text", "content": widget.note.description ?? ""}
      ];
      widget.note.contentBlocks = blocks.cast<Map<String, String>>();
      widget.note.save();
    }

    // Legacy map links → list of maps (kept as strings)
    if (widget.note.links is Map) {
      final oldLinks = (widget.note.links as Map).entries.map((e) {
        return {
          "id": const Uuid().v4(),
          "text": e.key.toString(),
          "noteId": e.value.toString(),
        };
      }).toList();
      widget.note.links
        ..clear()
        ..addAll(oldLinks.cast<Map<String, String>>());
    }

    _attachControllers();
  }

  void _attachControllers() {
    for (final b in blocks) {
      if (b['type'] == 'text') {
        final c = TextEditingController(text: (b['content'] ?? '') as String);
        final f = FocusNode();
        b['controller'] = c;
        b['focusNode'] = f;

        f.addListener(() {
          if (!f.hasFocus) {
            // clear selection if focus leaves this field
            setState(() {
              if (selectedBlockIndex == blocks.indexOf(b)) {
                selectedText = null;
                selectedBlockIndex = null;
                selectedStart = null;
                selectedEnd = null;
              }
            });
          }
        });

        c.addListener(() {
          b['content'] = c.text;
          widget.note.description = blocks
              .where((e) => e['type'] == 'text')
              .map((e) => (e['content'] ?? '') as String)
              .join("\n")
              .trim();

          // While editing: track selection live
          if (isEditingDescription && f.hasFocus) {
            final sel = c.selection;
            if (sel.start != sel.end &&
                sel.start >= 0 &&
                sel.end <= c.text.length) {
              final s = c.text.substring(sel.start, sel.end);
              if (s.trim().isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    selectedText = s;
                    selectedBlockIndex = blocks.indexOf(b);
                    selectedStart = sel.start;
                    selectedEnd = sel.end;
                  });
                });
              }
            } else {
              if (selectedText != null &&
                  selectedBlockIndex == blocks.indexOf(b)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    selectedText = null;
                    selectedStart = null;
                    selectedEnd = null;
                  });
                });
              }
            }
          }
        });
      }
    }
  }

  @override
  void dispose() {
    for (final b in blocks) {
      if (b['type'] == 'text') {
        (b['controller'] as TextEditingController?)?.dispose();
        (b['focusNode'] as FocusNode?)?.dispose();
      }
    }
    titleController.dispose();
    super.dispose();
  }

  List<Map<String, String>> _sanitizeBlocks() {
    return blocks.map((b) {
      final type = (b['type'] ?? 'text').toString();
      if (type == 'text') {
        final txt = (b['controller'] is TextEditingController)
            ? (b['controller'] as TextEditingController).text
            : (b['content'] ?? '').toString();
        return {"type": "text", "content": txt};
      } else if (type == 'image') {
        return {"type": "image", "path": (b['path'] ?? '').toString()};
      }
      return {"type": "text", "content": ""};
    }).toList();
  }

  void _safeSave(Note note) {
    final sanitized = _sanitizeBlocks();
    note.contentBlocks = sanitized;
    note.description = sanitized
        .where((b) => b['type'] == 'text')
        .map((b) => b['content'] ?? '')
        .join("\n")
        .trim();
    note.save();
  }

  // ---------- Image insertion ----------
  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.photos,
      Permission.storage,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> _pickImage(ImageSource source) async {
    if (selectedBlockIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap a text block first')),
      );
      return;
    }

    if (!await _requestPermissions()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission denied')),
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        final insertAt = selectedBlockIndex! + 1;
        blocks.insert(insertAt, {"type": "image", "path": pickedFile.path});
        blocks.insert(insertAt + 1, {
          "type": "text",
          "content": "",
          "controller": TextEditingController(),
          "focusNode": FocusNode(),
        });
      });
      _safeSave(widget.note);
    }
  }

  void _showImageOptions() {
    if (selectedBlockIndex == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tap a text block first')));
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.white54),
            title:
                const Text("Take Photo", style: TextStyle(color: Colors.white54)),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo, color: Colors.white54),
            title: const Text("Choose from Gallery",
                style: TextStyle(color: Colors.white54)),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  // ---------- Linking helpers ----------
  // Trim leading/trailing spaces from a selection (so stored ranges match visible word)
  (int, int) _normalizedRange(String text, int start, int end) {
    int s = start, e = end;
    while (s < e && text[s] == ' ') s++;
    while (e > s && text[e - 1] == ' ') e--;
    return (s, e);
  }

  // Render text with widgets at saved link ranges
  List<InlineSpan> _buildDescriptionSpans(String text, int blockIndex) {
    final spans = <InlineSpan>[];
    int cursor = 0;

    // Build safe ranges
    final ranges = widget.note.links
        .where((l) => l["block"] == blockIndex.toString())
        .map((l) => {
              ...l,
              "startInt": int.tryParse(l["start"] ?? '') ?? -1,
              "endInt": int.tryParse(l["end"] ?? '') ?? -1,
            })
        .where((l) {
          final s = l["startInt"] as int;
          final e = l["endInt"] as int;
          return s >= 0 && e > s && e <= text.length;
        })
        .toList()
      ..sort((a, b) =>
          (a["startInt"] as int).compareTo(b["startInt"] as int));

    for (final r in ranges) {
      final rStart = r["startInt"] as int;
      final rEnd = r["endInt"] as int;

      // Skip overlaps / out-of-order
      if (rStart < cursor) continue;

      // Plain text before link
      if (rStart > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, rStart),
          style: const TextStyle(color: Colors.white54),
        ));
      }

      final slice = text.substring(rStart, rEnd);
      final noteIdStr = (r["noteId"] ?? '').toString();
      final linkId = (r["id"] ?? '').toString();

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () {
              final id = int.tryParse(noteIdStr);
              if (id != null) {
                final target = Hive.box<Note>('notesBox_v2').get(id);
                if (target != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => NoteDetailScreen(note: target)),
                  );
                }
              }
            },
            onLongPress: () async {
              // Make sure unlink menu knows which exact range we're on
              setState(() {
                selectedText = slice;
                selectedBlockIndex = blockIndex;
                selectedStart = rStart;
                selectedEnd = rEnd;
              });
              await _showLinkOptions(slice, presetLinkId: linkId);
            },
            child: Text(
              slice,
              style: const TextStyle(
                color: Color(0xFF9B30FF),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      );

      cursor = rEnd;
    }

    // Trailing text
    if (cursor < text.length) {
      spans.add(TextSpan(
        text: text.substring(cursor),
        style: const TextStyle(color: Colors.white54),
      ));
    }

    return spans;
  }

  Future<void> _showLinkOptions(String selected,
      {String? presetLinkId}) async {
    final notesBox = Hive.box<Note>('notesBox_v2');

    if (selectedBlockIndex == null ||
        selectedStart == null ||
        selectedEnd == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select text to link')));
      return;
    }

    // Normalize selection against the actual text in that block
    final b = blocks[selectedBlockIndex!];
    final fullText =
        (b['controller'] as TextEditingController?)?.text ??
            (b['content'] ?? '') as String;
    final (s, e) = _normalizedRange(fullText, selectedStart!, selectedEnd!);
    final cleanSelected =
        (s >= 0 && e <= fullText.length && e > s)
            ? fullText.substring(s, e)
            : selected;

    // Detect existing link by exact range OR by preset id from long-press
    int existingIndex = -1;
    if (presetLinkId != null && presetLinkId.isNotEmpty) {
      existingIndex =
          widget.note.links.indexWhere((l) => l["id"] == presetLinkId);
    }
    if (existingIndex == -1) {
      existingIndex = widget.note.links.indexWhere((l) =>
          l["block"] == "$selectedBlockIndex" &&
          l["start"] == "$s" &&
          l["end"] == "$e");
    }

    final hasExisting = existingIndex != -1;
    final existingLink = hasExisting ? widget.note.links[existingIndex] : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!hasExisting) ...[
            ListTile(
              title: const Text("Link to existing note",
                  style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.pop(context);
                _pickNoteToLink(cleanSelected, s, e);
              },
            ),
            ListTile(
              title: const Text("Create new linked note",
                  style: TextStyle(color: Colors.white54)),
              onTap: () async {
                Navigator.pop(context);
                _safeSave(widget.note);

                final newNote = Note(
                  title: cleanSelected,
                  description: "",
                  contentBlocks: [
                    {"type": "text", "content": ""}
                  ],
                  links: const [],
                );

                final key = await notesBox.add(newNote);
                setState(() {
                  widget.note.links.add({
                    "id": const Uuid().v4(),
                    "text": cleanSelected,
                    "noteId": key.toString(),
                    "block": "$selectedBlockIndex",
                    "start": "$s",
                    "end": "$e",
                  });
                });
                _safeSave(widget.note);

                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => NoteDetailScreen(note: newNote)),
                );
              },
            ),
          ] else
            ListTile(
              title: const Text("Unlink",
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  widget.note.links
                      .removeWhere((l) => l["id"] == existingLink?["id"]);
                });
                _safeSave(widget.note);
              },
            ),
        ]),
      ),
    );
  }

  void _pickNoteToLink(String selected, int s, int e) {
    final notesBox = Hive.box<Note>('notesBox_v2');
    final others =
        notesBox.values.where((n) => n.key != widget.note.key).toList();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Select Note to Link"),
        content: SizedBox(
          width: double.maxFinite,
          child: others.isEmpty
              ? const Text("No other notes available")
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: others.length,
                  itemBuilder: (_, i) {
                    final n = others[i];
                    return ListTile(
                      title: Text(n.title),
                      onTap: () {
                        setState(() {
                          widget.note.links.add({
                            "id": const Uuid().v4(),
                            "text": selected,
                            "noteId": n.key.toString(),
                            "block": "$selectedBlockIndex",
                            "start": "$s",
                            "end": "$e",
                          });
                        });
                        _safeSave(widget.note);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  // ---------- UI ----------
  void _enterEditMode() {
    setState(() {
      isEditingDescription = true;

      // ensure there is at least one text block
      int firstTextIndex =
          blocks.indexWhere((b) => (b['type'] ?? 'text') == 'text');
      if (firstTextIndex == -1) {
        blocks.add({
          "type": "text",
          "content": "",
          "controller": TextEditingController(),
          "focusNode": FocusNode(),
        });
        firstTextIndex = blocks.length - 1;
        // also reflect in note immediately
        _safeSave(widget.note);
      }

      selectedBlockIndex = firstTextIndex;

      // focus it so image button just works
      final f = blocks[firstTextIndex]['focusNode'] as FocusNode?;
      final c = blocks[firstTextIndex]['controller'] as TextEditingController?;
      if (f != null) {
        f.requestFocus();
      }
      if (c != null) {
        c.selection = TextSelection.collapsed(offset: c.text.length);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: isEditingTitle
            ? TextField(
                controller: titleController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                onSubmitted: (_) => setState(() => isEditingTitle = false),
              )
            : GestureDetector(
                onTap: () => setState(() => isEditingTitle = true),
                child: Text(widget.note.title),
              ),
        actions: [
          if (selectedText != null)
            IconButton(
              icon: const Icon(Icons.link, color: Colors.white54),
              onPressed: () async => await _showLinkOptions(selectedText!),
            )
          else if (isEditingDescription)
            IconButton(
              icon: const Icon(Icons.image_outlined, color: Colors.white54),
              onPressed: _showImageOptions,
            )
          else
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white54),
              onPressed: _enterEditMode,
            ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: blocks.length,
        itemBuilder: (context, i) {
          final b = blocks[i];
          if (b['type'] == 'text') {
            final c = b['controller'] as TextEditingController?;
            final f = b['focusNode'] as FocusNode?;
            // Safety: attach if missing (e.g., after hot restart)
            if (c == null || f == null) {
              final nc = TextEditingController(text: (b['content'] ?? '') as String);
              final nf = FocusNode();
              b['controller'] = nc;
              b['focusNode'] = nf;
              // keep listeners minimal; we won't re-wire full listeners here to avoid duplicates
            }
            final ctrl = (b['controller'] as TextEditingController);
            final foc = (b['focusNode'] as FocusNode);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: isEditingDescription
                  ? TextField(
                      controller: ctrl,
                      focusNode: foc,
                      maxLines: null,
                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "Description…",
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                      onTap: () => setState(() => selectedBlockIndex = i),
                    )
                  : SelectableText.rich(
                      TextSpan(
                        children: _buildDescriptionSpans(b['content'] ?? '', i),
                      ),
                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                      onSelectionChanged: (sel, cause) {
                        final text = (b['content'] ?? '') as String;
                        if (sel.start != sel.end &&
                            sel.start >= 0 &&
                            sel.end <= text.length) {
                          final (s, e) = _normalizedRange(text, sel.start, sel.end);
                          setState(() {
                            selectedText = text.substring(s, e);
                            selectedBlockIndex = i;
                            selectedStart = s;
                            selectedEnd = e;
                          });
                        } else {
                          setState(() {
                            selectedText = null;
                            selectedStart = null;
                            selectedEnd = null;
                          });
                        }
                      },
                    ),
            );
          } else if (b['type'] == 'image') {
            final file = File(b['path']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() => selectedBlockIndex = i);
                      showGeneralDialog(
                        context: context,
                        barrierDismissible: true,
                        barrierColor: Colors.black87,
                        pageBuilder: (_, __, ___) => GestureDetector(
                          onVerticalDragEnd: (_) => Navigator.pop(context),
                          child: Scaffold(
                            backgroundColor: Colors.black,
                            body: Center(
                              child: InteractiveViewer(child: Image.file(file)),
                            ),
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        file,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  if (isEditingDescription)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red, size: 22),
                      onPressed: () {
                        setState(() {
                          blocks.removeAt(i);
                          _safeSave(widget.note);
                        });
                      },
                    ),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF4B0082),
        onPressed: () {
          widget.note.title = titleController.text;
          _safeSave(widget.note);
          setState(() {
            isEditingDescription = false;
            selectedBlockIndex = null;
            selectedStart = null;
            selectedEnd = null;
            selectedText = null;
          });
          Navigator.pop(context, widget.note);
        },
        child: const Icon(Icons.check, color: Colors.white54),
      ),
    );
  }
}







