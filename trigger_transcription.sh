#!/bin/bash

# Define variables
RESOURCE_GROUP="rg-transcription-demo-ae"
COGNITIVE_ACCOUNT="cogs-transcription-speech-ae"
STORAGE_ACCOUNT="sttranscriptiondemoae"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:?Error: Subscription ID is missing or empty. Please set the environment variable.}"
LOCATION="australiaeast"
MODEL_ID=""
TOP=100
SKIP=0
TOTAL_MODELS_CHECKED=0

# Get the Subscription Key
echo -e "\033[1;34m🔑 Retrieving Subscription Key...\033[0m"
SUBSCRIPTION_KEY=$(az cognitiveservices account keys list --name $COGNITIVE_ACCOUNT --resource-group $RESOURCE_GROUP --subscription $SUBSCRIPTION_ID --query "key1" --output tsv)

# Check if the key retrieval was successful
if [ -z "$SUBSCRIPTION_KEY" ]; then
    echo -e "\033[1;31m❌ Failed to retrieve the Subscription Key. Please check your Azure CLI setup.\033[0m"
    exit 1
fi

echo -e "\033[1;32m✅ Subscription Key retrieved successfully!\033[0m"


# Prerequisite checks
echo -e "\033[1;34m🔍 Checking security best practices...\033[0m"

# Check if public access to blobs is disabled
BLOB_PUBLIC_ACCESS=$(az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query "allowBlobPublicAccess" --output tsv)
if [ "$BLOB_PUBLIC_ACCESS" == "false" ]; then
    echo -e "\033[1;32m✅ Public access to blobs is disabled.\033[0m"
else
    echo -e "\033[1;31m❌ Public access to blobs is not disabled. Please disable it in the Azure portal.\033[0m"
    exit 1
fi

# Check if storage account key access is disabled
KEY_ACCESS=$(az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query "allowSharedKeyAccess" --output tsv)
if [ "$KEY_ACCESS" == "false" ]; then
    echo -e "\033[1;32m✅ Storage account key access is disabled.\033[0m"
else
    echo -e "\033[1;31m❌ Storage account key access is not disabled. Please disable it in the Azure portal.\033[0m"
    exit 1
fi

NETWORK_RULES=$(az storage account network-rule list --account-name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query "defaultAction" --output tsv)
if [ "$NETWORK_RULES" == "Allow" ]; then
    echo -e "\033[1;31m❌ Access to all external network traffic is allowed. Please restrict it in the Azure portal.\033[0m"
    exit 1
else
    echo -e "\033[1;32m✅ Access to all external network traffic is restricted.\033[0m"
fi


# Check if Trusted Azure services security mechanism is configured
TRUSTED_SERVICES=$(az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query "networkRuleSet.bypass" --output tsv)
if [ "$TRUSTED_SERVICES" == "AzureServices" ] || [[ "$TRUSTED_SERVICES" == *"AzureServices"* ]]; then
    echo -e "\033[1;32m✅ Trusted Azure services security mechanism is configured.\033[0m"
else
    echo -e "\033[1;31m❌ Trusted Azure services security mechanism is not configured. Please configure it in the Azure portal.\033[0m"
    exit 1
fi


# Fetch available Whisper models
echo -e "\033[1;34m🔍 Fetching available Whisper models...\033[0m"

while true; do
    MODELS_RESPONSE=$(curl -s -X GET "https://$LOCATION.api.cognitive.microsoft.com/speechtotext/v3.2-preview.2/models/base?top=$TOP&skip=$SKIP" -H "Ocp-Apim-Subscription-Key: $SUBSCRIPTION_KEY")
    
    # Check if the models retrieval was successful
    if [[ "$MODELS_RESPONSE" == *"error"* ]]; then
        echo -e "\033[1;31m❌ Failed to retrieve models. Please check the response for details:\033[0m"
        echo "$MODELS_RESPONSE"
        exit 1
    else
        echo -e "\033[1;32m⏳ Models retrieved successfully! (Page: $((SKIP / TOP + 1)))\033[0m"
        TOTAL_MODELS_CHECKED=$((TOTAL_MODELS_CHECKED + $(echo "$MODELS_RESPONSE" | jq '.values | length')))
        MODEL_ID=$(echo "$MODELS_RESPONSE" | jq -r '.values[] | select(.displayName | contains("Whisper")) | .self')
        
        if [ -n "$MODEL_ID" ]; then
            echo -e "\033[1;32m✅ Whisper model found after checking $TOTAL_MODELS_CHECKED models.\033[0m"
            break
        fi
        
        # Check if there are more models to fetch
        MODELS_COUNT=$(echo "$MODELS_RESPONSE" | jq '.values | length')
        if [ "$MODELS_COUNT" -lt "$TOP" ]; then
            break
        fi
        
        SKIP=$((SKIP + TOP))
    fi
done

# Check if a Whisper model was found
if [ -z "$MODEL_ID" ]; then
    echo -e "\033[1;31m❌ No Whisper models found. Please check your Azure setup.\033[0m"
    exit 1
fi

# Define the transcription request
TRANSCRIPTION_REQUEST=$(cat <<EOF
{
  "contentUrls": [
    "https://$STORAGE_ACCOUNT.blob.core.windows.net/audiofiles-source/test.mp3"
  ],
  "locale": "de-CH",
  "displayName": "My Transcription",
  "model": {
    "self": "$MODEL_ID"
  },
  "properties": {}
}
EOF
)

# Trigger the transcription
echo -e "\033[1;34m🚀 Triggering Transcription using model $MODEL_ID...\033[0m"
RESPONSE=$(curl -s -X POST -H "Ocp-Apim-Subscription-Key: $SUBSCRIPTION_KEY" -H "Content-Type: application/json" -d "$TRANSCRIPTION_REQUEST" "https://$LOCATION.api.cognitive.microsoft.com/speechtotext/v3.2-preview.2/transcriptions")

# Check the response
if [[ "$RESPONSE" == *"error"* ]]; then
    echo -e "\033[1;31m❌ Transcription request failed. Please check the response for details:\033[0m"
    echo "$RESPONSE"
    exit 1
else
    echo -e "\033[1;32m✅ Transcription request was successful!\033[0m"
    TRANSCRIPTION_ID=$(echo "$RESPONSE" | jq -r '.self' | awk -F'/' '{print $NF}')
    echo -e "\033[1;34m📄 Response:\033[0m $RESPONSE"
fi

# Check transcription status and fetch results
echo -e "\033[1;34m🔍 Checking transcription status...\033[0m"
STATUS=""

while [ "$STATUS" != "Succeeded" ]; do
    STATUS_RESPONSE=$(curl -s -X GET "https://$LOCATION.api.cognitive.microsoft.com/speechtotext/v3.2-preview.2/transcriptions/$TRANSCRIPTION_ID" -H "Ocp-Apim-Subscription-Key: $SUBSCRIPTION_KEY")
    STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status')
    echo -e "\033[1;34m⏳ Current status: $STATUS\033[0m"
    if [ "$STATUS" == "Failed" ]; then
        echo -e "\033[1;31m❌ Transcription failed. Please check the response for details:\033[0m"
        echo "$STATUS_RESPONSE"
        exit 1
    fi
    sleep 5 
done

# Get transcription results
echo -e "\033[1;34m📄 Fetching transcription results...\033[0m"
RESULTS_RESPONSE=$(curl -s -X GET "https://$LOCATION.api.cognitive.microsoft.com/speechtotext/v3.2-preview.2/transcriptions/$TRANSCRIPTION_ID/files" -H "Ocp-Apim-Subscription-Key: $SUBSCRIPTION_KEY")

# Display results
TRANSCRIPT_URL=$(echo "$RESULTS_RESPONSE" | jq -r '.values[] | select(.kind == "Transcription") | .links.contentUrl')
REPORT_URL=$(echo "$RESULTS_RESPONSE" | jq -r '.values[] | select(.kind == "TranscriptionReport") | .links.contentUrl')

# Fetch and display the transcription content
TRANSCRIPT_CONTENT=$(curl -s "$TRANSCRIPT_URL")

echo -e "\033[1;32m✅ Transcription results:\033[0m"
echo "$TRANSCRIPT_CONTENT"

echo -n "Would you like to delete the transcription job now? (yes/CTRL+C to cancel): "
read DELETE_JOB

echo -e "\033[1;34m🗑 Deleting transcription job...\033[0m"
DELETE_RESPONSE=$(curl -s -X DELETE "https://$LOCATION.api.cognitive.microsoft.com/speechtotext/v3.2-preview.2/transcriptions/$TRANSCRIPTION_ID" -H "Ocp-Apim-Subscription-Key: $SUBSCRIPTION_KEY")

if [ -z "$DELETE_RESPONSE" ]; then
    echo -e "\033[1;32m✅ Transcription job deleted successfully!\033[0m"
else
    echo -e "\033[1;31m❌ Failed to delete transcription job. Please check the response for details:\033[0m"
    echo "$DELETE_RESPONSE"
fi