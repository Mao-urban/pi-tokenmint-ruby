# pi-tokenmint-ruby
To mint Tokens on Pi Testnet and create a Liquidity Pool using ruby
# KVERSE Pi Testnet Token Toolkit (Ruby)

This repository contains a **complete Ruby-based workflow** for creating, configuring, and provisioning a custom token on the **Pi Testnet (Stellar-compatible Horizon)**  using ruby with stelar sdk gem .
Visit Pi platfor docs for more details https://github.com/pi-apps/pi-platform-docs/blob/master/tokens.md
The scripts are designed to be executed **in a strict order**, where each step depends on the successful completion of the previous one.

#Advanced 
The files in advanced is for analysing and transfer of minted tokens
---

## 📂 Files in This Repository

| File | Purpose |
|----|----|
| `VerifyKey.rb` | Verifies network connectivity, Horizon access, and fetches recommended base fee |
| `token_mint.rb` | Creates and mints the custom asset from the Issuer to Distributor |
| `token_domain.rb` | Sets Home Domain + TOML metadata for token verification |
| `Token_LP.rb` | Creates and deposits into a Liquidity Pool (AMM) |
| `.env` | Environment variables for secrets and configuration |

---

## 🔁 **Execution Order (IMPORTANT)**

Run the scripts **exactly in the following order**:

1. `VerifyKey.rb`
2. `token_mint.rb`
3. `token_domain.rb`
4. `Token_LP.rb`

Skipping or reordering steps may cause transaction failures.

---

## ⚙️ System Requirements

- Ruby **3.1+** (3.2 or 3.3 recommended)
- Bundler (`gem install bundler`)
- Internet access (Pi Testnet Horizon)

---

## 📦 Gemfile

Create a file named **`Gemfile`** in the root of the repository with the following content:

```ruby
source "https://rubygems.org"

ruby ">= 3.1"

gem "stellar-sdk", "~> 0.31"
gem "faraday", ">= 2.0"
gem "json"
```
or use gem install for each

### Install Dependencies

```bash
bundle install
```

---

## 🔐 Environment Configuration (`.env`)

Create or edit `.env` with the following values:

```env
# ISSUER WALLET (creates the token)
ISSUER_SECRET=SBXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
ISSUER_ADDRESS=GAXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# DISTRIBUTOR WALLET (holds supply + LP)
DISTRIBUTOR_SECRET=SBXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
DISTRIBUTOR_ADDRESS=GBXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# TOKEN DETAILS
TOKEN_CODE=KVERSE
HOME_DOMAIN=example.com
```

⚠️ **Never commit real secrets to GitHub**

---

## 🧩 STEP-BY-STEP EXECUTION GUIDE

---

### **1️⃣ Verify Network & Fees**

```bash
ruby VerifyKey.rb
```

**What this does:**
- Connects to Pi Testnet Horizon
- Confirms Horizon availability
- Fetches recommended base fee

**Expected Output:**
```
Horizon reachable
Recommended Fee (stroops): 10000
```

✔️ If this fails, **do not proceed further**.

---

### **2️⃣ Mint the Token** (`token_mint.rb`)

```bash
ruby token_mint.rb
```

**What this does:**
- Creates the custom asset (`TOKEN_CODE`)
- Establishes trustline from Distributor
- Mints initial supply from Issuer → Distributor

**On-chain results:**
- Token exists on Pi Testnet
- Distributor holds total supply

**Expected Output:**
```
Token minted successfully
Tx hash: XXXXX
```

---

### **3️⃣ Set Home Domain & TOML** (`token_domain.rb`)

```bash
ruby token_domain.rb
```

**What this does:**
- Sets `home_domain` on Issuer account
- Enables token verification via `pi.toml`

You must host a valid:
```
https://<HOME_DOMAIN>/.well-known/pi.toml
```

**Example TOML snippet:**
```toml
[[CURRENCIES]]
code = "KVERSE"
issuer = "GAXXXXXXXXXXXXX"
status = "live"
```

---

### **4️⃣ Create Liquidity Pool (AMM)** (`Token_LP.rb`)

```bash
ruby Token_LP.rb
```

**What this does:**
- Creates a constant-product liquidity pool
- Deposits base asset + KVERSE
- Enables trading on DEX

**Expected Output:**
```
Liquidity pool created
LP shares received: XXXXX
```

If LP shares are not shown immediately, check Horizon Explorer.

---

## 🧠 Architecture Notes

- Issuer wallet **never** holds LP or circulating supply
- Distributor handles:
  - User distribution
  - Liquidity provisioning
- All transactions are signed locally

---

## 🔍 Troubleshooting

### SSL / OpenSSL errors
```bash
gem uninstall openssl
bundle install
```

### Liquidity pool not visible
- Horizon indexing delay
- Verify asset order and fee

### `tx_bad_auth`
- Wrong secret key
- Network mismatch (Testnet vs Mainnet)

---

## 🚀 Next Steps

- Add price-controlled LP rebalancing
- Automated airdrop scripts
- Governance / voting token extensions

---

## 📜 License

MIT – free to use, modify, and deploy.

---

### Maintained for Pi Testnet 

