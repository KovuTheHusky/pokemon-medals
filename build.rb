require 'nokogiri'
require 'fileutils'
require 'mini_magick'
require 'json'
require 'shellwords'

# --- CONFIGURATION ---
URL = 'https://bulbapedia.bulbagarden.net/wiki/Medal_(GO)'
USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
SHADOW_RING_WIDTH = 28

# Define output folders
folders = %w[
  general/shadow general/bronze general/silver general/gold general/platinum
  type/shadow type/bronze type/silver type/gold type/platinum
  other
]
folders.each { |f| FileUtils.mkdir_p(f) }

data_store = { general: {}, type: {}, other: {} }

# --- HELPERS ---

def normalize_text(text)
  text.to_s
      .gsub('*', '')
      .gsub(/[‘’]/, "'")
      .gsub(/[“”]/, '"')
      .gsub(/[–—]/, '-')
      .gsub(/\u00A0/, ' ') 
      .strip
end

def clean_filename(text)
  normalized = normalize_text(text)
  slug = normalized.downcase
      .gsub('%c3%a9', 'e')
      .gsub('é', 'e')
      .gsub("'", "")
      .gsub('"', "")
      .gsub('.', "")
      .gsub(':', "")
      .gsub(/[^a-z0-9\-_]/, '-')
      .gsub(/-+/, '-')
      .sub(/^-/, '')
      .sub(/-$/, '')
  # Truncate to 100 chars to avoid filesystem errors
  slug[0...100].sub(/-$/, '') 
end

def extract_clean_name(node)
  return "" unless node
  copy = node.dup
  copy.css('small, sup, span').remove 
  copy.search('br').each { |br| br.replace(" ") }
  normalize_text(copy.text)
end

def fetch_with_curl(url)
  cmd = "curl -L -s -H 'User-Agent: #{USER_AGENT}' " \
        "-H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8' " \
        "#{Shellwords.escape(url)}"
  content = `#{cmd}`
  return content if $?.success? && !content.empty?
  raise "Curl failed to fetch #{url}"
end

def download_image(url, filepath)
  url = "https:#{url}" if url.start_with?('//')
  url = "https://bulbapedia.bulbagarden.net#{url}" if url.start_with?('/')
  
  if url.include?('/thumb/')
    url = url.sub('/thumb/', '/')
    url = url.split('/')[0..-2].join('/')
  end

  temp_file = "temp_img_#{Time.now.to_i}_#{rand(1000)}.tmp"

  cmd = "curl -L -s -H 'User-Agent: #{USER_AGENT}' -o #{temp_file} #{Shellwords.escape(url)}"
  system(cmd)
  
  if File.exist?(temp_file) && File.size(temp_file) > 0
    begin
      image = MiniMagick::Image.open(temp_file)
      image.format 'webp'
      image.write filepath
      File.delete(temp_file)
      return true
    rescue => e
      puts "    [!] Image Error (#{filepath}): #{e.message}"
      File.delete(temp_file) if File.exist?(temp_file)
      return false
    end
  else
    puts "    [!] Download failed for #{url}"
    return false
  end
end

def generate_shadow_icon(source_filepath, dest_filepath)
  return unless File.exist?(source_filepath)
  cutoff_radius = 128 - SHADOW_RING_WIDTH
  
  begin
    image = MiniMagick::Image.open(source_filepath)
    image.format 'webp'
    image.combine_options do |c|
      c.resize '256x256!'
      c.fill '#efefef'
      c.colorize '100'
      c.fx "hypot(i-w/2, j-h/2) > #{cutoff_radius} ? 0 : u"
    end
    image.write dest_filepath
  rescue => e
    puts "    [!] Shadow Generation Error: #{e.message}"
  end
end

def process_event_medal(raw_name, safe_name, img_url, data_store)
  # NOTE: We do NOT append numbers for collisions here (removed per request).
  # If 'safe_name' exists, we overwrite/reuse it.
  
  filepath = "other/#{safe_name}.webp"
  data_store[:other][safe_name] = raw_name
  puts "  [OTHER] #{raw_name} -> #{safe_name}.webp"
  download_image(img_url, filepath)
end

# --- MAIN LOGIC ---

puts "---------------------------------------------------"
puts "Scraping Bulbapedia: #{URL}"
puts "---------------------------------------------------"

begin
  html = fetch_with_curl(URL)
  doc = Nokogiri::HTML(html)
rescue => e
  puts "Fatal Error: #{e.message}"
  exit
end

tables = doc.css('table')
puts "Found #{tables.length} tables. Analyzing..."

tables.each_with_index do |table, index|
  next if table.text.include?('Project Sidegames')

  headers = table.css('th').map { |th| th.text.strip.downcase }
  is_tiered_table = headers.any? { |h| h.include?('bronze') } && headers.any? { |h| h.include?('gold') }

  rows = table.css('tr')
  
  # =========================================================
  # CASE A: TIERED MEDALS
  # =========================================================
  if is_tiered_table
    puts "Processing Tiered Table (Index #{index})..."
    
    col_map = {}
    table.css('th').each_with_index do |th, i|
      txt = th.text.strip.downcase
      col_map[:bronze]   = i if txt.include?('bronze')
      col_map[:silver]   = i if txt.include?('silver')
      col_map[:gold]     = i if txt.include?('gold')
      col_map[:platinum] = i if txt.include?('platinum')
      col_map[:name]     = i if txt == 'medal' || txt == 'name'
      col_map[:desc]     = i if txt.include?('description') || txt.include?('requirement')
    end
    col_map[:name] ||= 0 

    rows.each do |row|
      cols = row.css('td')
      next if cols.empty?
      
      name_node = row.css('th').first || cols[col_map[:name]]
      next unless name_node
      
      raw_name = extract_clean_name(name_node)
      next if raw_name.empty? || raw_name.downcase == 'medal'

      safe_name = clean_filename(raw_name)

      is_type = false
      if col_map[:desc] && cols[col_map[:desc]]
        desc = cols[col_map[:desc]].text.downcase
        is_type = desc.include?('type') && (desc.include?('catch') || desc.include?('caught'))
      end
      if raw_name.match?(/Rail Staff|Depot Agent|Schoolkid|Black Belt|Bird Keeper|Punk Girl|Ruin Maniac|Hiker|Bug Catcher|Hex Maniac|Kindler|Swimmer|Gardener|Rocker|Psychic|Skier|Dragon Tamer|Delinquent|Fairy Tale Girl/i)
        is_type = true
      end

      category = is_type ? :type : :general
      folder_base = is_type ? 'type' : 'general'

      data_store[category][safe_name] = raw_name
      puts "  [#{category.upcase}] #{raw_name}"

      [:bronze, :silver, :gold, :platinum].each do |tier|
        idx = col_map[tier]
        next unless idx && cols[idx]
        
        img_tag = cols[idx].css('img').first
        next unless img_tag
        img_url = img_tag['data-src'] || img_tag['src']
        next unless img_url

        filepath = "#{folder_base}/#{tier}/#{safe_name}.webp"
        download_image(img_url, filepath)
      end

      # Generate Shadow
      bronze_path = "#{folder_base}/bronze/#{safe_name}.webp"
      shadow_path = "#{folder_base}/shadow/#{safe_name}.webp"
      if File.exist?(bronze_path)
        generate_shadow_icon(bronze_path, shadow_path)
      elsif File.exist?("#{folder_base}/silver/#{safe_name}.webp")
        generate_shadow_icon("#{folder_base}/silver/#{safe_name}.webp", shadow_path)
      end
    end

  # =========================================================
  # CASE B: EVENT / OTHER MEDALS
  # =========================================================
  else
    has_images = table.css('img').any?
    next unless has_images

    puts "Processing Other/Event Table (Index #{index})..."
    
    rows.each do |row|
      cols = row.css('td')
      next if cols.empty?

      img_col = cols.find { |c| c.css('img').any? }
      name_col = cols.find { |c| c.text.strip.length > 3 && c != img_col }
      
      img_col ||= cols[0]
      name_col ||= (cols[1] || cols[0])
      
      next unless img_col && name_col

      # 1. Grab all Valid Images
      valid_imgs = img_col.css('img').select { |i| i['width'].to_i > 25 }
      next if valid_imgs.empty?

      # 2. Extract Names (List or Block)
      names_found = []
      if name_col.css('li').any?
        name_col.css('li').each do |li|
          names_found << extract_clean_name(li)
        end
      elsif name_col.to_html.include?('<br')
        name_col.inner_html.split(/<br\s*\/?>/i).each do |chunk|
          names_found << extract_clean_name(Nokogiri::HTML.fragment(chunk))
        end
      else
        names_found << extract_clean_name(name_col)
      end

      names_found.reject! { |n| n =~ /medal|description|requirement|date/i || n.length < 3 || n.end_with?(':') }
      next if names_found.empty?

      # 3. Decision Matrix
      if valid_imgs.length > 1
        # SCENARIO: Multiple Icons in one row
        # Action: Use the FIRST name as the base for all.
        # Filenames: Append -2, -3 to ensure we save all images.
        # JSON Name: Keep the exact same clean name for all entries.
        base_name = names_found.first
        safe_base = clean_filename(base_name)
        
        valid_imgs.each_with_index do |img, idx|
          suffix = idx == 0 ? "" : "-#{idx + 1}"
          final_safe_name = "#{safe_base}#{suffix}"
          img_url = img['data-src'] || img['src']
          process_event_medal(base_name, final_safe_name, img_url, data_store)
        end
      else
        # SCENARIO: Single Icon, Multiple Names (e.g. Timed Research)
        # Action: Create a separate entry for each name.
        # Filename: Derived from each specific name (No numbers appended).
        # JSON Name: Full name.
        shared_img_url = valid_imgs.first['data-src'] || valid_imgs.first['src']
        
        names_found.each do |n|
          safe_n = clean_filename(n)
          process_event_medal(n, safe_n, shared_img_url, data_store)
        end
      end
    end
  end
end

# =========================================================
# MANUAL INJECTIONS (Local Files)
# =========================================================
puts "Processing Manual Injections..."

# Configuration: Map "Event Name" to "Your Local File Path"
manual_medals = {
  "Pokémon GO Fest 2023 New York City - Addon" => "manual_assets/2023-nyc-addon.webp",
  "Pokémon GO Fest 2023 New York City - City"  => "manual_assets/2023-nyc-city.webp",
  "Pokémon GO Fest 2023 New York City - Park"  => "manual_assets/2023-nyc-park.webp"
}

manual_medals.each do |name, source_path|
  if File.exist?(source_path)
    safe_name = clean_filename(name)
    dest_path = "other/#{safe_name}.webp"

    begin
      # Open local file, convert to webp, save to destination
      image = MiniMagick::Image.open(source_path)
      image.format 'webp'
      image.write dest_path
      
      # Important: Register it in the JSON data
      data_store[:other][safe_name] = name
      puts "  [MANUAL] #{name} -> #{safe_name}.webp"
    rescue => e
      puts "    [!] Error processing #{source_path}: #{e.message}"
    end
  else
    puts "    [!] Warning: File not found at #{source_path}"
  end
end

puts "\nSaving JSON data..."
FileUtils.mkdir_p('_data/')
File.write('_data/general.json', JSON.pretty_generate(data_store[:general]))
File.write('_data/type.json', JSON.pretty_generate(data_store[:type]))
File.write('_data/other.json', JSON.pretty_generate(data_store[:other]))

puts "Done!"
puts "Stats: General: #{data_store[:general].count}, Type: #{data_store[:type].count}, Other: #{data_store[:other].count}"