local M = {}

local API = {
  load_test_namespaces = "io.julienvincent.clojure-test.json/load-test-namespaces",
  get_all_tests = "io.julienvincent.clojure-test.json/get-all-tests",

  run_test = "io.julienvincent.clojure-test.json/run-test",

  resolve_metadata_for_symbol = "io.julienvincent.clojure-test.json/resolve-metadata-for-symbol",
  analyze_exception = "io.julienvincent.clojure-test.json/analyze-exception",
  get_tests_in_path = "io.julienvincent.clojure-test.json/get-tests-in-path",

  run_tests_parallel_start = "io.julienvincent.clojure-test.json/run-tests-parallel-start",
  stop_parallel_tests = "io.julienvincent.clojure-test.json/stop-parallel-tests",
  get_parallel_results = "io.julienvincent.clojure-test.json/get-parallel-results",
}

local function statement(api, ...)
  local call_statement = "((requiring-resolve '" .. api .. ")"
  for _, arg in ipairs({ ... }) do
    call_statement = call_statement .. " " .. arg
  end
  return call_statement .. ")"
end

local function clj_string(value)
  return vim.json.encode(value)
end

local function clj_symbol(value)
  return "(symbol " .. clj_string(value) .. ")"
end

local function clj_vector_of_symbols(values)
  local symbols = {}
  for _, value in ipairs(values) do
    table.insert(symbols, clj_symbol(value))
  end
  return "[" .. table.concat(symbols, " ") .. "]"
end

local function clj_opts(opts)
  if not opts then
    return "{}"
  end

  local parts = {}
  if opts.thread_count ~= nil then
    local thread_count = tonumber(opts.thread_count)
    if thread_count then
      table.insert(parts, ":thread-count " .. thread_count)
    end
  end

  if #parts == 0 then
    return "{}"
  end
  return "{" .. table.concat(parts, " ") .. "}"
end

local function format_error(api, message)
  return string.format("RPC %s failed: %s", api, message)
end

local function decode_envelope(api, payload)
  local decode_ok, decoded = pcall(vim.json.decode, payload)
  if not decode_ok then
    return nil, format_error(api, "invalid JSON response"), false
  end

  if type(decoded) == "string" then
    local nested_ok, nested = pcall(vim.json.decode, decoded)
    if not nested_ok then
      return nil, format_error(api, "invalid nested JSON response"), false
    end
    decoded = nested
  end

  if type(decoded) ~= "table" then
    return nil, format_error(api, "unexpected response type"), false
  end

  if decoded.ok ~= true then
    local rpc_error = decoded.error or {}
    local code = rpc_error.code or "rpc-error"
    local message = rpc_error.message or "Unknown RPC error"
    return nil, format_error(api, string.format("[%s] %s", code, message)), false
  end

  return decoded.data, nil, true
end

local function eval(client, api, ...)
  local success, result = pcall(client.eval("user", statement(api, ...)).wait)
  if not success then
    return nil, format_error(api, tostring(result)), false
  end

  return decode_envelope(api, result)
end

local function notify_rpc_error(err)
  vim.notify(err, vim.log.levels.ERROR)
end

local function eval_or_notify(client, api, ...)
  local data, err, ok = eval(client, api, ...)
  if not ok then
    notify_rpc_error(err)
    return nil, false
  end
  return data, true
end

local function parse_test_report(test, report)
  if type(report) ~= "table" then
    return nil
  end

  local status = "passed"
  local assertions = {}

  for _, entry in ipairs(report) do
    if entry.type == "error" or entry.type == "fail" then
      status = "failed"
      table.insert(assertions, entry)
    end
    if entry.type == "pass" then
      table.insert(assertions, entry)
    end
  end

  return {
    test = test,
    status = status,
    assertions = assertions,
  }
end

function M.create(client)
  local backend = {}

  function backend:is_connected()
    return client.is_connected().wait()
  end

  function backend:load_test_namespaces()
    local _, ok = eval_or_notify(client, API.load_test_namespaces)
    return ok
  end

  function backend:get_tests()
    local tests, ok = eval_or_notify(client, API.get_all_tests)
    if not ok then
      return nil
    end
    if type(tests) ~= "table" then
      return nil
    end
    return tests
  end

  function backend:run_test(test)
    local report, ok = eval_or_notify(client, API.run_test, clj_symbol(test))
    if not ok then
      return nil
    end
    return parse_test_report(test, report)
  end

  function backend:resolve_metadata_for_symbol(symbol)
    local data, ok = eval_or_notify(client, API.resolve_metadata_for_symbol, clj_symbol(symbol))
    if not ok then
      return nil
    end
    return data
  end

  function backend:analyze_exception(symbol)
    local data, ok = eval_or_notify(client, API.analyze_exception, clj_symbol(symbol))
    if not ok then
      return nil
    end
    return data
  end

  function backend:get_tests_in_path(path)
    local tests, ok = eval_or_notify(client, API.get_tests_in_path, clj_string(path))
    if not ok then
      return nil
    end
    if type(tests) ~= "table" then
      return nil
    end
    return tests
  end

  function backend:run_tests_parallel_start(tests, opts)
    local data, ok = eval_or_notify(client, API.run_tests_parallel_start, clj_vector_of_symbols(tests), clj_opts(opts))
    if not ok then
      return nil
    end
    return data
  end

  function backend:stop_parallel_tests()
    local data, ok = eval_or_notify(client, API.stop_parallel_tests)
    if not ok then
      return nil
    end
    return data
  end

  function backend:get_parallel_results()
    local state, ok = eval_or_notify(client, API.get_parallel_results)
    if not ok then
      return nil
    end
    if type(state) ~= "table" then
      return nil
    end
    return state
  end

  return backend
end

return M
