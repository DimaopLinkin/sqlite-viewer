import 'package:flutter/material.dart';

import 'ui/home_page.dart';
import 'ui/theme.dart';

void main() => runApp(const SqliteViewerApp());

class SqliteViewerApp extends StatefulWidget {
  const SqliteViewerApp({super.key, this.picker = pickAndOpenSqlite});

  final SourcePicker picker;

  @override
  State<SqliteViewerApp> createState() => _SqliteViewerAppState();
}

class _SqliteViewerAppState extends State<SqliteViewerApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SQLite Viewer',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: HomePage(
        themeMode: _themeMode,
        picker: widget.picker,
        onToggleTheme: () => setState(() {
          _themeMode = _themeMode == ThemeMode.dark
              ? ThemeMode.light
              : ThemeMode.dark;
        }),
      ),
    );
  }
}
