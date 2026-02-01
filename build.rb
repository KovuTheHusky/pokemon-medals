require 'nokogiri'
require 'fileutils'
require 'mini_magick'
require 'json'
require 'shellwords'

# --- CONFIGURATION ---
URL = 'https://bulbapedia.bulbagarden.net/wiki/Medal_(GO)'
USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

# Width of the ring to remove (in pixels) for the shadow icon
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
  normalized.downcase
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
      puts "    [!] Image Error: #{e.message}"
      File.delete(temp_file) if File.exist?(temp_file)
      return false
    end
  else
    puts "    [!] Download failed for #{url}"
    return false
  end
end

# --- SHADOW ICON GENERATOR (Radial FX) ---
def generate_shadow_icon(source_filepath, dest_filepath)
  return unless File.exist?(source_filepath)
  
  # Calculate cutoff radius
  # Center is 128 (half of 256). Radius = Center - RingWidth.
  cutoff_radius = 128 - SHADOW_RING_WIDTH
  
  begin
    image = MiniMagick::Image.open(source_filepath)
    image.format 'webp'
    
    image.combine_options do |c|
      # 1. Force Resize to 256x256 first
      c.resize '256x256!'
      
      # 2. Colorize to Target Hex
      c.fill '#efefef'
      c.colorize '100'
      
      # 3. Apply Circular Mask
      #    We inject the calculated cutoff_radius into the FX formula
      c.fx "hypot(i-w/2, j-h/2) > #{cutoff_radius} ? 0 : u"
    end
    
    image.write dest_filepath
  rescue => e
    puts "    [!] Shadow Generation Error: #{e.message}"
  end
end

# --- MAIN LOGIC ---

puts "---------------------------------------------------"
puts "Scraping Bulbapedia: #{URL}"
puts "Shadow Ring Width Configured to: #{SHADOW_RING_WIDTH}px"
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

  if table.text.include?('Project Sidegames')
    puts "Skipping 'Project Sidegames' table..."
    next
  end

  headers = table.css('th').map { |th| th.text.strip.downcase }
  is_tiered_table = headers.any? { |h| h.include?('bronze') } && headers.any? { |h| h.include?('gold') }

  rows = table.css('tr')
  
  # --- CASE A: TIERED MEDALS ---
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
      
      raw_name = normalize_text(name_node.text)
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

        filepath = "#{folder_base}/#{tier}/#{safe_name}.webp"
        download_image(img_tag['src'], filepath)
      end

      # Generate Shadow from Bronze
      bronze_path = "#{folder_base}/bronze/#{safe_name}.webp"
      shadow_path = "#{folder_base}/shadow/#{safe_name}.webp"
      
      if File.exist?(bronze_path)
        generate_shadow_icon(bronze_path, shadow_path)
      else
        silver_path = "#{folder_base}/silver/#{safe_name}.webp"
        generate_shadow_icon(silver_path, shadow_path) if File.exist?(silver_path)
      end
    end

  # --- CASE B: EVENT / OTHER MEDALS ---
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

      names_found = []

      if name_col.css('li').any?
        name_col.css('li').each do |li|
          txt = normalize_text(li.text)
          names_found << txt unless txt.empty?
        end
      elsif name_col.to_html.include?('<br')
        chunks = name_col.inner_html.split(/<br\s*\/?>/i)
        chunks.each do |chunk|
          clean = normalize_text(Nokogiri::HTML.fragment(chunk).text)
          names_found << clean unless clean.empty?
        end
      else
        txt = normalize_text(name_col.text)
        names_found << txt unless txt.empty?
      end

      target_img = img_col.css('img').find { |i| i['width'].to_i > 25 }
      next unless target_img

      names_found.each do |raw_name|
        next if raw_name =~ /medal|description|requirement|date/i
        next if raw_name.length < 3

        is_simple_row = names_found.length == 1
        
        if is_simple_row
          date_text = cols.map(&:text).join(" ")
          year_match = date_text.match(/(20\d{2})/)
          if year_match && !raw_name.include?(year_match[1])
             if raw_name =~ /Fest|Safari|Zone|Day|Tour/i
               raw_name = "#{raw_name} #{year_match[1]}"
             end
          end
        end

        safe_name = clean_filename(raw_name)

        if data_store[:other].key?(safe_name)
          counter = 2
          base = safe_name
          while data_store[:other].key?(safe_name)
            safe_name = "#{base}-#{counter}"
            counter += 1
          end
        end

        filepath = "other/#{safe_name}.webp"
        data_store[:other][safe_name] = raw_name
        puts "  [OTHER] #{raw_name}"
        
        download_image(target_img['src'], filepath)
      end
    end
  end
end

puts "\nSaving JSON data..."
FileUtils.mkdir_p('_data/')
File.write('_data/general.json', JSON.pretty_generate(data_store[:general]))
File.write('_data/type.json', JSON.pretty_generate(data_store[:type]))
File.write('_data/other.json', JSON.pretty_generate(data_store[:other]))

puts "Done!"
puts "Stats: General: #{data_store[:general].count}, Type: #{data_store[:type].count}, Other: #{data_store[:other].count}"