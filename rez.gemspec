# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "rez"
  spec.version = File.read(File.join(__dir__, "lib/rez/version.rb"))[/VERSION = "(.+)"/, 1]
  spec.authors = ["Shannon Skipper"]
  spec.email = ["shannonskipper@gmail.com"]

  spec.summary = "Single-file version control"
  spec.description = "Just diff and patch under the hood. Snapshots a file with forward deltas you can diff, show and restore."
  spec.homepage = "https://github.com/havenwood/rez"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = %w[LICENSE.txt Rakefile README.md] + Dir["lib/**/*.rb"] + Dir["bin/*"]
  spec.executables = ["rez"]
end
