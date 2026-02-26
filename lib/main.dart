import 'package:flutter/material.dart';

import 'pages/home_page.dart';

/// 应用入口。
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  /// 构建应用根节点。
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Ruffle',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      builder: (context, child) {
        return Material(
          type: MaterialType.transparency,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomePage(),
    );
  }
}
