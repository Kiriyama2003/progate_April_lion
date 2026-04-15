---
name: implementing-new-function
description: Flutterプロジェクトで新機能を実装するとき、pubspec.yaml・pubspec.lock・pub コマンドで依存関係の実バージョンを確認し、そのバージョンに合うAPIと構文で実装する
when_to_use: Flutterアプリで新しいpackageを導入する時、既存packageを使って新機能を実装する時、サンプルコードを流用する時、breaking changesやdeprecated APIの混入を避けたい時に使う
argument-hint: "[package名 or 対象ファイル]"
user-invocable: true
disable-model-invocation: false
---

# Flutterで実インストール版に合わせて実装する

Flutterプロジェクトでは、推測や記憶で package の API を書かず、**このプロジェクトで実際に解決されているバージョン**に合わせて実装する。

## いつ使うか
- 新しい package を導入するとき
- 既存 package を使って新機能を追加するとき
- pub.dev や記事のサンプルコードを参考にするとき
- メジャーバージョン差分、deprecated API、breaking changes が疑われるとき

## 必須ルール
- 実装前に `pubspec.yaml` と `pubspec.lock` を確認する
- package のバージョンは、**宣言された制約**ではなく、まず **実際に解決されたバージョン** を基準に判断する
- 実装時は、そのバージョンに対応する公式ドキュメント・pub.dev・migration guide・release notes を優先して参照する
- バージョン未確認のまま import、コンストラクタ、named parameter、初期化手順、Widget名、API名を推測で書かない
- 既存コードベースに同じ package の利用箇所がある場合は、その記法と整合するように実装する
- deprecated と書かれているAPIは新規コードに使わない
- breaking changes がある場合は、必ず現在の解決バージョンに一致する書き方を採用する

## 優先順位
1. `pubspec.lock` に記録された実解決バージョン
2. `pubspec.yaml` の依存制約と SDK 制約
3. `dart pub deps` / `flutter pub deps` で見える依存関係
4. 対象バージョンの公式ドキュメント、pub.dev、migration guide、release notes
5. リポジトリ内の既存実装
6. ブログ、Q&A、外部記事

## 手順
1. `pubspec.yaml` を確認し、対象 package と SDK 制約を把握する
2. `pubspec.lock` を確認し、対象 package の実解決バージョンを特定する
3. 必要なら `dart pub deps` で依存関係を確認する
4. package をまだ追加していない場合は、手書きで version を決め打ちせず、まず `flutter pub add <package>` を検討する
5. 実解決バージョンに対応する公式情報を確認する
6. deprecated / migration / breaking changes の有無を確認する
7. そのバージョンに合う import・Widget・API・引数名・初期化手順で実装する
8. 提案前に、確認した package 名・バージョン・参照した情報の種類を短く添える

## 確認コマンド例
- 依存関係取得: `flutter pub get`
- package追加: `flutter pub add <package>`
- 依存関係確認: `dart pub deps`
- 古い制約や更新候補の確認: `dart pub outdated`

## 出力ルール
コードを提示する前に、次を短く明記する。
- package 名
- 確認したバージョン
- 参照した情報源（pubspec.lock / dart pub deps / pub.dev / migration guide / release notes / 既存コード）

## 禁止事項
- `pubspec.yaml` の制約だけを見て、実解決バージョンを確認せずに実装しない
- pub.dev の最新サンプルを、そのまま現在のプロジェクトに流用しない
- 旧版と新版の API を混在させない
- package を追加する時に、必要もないのに手で version を決め打ちして `pubspec.yaml` へ直書きしない
- Flutter / Dart SDK 制約を無視して package API を採用しない