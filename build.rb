# Load the required libraries
require 'open-uri'
require 'nokogiri'
require 'fileutils'
require 'mini_magick'

FileUtils.mkdir_p('general/')
FileUtils.mkdir_p('general/shadow/')
FileUtils.mkdir_p('general/bronze/')
FileUtils.mkdir_p('general/silver/')
FileUtils.mkdir_p('general/gold/')
FileUtils.mkdir_p('general/platinum/')
FileUtils.mkdir_p('type/')
FileUtils.mkdir_p('type/shadow/')
FileUtils.mkdir_p('type/bronze/')
FileUtils.mkdir_p('type/silver/')
FileUtils.mkdir_p('type/gold/')
FileUtils.mkdir_p('type/platinum/')
FileUtils.mkdir_p('other/')

general = {}
type = {}
other = {}

# Specify the URL of the page to scrape
url = 'https://pokemongo.fandom.com/wiki/Medals'

# Open the URL and parse the HTML document
html = URI.open(url)
doc = Nokogiri::HTML(html)

# Find all tables with the class 'pogo-legacy-table'
tables = doc.css('.pogo-legacy-table')

# Iterate over each table
tables.each do |table|

  rows = table.css('tr')

  rows.each do |row|

    cols = row.css('td')

    if cols.length() == 7

      next if cols[2].css('a.image').length() == 0

      name = cols[0].text.strip
      filename = name.downcase.gsub(' ', '-')
      filename.gsub!('é', 'e')

      if filename.empty?
        image = cols[2].css('a.image')[0]
        parts = image['href'].split('/')
        filename = parts[-3].downcase
        filename.gsub!('%c3%a9', 'e')
        filename.gsub!('é', 'e')
        filename.gsub!('%27', '')
        filename.sub!('.png', '')
        filename.sub!('_medal', '')
        filename.sub!('_shadow', '')
        filename.gsub!('_', '-')
      end

      if cols[1].text.strip.end_with?('-type caught')
        folder = 'type/'
        type[filename] = name
      else
        folder = 'general/'
        general[filename] = name
      end

      webp_filepath = File.join(folder + 'shadow/', filename + '.webp')
      data = URI.open(cols[2].css('a.image')[0]['href'])
      image = MiniMagick::Image.read(data)
      image.format 'webp'
      image.write webp_filepath

      webp_filepath = File.join(folder + 'bronze/', filename + '.webp')
      data = URI.open(cols[3].css('a.image')[0]['href'])
      image = MiniMagick::Image.read(data)
      image.format 'webp'
      image.write webp_filepath

      webp_filepath = File.join(folder + 'silver/', filename + '.webp')
      data = URI.open(cols[4].css('a.image')[0]['href'])
      image = MiniMagick::Image.read(data)
      image.format 'webp'
      image.write webp_filepath

      webp_filepath = File.join(folder + 'gold/', filename + '.webp')
      data = URI.open(cols[5].css('a.image')[0]['href'])
      image = MiniMagick::Image.read(data)
      image.format 'webp'
      image.write webp_filepath

      webp_filepath = File.join(folder + 'platinum/', filename + '.webp')
      data = URI.open(cols[6].css('a.image')[0]['href'])
      image = MiniMagick::Image.read(data)
      image.format 'webp'
      image.write webp_filepath

    elsif cols.length() == 4

      images = cols[3].css('a.image')

      images.each do |image|
        parts = image['href'].split('/')
        filename = parts[-3].downcase
        filename.gsub!('%c3%a9', 'e')
        filename.gsub!('é', 'e')
        filename.gsub!('%27', '')
        filename.sub!('.png', '')
        filename.sub!('_medal', '')
        filename.gsub!('_', '-')

        other[filename] = cols[0].css('i > text()').text.strip

        webp_filepath = File.join('other/', filename + '.webp')

        data = URI.open(image['href'])
        image = MiniMagick::Image.read(data)
        image.format 'webp'
        image.write webp_filepath
      end
    end
  end
end

FileUtils.mkdir_p('_data/')
File.write('_data/general.json', JSON.pretty_generate(general))
File.write('_data/type.json', JSON.pretty_generate(type))
File.write('_data/other.json', JSON.pretty_generate(other))
