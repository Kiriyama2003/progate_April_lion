AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: Gao Gao Savannah Backend

Resources:
  # 1. 音声保存バケット
  SavannahBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "gaogao-savannah-${AWS::AccountId}"
      CorsConfiguration:
        CorsRules:
          - AllowedHeaders: ['*']
            AllowedMethods: [GET, PUT, POST, DELETE, HEAD]
            AllowedOrigins: ['*']

  # 2. 投稿データDB
  RoarTable:
    Type: AWS::Serverless::SimpleTable
    Properties:
      PrimaryKey: { Name: postId, Type: String }

  # 3. ユーザー認証 (Cognito)
  GaoGaoUserPool:
    Type: AWS::Cognito::UserPool
    Properties:
      AutoVerifiedAttributes: [email]
      UsernameAttributes: [email]

  GaoGaoUserPoolClient:
    Type: AWS::Cognito::UserPoolClient
    Properties:
      UserPoolId: !Ref GaoGaoUserPool
      ClientName: GaoGaoAppClient

  # 4. Lambda関数
  GaoGaoFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: roar_function/
      Handler: app.lambda_handler
      Runtime: python3.11
      Timeout: 60
      Environment:
        Variables:
          TABLE_NAME: !Ref RoarTable
          BUCKET_NAME: !Ref SavannahBucket
      Policies:
        - DynamoDBCrudPolicy: { TableName: !Ref RoarTable }
        - S3FullAccessPolicy: { BucketName: !Ref SavannahBucket }
        - AmazonBedrockFullAccess # AI用
      Events:
        PostRoar:
          Type: Api
          Properties: { Path: /roars, Method: post }
        GetTimeline:
          Type: Api
          Properties: { Path: /timeline, Method: get }

Outputs:
  ApiUrl:
    Value: !Sub "https://${ServerlessRestApi}.execute-api.${AWS::Region}.amazonaws.com/Prod/"
  UserPoolId:
    Value: !Ref GaoGaoUserPool
  ClientId:
    Value: !Ref GaoGaoUserPoolClient