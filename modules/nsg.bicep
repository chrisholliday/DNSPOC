@description('Name of the network security group')
param nsgName string

@description('Location for the NSG')
param location string = resourceGroup().location

@description('Security rules to apply')
param securityRules array = []

@description('Tags to apply to the NSG')
param tags object = {}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: securityRules
  }
}

output nsgId string = nsg.id
output nsgName string = nsg.name
