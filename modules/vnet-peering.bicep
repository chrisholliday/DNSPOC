@description('Name of the VNet peering from source to destination')
param peeringName string

@description('Name of the source virtual network')
param sourceVnetName string

@description('Resource ID of the destination virtual network')
param destVnetId string

@description('Allow virtual network access')
param allowVnetAccess bool = true

@description('Allow forwarded traffic')
param allowForwardedTraffic bool = true

@description('Allow gateway transit')
param allowGatewayTransit bool = false

@description('Use remote gateways')
param useRemoteGateways bool = false

resource sourceVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: sourceVnetName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: sourceVnet
  name: peeringName
  properties: {
    allowVirtualNetworkAccess: allowVnetAccess
    allowForwardedTraffic: allowForwardedTraffic
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: useRemoteGateways
    remoteVirtualNetwork: {
      id: destVnetId
    }
  }
}

output peeringId string = peering.id
output peeringName string = peering.name
