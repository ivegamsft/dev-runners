# Runner Egress Policy

## Default Posture
All runner infrastructure uses a Network Security Group (NSG) with **default-deny egress** and explicit allow rules.

## Allowed Outbound Traffic

| Priority | Name | Protocol | Port | Destination | Purpose |
|----------|------|----------|------|-------------|---------|
| 100 | Allow-HTTPS-Outbound | TCP | 443 | Internet | GitHub API, Azure DevOps, package registries |
| 110 | Allow-HTTP-Outbound | TCP | 80 | Internet | Package managers (apt, choco) |
| 120 | Allow-AzureCloud-Outbound | Any | Any | AzureCloud | Key Vault, ARM, IMDS, Azure services |
| 130 | Allow-DNS-Outbound | Any | 53 | Any | DNS resolution |
| 4000 | Deny-All-Outbound | Any | Any | Any | Default deny for all other traffic |

## Inbound Traffic
All inbound traffic from the Internet is denied by explicit NSG rule (priority 4000).

## Exception Process
To request a temporary outbound allowance:
1. Open an issue with the `egress-exception` label
2. Specify: destination, port, protocol, duration, business justification
3. Requires platform engineering approval
4. Exceptions are implemented as time-limited NSG rules (priority 200-999)
5. Exceptions must be reviewed and removed at expiry

## Public IP Policy
- The GitHub runner VM supports an optional public IP (`enableGhPublicIp` parameter)
- Public IP is intended for dev/test environments ONLY
- Production deployments MUST set `enableGhPublicIp: false`
- All runners should use private connectivity where possible
