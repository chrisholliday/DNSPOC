@description('Name of the virtual machine')
param vmName string

@description('Location for the VM')
param location string = resourceGroup().location

@description('VM size')
param vmSize string = 'Standard_B1s'

@description('Admin username')
param adminUsername string

@description('SSH public key for authentication')
@secure()
param sshPublicKey string

@description('Subnet ID for the VM NIC')
param subnetId string

@description('Private IP allocation method')
@allowed(['Dynamic', 'Static'])
param privateIPAllocationMethod string = 'Dynamic'

@description('Static private IP address (if allocation method is Static)')
param privateIPAddress string = ''

@description('Cloud-init script for VM initialization')
param cloudInit string = ''

@description('Tags to apply to resources')
param tags object = {}

var nicName = '${vmName}-nic'
var osDiskName = '${vmName}-osdisk'

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: privateIPAllocationMethod
          privateIPAddress: privateIPAllocationMethod == 'Static' ? privateIPAddress : null
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: !empty(cloudInit) ? base64(cloudInit) : null
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

output vmId string = vm.id
output vmName string = vm.name
output privateIPAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output nicId string = nic.id
