require "stellar-sdk"
require 'net/http'
require 'json'
require 'dotenv'

Dotenv.load

issuer_secret      = ENV["ISSUER_SECRET"] 
distributor_secret = ENV["DISTRIBUTOR_SECRET"] 

if issuer_secret.nil? || issuer_secret.strip.empty?
  raise "Missing credentials: issuer_secret is not set or is using a placeholder"
  else
  puts "ISSUER: #{issuer_secret}  ✅"
end

if distributor_secret.nil? || distributor_secret.strip.empty?
  raise "Missing credentials: distributor_secret is not set or is using a placeholder"
  else
  puts "DISTRIBUTOR: #{distributor_secret}  ✅"
end

TOKEN_CODE  = ENV["TOKEN_CODE"]
if TOKEN_CODE.nil? || TOKEN_CODE.strip.empty?
  raise "Missing credentials: TOKEN_CODE is not set or is using a placeholder"
  else
  puts "TOKEN_CODE: #{TOKEN_CODE}   ✅"
end
MINT_AMOUNT = ENV["MINT_Amount"]
if MINT_AMOUNT.nil? || MINT_AMOUNT.strip.empty?
  raise "Missing credentials: MINT_AMOUNT is not set or is using a placeholder"
  else
  puts "TOKEN MINT AMOUNT: #{MINT_AMOUNT}   ✅"
end
ISSUER_PUBLIC = ENV["ISSUER_PUBLIC_ADDRESS"]
if ISSUER_PUBLIC.nil? || ISSUER_PUBLIC.strip.empty?
  raise "Missing credentials: ISSUER_PUBLIC is not set or is using a placeholder"
  else
  puts "ISSUER PUBLIC Key: #{ISSUER_PUBLIC}  ✅"
end
PI_AMOUNT     = ENV["LP_PI_DEPOSIT"]      # Native PI
if PI_AMOUNT.nil? || PI_AMOUNT.strip.empty?
  raise "Missing credentials: PI_AMOUNT is not set or is using a placeholder"
  else
  puts "PI_AMOUNT: #{PI_AMOUNT}  ✔️"
end
TOKEN_AMOUNT = ENV["LP_TOKEN_DEPOSIT"] 
if TOKEN_AMOUNT.nil? || TOKEN_AMOUNT.strip.empty?
  raise "Missing credentials: TOKEN_AMOUNT is not set or is using a placeholder"
  else
  puts "LIQUIDITY POOL TOKEN AMOUNT: #{TOKEN_AMOUNT}  ✔️"
end



issuer      = Stellar::KeyPair.from_seed(issuer_secret)
distributor = Stellar::KeyPair.from_seed(distributor_secret)

puts "ISSUER PUBLIC KEY: #{issuer.address}   ✅Verified with Network"
puts "DISTRIBUTOR PUBLIC KEY: #{distributor.address}  ✅Verified with Network"
testnet = "https://api.mainnet.minepi.com"

#server = Stellar::Client.testnet
server = Stellar::Horizon::Client.new(horizon: testnet)
#puts server.inspect


ledgers = server.instance_variable_get(:@horizon).ledgers(order: "desc", limit: 1)
#puts ledgers.inspect
latest_ledger = ledgers._get["_embedded"]["records"].first
#puts latest_ledger.inspect
base_fee = latest_ledger["base_fee_in_stroops"]

puts "Base Fee (stroops): #{base_fee}"


uri = URI("https://api.testnet.minepi.com/fee_stats")
response = Net::HTTP.get(uri)
fee_stats = JSON.parse(response)
puts fee_stats.inspect

recommended_fee = fee_stats["fee_charged"]["p70"].to_i  # 70th percentile fee
puts "Recommended Fee (stroops): #{recommended_fee}"
