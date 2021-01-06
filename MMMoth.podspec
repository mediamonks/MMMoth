#
# MMMoth. Part of MMMTemple.
# Copyright (C) 2015-2020 MediaMonks. All rights reserved.
#

Pod::Spec.new do |s|

    s.name = "MMMoth"
    s.version = "1.3.0"
    s.summary = "Basic OAuth/OpenID library."
    s.description =  s.summary
    s.homepage = "https://github.com/mediamonks/#{s.name}"
    s.license = "MIT"
    s.authors = "MediaMonks"
    s.source = { :git => "https://github.com/mediamonks/#{s.name}.git", :tag => s.version.to_s }
    
    s.ios.deployment_target = '11.0'
    
    s.swift_versions = '4.2'
    s.static_framework = true   
    s.pod_target_xcconfig = {
        "DEFINES_MODULE" => "YES"
    }   

    s.dependency 'MMMLog'
  
    s.subspec 'Core' do |s|
      s.source_files = "Sources/Core/**/*.swift"
      s.dependency 'MMMLoadable'
    end

    s.subspec 'UI' do |s|
      s.source_files = "Sources/UI/**/*.swift"
      s.dependency 'MMMoth/Core'
      # For non-storyboardables, etc.
      s.dependency 'MMMCommonUI'
    end  
 
# There is a problem validating this one. 
#    s.subspec 'Mocks' do |s|
#      s.source_files = "Sources/Mocks/**/*.swift"
#      s.dependency 'MMMoth/UI'
#      # For MMMPseudoRandomSequence
#      s.dependency 'MMMocking'
#      s.dependency 'MMMObservables'
#      s.dependency 'MMMCommonCore'
#   end  
    
    s.test_spec 'Tests' do |ts|
      ts.source_files = "Tests/**/*.swift"
    end
  
    s.default_subspecs = ['Core', 'UI']
end
