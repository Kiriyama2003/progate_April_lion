import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'savannah_screen.dart';

void main() => runApp(const ProviderScope(child: MyApp()));

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a blue toolbar. Then, without quitting the app,
        // try changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (save your changes or press the "hot reload" button in
        // a Flutter-supported IDE, or press "r" in the console) to see the
        // toolbar color change to green!
        scaffoldBackgroundColor: const Color(0xFFF5F5DC),
      ), // サバンナベージュ
      home: const SavannahScreen(),
    );

    // return Authenticator(
    //   child:MaterialApp(
    //     builder: Authenticator.builder(),

    //   home: const MyHomePage(title: 'Flutter Demo Home Page'),
    //   ),
    // );
  }
}
