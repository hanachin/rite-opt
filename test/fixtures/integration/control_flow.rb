i = 0
log = []

begin
  while i < 4
    i += 1

    if i == 1
      log << "redo"
      redo
    end

    if i == 2
      log << "next"
      next
    end

    if i == 3
      log << "raise"
      raise "boom"
    end

    log << "body:#{i}"
  end
rescue => error
  log << "rescue:#{error.message}"
ensure
  log << "ensure"
end

value = catch(:done) do
  log << "catch"
  log << "throw"
  throw :done, 42
  log << "after-throw"
end

log << "after-catch:#{value}"
puts log.join(",")
