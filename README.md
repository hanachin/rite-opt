# RiteOpt

RiteOpt optimizes mruby RITE binaries.

The `rite-opt` command runs these passes by default, in this order:

1. `DebugRemoval`
2. `LvarRemoval`
3. `NopRemoval`

## CLI

```sh
rite-opt app.mrb > app.opt.mrb
rite-opt -o app.opt.mrb app.mrb
cat app.mrb | rite-opt - > app.opt.mrb
```

Disable individual passes when needed:

```sh
rite-opt --no-debug-removal app.mrb
rite-opt --no-lvar-removal app.mrb
rite-opt --no-nop-removal app.mrb
```

`-o` is optional. Without it, RiteOpt writes the optimized RITE binary to stdout.

## Bundler

RiteOpt has a gemspec, so a GitHub repository can be used directly from a Gemfile:

```ruby
gem "rite_opt", github: "<owner>/rite_opt"
```

Then run:

```sh
bundle exec rite-opt app.mrb > app.opt.mrb
```

## Nix

`flake.nix` uses Ruby 4.0.7, following the same Ruby source used by Chiburu.
No gem installation is required for the CLI.

```sh
nix run . -- app.mrb > app.opt.mrb
nix develop
mrbc --version
mruby --version
./exe/rite-opt app.mrb > app.opt.mrb
```

The development shell includes Ruby 4.0, `mrbc`, and `mruby`. `nix flake check` runs the unit tests and the mrbc integration tests. The integration tests compile real RITE0400 binaries and verify Debug, LVAR, and NOP removal, including jump and catch-table relocation.

`flake.lock` is intentionally not included yet.

## Ruby API

Each optimization pass is also available separately:

```ruby
require "rite_opt"

bytes = File.binread("app.mrb")
bytes = RiteOpt::Rite::DebugRemoval.call(bytes)
bytes = RiteOpt::Rite::LvarRemoval.call(bytes)
bytes = RiteOpt::Rite::NopRemoval.call(bytes)
File.binwrite("app.opt.mrb", bytes)
```

`NopRemoval` supports RITE0400. It rewrites branch and catch positions and rebuilds affected sizes. `LVAR` is position-independent. `DBG` must be removed before NOP removal because its PC mappings are not rewritten.
