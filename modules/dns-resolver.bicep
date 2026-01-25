@description('Name of the DNS Private Resolver')
param resolverName string

@description('Location for the resolver')
param location string = resourceGroup().location

@description('Virtual network ID where resolver will be deployed')
param vnetId string

@description('Subnet ID for inbound endpoint')
param inboundSubnetId string

@description('Subnet ID for outbound endpoint')
param outboundSubnetId string

@description('Tags to apply to resources')
param tags object = {}

resource dnsResolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: resolverName
  location: location
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource inboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  parent: dnsResolver
  name: '${resolverName}-inbound'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        subnet: {
          id: inboundSubnetId
        }
      }
    ]
  }
}

resource outboundEndpoint 'Microsoft.Network/dnsResolvers/outboundEndpoints@2022-07-01' = {
  parent: dnsResolver
  name: '${resolverName}-outbound'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: outboundSubnetId
    }
  }
}

output resolverId string = dnsResolver.id
output resolverName string = dnsResolver.name
output inboundEndpointId string = inboundEndpoint.id
output inboundEndpointIP string = inboundEndpoint.properties.ipConfigurations[0].privateIpAddress
output outboundEndpointId string = outboundEndpoint.id
