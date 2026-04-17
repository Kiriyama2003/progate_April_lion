//import 'package:amplify_authenticator/amplify_authenticator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'roar_button.dart';

void main() => runApp(const ProviderScope(child: MyApp()));

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override //メソッドの上書きの意味
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

class SavannahScreen extends ConsumerWidget {
  const SavannahScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(roarProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🦁 ガオガオ・サバンナ'),
        backgroundColor: Colors.orange,
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.person),
            label: const Text('Profile'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: const Text('🦁', style: TextStyle(fontSize: 30)),
                      title: Text(
                        post.text,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '音圧: ${post.volume.toStringAsFixed(1)} dB',
                      ),
                    ),
                    if (post.leaderReply != null)
                      Container(
                        margin: const EdgeInsets.only(left: 40, bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber, width: 2),
                        ),
                        child: Text(
                          '👑 リーダー: ${post.leaderReply}',
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.only(bottom: 40, top: 20),
            child: RoarButton(
              onFinished: (maxDb) {
                // AWSがないので、今はダミー投稿
                final newPost = RoarPost(
                  text: "大学一限がつらい！！",
                  volume: maxDb,
                  emotion: maxDb > 85 ? LionEmotion.angry : LionEmotion.tired,
                );
                ref.read(roarProvider.notifier).addPost(newPost);

                // 2秒後にリーダーが励ましてくれる演出
                Future.delayed(const Duration(seconds: 2), () {
                  ref
                      .read(roarProvider.notifier)
                      .updateWithReply(0, "よく吠えた！朝の狩りを制する者がサバンナを制するのだ！");
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
