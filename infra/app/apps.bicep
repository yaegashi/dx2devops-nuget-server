metadata description = 'Creates a container app in an Azure Container App environment.'
param name string
param location string = resourceGroup().location
param tags object = {}
param storageAccountName string
param containerAppsEnvironmentName string
param databaseName string
@secure()
param databaseConnectionString string
@secure()
param apiKey string

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2022-12-01' existing = {
  name: databaseName
  resource configuration 'configurations' = {
    name: 'azure.extensions'
    properties: {
      value: 'CITEXT'
      source: 'user-override'
    }
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: storageAccountName
  resource fileService 'fileServices' = {
    name: 'default'
    resource data 'shares' = {
      name: 'data'
    }
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-04-01-preview' existing = {
  name: containerAppsEnvironmentName
  resource data 'storages' = {
    name: 'data'
    properties: {
      azureFile: {
        accessMode: 'ReadWrite'
        accountName: storage.name
        accountKey: storage.listKeys().keys[0].value
        shareName: storage::fileService::data.name
      }
    }
  }
}

resource app 'Microsoft.App/containerApps@2023-04-01-preview' = {
  dependsOn: [ containerAppsEnvironment::data ]
  name: name
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
      }
    }
    template: {
      volumes: [
        {
          name: 'data'
          storageName: storage::fileService::data.name
          storageType: 'AzureFile'
        }
      ]
      containers: [
        {
          name: 'ebap'
          image: 'ghcr.io/yaegashi/easy-basic-auth-proxy:main'
          env: [
            { name: 'EBAP_LISTEN', value: ':80' }
            { name: 'EBAP_TARGET_URL', value: 'http://localhost:8080' }
            { name: 'EBAP_ACCOUNTS_DIR', value: '/data/ebap/accounts' }
          ]
          volumeMounts: [
            {
              volumeName: 'data'
              mountPath: '/data'
            }
          ]
        }
        {
          name: 'bagetter'
          image: 'bagetter/bagetter'
          env: [
            { name: 'ApiKey', value: apiKey }
            { name: 'Storage__Type', value: 'FileSystem' }
            { name: 'Storage__Path', value: '/data/bagetter/packages' }
            // AzureBlobStorage is disabled in BaGetter
            // { name: 'Storage__Type', value: 'AzureBlobStorage' }
            // { name: 'Storage__AccountName', value: storage.name }
            // { name: 'Storage__AccessKey', value: storage.listKeys().keys[0].value }
            // { name: 'Storage__Container', value: 'packages' }
            { name: 'Database__Type', value: 'PostgreSql' }
            { name: 'Database__ConnectionString', value: databaseConnectionString }
            { name: 'Search__Type', value: 'Database' }
          ]
          volumeMounts: [
            {
              volumeName: 'data'
              mountPath: '/data'
            }
          ]
        }
      ]
      initContainers: [
        {
          name: 'init'
          image: 'busybox'
          command: [ 'sh', '-c', 'mkdir -p /data/ebap/accounts /data/bagetter/packages' ]
          volumeMounts: [
            {
              volumeName: 'data'
              mountPath: '/data'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

output id string = app.id
output uri string = 'https://${app.properties.configuration.ingress.fqdn}'
