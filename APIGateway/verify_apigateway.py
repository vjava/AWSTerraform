import boto3
import json

region = 'us-east-1'
rest_api_id = 'lk3qtm7jda'
http_api_id = 'fiq1dxxbrc'
ws_api_id = '3v0buqwind'
vpc_link_id = 'f2jvav'

apigw_v1 = boto3.client('apigateway', region_name=region)
apigw_v2 = boto3.client('apigatewayv2', region_name=region)

print("\n" + "="*70)
print("VERIFYING API GATEWAY CONFIGURATIONS")
print("="*70)

try:
    # 1. Verify REST API & Stage Settings (Caching & Throttling)
    rest_api = apigw_v1.get_rest_api(restApiId=rest_api_id)
    print(f"REST API Name:            {rest_api.get('name')}")
    
    stage_info = apigw_v1.get_stage(restApiId=rest_api_id, stageName='prod')
    print(f"Cache Cluster Enabled:    {stage_info.get('cacheClusterEnabled')}")
    print(f"Cache Cluster Size:       {stage_info.get('cacheClusterSize')}")

    # Method Throttling Settings
    method_settings = stage_info.get('methodSettings', {}).get('*/*', {})
    print(f"Rest Rate Limit:          {method_settings.get('throttlingRateLimit')}")
    print(f"Rest Burst Limit:         {method_settings.get('throttlingBurstLimit')}")
    print("-" * 70)

    # 2. Verify HTTP API
    http_api = apigw_v2.get_api(ApiId=http_api_id)
    print(f"HTTP API Name:            {http_api.get('Name')}")
    print(f"Protocol Type:            {http_api.get('ProtocolType')}")
    print("-" * 70)

    # 3. Verify WebSocket API
    ws_api = apigw_v2.get_api(ApiId=ws_api_id)
    print(f"WebSocket API Name:       {ws_api.get('Name')}")
    print(f"Protocol Type:            {ws_api.get('ProtocolType')}")
    print(f"Route Selection Expr:     {ws_api.get('RouteSelectionExpression')}")
    print("-" * 70)

    # 4. Verify VPC Link
    vpc_link = apigw_v1.get_vpc_link(vpcLinkId=vpc_link_id)
    print(f"VPC Link ID:              {vpc_link.get('id')}")
    print(f"VPC Link Status:          {vpc_link.get('status')}")
    print("="*70)

    print("\nAPI Gateway Verification Completed Successfully!")

except Exception as e:
    print(f"Error during verification: {e}")