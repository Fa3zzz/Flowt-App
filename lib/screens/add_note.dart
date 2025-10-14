import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../utils/constants.dart';


class AddNotesScreen extends StatefulWidget {
  const AddNotesScreen({super.key});

  @override
  State<AddNotesScreen> createState() => _AddNotesScreenState();
}

class _AddNotesScreenState extends State<AddNotesScreen> {
  final titleController = TextEditingController();
  final scrollController = ScrollController();
  final _uuid = const Uuid();
  final titleFocus = FocusNode();


  // each block gets a stable id
  List<Map<String, dynamic>> blocks = [
    {"id": const Uuid().v4(), "type": "text", "content": "", "controller": null}
  ];

  String? selectedText;

  // links must match Note model
  final List<Map<String, String>> links = [];

  // track selection
  int? selectedBlockIndex;
  int? selectedStart;
  int? selectedEnd;
  String? selectedBlockId;

  @override
  void initState() {
    super.initState();

    titleFocus.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    titleFocus.dispose();
    titleController.dispose();
    for (final b in blocks) {
      if (b['type'] == 'text' && b['controller'] is TextEditingController) {
        (b['controller'] as TextEditingController).dispose();
      }
    }
    super.dispose();
  }

  // --- helpers ---
  (int, int) _normalizedRange(String text, int start, int end) {
    int s = start, e = end;
    while (s < e && text[s] == ' ') s++;
    while (e > s && text[e - 1] == ' ') e--;
    return (s, e);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return;

    // ✅ Safely persist image file (works for both camera & gallery)
    final dir = await getApplicationDocumentsDirectory();
    final fileExt = pickedFile.path.split('.').last;
    final newPath = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final newFile = File(newPath);

    // 🔹 Use bytes copy for cross-platform stability
    final bytes = await pickedFile.readAsBytes();
    await newFile.writeAsBytes(bytes);
    await Future.delayed(const Duration(milliseconds: 100));

    // ⚙️ Prepare split logic
    int insertAt = blocks.length;
    String beforeText = "";
    String afterText = "";

    // 🔍 Stabilize selected block index (ensure it’s still valid)
    if (selectedBlockIndex != null &&
        selectedBlockIndex! >= 0 &&
        selectedBlockIndex! < blocks.length &&
        blocks[selectedBlockIndex!]['type'] == 'text') {
      final b = blocks[selectedBlockIndex!];
      final ctrl = b['controller'] as TextEditingController?;
      if (ctrl != null) {
        final text = ctrl.text;
        final cursor = ctrl.selection.baseOffset.clamp(0, text.length);
        beforeText = text.substring(0, cursor);
        afterText = text.substring(cursor);

        ctrl.text = beforeText;
        b['content'] = beforeText;

        insertAt = blocks.indexOf(b) + 1;
      }
    } else {
      // fallback: find last text block instead of top/bottom randomness
      final lastTextIndex = blocks.lastIndexWhere((b) => b['type'] == 'text');
      insertAt = (lastTextIndex != -1) ? lastTextIndex + 1 : blocks.length;
    }

    // ✅ Safe insertion sequence (atomic)
    setState(() {
      // 🖼 Insert image exactly after caret or last text block
      blocks.insert(insertAt, {
        "id": _uuid.v4(),
        "type": "image",
        "path": newFile.path,
      });

      // 🧱 Insert following text block to continue typing
      final newController = TextEditingController(text: afterText);
      final newFocus = FocusNode();
      newController.addListener(() {
        final idx = blocks.indexWhere((x) => x["controller"] == newController);
        if (idx != -1) blocks[idx]["content"] = newController.text;
      });

      blocks.insert(insertAt + 1, {
        "id": _uuid.v4(),
        "type": "text",
        "content": afterText,
        "controller": newController,
        "focusNode": newFocus,
      });

      // 🔁 Re-wire selection reference to the new block for next insertion
      selectedBlockIndex = insertAt + 1;
    });

    // 🎯 Auto-focus new text block
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (selectedBlockIndex != null &&
          selectedBlockIndex! >= 0 &&
          selectedBlockIndex! < blocks.length) {
        final next = blocks[selectedBlockIndex!];
        final focus = next['focusNode'] as FocusNode?;
        final ctrl = next['controller'] as TextEditingController?;
        if (focus != null && ctrl != null) {
          focus.requestFocus();
          ctrl.selection = const TextSelection.collapsed(offset: 0);
        }
      }
    });

    // 🔽 Smooth scroll to keep image visible
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    scrollController.animateTo(
      scrollController.position.maxScrollExtent + 200,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }




  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (_) => SafeArea(
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

  // ---------- Linking ----------
  Future<void> _showLinkOptions(String selected) async {
    if (selectedBlockIndex == null || selectedStart == null || selectedEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select text to link')));
      return;
    }

    final b = blocks[selectedBlockIndex!];
    final c = (b['controller'] as TextEditingController?);
    final fullText = c?.text ?? (b['content'] ?? '').toString();
    final (s, e) = _normalizedRange(fullText, selectedStart!, selectedEnd!);
    if (!(s >= 0 && e <= fullText.length && e > s)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid selection')));
      return;
    }
    final cleanSelected = fullText.substring(s, e);

    final blockId = selectedBlockId ?? (b["id"] ??= _uuid.v4()).toString();

    final existingIndex = links.indexWhere((l) =>
        l["block"] == blockId &&
        l["start"] == s.toString() &&
        l["end"] == e.toString());

    final hasExisting = existingIndex != -1;
    final existingLink = hasExisting ? links[existingIndex] : null;

    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!hasExisting) ...[
            ListTile(
              title: const Text("Link to existing note", style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.pop(context);
                _pickNoteToLink(cleanSelected, s, e);
              },
            ),
            ListTile(
              title: const Text("Create new linked note", style: TextStyle(color: Colors.white54)),
              onTap: () async {
                Navigator.pop(context);
                final newNote = Note(
                  title: cleanSelected,
                  description: "",
                  contentBlocks: [
                    {"id": _uuid.v4(), "type": "text", "content": ""}
                  ],
                  links: const [],
                );
                final key = await Hive.box<Note>('notesBox_v2').add(newNote);
                if (!mounted) return;
                setState(() {
                  links.add({
                    "id": _uuid.v4(),
                    "text": cleanSelected,
                    "noteId": key.toString(),
                    "block": blockId,
                    "start": s.toString(),
                    "end": e.toString(),
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
      ),
    );
  }

  void _pickNoteToLink(String selected, int s, int e) {
    final notesBox = Hive.box<Note>('notesBox_v2');
    final others = notesBox.values.toList();

    // 🛡️ Guard: ensure selection context exists
    if (selectedBlockIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a text block before linking')),
      );
      return;
    }

    // 🧠 Get safe block + persistent id
    final b = blocks[selectedBlockIndex!];
    if (b['id'] == null || (b['id'] as String).isEmpty) {
      b['id'] = const Uuid().v4();
    }
    final blockId = b['id'].toString();

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
                          links.add({
                            "id": const Uuid().v4(),
                            "text": selected,
                            "noteId": n.key.toString(),
                            "block": blockId,
                            "start": s.toString(),
                            "end": e.toString(),
                          });
                        });
                        Navigator.pop(context);

                        if (!mounted) return;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Linked successfully'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        });
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }


  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Add flowt"),
        actions: [
          if (selectedText != null)
            IconButton(
              icon: const Icon(Icons.link, color: Colors.white54),
              onPressed: () async => await _showLinkOptions(selectedText!),
            )
          else if (!titleFocus.hasFocus) // 👈 hide image button when typing title
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
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.3),
                    blurRadius: 12,
                    spreadRadius: 2,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextField(
                controller: titleController,
                focusNode: titleFocus,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22, // ⬆️ bigger font
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: "Title",
                  hintStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // --- note blocks ---
            ...blocks.asMap().entries.map((entry) {
              final index = entry.key;
              final b = entry.value;

              if (b["type"] == "text") {
                if (b["controller"] == null) {
                  final c = TextEditingController(text: b["content"] ?? "");
                  final f = FocusNode();

                  f.addListener(() {
                    if (f.hasFocus) {
                      setState(() => selectedBlockIndex = index);
                    }
                  });

                  c.addListener(() {
                    b["content"] = c.text;

                    // 🧹 Auto-delete empty text block when backspaced fully (except first block)
                    if (c.text.isEmpty && blocks.length > 1) {
                      final currentIndex = blocks.indexOf(b);

                      if (currentIndex > 0) {
                        if (b['focusNode'] != null &&
                            (b['focusNode'] as FocusNode).hasFocus) {
                          setState(() {
                            blocks.removeAt(currentIndex);
                          });

                          final prevIndex = currentIndex - 1;
                          if (prevIndex >= 0 &&
                              blocks[prevIndex]['type'] == 'text' &&
                              blocks[prevIndex]['controller'] is TextEditingController) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              final prevCtrl = blocks[prevIndex]['controller'] as TextEditingController;
                              prevCtrl.selection =
                                  TextSelection.collapsed(offset: prevCtrl.text.length);
                              (blocks[prevIndex]['focusNode'] as FocusNode?)?.requestFocus();
                            });
                          }

                          if (blocks.isEmpty) {
                            setState(() {
                              blocks.add({
                                "id": _uuid.v4(),
                                "type": "text",
                                "content": "",
                                "controller": TextEditingController(),
                                "focusNode": FocusNode(),
                              });
                            });
                          }
                        }
                      }
                    }

                    // 🧠 Selection handling (unchanged)
                    final sel = c.selection;
                    if (sel.start != sel.end &&
                        sel.start >= 0 &&
                        sel.end <= c.text.length) {
                      final (s, e) = _normalizedRange(c.text, sel.start, sel.end);
                      if (e > s) {
                        setState(() {
                          selectedText = c.text.substring(s, e);
                          selectedBlockIndex = index;
                          selectedBlockId = (b["id"] ??= _uuid.v4()).toString();
                          selectedStart = s;
                          selectedEnd = e;
                        });
                      }
                    } else if (selectedText != null) {
                      setState(() {
                        selectedText = null;
                        selectedBlockIndex = null;
                        selectedBlockId = null;
                        selectedStart = null;
                        selectedEnd = null;
                      });
                    }
                  });

                  b["controller"] = c;
                  b["focusNode"] = f;
                }

                final c = b["controller"] as TextEditingController;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: c,
                    focusNode: b["focusNode"],
                    style: kBaseTextStyle,
                    decoration: InputDecoration(
                      hintText: index == 0 ? "Description…" : "",
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
                          child: Image.file(file,
                              width: double.infinity, fit: BoxFit.cover),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => setState(() => blocks.removeAt(index)),
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
            if (b['id'] == null || (b['id'] as String).isEmpty) {
              b['id'] = _uuid.v4();
            }
            final id = b['id'].toString();
            final type = (b['type'] ?? 'text').toString();

            if (type == 'text') {
              return {"id": id, "type": "text", "content": (b["content"] ?? "").toString()};
            } else if (type == 'image') {
              return {"id": id, "type": "image", "path": (b["path"] ?? "").toString()};
            }
            return {"id": id, "type": "text", "content": ""};
          }).toList();

          // ✅ Keep description as the *first text block* only (like a summary)
          final firstTextBlock = contentBlocks.firstWhere(
            (b) => b["type"] == "text" && (b["content"] ?? "").trim().isNotEmpty,
            orElse: () => {"content": ""},
          );
          final description = firstTextBlock["content"] ?? "";

          final cleanLinks = links
              .where((l) => l.containsKey("block") && l.containsKey("start") && l.containsKey("end"))
              .toList();

          final newNote = Note(
            title: titleController.text.trim(),
            description: description.isNotEmpty ? description : null,
            imagePaths: imagePaths,
            contentBlocks: contentBlocks,
            links: cleanLinks.cast<Map<String, String>>(),
          );

          newNote.lastModified = DateTime.now();
          Navigator.pop(context, newNote);
        },
        child: const Icon(Icons.check, color: Colors.white54),
      ),
    );
  }
}
