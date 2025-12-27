require "stellar-sdk"
require "faraday"
require "json"
require 'dotenv'

Dotenv.load

# =====================================================
# CONFIG
# =====================================================

HORIZON_URL = "https://api.testnet.minepi.com"
NETWORK     = "Pi Testnet"

HORIZON = Stellar::Horizon::Client.new(horizon: HORIZON_URL)

# -----------------------------------------------------
# Fetch base fee from latest ledger
# -----------------------------------------------------
ledgers = HORIZON.instance_variable_get(:@horizon)
                 .ledgers(order: "desc", limit: 1)
latest_ledger = ledgers._get["_embedded"]["records"].first
BASE_FEE = latest_ledger["base_fee_in_stroops"]

puts "Base Fee: #{BASE_FEE}"

# =====================================================
# ACCOUNTS
# =====================================================

LP_SECRET = ENV["DISTRIBUTOR_SECRET"] || " DISTRIBUTOR WALLET SECRET HERE" 

TOKEN_CODE    = ENV["TOKEN_CODE"]
ISSUER_PUBLIC = ENV["ISSUER_PUBLIC_ADDRESS"]

if LP_SECRET.nil? || LP_SECRET.strip.empty? || LP_SECRET == "DISTRIBUTOR WALLET SECRET HERE"
  raise "Missing credentials: distributor_secret is not set or not readable from env"
end
abort "Missing DISTRIBUTOR_SECRET" unless LP_SECRET

# =====================================================
# DEPOSIT CONFIG
# =====================================================

PI_AMOUNT     = ENV["LP_PI_DEPOSIT"]      # Native PI
TOKEN_AMOUNT = ENV["LP_TOKEN_DEPOSIT"]    # Token amount

# VERY WIDE bounds for first deposit (important)
MIN_PRICE = Stellar::Price.new(n: 1, d: 10_000)
MAX_PRICE = Stellar::Price.new(n: 10_000, d: 1)

# =====================================================
# NETWORK
# =====================================================

Stellar.default_network = NETWORK

# =====================================================
# HELPERS
# =====================================================

def account_info(account_id)
  JSON.parse(
    Faraday.get("#{HORIZON_URL}/accounts/#{account_id}").body
  )
end

def sequence(account_id)
  account_info(account_id)["sequence"].to_i
end

def liquidity_pool_exists?(pool_id)
  Faraday.get("#{HORIZON_URL}/liquidity_pools/#{pool_id}").status == 200
end

# =====================================================
# KEYPAIRS & ASSETS
# =====================================================

lp     = Stellar::KeyPair.from_seed(LP_SECRET)
issuer = Stellar::KeyPair.from_address(ISSUER_PUBLIC)

native = Stellar::Asset.native
token = Stellar::Asset.alphanum12(TOKEN_CODE, issuer)

puts "LP Address: #{lp.address}"
puts "Issuer: #{ISSUER_PUBLIC}"

# =====================================================
# DEFINE POOL (NOT ON-CHAIN YET)
# =====================================================

pool = Stellar::LiquidityPool.constant_product(
  asset_a: native,
  asset_b: token
)

puts "Liquidity Pool ID: #{pool.id}"

# =====================================================
# SAFETY CHECKS + CHECKLIST
# =====================================================

balances = account_info(lp.address)["balances"]

puts "\n🔎 PRE-FLIGHT CHECKLIST"

# ---- Native PI ----
native_entry = balances.find { |b| b["asset_type"] == "native" }
abort "❌ Native PI balance not found" unless native_entry

native_balance = native_entry["balance"].to_f
puts "• PI Balance: #{native_balance}"

abort "❌ Insufficient PI (need > #{PI_AMOUNT.to_f + 1})" \
  if native_balance < PI_AMOUNT.to_f + 1

# ---- token trustline ----
token_entry = balances.find do |b|
  b["asset_code"] == TOKEN_CODE &&
  b["asset_issuer"] == ISSUER_PUBLIC
end

abort "❌ #{TOKEN_CODE} Token trustline NOT FOUND — create trustline first" unless token_entry

token_balance = token_entry["balance"].to_f
puts "• token Balance: #{token_balance}"

abort "❌ Insufficient token (need #{TOKEN_AMOUNT})" \
  if token_balance < TOKEN_AMOUNT.to_f

puts "• #{TOKEN_CODE} Token trustline exists"
puts "• Price bounds are wide (first-deposit safe)"
puts "✅ ALL CHECKS PASSED\n"

# =====================================================
# DEPOSIT (POOL + LP TRUSTLINE AUTO-CREATED)
# =====================================================

puts liquidity_pool_exists?(pool.id) ?
     "ℹ️ Pool exists — adding liquidity" :
     "🚀 Creating pool via first deposit"

builder = Stellar::TransactionBuilder.new(
  source_account: lp,
  sequence_number: sequence(lp.address) + 1,
  base_fee: BASE_FEE,
  networkPassphrase: NETWORK
)

#

lp_trust = Stellar::ChangeTrustAsset.liquidity_pool(pool.pool_params)

builder.add_operation(
  Stellar::Operation.make(
    body: [:change_trust, Stellar::ChangeTrustOp.new(
      line: lp_trust,
      limit: Stellar::Operation::MAX_INT64
    )],
    source_account: lp
  )
)



builder.add_operation(
  Stellar::Operation.liquidity_pool_deposit(
    liquidity_pool_id: pool.id,
    max_amount_a: PI_AMOUNT,
    max_amount_b: TOKEN_AMOUNT,
    min_price: MIN_PRICE,
    max_price: MAX_PRICE
  )
)

builder.set_timeout(300)

tx  = builder.build
env = tx.to_envelope
env.signatures << lp.sign_decorated(tx.hash)

begin
  resp = HORIZON.submit_transaction(tx_envelope: env)
rescue Faraday::BadRequestError => e
  puts "❌ Horizon rejected transaction"
  puts e.response[:body]
  raise
end

puts "#-*-#._.#-*-#._.#-*-#._.#-*-#._.#-*-#._.#-*-#._.#-*-#"
puts "    🎉🎉🎉 LIQUIDITY DEPOSIT SUCCESSFUL 🎉🎉🎉    "
puts "#-*-#._.#-*-#._.#-*-#._.#-*-#._.#-*-#._.#-*-#._.#-*-#"
puts "Pool ID: #{pool.id}"
puts "Tx Hash: #{resp['hash']}"
puts "Ledger: #{resp['ledger']}"
# = #-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#
# Creating ini LP data file
# = #-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#
File.open("#{TOKEN_CODE}_LP.ini", "w") do |f|
  f.puts "[#{TOKEN_CODE} LiquidityPool]"
  f.puts "Pool ID = #{pool.id}"
  f.puts "Tx Hash = #{resp['hash']}"
  f.puts "Ledger = #{resp['ledger']}"
end
# =====================================================
# VERIFY LP SHARES
# =====================================================

balances = account_info(lp.address)["balances"]

lp_share = balances.find do |b|
  b["asset_type"] == "liquidity_pool_shares" &&
  b["liquidity_pool_id"] == pool.id
end

if lp_share
  puts "💧 LP Share Balance: #{lp_share['balance']}"
else
  puts "⚠️ LP shares not found yet (check Horizon explorer)"
end

