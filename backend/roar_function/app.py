import json
import boto3
import os
import uuid
from datetime import datetime
import decimal
from boto3.dynamodb.conditions import Attr # 検索用の魔法

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, decimal.Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super(DecimalEncoder, self).default(obj)

TABLE_NAME = os.environ.get('TABLE_NAME')
USER_TABLE_NAME = os.environ.get('USER_TABLE_NAME')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)
user_table = dynamodb.Table(USER_TABLE_NAME)

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Methods': '*'
}

def lambda_handler(event, context):
    try:
        http_method = event.get('httpMethod')
        resource = event.get('resource') # 👈 安全なパス判定
        query_params = event.get('queryStringParameters') or {}

        # ----------------------------------------
        # 1. 投稿する (POST /roars)
        # ----------------------------------------
        if resource == '/roars' and http_method == 'POST':
            body = json.loads(event.get('body', '{}'), parse_float=decimal.Decimal)
            
            post_id = str(uuid.uuid4())
            item = {
                'postId': post_id,
                'userId': body.get('userId', 'guest'),
                'userName': body.get('userName', '名無しライオン'),
                's3Key': body.get('s3Key', ''),
                'roarPower': body.get('roarPower', decimal.Decimal('0')),
                'message': body.get('message', ''),
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            }
            table.put_item(Item=item)
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps({'message': '保存成功！', 'postId': post_id})}

        # ----------------------------------------
        # 2. タイムライン取得 (GET /timeline)
        # ----------------------------------------
        elif resource == '/timeline' and http_method == 'GET':
            user_id = query_params.get('userId')
            
            # userIdが指定されていればその人だけ、なければ全員分！
            if user_id:
                response = table.scan(FilterExpression=Attr('userId').eq(user_id))
            else:
                response = table.scan()
                
            items = response.get('Items', [])
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps(items, cls=DecimalEncoder)}

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

        return {'statusCode': 400, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'Unsupported method'})}

    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'Internal error', 'errorDetail': str(e)})}