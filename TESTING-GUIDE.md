# DNS POC - Testing Guide

After deploying with the staged approach, use this guide to validate all DNS functionality.

## Quick Validation

### Stage 1: On-Prem DNS Server Tests

After `deploy-onprem-stage1.ps1` completes, verify the DNS server itself works:

```powershell
# Test internet DNS resolution
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-dns `
  --command-id RunShellScript `
  --scripts "nslookup microsoft.com 127.0.0.1"

# Test local domain (example.pvt)
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-dns `
  --command-id RunShellScript `
  --scripts "nslookup dnspoc-vm-spoke-dev.example.pvt 127.0.0.1"

# Get storage account name for next tests
$storage = (Get-AzStorageAccount -ResourceGroupName dnspoc-rg-spoke).StorageAccountName
Write-Host "Storage account: $storage"

# Test private endpoint resolution (should go through Hub Resolver)
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-dns `
  --command-id RunShellScript `
  --scripts "nslookup $storage.blob.core.windows.net 127.0.0.1"
```

**Expected Results:**

- ✅ microsoft.com → resolves to public IP
- ✅ dnspoc-vm-spoke-dev.example.pvt → resolves to 10.1.0.10
- ✅ [storage].blob.core.windows.net → resolves to 10.1.1.x (private endpoint IP)

### Stage 2: On-Prem Client Tests

After `deploy-onprem-stage2.ps1` completes and client VM has restarted (2-3 min):

```powershell
# Verify client is using on-prem DNS
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-client `
  --command-id RunShellScript `
  --scripts "cat /etc/resolv.conf | grep nameserver"

# Should show: nameserver 10.255.0.10 (eventually, after systemd-resolved processes it)

# Test internet DNS
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-client `
  --command-id RunShellScript `
  --scripts "nslookup microsoft.com"

# Test local domain
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-client `
  --command-id RunShellScript `
  --scripts "nslookup dnspoc-vm-spoke-dev.example.pvt"

# Test private endpoint
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-client `
  --command-id RunShellScript `
  --scripts "nslookup $storage.blob.core.windows.net"
```

**Expected Results:**

- ✅ All tests work from client VM
- ✅ Private endpoint resolves to 10.1.1.x

## Comprehensive Test Scenarios

### Scenario 1: Internet DNS From On-Prem

**Test:** Can on-prem VMs resolve public domains?

```powershell
# From on-prem client
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-client `
  --command-id RunShellScript --scripts "nslookup google.com; nslookup github.com"
```

**Expected:** Both resolve to public IPs

**Flow:** On-Prem Client → On-Prem DNS (127.0.0.1:53) → Upstream (8.8.8.8) → Internet DNS

---

### Scenario 2: Local Domain Resolution

**Test:** Can on-prem VMs resolve the example.pvt domain?

```powershell
# From on-prem client, test all VMs
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-client `
  --command-id RunShellScript --scripts "
    echo '=== Test all example.pvt domains ===';
    nslookup dnspoc-vm-spoke-dev.example.pvt;
    nslookup dnspoc-vm-onprem-dns.example.pvt;
    nslookup dnspoc-vm-onprem-client.example.pvt;
  "
```

**Expected:**

- dnspoc-vm-spoke-dev.example.pvt → 10.1.0.10
- dnspoc-vm-onprem-dns.example.pvt → 10.255.0.10
- dnspoc-vm-onprem-client.example.pvt → 10.255.0.11

**Flow:** On-Prem Client → On-Prem DNS → /etc/hosts file lookup

---

### Scenario 3: Azure Private Endpoints (Blob Storage)

**Test:** Can on-prem VMs resolve storage account private endpoints?

```powershell
$storage = (Get-AzStorageAccount -ResourceGroupName dnspoc-rg-spoke).StorageAccountName

az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-client `
  --command-id RunShellScript --scripts "nslookup $storage.blob.core.windows.net"
```

**Expected:** Resolves to 10.1.1.x (private endpoint IP in spoke subnet)

**Flow:** On-Prem Client → On-Prem DNS → Hub Resolver (10.0.0.4) → Private DNS Zone → Private Endpoint IP

---

### Scenario 4: Verify Private Endpoint Network Access

**Test:** Can on-prem reach the private endpoint?

```powershell
# Check connectivity to private endpoint IP
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-client `
  --command-id RunShellScript --scripts "ping -c 3 10.1.1.4 || echo 'Note: ICMP may be blocked, but DNS works'"
```

**Expected:** ICMP may be blocked (depends on NSG), but DNS resolution works

---

### Scenario 5: DNS Server Logging

**Test:** Check DNS server logs for troubleshooting

```powershell
# View dnsmasq logs
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-dns `
  --command-id RunShellScript --scripts "tail -50 /var/log/dnsmasq.log"

# View dnsmasq configuration
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-dns `
  --command-id RunShellScript --scripts "cat /etc/dnsmasq.d/custom.conf"

# Check dnsmasq service status
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-dns `
  --command-id RunShellScript --scripts "systemctl status dnsmasq --no-pager"
```

---

## Troubleshooting

### Issue: Private Endpoint Resolves to Public IP

**Cause:** DNS forwarding rule for the storage account's domain isn't configured.

**Solution:**

```powershell
$storageAccount = (Get-AzStorageAccount -ResourceGroupName dnspoc-rg-spoke).StorageAccountName

# Add forwarding rule
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-dns `
  --command-id RunShellScript --scripts "
    echo 'server=/blob.core.windows.net/10.0.0.4' >> /etc/dnsmasq.d/custom.conf
    systemctl restart dnsmasq
  "

# Verify
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-dns `
  --command-id RunShellScript --scripts "nslookup $storageAccount.blob.core.windows.net 127.0.0.1"
```

### Issue: example.pvt Domain Not Resolving

**Cause:** Host file isn't populated or dnsmasq isn't restarted.

**Solution:**

```powershell
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-dns `
  --command-id RunShellScript --scripts "
    echo '=== Check /etc/hosts ===';
    cat /etc/hosts | grep example.pvt;
    echo '';
    echo '=== Check dnsmasq status ===';
    systemctl status dnsmasq --no-pager;
    echo '';
    echo '=== Restart dnsmasq ===';
    systemctl restart dnsmasq;
  "
```

### Issue: DNS Queries Timeout

**Cause:** dnsmasq not running or listening on wrong interface.

**Solution:**

```powershell
az vm run-command invoke --resource-group dnspoc-rg-onprem --name dnspoc-vm-onprem-dns `
  --command-id RunShellScript --scripts "
    echo '=== Check listening ports ===';
    netstat -tlnp | grep 53;
    echo '';
    echo '=== Check dnsmasq process ===';
    ps aux | grep dnsmasq;
    echo '';
    echo '=== Restart service ===';
    systemctl restart dnsmasq;
    sleep 2;
    systemctl status dnsmasq --no-pager;
  "
```

---

## Cleanup

When done testing:

```powershell
# Delete all resource groups
Remove-AzResourceGroup -Name 'dnspoc-rg-hub' -Force
Remove-AzResourceGroup -Name 'dnspoc-rg-spoke' -Force
Remove-AzResourceGroup -Name 'dnspoc-rg-onprem' -Force

# Or use the teardown script
.\teardown.ps1
```

---

## Summary Checklist

- [ ] Stage 1 deployment completes without errors
- [ ] DNS server has dnsmasq running
- [ ] DNS server resolves internet domains (e.g., microsoft.com)
- [ ] DNS server resolves example.pvt domains correctly
- [ ] DNS server resolves storage account to private IP (10.1.1.x)
- [ ] Stage 2 deployment completes
- [ ] Client VM restarts and picks up new DNS settings
- [ ] Client VM resolves all three categories (internet, local, private endpoints)
- [ ] Logs show proper forwarding to Hub Resolver for privatelink zones
