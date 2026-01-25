@description('Name of the private DNS zone')
param zoneName string

@description('Tags to apply to the zone')
param tags object = {}

@description('Virtual network IDs to link to this zone')
param vnetLinks array = []

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: zoneName
  location: 'global'
  tags: tags
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for (link, i) in vnetLinks: {
    parent: privateDnsZone
    name: link.name
    location: 'global'
    tags: tags
    properties: {
      registrationEnabled: link.?registrationEnabled ?? false
      virtualNetwork: {
        id: link.vnetId
      }
    }
  }
]

output zoneId string = privateDnsZone.id
output zoneName string = privateDnsZone.name
