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

@description('VM private DNS zone ID')
param vmPrivateDnsZoneId string

@description('VM private DNS zone name')
param vmPrivateDnsZoneName string

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
    dnsServers: [hubResolverInboundIP]
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

// Link on-prem VNet to VM private DNS zone
module onpremVmDnsLink '../modules/private-dns-zone.bicep' = {
  name: 'deploy-onprem-vm-dns-link'
  scope: resourceGroup(hubResourceGroupName)
  params: {
    zoneName: vmPrivateDnsZoneName
    tags: tags
    vnetLinks: [
      {
        name: '${onpremVnetName}-link'
        vnetId: onpremVnet.outputs.vnetId
        registrationEnabled: false
      }
    ]
  }
}

// On-prem DNS server
var dnsServerName = '${envPrefix}-vm-onprem-dns'

var dnsServerCloudInit = '''#cloud-config
package_update: true
package_upgrade: true
packages:
  - dnsmasq
  - dnsutils
  - net-tools

write_files:
  - path: /etc/dnsmasq.d/custom.conf
    content: |
      # Local domain
      local=/example.pvt/
      domain=example.pvt
      
      # Listen on all interfaces
      interface=eth0
      bind-interfaces
      
      # Cache settings
      cache-size=1000
      
      # Log queries for troubleshooting
      log-queries
      log-facility=/var/log/dnsmasq.log

runcmd:
  - systemctl enable dnsmasq
  - systemctl restart dnsmasq
  - touch /var/log/dnsmasq.log
  - chown dnsmasq:nogroup /var/log/dnsmasq.log
'''

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

// On-prem client VM
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
