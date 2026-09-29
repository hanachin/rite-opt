# frozen_string_literal: true

require_relative "lib/rite_opt/version"

Gem::Specification.new do |spec|
  spec.name = "rite_opt"
  spec.version = RiteOpt::VERSION
  spec.authors = ["Seiei Miyagi"]
  spec.summary = "Optimizer for mruby RITE binaries"
  spec.description = "RiteOpt applies size-oriented optimization passes to mruby RITE binaries."
  spec.homepage = "https://github.com/hanachin/rite_opt"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir[
    "LICENSE",
    "README.md",
    "THIRD_PARTY_LICENSES",
    "lib/**/*.rb",
    "sig/**/*.rbs",
    "exe/*"
  ]
  spec.bindir = "exe"
  spec.executables = ["rite-opt"]
  spec.require_paths = ["lib"]
end
