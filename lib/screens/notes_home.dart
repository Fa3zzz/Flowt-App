import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/note.dart';
import 'add_note.dart';
import 'note_detail.dart';
import 'search_notes.dart';


class NotesHome extends StatefulWidget {
  const NotesHome({super.key});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  final notesBox = Hive.box<Note>('notesBox_v2');

  final List<String> _monthNameList = const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  String _sectionLabel(DateTime noteDate) {
    final now = DateTime.now();
    final diff = now.difference(noteDate).inDays;

    if (diff == 0 &&
        noteDate.day == now.day &&
        noteDate.month == now.month &&
        noteDate.year == now.year) {
      return "Today";
    } else if (diff == 1 &&
        noteDate.month == now.month &&
        noteDate.year == now.year) {
      return "Yesterday";
    } else if (noteDate.year == now.year) {
      return _monthNameList[noteDate.month - 1];
    } else {
      return noteDate.year.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: const Text("Flowt"),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchNotesScreen()),
              );
            },
          )
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: notesBox.listenable(),
        builder: (context, Box<Note> box, _) {
          if (box.isEmpty) {
            return const Center(
              child: Text(
                "No flowts yet",
                style: TextStyle(color: Colors.white54, fontSize: 18),
              ),
            );
          }

          final notes = box.values.toList()
            ..sort((a, b) => b.lastModified.compareTo(a.lastModified));

          final Map<String, List<Note>> groupedNotes = {};
          for (var note in notes) {
            final label = _sectionLabel(note.lastModified);
            groupedNotes.putIfAbsent(label, () => []).add(note);
          }

          final orderedKeys = groupedNotes.keys.toList()
            ..sort((a, b) {
              final now = DateTime.now();
              DateTime getDate(String label) {
                if (label == "Today") return now;
                if (label == "Yesterday") return now.subtract(const Duration(days: 1));
                final monthIndex = _monthNameList.indexOf(label);
                if (monthIndex != -1) return DateTime(now.year, monthIndex + 1);
                final yearNum = int.tryParse(label);
                if (yearNum != null) return DateTime(yearNum);
                return now;
              }

              return getDate(b).compareTo(getDate(a));
            });

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: orderedKeys.length,
            itemBuilder: (context, sectionIndex) {
              final sectionTitle = orderedKeys[sectionIndex];
              final sectionNotes = groupedNotes[sectionTitle]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      sectionTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: (sectionTitle == "Today" || sectionTitle == "Yesterday")
                            ? 28
                            : 24,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepPurple.withOpacity(0.25),
                          blurRadius: 8,
                          spreadRadius: 1,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < sectionNotes.length; i++) ...[
                          Dismissible(
                            key: ValueKey(sectionNotes[i].key),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.redAccent,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) async {
                              await Future.delayed(const Duration(milliseconds: 100));
                              sectionNotes[i].delete();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Note deleted'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              title: Text(
                                sectionNotes[i].title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (sectionTitle == "2024" ||
                                      int.tryParse(sectionTitle) != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Text(
                                        "${sectionNotes[i].lastModified.day} ${_monthNameList[sectionNotes[i].lastModified.month - 1]}",
                                        style: const TextStyle(
                                            color: Colors.white38, fontSize: 13),
                                      ),
                                    ),
                                  Expanded(
                                    child: sectionNotes[i].description != null &&
                                            sectionNotes[i].description!.isNotEmpty
                                        ? Text(
                                            sectionNotes[i].description!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white38),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                final updatedNote = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        NoteDetailScreen(note: sectionNotes[i]),
                                  ),
                                );
                                if (updatedNote != null) {
                                  sectionNotes[i].title = updatedNote.title;
                                  sectionNotes[i].description =
                                      updatedNote.description;
                                  sectionNotes[i].save();
                                }
                              },
                            ),
                          ),
                          if (i < sectionNotes.length - 1)
                            Container(
                              height: 0.6,
                              color: Colors.white38,
                              margin: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
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
        child: const Icon(Icons.add, color: Colors.white54),
      ),
    );
  }
}

