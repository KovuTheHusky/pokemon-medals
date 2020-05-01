require 'fileutils'
require 'git'
require 'i18n'
require 'json'
require 'rmagick'

require 'zip'

include Magick

I18n.available_locales = [:en]

colors = ['shadow', 'bronze', 'silver', 'gold']
dir = 'assets/decrypted_assets/png/'
empty = Image.new(256, 256) {
  self.background_color = 'transparent'
}
specials = [
  ['5001', '5021', '5031'],
  ['5039'],
  ['5100']
]

FileUtils.rm_rf('assets')
Git.clone('https://github.com/ZeChrales/PogoAssets.git', 'assets')

colors.each do |color|
  FileUtils.mkdir_p('standard/' + color)
  FileUtils.mkdir_p('type/' + color)
end
FileUtils.mkdir_p('special');

FileUtils.mkdir_p('_data');

# Standard

json = []
JSON.parse(File.read('standard.json')).each do |entry|
  name = I18n.transliterate(entry[1].tr(' ', '-').downcase)
  for i in 1..3 do
    inner = ImageList.new(dir + 'Badge_' + entry[0] + '_' + i.to_s + '_01.png').scale(144, 144)
    outer = ImageList.new(dir + 'badge_ring_' + i.to_s + '.png')
    icon = outer.composite(inner, CenterGravity, OverCompositeOp)
    icon.write('standard/' + colors[i] + '/' + name + '.png')
  end
  shadow = ImageList.new(dir + 'Badge_' + entry[0] + '_1_01.png').scale(144, 144)
  shadow.alpha(ExtractAlphaChannel)
  shadow.fuzz = '50%'
  shadow = shadow.negate().transparent('white').opaque('black', '#efefef').blur_image(0, 0.5)
  icon = empty.composite(shadow, CenterGravity, OverCompositeOp)
  icon.write('standard/' + colors[0] + '/' + name + '.png')
  json << name
end
file = File.open("_data/standard.json", "w")
file.puts(JSON.pretty_generate(json))
file.close

# Type

json = []
JSON.parse(File.read('type.json')).each do |entry|
  name = I18n.transliterate(entry[1].tr(' ', '-').downcase)
  inner = ImageList.new(dir + 'Badge_' + entry[0] + '_01.png').scale(144, 144)
  for i in 1..3 do
    outer = ImageList.new(dir + 'badge_ring_' + i.to_s + '.png')
    icon = outer.composite(inner, CenterGravity, OverCompositeOp)
    icon.write('type/' + colors[i] + '/' + name + '.png')
  end
  shadow = inner
  shadow.alpha(ExtractAlphaChannel)
  shadow.fuzz = '50%'
  shadow = shadow.negate().transparent('white').opaque('black', '#efefef').blur_image(0, 0.5)
  icon = empty.composite(shadow, CenterGravity, OverCompositeOp)
  icon.write('type/' + colors[0] + '/' + name + '.png')
  json << name
end
file = File.open("_data/type.json", "w")
file.puts(JSON.pretty_generate(json))
file.close

# Special

json = []
JSON.parse(File.read('special.json')).each do |entry|
  name = I18n.transliterate(entry[1].tr(' ', '-').downcase)
  inner = ImageList.new(dir + 'Badge_' + entry[0] + '_01.png')
  outer = nil
  for i in 0..2 do
    if specials[i].include? entry[0]
      outer = ImageList.new(dir + 'badge_frame_' + i.to_s + '.png')
    end
  end
  if outer.nil?
    FileUtils.cp(dir + 'Badge_' + entry[0] + '_01.png', 'special/' + name + '.png')
  else
    icon = outer.composite(inner, CenterGravity, OverCompositeOp)
    icon.write('special/' + name + '.png')
  end
  json << name
end
file = File.open("_data/special.json", "w")
file.puts(JSON.pretty_generate(json))
file.close



FileUtils.rm_rf('medals.zip')
directories = ['special', 'standard', 'type']

zipfile_name = "medals.zip"

Zip::File.open(zipfile_name, Zip::File::CREATE) do |zipfile|
  directories.each do |directory|
    Dir["#{directory}/**/**"].each do |file|
      zipfile.add(file, file)
    end
  end
end



FileUtils.rm_rf('assets')
