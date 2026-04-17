import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'roar_button.dart';

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

class SavannahScreen extends ConsumerWidget {
  const SavannahScreen({super.key});

  String _formatTime(DateTime time) {
    return '${time.year}/${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')} '
           '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

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
                      title: Text(post.text, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '音圧: ${post.volume.toStringAsFixed(1)} dB ・ ${_formatTime(post.createdAt)}',
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.thumb_up,
                              color: post.likes > 0 ? Colors.blue : Colors.grey),
                          onPressed: () => ref.read(roarProvider.notifier).likePost(index),
                        ),
                        Text('${post.likes}'),
                      ],
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
                    ...post.comments.map(
                      (comment) => Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 8),
                        child: Text(
                          '💬 ${comment.text} ・ ${_formatTime(comment.createdAt)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                      child: _CommentInput(
                        onSubmit: (comment) {
                          if (comment.isNotEmpty) {
                            ref.read(roarProvider.notifier).addComment(index, comment);
                          }
                        },
                      ),
                    ),
                    const Divider(),
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
                  createdAt: DateTime.now(),
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

class _CommentInput extends StatefulWidget {
  final Function(String) onSubmit;
  const _CommentInput({required this.onSubmit});

  @override
  State<_CommentInput> createState() => _CommentInputState();
}

class _CommentInputState extends State<_CommentInput> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'コメントを追加...',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.send, color: Colors.orange),
          onPressed: () {
            widget.onSubmit(_controller.text);
            _controller.clear();
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}