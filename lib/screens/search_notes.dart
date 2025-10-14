import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../models/note.dart';
import 'note_detail.dart';


class SearchNotesScreen extends StatefulWidget {
  const SearchNotesScreen({super.key});

  @override
  State<SearchNotesScreen> createState() => _SearchNotesScreenState();
}

class _SearchNotesScreenState extends State<SearchNotesScreen> {
  final TextEditingController searchController = TextEditingController();
  List<Note> allNotes = [];
  List<Map<String, dynamic>> results = [];
  String? fadedHighlight; // <-- to track when highlight should fade

  @override
  void initState() {
    super.initState();
    final box = Hive.box<Note>('notesBox_v2');
    allNotes = box.values.toList();
  }

  void _search(String query) {
    final lower = query.toLowerCase();
    final matches = <Map<String, dynamic>>[];

    for (final note in allNotes) {
      final title = note.title.toLowerCase();
      final desc = note.description?.toLowerCase() ?? "";

      // 🟣 Match in title
      if (title.contains(lower)) {
        matches.add({
          "note": note,
          "matchType": "title",
          "highlight": query,
          "context": note.title,
        });
      }

      // 🟣 Match in description (multi-hit safe version)
      if (desc.contains(lower)) {
        final full = note.description!;
        int idx = 0;
        while (true) {
          idx = desc.indexOf(lower, idx);
          if (idx == -1) break;

          int start = full.lastIndexOf('.', idx);
          if (start == -1) start = (idx - 40).clamp(0, full.length);
          int end = full.indexOf('.', idx + lower.length);
          if (end == -1) end = (idx + 250).clamp(0, full.length);
          start = start.clamp(0, full.length);
          end = end.clamp(start, full.length);


          if (end > start && end <= full.length && start >= 0) {
            final snippet = full.substring(start, end).trim();
            matches.add({
              "note": note,
              "matchType": "description",
              "highlight": query,
              "context": snippet,
              "matchIndex": idx,
            });
          }

          idx += lower.length;
        }
      }
    }

    // 🧠 Sort priority: title > description
    matches.sort((a, b) {
      if (a["matchType"] == "title" && b["matchType"] != "title") return -1;
      if (a["matchType"] != "title" && b["matchType"] == "title") return 1;
      return a["context"].toString().compareTo(b["context"].toString());
    });

    setState(() {
      results = matches;
      fadedHighlight = null;
    });

    // 🎨 Fade highlight smoothly
    if (query.isNotEmpty) {
      const fadeDuration = Duration(seconds: 2);
      const steps = 20;
      final stepTime = fadeDuration.inMilliseconds ~/ steps;

      Future.delayed(const Duration(seconds: 1), () async {
        for (int i = 0; i <= steps; i++) {
          await Future.delayed(Duration(milliseconds: stepTime));
          if (!mounted || searchController.text != query) return;
          setState(() => fadedHighlight = "$query|${1 - (i / steps)}");
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: TextField(
          controller: searchController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Search notes...",
            hintStyle: TextStyle(color: Colors.white54),
            border: InputBorder.none,
          ),
          onChanged: _search,
        ),
      ),
      body: results.isEmpty
          ? const Center(
              child: Text(
                "No matches found",
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              itemCount: results.length,
              itemBuilder: (_, i) {
                final match = results[i];
                final note = match["note"] as Note;
                final highlight = match["highlight"] as String;
                final contextText = match["context"] as String;

                final lower = contextText.toLowerCase();
                final idx = lower.indexOf(highlight.toLowerCase());
                InlineSpan textSpan;

                if (idx != -1) {
                  // Extract opacity from fadedHighlight (e.g., "query|0.6")
                  double fadeValue = 1.0;
                  if (fadedHighlight != null && fadedHighlight!.startsWith(highlight)) {
                    final parts = fadedHighlight!.split('|');
                    if (parts.length == 2) fadeValue = double.tryParse(parts[1]) ?? 1.0;
                  }

                  textSpan = TextSpan(children: [
                    TextSpan(
                      text: contextText.substring(0, idx),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    TextSpan(
                      text: contextText.substring(idx, idx + highlight.length),
                      style: const TextStyle(
                        color: Color(0xFF9B30FF),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    TextSpan(
                      text: contextText.substring(idx + highlight.length),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ]);
                } else {
                  textSpan = TextSpan(
                    text: contextText,
                    style: const TextStyle(color: Colors.white54),
                  );
                }


                return Card(
                  color: Colors.grey[900],
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    title: Text(
                      note.title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: RichText(text: textSpan),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NoteDetailScreen(
                            note: note,
                            highlightQuery: highlight,
                            matchGlobalOffset: match["matchIndex"], // ✅ added for precise scroll
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
