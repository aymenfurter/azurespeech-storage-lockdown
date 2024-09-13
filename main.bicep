targetScope = 'resourceGroup'

param location string = 'australiaeast'
param storageAccountName string = 'sttranscriptiondemoswn'
param speechServiceName string = 'cogs-transcription-speech-ae'
param storageAccountSku string = 'Standard_RAGRS'
param storageAccountKind string = 'StorageV2'
param speechServiceSku string = 'S0'
param networkIp string = '<your-ip-address>'
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: 'switzerlandnorth'
  sku: {
    name: storageAccountSku
  }
  kind: storageAccountKind
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    largeFileSharesState: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: [
        {
          value: networkIp
          action: 'Allow'
        }
      ]
      defaultAction: 'Deny'
            resourceAccessRules: [
        {
          tenantId: subscription().tenantId
          resourceId: resourceId('Microsoft.CognitiveServices/accounts', speechServiceName)
        }
      ]
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource speechService 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: speechServiceName
  location: location
  sku: {
    name: speechServiceSku
  }
  kind: 'SpeechServices'
  properties: {
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    userOwnedStorage: [
      {
        resourceId: storageAccount.id
      }
    ]
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2021-04-01' = {
  parent: storageAccount
  name: 'default'
}

resource audiofilesSourceContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' = {
  parent: blobService
  name: 'audiofiles-source'
  properties: {
    publicAccess: 'None'
  }
}

resource customspeechArtifactsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' = {
  parent: blobService
  name: 'customspeech-artifacts'
  properties: {
    publicAccess: 'None'
  }
}

resource customspeechModelsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' = {
  parent: blobService
  name: 'customspeech-models'
  properties: {
    publicAccess: 'None'
  }
}

resource customspeechAudiologsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' = {
  parent: blobService
  name: 'customspeech-audiologs'
  properties: {
    publicAccess: 'None'
  }
}

resource blobContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, speechServiceName, 'blob-contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Blob Contributor role
    principalId: speechService.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2021-04-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          enabled: true
          name: 'DeleteAudioFilesAfter24Hours'
          type: 'Lifecycle'
          definition: {
            actions: {
              baseBlob: {
                delete: {
                  daysAfterModificationGreaterThan: 1
                }
              }
            }
            filters: {
              blobTypes: [ 'blockBlob' ]
              prefixMatch: [
                'audiofiles-source/'
              ]
            }
          }
        }
      ]
    }
  }
}