# frozen_string_literal: true

require_relative "lib/rite_opt/version"

Gem::Specification.new do |spec|
  spec.name = "rite_opt"
  spec.version = RiteOpt::VERSION
  spec.authors = ["RiteOpt contributors"]
  spec.summary = "Optimizer for mruby RITE binaries"
  spec.description = "RiteOpt applies size-oriented optimization passes to mruby RITE binaries."
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir[
    "README.md",
    "lib/**/*.rb",
    "sig/**/*.rbs",
    "exe/*"
  ]
  spec.bindir = "exe"
  spec.executables = ["rite-opt"]
  spec.require_paths = ["lib"]
end
