-- Specs run inside Busted's Neovim environment. Required modules share plain
-- `_G`, so import luassert directly and provide deferred per-case cleanup.
local luassert = require('luassert')

local M = {}

-- Cleanup registered during the current case, newest first. `cleanup()` drains
-- it from the shared `after_each`, so helpers can undo their own state.
local teardown = {}

---Run `callback` once the current case finishes, whatever its outcome.
---@param callback function
function M.on_cleanup(callback)
  table.insert(teardown, callback)
end

---Run everything `on_cleanup()` registered during the case.
function M.cleanup()
  local errors = {}
  while #teardown > 0 do
    local ok, err = pcall(table.remove(teardown))
    if not ok then
      table.insert(errors, tostring(err))
    end
  end
  if #errors > 0 then
    error(table.concat(errors, '\n'), 0)
  end
end

---Deep equality, with the value under test first: `eq(actual, expected)`.
---luassert takes them the other way round and labels them in its failure
---output, so the swap happens here rather than at every call site.
---@param actual any
---@param expected any
function M.eq(actual, expected)
  luassert.are.same(expected, actual)
end

---Call through a variable so the function checks the arguments at runtime instead of
---rejecting the deliberately invalid ones a validation case passes.
---@param callback function
---@param ... any
---@return any
function M.call(callback, ...)
  return callback(...)
end

---Assert that `callback` fails with an error containing `message` verbatim.
---@param message string
---@param callback function
function M.expect_error(message, callback)
  local ok, err = pcall(callback)
  assert(not ok, ('expected an error containing %q, but the call succeeded'):format(message))
  assert(
    tostring(err):find(message, 1, true),
    ('expected an error containing %q, got %q'):format(message, tostring(err))
  )
end

---Hide a notification emitted by code under test until the current case ends.
function M.silence_notifications()
  local notify = vim.notify
  vim.notify = function() end
  M.on_cleanup(function()
    -- Provider errors report through `vim.schedule()`, so let pending
    -- callbacks run while the replacement is still installed.
    vim.wait(10, function()
      return false
    end)
    vim.notify = notify
  end)
end

---Hide a `print()` emitted by code under test until the current case ends.
function M.silence_prints()
  local original_print = _G.print
  _G.print = function() end
  M.on_cleanup(function()
    _G.print = original_print
  end)
end

function M.range(start_line, start_character, end_line, end_character)
  return {
    start = { line = start_line, character = start_character },
    ['end'] = { line = end_line, character = end_character },
  }
end

return M
