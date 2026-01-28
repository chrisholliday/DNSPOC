targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment prefix for naming')
param envPrefix string = 'dnspoc'

@description('On-prem VNet address space')
param onpremVnetAddressPrefix string = '10.255.0.0/16'

@description('Hub VNet ID for peering')
param hubVnetId string

@description('Hub VNet name for peering')
param hubVnetName string

@description('Hub resource group name')
param hubResourceGroupName string

@description('Hub resolver inbound IP for DNS configuration')
param hubResolverInboundIP string

@description('SSH public key for VMs')
param sshPublicKey string

@description('Admin username for VMs')
param adminUsername string = 'azureuser'

@description('DNS server static IP address')
param dnsServerIP string = '10.255.0.10'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'POC'
  Project: 'DNS-Hub-Spoke'
}

// On-prem VNet
var onpremVnetName = '${envPrefix}-vnet-onprem'
var onpremDefaultSubnetName = 'default'

module onpremNsg '../modules/nsg.bicep' = {
  name: 'deploy-${onpremVnetName}-nsg'
  params: {
    nsgName: '${onpremVnetName}-nsg'
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
      {
        name: 'AllowDNS'
        properties: {
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
    tags: tags
  }
}

module onpremVnet '../modules/vnet.bicep' = {
  name: 'deploy-${onpremVnetName}'
  params: {
    vnetName: onpremVnetName
    location: location
    addressPrefix: onpremVnetAddressPrefix
    dnsServers: [] // Use Azure default DNS initially - will be updated after DNS server is configured
    subnets: [
      {
        name: onpremDefaultSubnetName
        addressPrefix: '10.255.0.0/24'
        nsgId: onpremNsg.outputs.nsgId
      }
    ]
    tags: tags
  }
}

// Peering: On-prem to Hub
module onpremToHubPeering '../modules/vnet-peering.bicep' = {
  name: 'deploy-onprem-to-hub-peering'
  params: {
    peeringName: 'onprem-to-hub'
    sourceVnetName: onpremVnet.outputs.vnetName
    destVnetId: hubVnetId
    allowForwardedTraffic: true
  }
}

// Peering: Hub to On-prem
module hubToOnpremPeering '../modules/vnet-peering.bicep' = {
  name: 'deploy-hub-to-onprem-peering'
  scope: resourceGroup(hubResourceGroupName)
  params: {
    peeringName: 'hub-to-onprem'
    sourceVnetName: hubVnetName
    destVnetId: onpremVnet.outputs.vnetId
    allowForwardedTraffic: true
  }
}

// NOTE: example.pvt DNS zone NOT linked here - on-prem DNS server is authoritative for this zone

// On-prem DNS server
var dnsServerName = '${envPrefix}-vm-onprem-dns'

var dnsServerCloudInit = format(
  '''{0}
package_update: true
package_upgrade: true
packages:
  - dnsmasq
  - dnsutils
  - net-tools

write_files:
  - path: /etc/dnsmasq.d/custom.conf
    content: |
      # Local domain for VMs
      local=/example.pvt/
      domain=example.pvt
      
      # Forward Azure privatelink zones to Hub Resolver
      # This enables hybrid DNS - on-prem can resolve Azure private endpoints
      server=/privatelink.blob.core.windows.net/{1}
      server=/blob.core.windows.net/{1}
      server=/privatelink.file.core.windows.net/{1}
      server=/file.core.windows.net/{1}
      server=/privatelink.database.windows.net/{1}
      server=/database.windows.net/{1}
      server=/privatelink.postgres.database.azure.com/{1}
      server=/postgres.database.azure.com/{1}
      
      # Upstream DNS servers for internet resolution
      server=8.8.8.8
      server=8.8.4.4
      
      # Listen on all interfaces
      interface=eth0
      bind-interfaces
      
      # Cache settings
      cache-size=1000
      
      # Log queries for troubleshooting
      log-queries
      log-facility=/var/log/dnsmasq.log
  
  - path: /etc/hosts.example-pvt
    content: |
      # VM records for example.pvt domain
      # Note: Spoke VM uses static IP, on-prem VMs use static IPs
      10.1.0.10   {2}-vm-spoke-dev.example.pvt      {2}-vm-spoke-dev
      10.255.0.10 {2}-vm-onprem-dns.example.pvt     {2}-vm-onprem-dns
      10.255.0.11 {2}-vm-onprem-client.example.pvt  {2}-vm-onprem-client

runcmd:
  - cat /etc/hosts.example-pvt >> /etc/hosts
  - systemctl enable dnsmasq
  - systemctl restart dnsmasq
  - touch /var/log/dnsmasq.log
  - chown dnsmasq:nogroup /var/log/dnsmasq.log
''',
  '#cloud-config',
  hubResolverInboundIP,
  envPrefix
)

module dnsServerVm '../modules/vm.bicep' = {
  name: 'deploy-${dnsServerName}'
  params: {
    vmName: dnsServerName
    location: location
    vmSize: 'Standard_B2s'
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    subnetId: onpremVnet.outputs.subnets[0].id
    privateIPAllocationMethod: 'Static'
    privateIPAddress: dnsServerIP
    cloudInit: dnsServerCloudInit
    tags: tags
  }
}

// On-prem client VM (using static IP 10.255.0.11)
var clientVmName = '${envPrefix}-vm-onprem-client'

module clientVm '../modules/vm.bicep' = {
  name: 'deploy-${clientVmName}'
  params: {
    vmName: clientVmName
    location: location
    vmSize: 'Standard_B1s'
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    subnetId: onpremVnet.outputs.subnets[0].id
    privateIPAllocationMethod: 'Static'
    privateIPAddress: '10.255.0.11'
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

output onpremVnetId string = onpremVnet.outputs.vnetId
output onpremVnetName string = onpremVnet.outputs.vnetName
output dnsServerIP string = dnsServerVm.outputs.privateIPAddress
output clientVmPrivateIP string = clientVm.outputs.privateIPAddress
