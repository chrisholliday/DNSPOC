targetScope = 'resourceGroup'

@description('Name of the DNS forwarding ruleset')
param rulesetName string

@description('Location for the ruleset')
param location string = resourceGroup().location

@description('Outbound endpoint IDs to associate')
param outboundEndpointIds array

@description('Virtual network links')
param vnetLinks array = []

@description('Forwarding rules to create')
param forwardingRules array = []

module forwardingRulesetModule '../modules/dns-forwarding-ruleset.bicep' = {
  name: 'deploy-${rulesetName}'
  params: {
    rulesetName: rulesetName
    location: location
    outboundEndpointIds: outboundEndpointIds
    vnetLinks: vnetLinks
    forwardingRules: forwardingRules
  }
}

output rulesetId string = forwardingRulesetModule.outputs.rulesetId
output rulesetName string = forwardingRulesetModule.outputs.rulesetName
