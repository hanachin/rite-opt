# RiteOpt

RITE optimization experiments and utilities.

## NOP removal

`RiteOpt::Rite::NopRemoval` removes RITE0400 `NOP` instructions and relocates branch and catch positions.
It also rebuilds IREP record, section, and binary sizes.

```ruby
bytes = RiteOpt::Rite::NopRemoval.call(File.binread("app.mrb"))
File.binwrite("app.opt.mrb", bytes)
```

`LVAR` is preserved. `DBG` is rejected until debug PC mappings are rewritten.

## Debug removal

`RiteOpt::Rite::DebugRemoval` removes the `DBG` section and updates the RITE binary size.

```ruby
bytes = RiteOpt::Rite::DebugRemoval.call(File.binread("app.mrb"))
File.binwrite("app.opt.mrb", bytes)
```

## LVAR removal

`RiteOpt::Rite::LvarRemoval` removes the `LVAR` section and updates the RITE binary size.

```ruby
bytes = RiteOpt::Rite::LvarRemoval.call(File.binread("app.mrb"))
File.binwrite("app.opt.mrb", bytes)
```
