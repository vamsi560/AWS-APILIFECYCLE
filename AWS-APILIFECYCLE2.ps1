# AWS credentials and region
$awsAccessKey = "AKIA4MTWJOP5BEITHBVV"
$awsSecretKey = "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"
$awsRegion = "us-east-1"
$lambdaFunctionArn = "arn:aws:lambda:us-east-1:851725349882:function:dev-portal-DevPortalLambdaFunction-LIKU32SglT3s"

# Import API from OpenAPI definition
$importApiCommand = "aws apigateway import-rest-api --no-fail-on-warnings --cli-binary-format raw-in-base64-out --body fileb://C:/Users/VMADMIN/POC/petstore.yaml"
$importApiResult = Invoke-Expression $importApiCommand | ConvertFrom-Json
$apiId = $importApiResult.id
$apiName = $importApiResult.name

# Get the list of resources
$resourcesCommand = "aws apigateway get-resources --rest-api-id $apiId"
$resourcesResult = Invoke-Expression $resourcesCommand | ConvertFrom-Json

$methodResource = $resourcesResult.items | Where-Object { $_.resourceMethods -ne $null }

# Debugging: Display information about $methodResource
Write-Host "Debug: Method Resource - $($methodResource | ConvertTo-Json -Depth 5)"

# Use existing API key
$existingApiKey = "72KjYUm1DZ3vBFBpHy5M73D0QBdYQqfW3qWcAMIG"
$apiKey = $existingApiKey

$resourceId = $methodResource.id

# Extract HTTP methods from nested properties
$methodResource = $resourcesResult.items | Where-Object { $_.resourceMethods -ne $null }

$integrationHttpMethod = "POST"  # Change this to the specific HTTP method you want to integrate
$createIntegrationCommand = "aws apigateway put-integration --rest-api-id $apiId --resource-id $resourceId --http-method $integrationHttpMethod --type AWS_PROXY --integration-http-method POST --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/$lambdaFunctionArn/invocations"
try {
    $createIntegrationResult = Invoke-Expression $createIntegrationCommand
    Write-Host "Integration created successfully."
} catch {
    Write-Host "Integration creation failed. Error: $_"
}

# Set the desired stage name
$stageName = "Development"

# Obtain the ID of the existing usage plan
$existingUsagePlanName = "devportal"
$existingUsagePlanId = (aws apigateway get-usage-plans --query "items[?name=='$existingUsagePlanName'].id" | ConvertFrom-Json)

# Deploy API to Stage
$deployStageCommand = "aws apigateway create-deployment --rest-api-id $apiId --stage-name $stageName"
Invoke-Expression $deployStageCommand

# Enable CloudWatch metrics for your API stage
$metricName = "Latency"
$namespace = "AWS/ApiGateway"

# Construct the Dimensions object
$dimensions = @()

# Add dimensions to the array
$apiNameDimension = New-Object 'Amazon.CloudWatch.Model.Dimension'
$apiNameDimension.Name = "ApiName"
$apiNameDimension.Value = $apiName  # Replace with the actual API name
$dimensions += $apiNameDimension

$stageNameDimension = New-Object 'Amazon.CloudWatch.Model.Dimension'
$stageNameDimension.Name = "StageName"
$stageNameDimension.Value = $stageName  # Replace with the actual stage name
$dimensions += $stageNameDimension

# Enable metric
$alarmActionArn = "arn:aws:sns:us-east-1:851725349882:API"  # Replace with your SNS topic ARN
Write-CWMetricAlarm -AlarmName MyApiLatencyAlarm -MetricName $metricName -Namespace $namespace -Dimensions $dimensions -Statistic Average -Period 300 -Threshold 200 -ComparisonOperator GreaterThanThreshold -EvaluationPeriods 2 -AlarmActions $alarmActionArn -AlarmDescription 'High API latency detected'

Write-Host "API created successfully with ID: $apiId"
Write-Host "API Key used: $apiKey"
Write-Host "Lambda function integrated successfully"
Write-Host "API deployed to stage: $stageName"
