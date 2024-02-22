# Set execution policy to Bypass
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# Define the path to your configuration file
$configFilePath = Join-Path $env:GITHUB_WORKSPACE "config.properties"

# Load content from the configuration file
$configContent = Get-Content -Path $configFilePath

# Convert the content to a hashtable
$configMap = @{}
foreach ($line in $configContent -split "`n") {
    $key, $value = $line -split '='
    $configMap[$key] = $value
}

# AWS credentials and region
$awsAccessKey = $configMap["AwsAccessKey"]
$awsSecretKey = $configMap["AwsSecretKey"]
$awsRegion = $configMap["AwsRegion"]
$lambdaFunctionArn = $configMap["LambdaFunctionArn"]
$oasFilePath = "$env:GITHUB_WORKSPACE\openapi.yaml"

# Import API from OpenAPI definition
$importApiCommand = "aws apigateway import-rest-api --no-fail-on-warnings --cli-binary-format raw-in-base64-out --body fileb://C:/Users/VMADMIN/POC/star-trek.yaml"
$importApiResult = Invoke-Expression $importApiCommand | ConvertFrom-Json
$apiId = $importApiResult.id
$apiName = $importApiResult.name

# Get the list of resources
$resourcesCommand = "aws apigateway get-resources --rest-api-id $apiId"
$resourcesResult = Invoke-Expression $resourcesCommand | ConvertFrom-Json

# Check if resources are present
if ($resourcesResult.items) {
    # Iterate through each resource
    foreach ($resource in $resourcesResult.items) {
        Write-Host "Resource ID: $($resource.id)"
        Write-Host "Resource Path: $($resource.path)"
        
        # Check if resource methods are present
        if ($resource.resourceMethods) {
            # Iterate through each method for the current resource
            foreach ($methodKey in $resource.resourceMethods.PSObject.Properties) {
                Write-Host "HTTP Method: $($methodKey.Name)"
                
                # Access other properties specific to the method using $resource.resourceMethods[$methodKey.Name]
                
                # Now you can perform actions based on each resource and its methods
            }
        }
        else {
            Write-Host "No resource methods found for resource: $($resource.path)"
        }
    }
}
else {
    Write-Host "No resources found for API ID: $apiId"
}

$methodResource = $resourcesResult.items | Where-Object { $_.resourceMethods -ne $null }

# Debugging: Display information about $methodResource
Write-Host "Debug: Method Resource - $($methodResource | ConvertTo-Json -Depth 5)"

# Use existing API key
$existingApiKey = $configMap["ApiKey"]
$apiKey = $existingApiKey

$resourceId = $methodResource.id
# Iterate through each resource
foreach ($resource in $resourcesResult.items) {
    Write-Host "Processing resource: $($resource.path)"

    # Check if resource methods are present
    if ($resource.resourceMethods) {
        # Iterate through each method for the current resource
        foreach ($methodKey in $resource.resourceMethods.PSObject.Properties) {
            $httpMethod = $methodKey.Name
            Write-Host "HTTP Method: $($httpMethod)"

            # Access other properties specific to the method using $resource.resourceMethods[$methodKey.Name]
            # Now you can perform actions based on each resource and its methods

            # Your integration logic here
            $createIntegrationCommand = "aws apigateway put-integration --rest-api-id $apiId --resource-id $($resource.id) --http-method $httpMethod --type AWS_PROXY --integration-http-method POST --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/$lambdaFunctionArn/invocations"

            try {
                $createIntegrationResult = Invoke-Expression $createIntegrationCommand
                Write-Host "Integration created successfully for $($httpMethod) method on $($resource.path)."
            } catch {
                Write-Host "Integration creation failed for $($httpMethod) method on $($resource.path). Error: $_"
            }
        }
    }
    else {
        Write-Host "No resource methods found for resource: $($resource.path)"
    }
}

# Set the desired stage name
$stageName = $configMap["StageName"]

# Obtain the ID of the existing usage plan
$existingUsagePlanName = $configMap["UsagePlanName"]
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

# Enable metric
$alarmActionArn = "arn:aws:sns:us-east-1:851725349882:API"  # Replace with your SNS topic ARN
Write-CWMetricAlarm -AlarmName $configMap["AlarmName"] -MetricName $metricName -Namespace $namespace -Dimensions $dimensions -Statistic Average -Period 300 -Threshold 200 -ComparisonOperator GreaterThanThreshold -EvaluationPeriods 2 -AlarmActions $alarmActionArn -AlarmDescription 'High API latency detected'

Write-Host "API created successfully with ID: $apiId"
Write-Host "API Key used: $apiKey"
Write-Host "Lambda function integrated successfully"
Write-Host "API deployed to stage: $stageName"
