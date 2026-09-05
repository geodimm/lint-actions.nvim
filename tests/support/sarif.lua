local function region(start_line, start_column, end_line, end_column)
  return {
    startLine = start_line,
    startColumn = start_column,
    endLine = end_line,
    endColumn = end_column,
  }
end

local function replacement(deleted_region, text)
  local value = { deletedRegion = deleted_region }
  if text ~= nil then
    value.insertedContent = { text = text }
  end
  return value
end

local function change(uri, replacements)
  return {
    artifactLocation = type(uri) == 'table' and uri or { uri = uri },
    replacements = replacements,
  }
end

local function fix(description, changes)
  return {
    description = description and { text = description } or nil,
    artifactChanges = changes,
  }
end

local function location(uri, value)
  return {
    physicalLocation = {
      artifactLocation = type(uri) == 'table' and uri or { uri = uri },
      region = value,
    },
  }
end

local function output(run)
  run.tool = run.tool or { driver = { name = 'example' } }
  return vim.json.encode({ version = '2.1.0', runs = { run } })
end

return { region = region, replacement = replacement, change = change, fix = fix, location = location, output = output }
