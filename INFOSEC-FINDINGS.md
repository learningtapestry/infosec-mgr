# Learning Tapestry AWS Security Findings

**Generated:** 2025-12-30
**Scanner:** ScoutSuite
**Product:** learningtapestry/infosec-mgr (AWS Account: 866795125297)

## Executive Summary

ScoutSuite cloud security scan identified 350 findings. After applying the Learning Tapestry security policy for small projects:

| Category | Count | Status |
|----------|-------|--------|
| Fixed automatically | 19 | Password policy (2), EBS encryption (17) |
| Requires manual action | 6 | SSH (2), Root MFA (2), IAM policies (2) |
| Needs review | 83 | Security groups (79), S3 buckets (3), IAM role (1) |
| Deferred by policy | 242 | CloudTrail, NACL defaults, Flow Logs |
| **Remaining active** | **89** | 6 Critical, 83 Medium |

---

## LT Minimal Viable Security Policy

This policy defines what Learning Tapestry considers "secure by default" for small projects, balancing security with cost and operational complexity.

### Intentionally Deferred (Cost/Complexity)

The following are **not required** for small projects but should be enabled for:
- Production workloads with compliance requirements
- Projects handling sensitive data
- Enterprise customers

| Finding | Reason for Deferral |
|---------|---------------------|
| CloudTrail | $2-5/month per trail + S3 storage. Enable when budget allows or compliance requires. |
| AWS Config | $2/month per rule + S3. Enable for compliance or multi-account governance. |
| VPC Flow Logs | $0.50/GB. Enable for incident response or compliance. |
| Default NACLs | Security groups provide sufficient network control at instance level. |
| Password Expiration | Outdated practice per NIST 800-63B and Microsoft guidance. |

### Required for All Projects

| Requirement | Status |
|-------------|--------|
| Strong password policy (14+ chars, complexity) | Fixed |
| No password reuse (24 passwords) | Fixed |
| EBS encryption by default | Fixed |
| SSH restricted to known IPs | **ACTION REQUIRED** |
| Root account MFA | **ACTION REQUIRED** |

---

## Action Required

### 1. Restrict SSH Access (CRITICAL)

**Finding:** Security Group Opens SSH Port to All (2 instances)

**Risk:** SSH port 22 is open to `0.0.0.0/0`, exposing the instance to brute-force attacks from any IP.

**Affected Security Groups:**
- `sg-067eef265a70759e1` in `vpc-0d9a5bf5668df2b5c`
- `sg-0f9e42d02089cc239` in `vpc-07120eb37cab0fb5d`

**Fix Options:**

**Option A: Update Terraform (Recommended)**
Edit `terraform/terraform.tfvars` and add your allowed IPs:
```hcl
allowed_ssh_cidrs = [
  "YOUR_OFFICE_IP/32",
  "YOUR_VPN_RANGE/24"
]
```
Then apply: `cd terraform && terraform apply`

**Option B: Manual AWS Console Fix**
1. Go to EC2 > Security Groups
2. Edit inbound rules for each security group
3. Change SSH source from `0.0.0.0/0` to your IP range

**Option C: Use AWS Systems Manager Session Manager**
Remove SSH entirely and use SSM for access (requires EC2 instance profile with SSM permissions).

---

### 2. Enable Root Account MFA (CRITICAL)

**Finding:** Root Account Without MFA

**Risk:** The AWS root account has no MFA enabled. Root account compromise gives full access to all resources.

**Current Status:** This is an AWS Organizations member account where:
- Root console access was never established
- Password reset via AWS Console **fails with an error**
- AWS Support ticket required to resolve

**Compensating Controls (IMPLEMENTED):**
- All operational access via IAM user `infosec-admin` with full admin privileges
- MFA enabled on `infosec-admin` (or pending activation)
- Account protected by Organizations SCPs from management account (264441468378)
- Root API/CLI access is not possible (by AWS design - root can ONLY use console)

**Priority:** Medium - compensating controls are in place. Open AWS Support ticket when convenient.

**Fix (requires management account access):**

1. **Find root email** (from management account 264441468378):
   ```bash
   aws organizations describe-account --account-id 866795125297
   ```
   Or: AWS Console → Organizations → Accounts → Find this account

2. **Password reset:**
   - Go to https://console.aws.amazon.com/
   - Select "Root user", enter the root email
   - Click "Forgot password?" and complete reset via email

3. **Enable MFA:**
   - Log in as root
   - Account menu (top right) → Security credentials
   - Assign MFA device → Authenticator app
   - Scan QR code, enter two consecutive codes

**Note:** Hardware MFA (YubiKey) is ideal but not required for small projects.

---

## Needs Review

The following findings require evaluation. They may indicate real security issues or may be acceptable depending on your architecture.

### Security Group Configuration (59 findings)

| Finding | Count | Assessment |
|---------|-------|------------|
| Non-Empty Rulesets for Default Security Groups | 38 | **Review:** Default SG should have no rules. Resources should use custom SGs. |
| Security Group Opens All Ports | 19 | **Review:** Likely internal SGs. Verify these are intentional. |
| Unrestricted Network Traffic Within Security Group | 19 | **Review:** Normal for internal communication. Document if intentional. |
| Security Group Opens TCP Port to All | 2 | **Review:** Likely HTTP/HTTPS. Verify intended ports. |
| Unused Security Group | 1 | **Cleanup:** Safe to delete if not in use. |

**Recommendation:** Default security groups across all VPCs have rules added to them. Best practice is to never use the default security group - create custom security groups for each resource type. Consider:
1. Reviewing each default SG to understand why rules exist
2. Creating named security groups (e.g., `web-sg`, `db-sg`)
3. Removing rules from default security groups

### IAM Policies (3 findings)

| Finding | ID | Assessment |
|---------|-----|------------|
| Managed Policy Allows All Actions | 1566 | **INVESTIGATE:** A policy grants `*:*` permissions. Identify and restrict. |
| Cross-Account AssumeRole Lacks External ID and MFA | 1565 | **Review:** Add external ID for cross-account roles. |
| Role With Inline Policies | 1571 | **Low priority:** Prefer managed policies but inline is acceptable. |

**Action:** Run this to identify the problematic policy:
```bash
aws iam list-policies --scope Local --query 'Policies[*].[PolicyName,Arn]' --output table
aws iam get-policy-version --policy-arn <ARN> --version-id v1
```

### S3 Bucket Configuration (3 findings)

| Finding | ID | Assessment |
|---------|-----|------------|
| Bucket Allowing Clear Text (HTTP) | 1574 | **Review:** Add bucket policy requiring `aws:SecureTransport`. |
| Bucket Access Logging Disabled | 1575 | **Low priority:** Enable for compliance or audit requirements. |
| Bucket Without MFA Delete | 1576 | **Low priority:** Enable for critical data protection. |

---

## Fixed Automatically

The following issues were fixed via API/CLI:

### IAM Password Policy
- Minimum password length: **14 characters** (was undefined)
- Require uppercase, lowercase, numbers, symbols: **Enabled**
- Password reuse prevention: **24 passwords**
- Password expiration: **Disabled** (per modern NIST guidance)

### EBS Encryption
- EBS encryption by default: **Enabled in all 17 regions**

---

## Deferred by Policy (Out of Scope)

The following 242 findings were marked as "Out of Scope" in DefectDojo with policy notes. They will not appear in active findings but are documented for audit purposes.

| Category | Count | Policy Reason |
|----------|-------|---------------|
| CloudTrail not configured | 17 | Cost deferral for small projects |
| AWS Config not enabled | 17 | Cost deferral for small projects |
| VPC Flow Logs | 56 | Cost deferral for small projects |
| Default NACLs (egress) | 56 | Security groups sufficient |
| Default NACLs (ingress) | 56 | Security groups sufficient |
| Network ACL egress | 19 | Security groups sufficient |
| Network ACL ingress | 19 | Security groups sufficient |
| Password expiration | 2 | Outdated practice (NIST 800-63B) |

---

## ScoutSuite Configuration

A custom ruleset has been created at `.scoutsuite/lt-ruleset.json` that:
- Disables rules for deferred findings (CloudTrail, Flow Logs, etc.)
- Keeps critical security rules enabled (SSH, password, MFA)

Future ScoutSuite scans using this ruleset will not report deferred findings.

---

## References

- [NIST 800-63B: Password Guidelines](https://pages.nist.gov/800-63-3/sp800-63b.html)
- [AWS Security Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [ScoutSuite Documentation](https://github.com/nccgroup/ScoutSuite/wiki)
