# Azure Speech-to-Text Transcription Demo

This repository demonstrates how to use the Azure Speech-to-Text API for batch transcription and secure a storage account. It includes a script `trigger_transcription.sh` to showcase the transcription process.

## Prerequisites

- Azure CLI installed
- Logged into your Azure account
- Set the `SUBSCRIPTION_ID` environment variable

## How to Run

1. **Deploy Infrastructure**:
    ```sh
    az group create --name rg-transcription-demo-ae --location australiaeast
    az deployment group create --resource-group rg-transcription-demo-ae --template-file main.bicep
    ```

2. **Upload `test.mp3` file** to the `audiofiles-source` container via the Azure portal.

3. **Run the Transcription Script**:
    ```sh
    ./trigger_transcription.sh
    ```

The script will verify security settings, fetch a Whisper model, trigger the transcription, and display the results.

## References
- [Batch Transcription Audio Data](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/batch-transcription-audio-data?tabs=portal)
- [Batch Transcription - Create](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/batch-transcription-create?pivots=rest-api)
- [Batch Transcription - Get Results](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/batch-transcription-get?pivots=rest-api)
- [Call Center OpenAI Analytics - Reference Architecture](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/openai/architecture/call-center-openai-analytics)
