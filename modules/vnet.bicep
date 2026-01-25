@description('Name of the virtual network')
param vnetName string

@description('Location for the virtual network')
param location string = resourceGroup().location

@description('Address prefix for the virtual network')
param addressPrefix string

@description('Array of subnets to create')
param subnets array = []

@description('Tags to apply to the virtual network')
param tags object = {}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      for subnet in subnets: {
        name: subnet.name
        properties: {
          addressPrefix: subnet.addressPrefix
          delegations: subnet.?delegations ?? []
          networkSecurityGroup: subnet.?nsgId != null
            ? {
                id: subnet.nsgId
              }
            : null
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output subnets array = [
  for (subnet, i) in subnets: {
    name: vnet.properties.subnets[i].name
    id: vnet.properties.subnets[i].id
    addressPrefix: vnet.properties.subnets[i].properties.addressPrefix
  }
]
