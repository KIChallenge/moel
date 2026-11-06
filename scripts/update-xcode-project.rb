#!/usr/bin/env ruby
# Optional maintenance helper; the checked-in project builds without Ruby gems.
require 'xcodeproj'
ROOT = File.expand_path('..', __dir__)
Dir.chdir(File.join(ROOT, 'apps/ios'))
project = Xcodeproj::Project.new('Sovi.xcodeproj')
project.root_object.development_region = 'de'
project.root_object.known_regions = ['de', 'en', 'ar', 'tr', 'Base']
app = project.new_target(:application, 'Sovi', :ios, '18.0', nil, :swift)
source_group = project.main_group.new_group('Sovi', 'Sovi')

def sources(group, directory, target)
  Dir.children(directory).sort.each do |name|
    item = File.join(directory, name)
    if File.directory?(item)
      sources(group.new_group(name, name), item, target)
    elsif File.extname(name) == '.swift'
      target.source_build_phase.add_file_reference(group.new_file(name))
    end
  end
end
Dir.children('Sovi').sort.each do |name|
  next if name == 'Resources' || !File.directory?(File.join('Sovi', name))
  sources(source_group.new_group(name, name), File.join('Sovi', name), app)
end
resources = source_group.new_group('Resources', 'Resources')
['Assets.xcassets', 'AppIcon.icon', 'PrivacyInfo.xcprivacy', 'Fixtures'].each do |name|
  next unless File.exist?(File.join('Sovi/Resources', name))
  ref = resources.new_file(name)
  ref.last_known_file_type = 'folder' if name == 'Fixtures'
  ref.last_known_file_type = 'folder.iconcomposer.icon' if name.end_with?('.icon')
  app.resources_build_phase.add_file_reference(ref)
end
strings = resources.new_variant_group('Localizable.strings')
['de', 'en', 'ar', 'tr'].each { |language| strings.new_file("#{language}.lproj/Localizable.strings").name = language }
app.resources_build_phase.add_file_reference(strings)
info_strings = resources.new_variant_group('InfoPlist.strings')
['de', 'en', 'ar', 'tr'].each { |language| info_strings.new_file("#{language}.lproj/InfoPlist.strings").name = language }
app.resources_build_phase.add_file_reference(info_strings)
config_group = project.main_group.new_group('Configuration', 'Configuration')
config_group.new_file('Base.xcconfig')
config_group.new_file('Info.plist')
config_group.new_file('Local.xcconfig.example')
['Debug', 'Release'].each do |name|
  ref = config_group.new_file("#{name}.xcconfig")
  config = app.build_configurations.find { |c| c.name == name }
  config.base_configuration_reference = ref
  config.build_settings.delete('SWIFT_VERSION')
  config.build_settings.delete('IPHONEOS_DEPLOYMENT_TARGET')
  config.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
  config.build_settings['SUPPORTS_MACCATALYST'] = 'NO'
end
unit = project.new_target(:unit_test_bundle, 'SoviTests', :ios, '18.0', nil, :swift)
ui = project.new_target(:ui_test_bundle, 'SoviUITests', :ios, '18.0', nil, :swift)
[unit, ui].each do |target|
  target.add_dependency(app)
  Dir.mkdir(target.name) unless Dir.exist?(target.name)
  sources(project.main_group.new_group(target.name, target.name), target.name, target)
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'SWIFT_VERSION' => '6.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
      'PRODUCT_BUNDLE_IDENTIFIER' => "at.sovi.companion.#{target.name.downcase}",
      'TARGETED_DEVICE_FAMILY' => '1,2', 'CODE_SIGN_STYLE' => 'Automatic'
    })
    if target == unit
      config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Sovi.app/Sovi'
      config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
    else
      config.build_settings['TEST_TARGET_NAME'] = 'Sovi'
    end
  end
end
ecard_fixtures = project.main_group['SoviTests'].new_file('../SoviUITests/Fixtures')
ecard_fixtures.name = 'e-card fixtures'
ecard_fixtures.last_known_file_type = 'folder'
unit.resources_build_phase.add_file_reference(ecard_fixtures)
project.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
end
project.files.select { |ref| ref.path&.end_with?('.framework') }.each do |ref|
  ref.path = "System/Library/Frameworks/#{File.basename(ref.path)}"
  ref.source_tree = 'SDKROOT'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, unit, launch_target: true)
scheme.add_build_target(ui, false)
scheme.add_test_target(ui)
scheme.save_as('Sovi.xcodeproj', 'Sovi', true)
test_scheme = Xcodeproj::XCScheme.new
test_scheme.configure_with_targets(app, unit, launch_target: true)
test_scheme.save_as('Sovi.xcodeproj', 'SoviTests', true)
puts 'Updated shared Sovi and SoviTests schemes.'
