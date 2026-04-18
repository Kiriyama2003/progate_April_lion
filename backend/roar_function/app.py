import json
import boto3
import os
import uuid
import time
import urllib.request
from datetime import datetime
import decimal
from boto3.dynamodb.conditions import Attr

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, decimal.Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super(DecimalEncoder, self).default(obj)

TABLE_NAME = os.environ.get('TABLE_NAME')
USER_TABLE_NAME = os.environ.get('USER_TABLE_NAME')
REACTION_TABLE_NAME = os.environ.get('REACTION_TABLE_NAME')
COMMENT_TABLE_NAME = os.environ.get('COMMENT_TABLE_NAME')
BUCKET_NAME = os.environ.get('BUCKET_NAME')

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)
user_table = dynamodb.Table(USER_TABLE_NAME)
reaction_table = dynamodb.Table(REACTION_TABLE_NAME)
comment_table = dynamodb.Table(COMMENT_TABLE_NAME)

# AI関連のクライアント
transcribe = boto3.client('transcribe')
bedrock = boto3.client('bedrock-runtime', region_name='ap-northeast-1')

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Methods': '*'
}

# --- 🎙️ 1. 文字起こし関数 ---
def transcribe_audio(s3_key):
    job_name = f"roar_transcribe_{uuid.uuid4()}"
    job_uri = f"s3://{BUCKET_NAME}/{s3_key}"
    
    try:
        transcribe.start_transcription_job(
            TranscriptionJobName=job_name,
            Media={'MediaFileUri': job_uri},
            MediaFormat='m4a', # Flutterからの形式に合わせる
            LanguageCode='ja-JP'
        )
        
        # 完了するまで待つ（簡易的なポーリング）
        while True:
            status = transcribe.get_transcription_job(TranscriptionJobName=job_name)
            job_status = status['TranscriptionJob']['TranscriptionJobStatus']
            if job_status in ['COMPLETED', 'FAILED']:
                break
            time.sleep(2) # 2秒待って再確認
            
        if job_status == 'COMPLETED':
            transcript_uri = status['TranscriptionJob']['Transcript']['TranscriptFileUri']
            # 結果のJSONをダウンロードしてテキストを抽出
            with urllib.request.urlopen(transcript_uri) as response:
                data = json.loads(response.read().decode())
                return data['results']['transcripts'][0]['transcript']
        return "（言葉にならない咆哮）"
    except Exception as e:
        print(f"Transcribe Error: {e}")
        return "（文字起こし失敗だガオ）"

# --- 🦁 2. AIアドバイス生成関数 ---
def generate_lion_advice(transcript, power_db):
    prompt = f"""
あなたはサバンナの王、熱血系のライオンです。
後輩ライオン（ユーザー）が吠えました。以下の情報をもとに、アドバイスと評価を1〜2文で熱く返信してください。

【情報】
- 吠えた言葉: 「{transcript}」
- 声のデシベル(0に近いほど大きい): {power_db} dB

【ルール】
- 語尾は「ガオ！」や「だぜ！」など熱血に。
- デシベルが-10以上なら「すげぇ声だ！」、-30以下なら「腹から声出せ！」など、数値に触れること。
"""
    
    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 200,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.7
    })

    try:
        response = bedrock.invoke_model(
            body=body, 
            modelId='anthropic.claude-3-haiku-20240307-v1:0', # 高速で安価なHaikuモデルを使用
            accept='application/json', 
            contentType='application/json'
        )
        response_body = json.loads(response.get('body').read())
        return response_body.get('content')[0].get('text')
    except Exception as e:
        print(f"Bedrock Error: {e}")
        return "通信エラーでアドバイスできないガオ！"

# --- メインハンドラ ---
def lambda_handler(event, context):
    try:
        http_method = event.get('httpMethod')
        resource = event.get('resource')
        query_params = event.get('queryStringParameters') or {}
        # ----------------------------------------
        # 🚀 投稿する (POST /roars)
        # ----------------------------------------
        if resource == '/roars' and http_method == 'POST':
            body = json.loads(event.get('body', '{}'), parse_float=decimal.Decimal)
            s3_key = body.get('s3Key', '')
            roar_power = body.get('roarPower', decimal.Decimal('0'))
            
            # 1. 🌟 文字起こしを実行（数秒待つ）
            transcript = transcribe_audio(s3_key)
            
            # 2. 🌟 AIにアドバイスをもらう
            ai_advice = generate_lion_advice(transcript, float(roar_power))
            
            post_id = str(uuid.uuid4())
            item = {
                'postId': post_id,
                'userId': body.get('userId', 'guest'),
                'userName': body.get('userName', '名無しライオン'),
                's3Key': s3_key,
                'roarPower': roar_power,
                # 3. 🌟 新しい項目をデータベースに保存
                'transcript': transcript, 
                'aiAdvice': ai_advice,    
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            }
            table.put_item(Item=item)
            
            # 返信にもAIの結果を含める
            return {
                'statusCode': 200, 
                'headers': CORS_HEADERS, 
                'body': json.dumps({
                    'message': '保存大成功！', 
                    'postId': post_id,
                    'transcript': transcript,
                    'aiAdvice': ai_advice
                })
            }

        # ----------------------------------------
        # 2. タイムライン取得 (GET /timeline)
        # ----------------------------------------
        elif resource == '/timeline' and http_method == 'GET':
            user_id = query_params.get('userId')
            
            if user_id:
                response = table.scan(FilterExpression=Attr('userId').eq(user_id))
            else:
                response = table.scan()
            posts = response.get('Items', [])

            # 🌟 ここで「最新のユーザー情報」をすべて取得
            user_response = user_table.scan()
            users = {u['userId']: u for u in user_response.get('Items', [])}

            # 🌟 投稿データの名前を、最新のユーザー情報の名前で上書きする！
            for post in posts:
                uid = post.get('userId')
                if uid in users:
                    # 最新の名前があれば上書き。なければ投稿時の名前を使う
                    post['userName'] = users[uid].get('userName', post.get('userName', '名無し'))
                    # ついでにアバターのキーも渡せるようにしておくと便利
                    post['avatarS3Key'] = users[uid].get('avatarS3Key', '')
                
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps(posts, cls=DecimalEncoder)}

        # ----------------------------------------
        # 3. プロフィール更新 (POST /profile)
        # ----------------------------------------
        elif resource == '/profile' and http_method == 'POST':
            body = json.loads(event.get('body', '{}'))
            user_id = body.get('userId')
            
            user_item = {
                'userId': user_id,
                'userName': body.get('userName', ''),
                'avatarS3Key': body.get('avatarS3Key', ''),
                'updatedAt': datetime.utcnow().isoformat() + 'Z'
            }
            user_table.put_item(Item=user_item)
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'プロフ更新成功！'})}

        # ----------------------------------------
        # 4. プロフィール取得 (GET /profile)
        # ----------------------------------------
        elif resource == '/profile' and http_method == 'GET':
            user_id = query_params.get('userId')
            response = user_table.get_item(Key={'userId': user_id})
            item = response.get('Item', {})
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps(item)}

        # ----------------------------------------
        # 5. リアクション追加 (POST /reactions)
        # ----------------------------------------
        elif resource == '/reactions' and http_method == 'POST':
            body = json.loads(event.get('body', '{}'))
            post_id = body.get('postId')
            user_id = body.get('userId')
            reaction_type = body.get('reactionType')
            
            reaction_id = f"{post_id}#{user_id}"
            
            reaction_table.put_item(Item={
                'reactionId': reaction_id,
                'postId': post_id,
                'userId': user_id,
                'reactionType': reaction_type,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
            
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'リアクション追加！'})}

        # ----------------------------------------
        # 6. リアクション削除 (DELETE /reactions)
        # ----------------------------------------
        elif resource == '/reactions' and http_method == 'DELETE':
            post_id = query_params.get('postId')
            user_id = query_params.get('userId')
            
            reaction_id = f"{post_id}#{user_id}"
            reaction_table.delete_item(Key={'reactionId': reaction_id})
            
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'リアクション削除！'})}

        # ----------------------------------------
        # 7. 投稿のリアクション一覧取得 (GET /reactions)
        # ----------------------------------------
        elif resource == '/reactions' and http_method == 'GET':
            post_id = query_params.get('postId')
            
            response = reaction_table.scan(FilterExpression=Attr('postId').eq(post_id))
            reactions = response.get('Items', [])
            
            grouped = {}
            for r in reactions:
                rt = r.get('reactionType')
                if rt not in grouped:
                    grouped[rt] = {'count': 0, 'users': []}
                grouped[rt]['count'] += 1
                grouped[rt]['users'].append(r.get('userId'))
            
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps(grouped)}

        # ----------------------------------------
        # 8. コメント追加 (POST /comments)
        # ----------------------------------------
        elif resource == '/comments' and http_method == 'POST':
            body = json.loads(event.get('body', '{}'))
            post_id = body.get('postId')
            user_id = body.get('userId')
            user_name = body.get('userName', '名無しライオン')
            content = body.get('content', '')
            parent_comment_id = body.get('parentCommentId')
            
            comment_id = str(uuid.uuid4())
            
            comment_table.put_item(Item={
                'commentId': comment_id,
                'postId': post_id,
                'userId': user_id,
                'userName': user_name,
                'content': content,
                'parentCommentId': parent_comment_id,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
            
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps({
                'message': 'コメント追加！',
                'commentId': comment_id
            })}

        # ----------------------------------------
        # 9. コメント一覧取得 (GET /comments)
        # ----------------------------------------
        elif resource == '/comments' and http_method == 'GET':
            post_id = query_params.get('postId')
            
            response = comment_table.scan(FilterExpression=Attr('postId').eq(post_id))
            comments = response.get('Items', [])
            
            comments.sort(key=lambda x: x.get('timestamp', ''), reverse=True)
            
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps(comments, cls=DecimalEncoder)}

        # ----------------------------------------
        # 10. コメント削除 (DELETE /comments)
        # ----------------------------------------
        elif resource == '/comments' and http_method == 'DELETE':
            comment_id = query_params.get('commentId')
            user_id = query_params.get('userId')
            
            comment = comment_table.get_item(Key={'commentId': comment_id}).get('Item', {})
            
            if comment.get('userId') == user_id:
                comment_table.delete_item(Key={'commentId': comment_id})
                return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'コメント削除！'})}
            else:
                return {'statusCode': 403, 'headers': CORS_HEADERS, 'body': json.dumps({'message': '権限なし'})}

        return {'statusCode': 400, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'Unsupported method'})}

    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'Internal error', 'errorDetail': str(e)})}