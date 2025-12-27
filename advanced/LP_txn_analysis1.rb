require "faraday"
require "json"
require "time"
require "date"
require "gruff"
require "csv"
require "write_xlsx"   # gem install write_xlsx
require "zip"          # gem install rubyzip
require "fileutils"

# Generate timestamp once per run
TIMESTAMP  = Time.now.strftime("%Y%m%d_%H%M%S")
OUTPUT_DIR = "pool_analytics/analytics_#{TIMESTAMP}_time_vol"
puts "Getting things ready ........"
# Create subfolder
FileUtils.mkdir_p(OUTPUT_DIR)

HORIZON_URL = "https://api.testnet.minepi.com"
POOL_ID     = " "  #Enter Your Liquidity pool id here

def pool_transactions(pool_id, limit: 200)
  url = "#{HORIZON_URL}/liquidity_pools/#{pool_id}/transactions?order=desc&limit=#{limit}"
  JSON.parse(Faraday.get(url).body)["_embedded"]["records"]
end

def pool_operations(pool_id, limit: 200)
  url = "#{HORIZON_URL}/liquidity_pools/#{pool_id}/operations?order=desc&limit=#{limit}"
  JSON.parse(Faraday.get(url).body)["_embedded"]["records"]
end

def time_bucket_4h(time)
  t = Time.parse(time)
  bucket_start_hour = (t.hour / 4) * 4
  bucket_start = Time.new(t.year, t.month, t.day, bucket_start_hour, 0, 0, t.utc_offset)
  bucket_end   = bucket_start + (4 * 3600) - 1

  "#{bucket_start.strftime('%Y-%m-%d %H:00')}–#{bucket_end.strftime('%H:59')}"
end


def analytics(transactions, operations)
  # Transactions per day
  tx_per_day = transactions
    .group_by { |tx| Date.parse(tx["created_at"]) }
    .transform_values(&:count)

  # Unique transactions per day (by hash)
  unique_tx_per_day = transactions
    .group_by { |tx| Date.parse(tx["created_at"]) }
    .transform_values { |arr| arr.map { |tx| tx["hash"] }.uniq.count }

  # Transactions per hour (string key "YYYY-MM-DD HH:00")
  #tx_per_hour = transactions.group_by { |tx| Time.parse(tx["created_at"]).strftime("%Y-%m-%d %H:00") }.transform_values(&:count)
# Transactions per 4-hour bucket
	tx_per_4h = transactions
		.group_by { |tx| time_bucket_4h(tx["created_at"]) }
	.transform_values(&:count)

	avg_tx_per_4h = tx_per_4h.values.sum.to_f / (tx_per_4h.values.size.nonzero? || 1)

	above_avg_tx_per_4h = tx_per_4h.select { |_, count| count > avg_tx_per_4h }



  # Averages
  avg_tx_per_day  = tx_per_day.values.sum.to_f / (tx_per_day.values.size.nonzero? || 1)
  #avg_tx_per_hour = tx_per_hour.values.sum.to_f / (tx_per_hour.values.size.nonzero? || 1)

  # Operations per account
  ops_per_account = operations
    .group_by { |op| op["source_account"] }
    .transform_values(&:count)

  avg_ops_per_account = ops_per_account.values.sum.to_f / (ops_per_account.values.size.nonzero? || 1)

  # Above-average filters
  above_avg_tx_per_day  = tx_per_day.select  { |_, count| count > avg_tx_per_day }
  #above_avg_tx_per_hour = tx_per_4h.select { |_, count| count > avg_tx_per_4h }
  above_avg_ops_account = ops_per_account.select { |_, count| count > avg_ops_per_account }

  {
    tx_per_day: tx_per_day,
    unique_tx_per_day: unique_tx_per_day,
    #tx_per_hour: tx_per_hour,
    avg_tx_per_day: avg_tx_per_day,
    #avg_tx_per_hour: avg_tx_per_hour,
    ops_per_account: ops_per_account,
    avg_ops_per_account: avg_ops_per_account,
    above_avg_tx_per_day: above_avg_tx_per_day,
    #above_avg_tx_per_hour: above_avg_tx_per_hour,
    above_avg_ops_account: above_avg_ops_account,
	tx_per_4h: tx_per_4h,
	avg_tx_per_4h: avg_tx_per_4h,
	above_avg_tx_per_4h: above_avg_tx_per_4h
  }
end

def shorten_account(account)
  return account if account.nil? || account.size < 6
  "#{account[0,2]}...#{account[-3,3]}"
end

def plot_bar(data, title, filename)
  width = [data.keys.size * 80, 1200].max
  #puts width.inspect
  g = Gruff::Bar.new(width)   # width only for Gruff 0.29.0
  g.title = title
  g.marker_font_size = 16
  g.legend_font_size = 18
  g.title_font_size  = 20

  # Build readable labels: dates -> MM-DD, time strings -> HH:00, accounts -> GA...XYZ
  short_labels = data.keys.each_with_index.map do |k, i|
    label =
      case k
      when Date
        k.strftime("%m-%d")
      else
        begin
          Time.parse(k).strftime("%H:00")
        rescue
          shorten_account(k.to_s)
        end
      end
    [i, label]
  end.to_h

  # Optionally skip labels if too many (keeps chart clean)
  if short_labels.size > 30
    skipped = {}
    short_labels.each { |i, lbl| skipped[i] = lbl if i % 2 == 0 }
    g.labels = skipped
  else
    g.labels = short_labels
  end

  g.data(title, data.values)
  g.write(filename)
end


def plot_bar_horizontal(data, title, filename)
  height = [data.keys.size * 60, 800].max
  g = Gruff::SideBar.new(height)

  g.title = title
  g.marker_font_size = 16
  g.legend_font_size = 18
  g.title_font_size  = 20
  g.hide_legend = true

  labels = {}
  values = []

  data.each_with_index do |(account, count), i|
    labels[i] = shorten_account(account.to_s)
    values << count
  end

  g.labels = labels
  g.data("Transactions", values)
  g.write(filename)
end




def plot_line(data, avg, title, filename)
  width = [data.keys.size * 80, 1200].max
  g = Gruff::Line.new(width)
  g.title = title
  g.marker_font_size = 16
  g.legend_font_size = 18
  g.title_font_size  = 20

  # Labels: keep as strings; for long account strings, shorten
  labels = data.keys.each_with_index.map do |k, i|
    lbl =
      begin
        Time.parse(k).strftime("%H:00")
      rescue
        k.is_a?(Date) ? k.strftime("%m-%d") : shorten_account(k.to_s)
      end
    [i, lbl]
  end.to_h

  if labels.size > 30
    skipped = {}
    labels.each { |i, lbl| skipped[i] = lbl if i % 2 == 0 }
    g.labels = skipped
  else
    g.labels = labels
  end

  g.data("Transactions", data.values)
  g.data("Average", Array.new(data.size, avg))
  g.write(filename)
end

def save_csv(stats, filename)
  CSV.open(filename, "w") do |csv|
    # Transactions per day
    csv << ["Day", "Transactions", "Unique Transactions"]
    stats[:tx_per_day].each do |day, count|
      csv << [day, count, stats[:unique_tx_per_day][day]]
    end
    csv << []
    csv << ["Average Transactions per Day", stats[:avg_tx_per_day]]
    csv << []
    csv << ["Above-Average Transactions per Day"]
    stats[:above_avg_tx_per_day].each { |day, count| csv << [day, count] }

    # Transactions per 4 hour
    csv << []
    csv << ["Hours", "Transactions"]
    stats[:tx_per_4h].each { |hour, count| csv << [hour, count] }
    csv << []
    csv << ["Average Transactions per 4Hours", stats[:avg_tx_per_4h]]
    csv << []
    csv << ["Above-Average Transactions per 4Hours"]
    stats[:above_avg_tx_per_4h].each { |hour, count| csv << [hour, count] }

    # Operations per account
    csv << []
    csv << ["Account", "Operations"]
    stats[:ops_per_account].each { |account, count| csv << [account, count] }
    csv << []
    csv << ["Average Operations per Account", stats[:avg_ops_per_account]]
    csv << []
    csv << ["Above-Average Operations per Account"]
    stats[:above_avg_ops_account].each { |account, count| csv << [account, count] }
  end
end

def save_xlsx(stats, filename)
  workbook  = WriteXLSX.new(filename)

  # Analytics sheet
  sheet     = workbook.add_worksheet("Analytics")

  row = 0
  # Transactions per day
  sheet.write(row, 0, "Day")
  sheet.write(row, 1, "Transactions")
  sheet.write(row, 2, "Unique Transactions")
  row += 1
  stats[:tx_per_day].each do |day, count|
    sheet.write(row, 0, day.to_s)
    sheet.write(row, 1, count)
    sheet.write(row, 2, stats[:unique_tx_per_day][day])
    row += 1
  end
  row += 1
  sheet.write(row, 0, "Average Transactions per Day")
  sheet.write(row, 1, stats[:avg_tx_per_day])

  # NEW: Above-average transactions per day
  row += 2
  sheet.write(row, 0, "Above-Average Transactions per Day")
  row += 1
  stats[:above_avg_tx_per_day].each do |day, count|
    sheet.write(row, 0, day.to_s)
    sheet.write(row, 1, count)
    row += 1
  end

  # Transactions per hour
  row += 2
  sheet.write(row, 0, "Hours")
  sheet.write(row, 1, "Transactions")
  row += 1
  stats[:tx_per_4h].each do |hour, count|
    sheet.write(row, 0, hour)
    sheet.write(row, 1, count)
    row += 1
  end
  row += 1
  sheet.write(row, 0, "Average Transactions per 4 Hours")
  sheet.write(row, 1, stats[:avg_tx_per_4h])

  # NEW: Above-average transactions per 4 hour
  row += 2
  sheet.write(row, 0, "Above-Average Transactions per 4 Hours")
  row += 1
  stats[:above_avg_tx_per_4h].each do |hour, count|
    sheet.write(row, 0, hour)
    sheet.write(row, 1, count)
    row += 1
  end

  # Operations per account
  row += 2
  sheet.write(row, 0, "Account")
  sheet.write(row, 1, "Operations")
  row += 1
  stats[:ops_per_account].each do |account, count|
    sheet.write(row, 0, account)
    sheet.write(row, 1, count)
    row += 1
  end
  row += 1
  sheet.write(row, 0, "Average Operations per Account")
  sheet.write(row, 1, stats[:avg_ops_per_account])

  # NEW: Above-average operations per account
  row += 2
  sheet.write(row, 0, "Above-Average Operations per Account")
  row += 1
  stats[:above_avg_ops_account].each do |account, count|
    sheet.write(row, 0, account)
    sheet.write(row, 1, count)
    row += 1
  end

  # Summary sheet (already implemented)
  summary = workbook.add_worksheet("Summary")
  summary.write(0, 0, "Metric")
  summary.write(0, 1, "Average")
  summary.write(0, 2, "Above-Average Entries")

  summary.write(1, 0, "Transactions per Day")
  summary.write(1, 1, stats[:avg_tx_per_day])
  stats[:above_avg_tx_per_day].each_with_index do |(day, count), idx|
    summary.write(2 + idx, 2, "#{day}: #{count}")
  end

  base_row = 2 + stats[:above_avg_tx_per_day].size + 1
  summary.write(base_row, 0, "Transactions per 4 Hour")
  summary.write(base_row, 1, stats[:avg_tx_per_4h])
  stats[:above_avg_tx_per_4h].each_with_index do |(hour, count), idx|
    summary.write(base_row + 1 + idx, 2, "#{hour}: #{count}")
  end

  base_row = base_row + stats[:above_avg_tx_per_4h].size + 2
  summary.write(base_row, 0, "Operations per Account")
  summary.write(base_row, 1, stats[:avg_ops_per_account])
  stats[:above_avg_ops_account].each_with_index do |(account, count), idx|
    summary.write(base_row + 1 + idx, 2, "#{account}: #{count}")
  end

  workbook.close
end

def save_above_average_txt(stats, filename)
  File.open(filename, "w") do |f|
    f.puts "[AboveAverageTransactionsPerDay]"
    stats[:above_avg_tx_per_day]
      .sort_by { |_, count| -count }
      .each { |day, count| f.puts "#{day}=#{count}" }

    f.puts "\n[AboveAverageTransactionsPer4Hours]"
    stats[:above_avg_tx_per_4h]
      .sort_by { |_, count| -count }
      .each { |hour, count| f.puts "#{hour}=#{count}" }

    f.puts "\n[AboveAverageOperationsPerAccount]"
    stats[:above_avg_ops_account]
      .sort_by { |_, count| -count }
      .each { |account, count| f.puts "#{account}=#{count}" }
  end
end


def zip_files(output_zip, files)
  Zip::File.open(output_zip, create: true) do |zipfile|
    files.each do |file|
      zipfile.add(File.basename(file), file) if File.exist?(file)
    end
  end
end
puts "Gathering Datas on POOL #-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#"
# === Example usage ===
transactions = pool_transactions(POOL_ID)
operations   = pool_operations(POOL_ID)
stats        = analytics(transactions, operations)
puts "Analysing Data Gathered =)#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#_#-*-#._.#-*-#(="
# Save data into subfolder
csv_file  = File.join(OUTPUT_DIR, "pool_stats_#{TIMESTAMP}.csv")
xlsx_file = File.join(OUTPUT_DIR, "pool_stats_#{TIMESTAMP}.xlsx")
save_csv(stats, csv_file)
save_xlsx(stats, xlsx_file)
txt_file = File.join(OUTPUT_DIR, "above_average_#{TIMESTAMP}.ini")
save_above_average_txt(stats, txt_file)
puts "analytics Files created, generating zip file and data charts .................."
# Generate charts into subfolder (full dataset)
files_to_zip = []
files_to_zip << File.join(OUTPUT_DIR, "transactions_per_day_#{TIMESTAMP}.png")
plot_bar(stats[:tx_per_day], "Transactions per Day", files_to_zip.last)

files_to_zip << File.join(OUTPUT_DIR, "unique_transactions_per_day_#{TIMESTAMP}.png")
plot_bar(stats[:unique_tx_per_day], "Unique Transactions per Day", files_to_zip.last)

files_to_zip << File.join(OUTPUT_DIR, "transactions_per_4hour_#{TIMESTAMP}.png")
plot_bar(stats[:tx_per_4h], "Transactions per 4 Hours", files_to_zip.last)

files_to_zip << File.join(OUTPUT_DIR, "avg_transactions_per_4hour_#{TIMESTAMP}.png")
plot_line(stats[:tx_per_4h], stats[:avg_tx_per_4h], "Transactions vs Average per 4 Hours", files_to_zip.last)

files_to_zip << File.join(OUTPUT_DIR, "operations_per_account_#{TIMESTAMP}.png")
plot_bar(stats[:ops_per_account], "Operations per Account", files_to_zip.last)

files_to_zip << File.join(OUTPUT_DIR, "operations_per_account_Hrz#{TIMESTAMP}.png")
plot_bar_horizontal(stats[:ops_per_account], "Operations per Account", files_to_zip.last)

# Generate charts for above‑average subsets
files_to_zip << File.join(OUTPUT_DIR, "above_avg_tx_per_day_#{TIMESTAMP}.png")
plot_bar(stats[:above_avg_tx_per_day], "Above Avg Transactions per Day", files_to_zip.last)

files_to_zip << File.join(OUTPUT_DIR, "above_avg_tx_per_4hour_#{TIMESTAMP}.png")
plot_bar(stats[:above_avg_tx_per_4h], "Above Avg Transactions per 4 Hour", files_to_zip.last)

files_to_zip << File.join(OUTPUT_DIR, "above_avg_ops_account_#{TIMESTAMP}.png")
plot_bar(stats[:above_avg_ops_account], "Above Avg Operations per Account", files_to_zip.last)

files_to_zip << File.join(OUTPUT_DIR, "above_avg_ops_account_Horizo#{TIMESTAMP}.png")
plot_bar_horizontal(stats[:above_avg_ops_account], "Above Avg Operations per Account", files_to_zip.last)

# Add CSV/XLSX to zip list
files_to_zip.unshift(csv_file, xlsx_file)
files_to_zip.unshift(txt_file)


# Zip everything together into the same folder
zip_file = File.join(OUTPUT_DIR, "pool_analytics_bundle_#{TIMESTAMP}.zip")
zip_files(zip_file, files_to_zip)

puts "Done. Outputs saved in #{OUTPUT_DIR} and zipped to #{zip_file}"
