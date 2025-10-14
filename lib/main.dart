import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/note.dart';
import 'screens/notes_home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(NoteAdapter());
  await Hive.openBox<Note>(
    'notesBox_v2',
    compactionStrategy: (total, deleted) => deleted > 20,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flowt',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF4B0082),
          foregroundColor: Colors.white,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF4B0082),
          foregroundColor: Colors.white,
        ),
      ),
      home: const NotesHome(),
    );
  }
}
