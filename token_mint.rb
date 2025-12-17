require "stellar-sdk"
require "faraday"
require "json"
require 'dotenv'

Dotenv.load

HORIZON_URL = "https://api.testnet.minepi.com"
HORIZON     = Stellar::Horizon::Client.new(horizon: HORIZON_URL)
#puts HORIZON.inspect #Enale for debugging 
# Pi Testnet passphrase
NETWORK     = "Pi Testnet"

issuer_secret      = ENV["ISSUER_SECRET"] || " ISSUER WALLET SECRET here "
distributor_secret = ENV["DISTRIBUTOR_SECRET"] || " DISTRIBUTOR WALLET SECRET HERE"

if issuer_secret.nil? || issuer_secret.strip.empty? || issuer_secret == "ISSUER WALLET SECRET here"
  raise "Missing credentials: issuer_secret is not set or is using a placeholder"
end

if distributor_secret.nil? || distributor_secret.strip.empty? || distributor_secret == "DISTRIBUTOR WALLET SECRET HERE"
  raise "Missing credentials: distributor_secret is not set or is using a placeholder"
end

abort "Missing ISSUER_SECRET" unless issuer_secret
abort "Missing DISTRIBUTOR_SECRET" unless distributor_secret

TOKEN_CODE  = ENV["TOKEN_CODE"]
MINT_AMOUNT = ENV["MINT_Amount"] || "10000000" #10M Tokens default 

Stellar.default_network = NETWORK
# fetch latest ledger for base fee
ledgers = HORIZON.instance_variable_get(:@horizon).ledgers(order: "desc", limit: 1)
latest_ledger = ledgers._get["_embedded"]["records"].first
BASE_FEE = latest_ledger["base_fee_in_stroops"]
bf=BASE_FEE/1000000
puts "Base FEE in regular Decimals ... .."
puts bf
def sequence(pubkey)
  json = JSON.parse(Faraday.get("#{HORIZON_URL}/accounts/#{pubkey}").body)
  json["sequence"].to_i
end

def submit_with_logging(env)
  unless env.is_a?(Stellar::TransactionEnvelope)
    raise "Expected TransactionEnvelope, got #{env.class}"
  end

  if env.signatures.empty?
    raise "Refusing to submit unsigned transaction .... #{env.inspect}   ...."
  end

  resp = HORIZON.submit_transaction(tx_envelope: env)
  puts "✔ OK → #{resp['hash']}  -- Hash Value"
  resp
rescue Faraday::BadRequestError => e
  puts "⚠️ Horizon rejected transaction:"
  puts e.response[:body]
  exit
end

def debug_envelope(env)
  #puts "Envelope class: #{env.class}" ### comment out for debugging
  puts "Signature count: #{env.signatures.length}" #If Value is 0 the Signature is invalid expected value 1
  env.signatures.each_with_index do |sig, i|
    #puts "  Sig #{i} hint: #{Base64.strict_encode64(sig.hint)}" # comment out for debugging
  end
end


begin
  issuer      = Stellar::KeyPair.from_seed(issuer_secret)
  puts "issuer public address... .... "
  #puts issuer.inspect ### comment out for debugging
  puts issuer.address
  distributor = Stellar::KeyPair.from_seed(distributor_secret)
  puts "distributor public address... .... "
  #puts distributor.inspect ### comment out for debugging
  puts distributor.address
  
  asset = Stellar::Asset.alphanum12(TOKEN_CODE, issuer)
  puts "asset to mint ... ..... ......"
  puts asset.inspect

  puts "####################################################################"
  puts "#*# STEP 1: Creating trustline... ........           .....       #*#"
  puts "####################################################################"

  seq = sequence(distributor.address)
  puts "DISTRIBUTOR sequnce ... .... ....."
  puts seq.inspect
  seq_n = seq+1
  puts "using sequence for this transaction-- #{seq_n.inspect}"
  trust_builder = Stellar::TransactionBuilder.new(
    source_account: distributor,
    sequence_number: seq_n,
    base_fee: BASE_FEE,
    networkPassphrase: NETWORK
  )
  puts "initiating trust builder ......."
  trust_builder.add_operation(
    Stellar::Operation.change_trust(
      asset: asset,
      limit: ENV["MINT_LIMIT"] || "1000000000"   ## use string, not nil. limit of token mints 10B default 
    )
  )

  trust_builder.set_timeout(300)
  trust_tx = trust_builder.build
  trust_txd = trust_tx.to_envelope 
  tx_hash = trust_tx.hash
  sig = distributor.sign_decorated(tx_hash)
  trust_txd.signatures << sig
  debug_envelope(trust_txd)
  res1 = submit_with_logging(trust_txd)
  puts "trustline build ledger value .... ....."
  puts res1['ledger']

  puts "####################################################################"
  puts "#*# STEP 2: Minting #{MINT_AMOUNT} ,-'  #{TOKEN_CODE}...  ....   #*#"
  puts "####################################################################"

  seq1 = sequence(issuer.address)
  puts "issuer sequence .... ...... ........"
  puts seq1.inspect
  seq1_n = seq1+1
  puts "using sequence for current transaction-- #{seq1_n.inspect}"
  pay_builder = Stellar::TransactionBuilder.new(
    source_account: issuer,
    sequence_number: seq1_n,
    base_fee: BASE_FEE,
    networkPassphrase: NETWORK
  )
  pay_builder.add_operation(
    Stellar::Operation.payment(
      destination: distributor,
      amount: [asset, MINT_AMOUNT]
    )
  )
  puts "paying builder for operation Mint"


  pay_builder.set_timeout(300)
  pay_tx = pay_builder.build
  puts "pay transaction.. .... ......."
  pay_txd = pay_tx.to_envelope
  tx_hash = pay_tx.hash
  sig = issuer.sign_decorated(tx_hash)
  pay_txd.signatures << sig
  debug_envelope(pay_txd)
  res2 = submit_with_logging(pay_txd)
  puts "ledger for issing Tokens"
  puts res2['ledger']

  puts "####################################################################"
  puts "## STEP 3: Checking distributor balances... ... ... ... ... ... ..##"
  puts "####################################################################"

  distributor_info = JSON.parse(Faraday.get("#{HORIZON_URL}/accounts/#{distributor.address}").body)
  distributor_info["balances"].each do |bal|
    if bal["asset_type"] == "native"
      puts "Test-Pi Balance: #{bal["balance"]}"
    else
      puts "#{bal["asset_code"]} Balance: #{bal["balance"]}"
    end
  end

  puts "\n🎉 DONE — Trustline + mint complete!"

rescue => e
  puts "\n❌ ERROR: #{e.class} — #{e.message}"
  puts e.backtrace.join("\n")
end