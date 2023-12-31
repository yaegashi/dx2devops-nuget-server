targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

param principalId string

@secure()
param apiKey string

param dbName string = 'packages'

param dbUser string = 'packages'

@secure()
param dbPass string

@secure()
param sessionKey string

param resourceGroupName string = ''

param keyVaultName string = ''

param storageAccountName string = ''

param databaseName string = ''

param logAnalyticsName string = ''

param applicationInsightsName string = ''

param applicationInsightsDashboardName string = ''

param containerAppsEnvironmentName string = ''

param containerAppName string = ''

var abbrs = loadJsonContent('./abbreviations.json')

var tags = {
  'azd-env-name': environmentName
}

#disable-next-line no-unused-vars
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module keyVault './core/security/keyvault.bicep' = {
  name: 'keyVault'
  scope: rg
  params: {
    name: !empty(keyVaultName) ? keyVaultName : '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
    principalId: principalId
  }
}

module keyVaultSecretApiKey './core/security/keyvault-secret.bicep' = {
  name: 'keyVaultSecretApiKey'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    name: 'apiKey'
    secretValue: apiKey
    tags: tags
  }
}

module keyVaultSecretDbPass './core/security/keyvault-secret.bicep' = {
  name: 'keyVaultSecretDbPass'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    name: 'dbPass'
    secretValue: dbPass
    tags: tags
  }
}

module keyvaultSecretSessionKey './core/security/keyvault-secret.bicep' = {
  name: 'keyVaultSecretSessionKey'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    name: 'sessionKey'
    secretValue: sessionKey
    tags: tags
  }
}
module storageAccount './core/storage/storage-account.bicep' = {
  name: 'storageAccount'
  scope: rg
  params: {
    location: location
    tags: tags
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
  }
}

module psql './core/database/postgresql/flexibleserver.bicep' = {
  name: 'psql'
  scope: rg
  params: {
    location: location
    tags: tags
    name: !empty(databaseName) ? databaseName : '${abbrs.dBforPostgreSQLServers}${resourceToken}'
    version: '15'
    sku: {
      name: 'Standard_B1ms'
      tier: 'Burstable'
    }
    storage: {
      autoGrow: 'Disabled'
      backupRetentionDays: 7
      storageSizeGB: 32
    }
    administratorLogin: dbUser
    administratorLoginPassword: dbPass
    allowAzureIPsFirewall: true
    databaseNames: [ dbName ]
  }
}

module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: !empty(applicationInsightsDashboardName) ? applicationInsightsDashboardName : '${abbrs.portalDashboards}${resourceToken}'
  }
}

module containerAppEnv './core/host/container-apps-environment.bicep' = {
  name: 'containerAppEnv'
  scope: rg
  params: {
    name: !empty(containerAppsEnvironmentName) ? containerAppsEnvironmentName : '${abbrs.appManagedEnvironments}${resourceToken}'
    location: location
    tags: tags
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
  }
}

module app './app/apps.bicep' = {
  name: 'apps'
  scope: rg
  params: {
    name: !empty(containerAppName) ? containerAppName : '${abbrs.appContainerApps}${resourceToken}'
    location: location
    tags: tags
    storageAccountName: storageAccount.outputs.name
    containerAppsEnvironmentName: containerAppEnv.outputs.name
    databaseName: psql.outputs.name
    databaseConnectionString: 'Host=${psql.outputs.POSTGRES_DOMAIN_NAME};Port=5432;Database=${dbName};Username=${dbUser};Password=${dbPass};SSL Mode=Require'
    apiKey: apiKey
    sessionKey: sessionKey
  }
}

var portalLink = 'https://portal.azure.com/${tenant().tenantId}'

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
output AZURE_APP_SITE_LINK string = app.outputs.uri
output AZURE_APP_PORTAL_LINK string = '${portalLink}#resource${app.outputs.id}'
output AZURE_API_KEY_PORTAL_LINK string = '${portalLink}#asset/Microsoft_Azure_KeyVault/Secret/${keyVault.outputs.endpoint}secrets/apiKey'
