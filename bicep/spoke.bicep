targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment prefix for naming')
param envPrefix string = 'dnspoc'

@description('Spoke VNet address space')
param spokeVnetAddressPrefix string = '10.1.0.0/16'

@description('Hub VNet ID for peering')
param hubVnetId string

@description('Hub VNet name for peering')
param hubVnetName string

@description('Hub resource group name for DNS zone links')
param hubResourceGroupName string

@description('Blob private DNS zone ID')
param blobPrivateDnsZoneId string

@description('VM private DNS zone ID')
param vmPrivateDnsZoneId string

@description('SSH public key for VMs')
param sshPublicKey string

@description('Admin username for VMs')
param adminUsername string = 'azureuser'

@description('Storage account name (must be globally unique)')
param storageAccountName string

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'POC'
  Project: 'DNS-Hub-Spoke'
}

// Spoke VNet
var spokeVnetName = '${envPrefix}-vnet-spoke'
var spokeDefaultSubnetName = 'default'
var spokePrivateEndpointSubnetName = 'private-endpoints'

module spokeNsg '../modules/nsg.bicep' = {
  name: 'deploy-${spokeVnetName}-nsg'
  params: {
    nsgName: '${spokeVnetName}-nsg'
    location: location
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
    tags: tags
  }
}

module spokeVnet '../modules/vnet.bicep' = {
  name: 'deploy-${spokeVnetName}'
  params: {
    vnetName: spokeVnetName
    location: location
    addressPrefix: spokeVnetAddressPrefix
    subnets: [
      {
        name: spokeDefaultSubnetName
        addressPrefix: '10.1.0.0/24'
        nsgId: spokeNsg.outputs.nsgId
      }
      {
        name: spokePrivateEndpointSubnetName
        addressPrefix: '10.1.1.0/24'
      }
    ]
    tags: tags
  }
}

// Peering: Spoke to Hub
module spokeToHubPeering '../modules/vnet-peering.bicep' = {
  name: 'deploy-spoke-to-hub-peering'
  params: {
    peeringName: 'spoke-to-hub'
    sourceVnetName: spokeVnet.outputs.vnetName
    destVnetId: hubVnetId
    allowForwardedTraffic: true
  }
}

// Peering: Hub to Spoke (deployed in hub RG)
module hubToSpokePeering '../modules/vnet-peering.bicep' = {
  name: 'deploy-hub-to-spoke-peering'
  scope: resourceGroup(hubResourceGroupName)
  params: {
    peeringName: 'hub-to-spoke'
    sourceVnetName: hubVnetName
    destVnetId: spokeVnet.outputs.vnetId
    allowForwardedTraffic: true
  }
}

// Link spoke VNet to private DNS zones
module spokeBlobDnsLink '../modules/private-dns-zone.bicep' = {
  name: 'deploy-spoke-blob-dns-link'
  scope: resourceGroup(hubResourceGroupName)
  params: {
    zoneName: reference(blobPrivateDnsZoneId, '2020-06-01').name
    tags: tags
    vnetLinks: [
      {
        name: '${spokeVnetName}-link'
        vnetId: spokeVnet.outputs.vnetId
        registrationEnabled: false
      }
    ]
  }
}

module spokeVmDnsLink '../modules/private-dns-zone.bicep' = {
  name: 'deploy-spoke-vm-dns-link'
  scope: resourceGroup(hubResourceGroupName)
  params: {
    zoneName: reference(vmPrivateDnsZoneId, '2020-06-01').name
    tags: tags
    vnetLinks: [
      {
        name: '${spokeVnetName}-link'
        vnetId: spokeVnet.outputs.vnetId
        registrationEnabled: false
      }
    ]
  }
}

// Developer VM in spoke
var spokeVmName = '${envPrefix}-vm-spoke-dev'

module spokeDevVm '../modules/vm.bicep' = {
  name: 'deploy-${spokeVmName}'
  params: {
    vmName: spokeVmName
    location: location
    vmSize: 'Standard_B1s'
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    subnetId: spokeVnet.outputs.subnets[0].id
    cloudInit: '''
#cloud-config
package_update: true
package_upgrade: true
packages:
  - dnsutils
  - net-tools
'''
    tags: tags
  }
}

// Storage account with private endpoint
module spokeStorage '../modules/storage-private-endpoint.bicep' = {
  name: 'deploy-${storageAccountName}'
  params: {
    storageAccountName: storageAccountName
    location: location
    subnetId: spokeVnet.outputs.subnets[1].id
    privateDnsZoneId: blobPrivateDnsZoneId
    tags: tags
  }
}

output spokeVnetId string = spokeVnet.outputs.vnetId
output spokeVnetName string = spokeVnet.outputs.vnetName
output spokeDevVmPrivateIP string = spokeDevVm.outputs.privateIPAddress
output storageAccountName string = spokeStorage.outputs.storageAccountName
output storageBlobEndpoint string = spokeStorage.outputs.blobEndpoint
