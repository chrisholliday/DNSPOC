targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment prefix for naming')
param envPrefix string = 'dnspoc'

@description('Hub VNet address space')
param hubVnetAddressPrefix string = '10.0.0.0/16'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'POC'
  Project: 'DNS-Hub-Spoke'
}

// Hub VNet with subnets for DNS resolver
var hubVnetName = '${envPrefix}-vnet-hub'
var inboundSubnetName = 'resolver-inbound'
var outboundSubnetName = 'resolver-outbound'
var defaultSubnetName = 'default'

module hubVnet '../modules/vnet.bicep' = {
  name: 'deploy-${hubVnetName}'
  params: {
    vnetName: hubVnetName
    location: location
    addressPrefix: hubVnetAddressPrefix
    subnets: [
      {
        name: inboundSubnetName
        addressPrefix: '10.0.0.0/28'
        delegations: [
          {
            name: 'Microsoft.Network.dnsResolvers'
            properties: {
              serviceName: 'Microsoft.Network/dnsResolvers'
            }
          }
        ]
      }
      {
        name: outboundSubnetName
        addressPrefix: '10.0.0.16/28'
        delegations: [
          {
            name: 'Microsoft.Network.dnsResolvers'
            properties: {
              serviceName: 'Microsoft.Network/dnsResolvers'
            }
          }
        ]
      }
      {
        name: defaultSubnetName
        addressPrefix: '10.0.1.0/24'
      }
    ]
    tags: tags
  }
}

// DNS Private Resolver
var resolverName = '${envPrefix}-resolver-hub'

module dnsResolver '../modules/dns-resolver.bicep' = {
  name: 'deploy-${resolverName}'
  params: {
    resolverName: resolverName
    location: location
    vnetId: hubVnet.outputs.vnetId
    inboundSubnetId: hubVnet.outputs.subnets[0].id
    outboundSubnetId: hubVnet.outputs.subnets[1].id
    tags: tags
  }
}

// Private DNS Zones
var blobPrivateDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var vmPrivateDnsZoneName = 'example.pvt'

module blobPrivateDnsZone '../modules/private-dns-zone.bicep' = {
  name: 'deploy-blob-private-dns-zone'
  params: {
    zoneName: blobPrivateDnsZoneName
    tags: tags
    vnetLinks: [
      {
        name: '${hubVnetName}-link'
        vnetId: hubVnet.outputs.vnetId
        registrationEnabled: false
      }
    ]
  }
}

module vmPrivateDnsZone '../modules/private-dns-zone.bicep' = {
  name: 'deploy-vm-private-dns-zone'
  params: {
    zoneName: vmPrivateDnsZoneName
    tags: tags
    vnetLinks: [
      {
        name: '${hubVnetName}-link'
        vnetId: hubVnet.outputs.vnetId
        registrationEnabled: false
      }
    ]
  }
}

// Outputs for connecting spokes and on-prem
output hubVnetId string = hubVnet.outputs.vnetId
output hubVnetName string = hubVnet.outputs.vnetName
output resolverInboundIP string = dnsResolver.outputs.inboundEndpointIP
output resolverOutboundEndpointId string = dnsResolver.outputs.outboundEndpointId
output blobPrivateDnsZoneId string = blobPrivateDnsZone.outputs.zoneId
output vmPrivateDnsZoneId string = vmPrivateDnsZone.outputs.zoneId
output blobPrivateDnsZoneName string = blobPrivateDnsZone.outputs.zoneName
output vmPrivateDnsZoneName string = vmPrivateDnsZone.outputs.zoneName
