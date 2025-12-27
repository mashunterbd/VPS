1. ✅ The checklist **I originally designed** (engineering / practical / your real use-case driven)
2. ✅ The checklist **compiled from industry practice** (DevOps, sysadmins, communities, SaaS operators)

🔧 **What I did carefully**

* ✅ Merged both lists line-by-line
* ✅ Removed **only true duplicates**
* ❌ Did **NOT remove or skip** any requirement
* ➕ Added **extra expert suggestions** where professionals usually add guardrails
* 🧠 Structured so that **a beginner can follow**, but **a senior engineer will respect it**

This is now a **MASTER VPS BUYING & VERIFICATION CHECKLIST (2025-READY)**
You can use it **before buying**, **right after buying**, and **for long-term validation**.

# ✅ How to use
```
curl -fsSL https://raw.githubusercontent.com/mashunterbd/VPS/refs/heads/main/vps-check.sh | bash
```

---

# 🧾 MASTER VPS PRE-PURCHASE & POST-PURCHASE VERIFICATION CHECKLIST

**For Web Hosting, Email (Send/Receive), Automation, n8n, WordPress, and Advanced Services**

---

## SECTION 1 — PROVIDER-LEVEL CHECKS (BEFORE YOU BUY)

> Professionals ALWAYS evaluate the provider **before payment**.

### 1.1 Outbound SMTP Policy (CRITICAL — DO NOT SKIP)

Ask sales/support **before purchase**:

> “Are outbound SMTP ports **25, 587, and 465 open by default** on new VPS instances?”

**PASS**

* At least ONE port is open by default

**FAIL (REJECT PROVIDER)**

* “You must open a support ticket”
* “SMTP is blocked for security”
* “Use our relay only”

📌 If all SMTP ports are blocked → **email sending will never work reliably**

---

### 1.2 Reverse DNS (PTR) Control

Ask:

> “Can I set custom reverse DNS (PTR) for my VPS IP?”

**PASS**

* Self-service or support-assisted PTR allowed

**FAIL**

* No rDNS → emails go to spam or get rejected

---

### 1.3 IP Reputation Policy

Ask:

> “Are IPs checked against major blacklists before assignment?”

**PASS**

* Provider rotates or cleans IPs

**FAIL**

* “We don’t manage reputation” → risky for mail servers

---

### 1.4 Refund / Cancellation Policy

**PASS**

* Hourly billing or 24–72 hour refund

**FAIL**

* No refund window → high risk

---

## SECTION 2 — IMMEDIATE FIRST-BOOT CHECKS (AFTER BUY, BEFORE USING)

> Professionals run these checks **before installing anything**.

---

### 2.1 System & OS Validation

```bash
uname -a
lsb_release -a
```

**PASS**

* Ubuntu 20.04 / 22.04 / 24.04 LTS

---

### 2.2 CPU, RAM, Disk

```bash
lscpu
free -h
df -h
```

**PASS**

* ≥ 2 GB RAM (minimum)
* Adequate disk for mail + logs + apps

---

### 2.3 Disk Type & Performance

```bash
lsblk -o NAME,ROTA
```

**PASS**

* `ROTA = 0` (SSD / NVMe)

```bash
dd if=/dev/zero of=testfile bs=1G count=1 oflag=direct
```

**FAIL**

* Extremely slow I/O → automation & mail delays

---

## SECTION 3 — NETWORK & DNS HEALTH

### 3.1 Basic Connectivity

```bash
ping -c 3 1.1.1.1
ping -c 3 google.com
```

**PASS**

* Stable latency, no packet loss

---

### 3.2 DNS Resolution

```bash
dig google.com
```

**FAIL**

* Slow or broken DNS → web & mail failures

---

### 3.3 Public IP Verification

```bash
curl ifconfig.me
```

* Save this IP for rDNS & reputation checks

---

## SECTION 4 — OUTBOUND PORT VERIFICATION (MOST IMPORTANT)

> This section alone prevents 90% of VPS email problems.

### 4.1 SMTP Ports (MANDATORY)

Run ALL:

```bash
nc -vz gmail-smtp-in.l.google.com 25
nc -vz smtp.gmail.com 587
nc -vz smtp.gmail.com 465
```

**PASS**

* At least ONE succeeds

**FAIL (REJECT VPS IMMEDIATELY)**

* All timeout or hang

---

### 4.2 External SMTP Relay Compatibility

```bash
nc -vz smtp-relay.brevo.com 587
nc -vz smtp.mailgun.org 587
nc -vz email-smtp.us-east-1.amazonaws.com 587
```

**FAIL**

* Provider blocks SMTP globally

---

### 4.3 HTTPS & API Access (Automation Critical)

```bash
curl https://api.github.com
curl https://hooks.zapier.com
```

**FAIL**

* API blocked → n8n & integrations break

---

## SECTION 5 — FIREWALL & CONTROL

### 5.1 Provider Firewall Transparency

Check:

* Is there a cloud firewall UI?
* Can outbound rules be modified?

**FAIL**

* Hidden outbound rules = provider-controlled VPS

---

### 5.2 Local Firewall Control

```bash
ufw status
iptables -L -n
```

**PASS**

* Full admin control

---

## SECTION 6 — EMAIL SYSTEM READINESS (SEND & RECEIVE)

### 6.1 Required Mail Ports

| Service  | Ports          |
| -------- | -------------- |
| SMTP     | 25 / 587 / 465 |
| IMAP     | 143 / 993      |
| POP3     | 110 / 995      |
| DKIM     | 8891           |
| Loopback | 127.0.0.1      |

---

### 6.2 Local Mail Test (After Postfix Install)

```bash
printf "Subject: Test\n\nHello" | sendmail test@yourdomain.com
```

**PASS**

* Delivered locally

---

### 6.3 Mail Queue Check

```bash
postqueue -p
```

**PASS**

* Empty queue

**FAIL**

* Timeout / connection errors

---

## SECTION 7 — EMAIL DELIVERABILITY REQUIREMENTS

### 7.1 SPF (DNS)

```text
v=spf1 ip4:YOUR_SERVER_IP include:spf.brevo.com -all
```

---

### 7.2 DKIM

* Port 8891 must be allowed
* Loopback connections must not be blocked

---

### 7.3 DMARC

```text
v=DMARC1; p=none; rua=mailto:dmarc@yourdomain.com
```

---

### 7.4 IP Reputation Check

Check manually:

* mxtoolbox.com
* talosintelligence.com

**FAIL**

* Blacklisted IP → reject VPS

---

## SECTION 8 — WEB HOSTING (WORDPRESS / CYBERPANEL)

### Required Ports

| Service | Port |
| ------- | ---- |
| HTTP    | 80   |
| HTTPS   | 443  |
| SSH     | 22   |
| FTP     | 21   |
| DNS     | 53   |

---

### SSL Test

```bash
openssl s_client -connect yourdomain.com:443
```

---

## SECTION 9 — AUTOMATION & ADVANCED SERVICES (n8n, APIs)

### 9.1 Docker Support

```bash
docker --version
```

or

```bash
ls /sys/fs/cgroup
```

---

### 9.2 Webhook Accessibility

* Server must accept inbound HTTPS
* Outbound HTTPS must not be filtered

---

## SECTION 10 — LONG-TERM SCALABILITY

Check if you can:

* Reinstall OS freely
* Upgrade RAM / CPU
* Add IPv6
* Change hostname & rDNS
* Attach additional storage

**FAIL**

* Locked infrastructure → not suitable long-term

---

## FINAL GO / NO-GO DECISION MATRIX

### ✅ USE VPS IF:

* At least one outbound SMTP port works
* rDNS configurable
* Outbound HTTPS unrestricted
* Clean IP reputation
* Full firewall control

### ❌ REJECT VPS IF:

* All SMTP ports blocked
* SMTP requires support ticket
* No rDNS
* NAT/shared IP
* Hidden outbound filtering

---

## WHY THIS CHECKLIST EXISTS

This checklist is designed so that:

* You detect deal-breakers in **minutes**
* You never depend on support promises
* You avoid the exact SMTP trap you faced
* You can confidently host **WordPress, n8n, mail servers, and future services**

---
