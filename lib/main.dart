import 'package:flutter/material.dart';
import 'screens/tab_generator_screen.dart';

void main() {
  runApp(const TabGeneratorApp());
}

class TabGeneratorApp extends StatelessWidget {
  const TabGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tab Generator Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        canvasColor: const Color(0xFF121212),
      ),
      home: const TabGeneratorScreen(),
    );
  }
}