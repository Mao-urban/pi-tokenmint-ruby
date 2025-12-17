require "stellar-sdk"
require "faraday"
require "json"
require 'dotenv'

Dotenv.load

HORIZON_URL = "https://api.testnet.minepi.com"
NETWORK     = "Pi Testnet"

ISSUER_SECRET = ENV["ISSUER_SECRET"]
HOME_DOMAIN   = ENV["HOME_DOMAIN"]

Stellar.default_network = NETWORK
HORIZON = Stellar::Horizon::Client.new(horizon: HORIZON_URL)

def submit_with_logging(env)
  unless env.is_a?(Stellar::TransactionEnvelope)
    raise "Expected TransactionEnvelope, got #{env.class}"
  end

  if env.signatures.empty?
    raise "Refusing to submit unsigned transaction"
  end

  resp = HORIZON.submit_transaction(tx_envelope: env)
  puts "✔ OK → #{resp['hash']}"
  resp
rescue Faraday::BadRequestError => e
  puts "⚠️ Horizon rejected transaction:"
  puts e.response[:body]
  exit
end

def debug_envelope(env)
  puts "Envelope class: #{env.class}"
  puts "Signature count: #{env.signatures.length}"
  env.signatures.each_with_index do |sig, i|
    puts "  Sig #{i} hint: #{Base64.strict_encode64(sig.hint)}"
  end
end


def sequence(pubkey)
  JSON.parse(
    Faraday.get("#{HORIZON_URL}/accounts/#{pubkey}").body
  )["sequence"].to_i
end

issuer = Stellar::KeyPair.from_seed(ISSUER_SECRET)
seq    = sequence(issuer.address) + 1

builder = Stellar::TransactionBuilder.new(
  source_account: issuer,
  sequence_number: seq,
  base_fee: 100_000,
  networkPassphrase: NETWORK
)

builder.add_operation(
  Stellar::Operation.set_options(
    home_domain: HOME_DOMAIN
  )
)

builder.set_timeout(300)
tx  = builder.build
env = tx.to_envelope
tx_hash = tx.hash
sig = issuer.sign_decorated(tx_hash)
#env.sign(issuer)
env.signatures << sig
debug_envelope(env)
#puts env.inspect 										### comment out for debugging
#resp = horizon.submit_transaction(tx_envelope: env)	### comment out for debugging
resp = submit_with_logging(env) 
puts "✅ home_domain set correctly via SET_OPTIONS"
#puts "Tx hash: #{resp.inspect}" 						### comment out for debugging
puts "Tx hash: #{resp['hash']}"
