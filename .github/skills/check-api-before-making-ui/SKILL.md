---
name: check-api-before-making-ui

description: Roar API を使うUIを実装するときに、backend/roar_function/app.py の実際の入出力仕様に従い、API契約を壊さずにフォーム、一覧表示、送信処理、エラーハンドリングを実装する
argument-hint: "[対象画面 or 変更したいUI]"
user-invocable: true
disable-model-invocation: false
---

# Build UI with Roar API contract

このスキルは、`backend/roar_function/app.py` の API 仕様を前提として UI を実装するためのもの。  
UI は見た目だけでなく、**リクエストJSONのキー名、型、レスポンス形式、HTTPメソッド**を必ずこの API 実装に合わせる。  
推測で API を拡張したり、存在しないフィールドやエンドポイントを前提にしない。

## いつ使うか
- Roar 投稿画面を作るとき
- 投稿一覧画面を作るとき
- フォーム送信処理を実装するとき
- API クライアントコードを作るとき
- バックエンド連携を含む UI 修正を行うとき

## API 契約
このスキルでは、`backend/roar_function/app.py` を唯一の一次情報として扱う。

### 利用可能な HTTP メソッド
- `POST`
- `GET`

`OPTIONS` は CORS 用ヘッダに含まれているが、UI 実装上の業務ロジックとしては `POST` と `GET` を前提にする。

## POST の仕様
投稿作成は `POST` で行う。  
送信ボディは JSON。

### POST リクエスト body
以下のキー名をそのまま使うこと。
- `userId`
- `userName`
- `s3Key`
- `roarPower`
- `message`

### POST 各フィールド
- `userId`: 文字列。未指定時はバックエンド側で `'guest'`
- `userName`: 文字列。未指定時はバックエンド側で `'名無しライオン'`
- `s3Key`: 文字列。画像やファイルがない場合は空文字でもよい
- `roarPower`: 数値。バックエンドでは Decimal として処理される
- `message`: 文字列

### POST レスポンス
成功時:
```json
{
  "message": "ガオォォ！保存大成功！",
  "postId": "generated-uuid"
}
```

UI は成功判定時に少なくとも以下を扱えるようにすること。
- 成功メッセージ表示
- `postId` の取得
- 必要ならフォームリセットや一覧再取得

## GET の仕様
投稿一覧取得は `GET` で行う。

### GET レスポンス
レスポンス body は投稿オブジェクトの配列。  
各要素は少なくとも以下のキーを持つ前提で扱う。
- `postId`
- `userId`
- `userName`
- `s3Key`
- `roarPower`
- `message`
- `timestamp`

### GET レスポンス例
```json
[
  {
    "postId": "uuid",
    "userId": "guest",
    "userName": "名無しライオン",
    "s3Key": "",
    "roarPower": 10,
    "message": "ガオー",
    "timestamp": "2026-04-18T03:00:00.000000Z"
  }
]
```

## UI 実装ルール
- API のキー名はキャメルケースを維持し、勝手に snake_case に変換しない
- `roarPower` は UI 上では数値入力として扱う
- `roarPower` は文字列のまま送らず、可能な限り数値として扱う
- `message`、`userName`、`userId`、`s3Key` は文字列として扱う
- `timestamp` は GET 専用の表示用データとして扱い、POST では送らない
- `postId` はバックエンド採番なので、POST 時にクライアント側で生成しない
- UI は存在しない API を前提にしない。更新、削除、詳細取得 API は定義されていない
- API 仕様を変更する提案と UI 実装は分けて扱う。必要なら「現状APIではできない」と明示する

## フォーム実装ルール
フォームを作る場合は、最低限次を含める。
- `userName`
- `message`
- `roarPower`

必要に応じて次も含める。
- `userId`
- `s3Key`

ただし、UI で省略してもバックエンド側デフォルトがある項目は、無理に必須入力にしなくてよい。

## バリデーション方針
- `roarPower` は数値として解釈できることを確認する
- 空文字の数値送信は避ける。未入力時は 0 を使うか、送信前に数値へ変換する
- `message` が主目的の投稿なら、空投稿を避けるため最低限の入力確認を検討する
- 厳密な必須制約はバックエンドで強制されていないため、UI バリデーションは過剰にしない
- API 実装に存在しないバリデーションルールを勝手に追加する場合は、その旨を明示する

## 通信実装ルール
- 一覧取得は `GET`
- 新規投稿は `POST`
- `Content-Type: application/json` を使う
- `fetch` や HTTP クライアントの実装では、レスポンスの `statusCode` 相当だけでなく body の内容も確認する
- エラー時は「通信失敗」「保存失敗」など、ユーザーに分かる文言を表示する
- 500 エラー時の `errorDetail` は開発用情報として扱い、本番 UI ではそのまま露出しすぎない

## 一覧表示ルール
一覧画面では、少なくとも以下を表示候補として扱える。
- `userName`
- `message`
- `roarPower`
- `timestamp`

`s3Key` は URL そのものではない可能性があるため、**勝手に画像URLとして表示しない**。  
`s3Key` の解決方法が別途定義されていない限り、画像表示前提の UI は作らない。

## 実装前
SKILL.md
6 KB