# 🚀 Azure Private DNS Hub‑and‑Spoke Proof of Concept

A PaaS‑centric, IaC‑driven environment demonstrating centralized DNS governance with developer autonomy

## 📘 Overview

This project showcases how Azure Private DNS, Azure DNS Private Resolver, and a hub‑and‑spoke network topology work together to support scalable, and developer‑friendly name resolution for PaaS services. The environment is deployed entirely using Infrastructure as Code (IaC) and is intended to quickly demonstrate the technology and techniques to deliver the solution. While security is always important, enterprise scale security
configuration is beyond the scope of this simple project. This project also aims to be consumable, easy to understand, and quick to demo.

---

## 🎯 Goals

- Deploy a **hub‑and‑spoke virtual network architecture** using IaC.
- Centrally host and manage storage blob DNS zone.
- Allow developers to:
  - Deploy resources in their own spoke VNet.
  - Create Private Endpoints without DNS involvement.
  - Automatically generate DNS records for storage blobs.
  - Resolve PaaS private endpoint names from their spoke VMs.
  - Resolve PaaS private endpoint names in another spoke.
  - Resolve DNS records hosted in an "on-premises" network.
  - Resolve public DNS records via the "on-premises" dns solution.
- Simulate an **on‑premises DNS server** that:
  - Forwards queries to the Azure DNS Private Resolver.
  - Can resolve PaaS private endpoint names hosted in any spoke.
- Ensure **all DNS resolution flows through the hub**, using:
  - Azure Private DNS zones for PaaS services.
  - DNS Private Resolver for cross‑network and hybrid resolution.
  - Forwarding rules for on‑prem integration.

---

## 🏗️ Architecture

### Virtual Networks

- **Hub VNet**
  - Azure DNS Private Resolver (inbound + outbound endpoints)
  - DNS forwarding ruleset
  - Azure Private DNS Zone(s) for PaaS services
  - Azure Private DNS Zone for VMs
  - Peered to all networks

- **Spoke VNet** (single spoke for simplicity)
  - Developer‑owned
  - Hosts PaaS resources + Private Endpoints
  - Linux VM for DNS name resolution testing

- **On‑Prem Simulation VNet**
  - Linux DNS VM (dnsmasq) hosting sample "on-premises" DNS records
  - Provides Internet name resolution for all networks
  - Linux client VM for DNS resolution testing

### Platform DNS Zones (centrally owned)

Azure automatically manages records for PaaS private endpoints in these zones:

| Service | Private DNS Zone |
| -------- | ------------------ |
| Storage (blob) | `privatelink.blob.core.windows.net` |

Platform team will manually manage VM records in the vm zone

| Service | Private DNS Zone |
| -------- | ------------------ |
| Virtual Machines | `example.pvt` |

These zones are:

- Created and owned by the **platform team**
- Linked to **all VNets** (hub, spokes, on‑prem)
- Automatically populated by Azure when developers create Private Endpoints for PaaS services

---

## 🔐 Governance Model

### Platform Team Owns

- All `privatelink.*` Private DNS zones
- `example.pvt` Private DNS zone
- DNS Private Resolver (inbound + outbound)
- DNS forwarding ruleset
- Hub VNet and all VNet links

### Developer Teams Own

- Their resource group(s)
- Their spoke VNet
- Their PaaS resources (Storage, SQL, Key Vault, etc.)
- Their Private Endpoints
- Linux test VMs

### Developers Do *Not* Need

- Access to Private DNS zones
- Access to resolver configuration
- Ability to create or modify DNS records
- Azure automatically manages all PaaS DNS records.

## All Azure DNS flows route through the hub resolver

- Spoke → Azure DNS → Hub Resolver → Private DNS Zone
- On‑prem → On‑prem DNS → Hub Resolver → Private DNS Zone

### Public & On Prem DNS flows route through the On Prem DNS server

- Public queries → Hub Resolver → Public DNS forwarders -> On Prem DNS Server -> Public DNS resolution
- On prem queries → Hub Resolver → Public DNS forwarders -> On Prem DNS Server

---

## 🧪 Demonstration Scenarios

### 1. Developer creates a PaaS resource with a Private Endpoint in the Spoke Vnet

- Developer deploys a Storage Account with Blob storage.
- Developer creates a Private Endpoint in the spoke VNet.
- Azure automatically creates the DNS record in the correct `privatelink.blob.core.windows.net` zone.

### 2. Spoke VM resolves the PaaS private endpoints

- From a VM in Spoke Vnet:

```code
nslookup <spoke storage account>.blob.core.windows.net
```

### 3. Spoke VM resolves remote DNS Names

- From a VM in Spoke:

```code
nslookup microsoft.com
nslookup <onpclientvm>.example.pvt
```

### 4. On‑prem client resolves DNS names

- From the on‑prem client VM:

```code
nslookup <spoke storage>.blob.core.windows.net 
nslookup <Developer VM>.example.pvt
nslookup www.microsoft.com 
```

---

## 🧱 Infrastructure as Code (IaC)

- This project is authored entirely using **Powershell** and Bicep
- IaC should be focused on readabiliy and accuracy
  - All cmdlets should be found within the current (15.2.0) Az module as hosted on the Powershell Gallery
  - All parameters must be valid for the current Az module
  - No errors in code, or warnings in VScode
- Automation should be resuable, with a prefrence for many smaller, focused files over one file do do everything
- Deployment automation should stop deployment on any error and provide any available context to the user

## Naming standard

Object names should be created in the following format, or a closely as possible

`<DNSPOC>`-`<Object Type>`-`<Network>`-`<role and or suffix as needed>`

### Examples

- dnspoc-rg-hub
- dnspoc-vm-hub-dnsserver
- dnspocsaspoke1111 // *storage accounts have restricted naming requirements*
- dns-privateddnszone-hub-storage
