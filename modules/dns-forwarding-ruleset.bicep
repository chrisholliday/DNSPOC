@description('Name of the DNS forwarding ruleset')
param rulesetName string

@description('Location for the ruleset')
param location string = resourceGroup().location

@description('Outbound endpoint IDs to associate')
param outboundEndpointIds array

@description('Virtual network IDs to link to this ruleset')
param vnetLinks array = []

@description('Forwarding rules to create')
param forwardingRules array = []

@description('Tags to apply to resources')
param tags object = {}

resource forwardingRuleset 'Microsoft.Network/dnsForwardingRulesets@2022-07-01' = {
  name: rulesetName
  location: location
  tags: tags
  properties: {
    dnsResolverOutboundEndpoints: [
      for endpointId in outboundEndpointIds: {
        id: endpointId
      }
    ]
  }
}

resource rulesetVnetLink 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2022-07-01' = [
  for (link, i) in vnetLinks: {
    parent: forwardingRuleset
    name: link.name
    properties: {
      virtualNetwork: {
        id: link.vnetId
      }
    }
  }
]

resource forwardingRule 'Microsoft.Network/dnsForwardingRulesets/forwardingRules@2022-07-01' = [
  for (rule, i) in forwardingRules: {
    parent: forwardingRuleset
    name: rule.name
    properties: {
      domainName: rule.domainName
      targetDnsServers: [
        for target in rule.targetDnsServers: {
          ipAddress: target.ipAddress
          port: target.?port ?? 53
        }
      ]
      forwardingRuleState: rule.?forwardingRuleState ?? 'Enabled'
    }
  }
]

output rulesetId string = forwardingRuleset.id
output rulesetName string = forwardingRuleset.name
