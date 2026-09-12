local eq = require('tests.helpers').eq
local offsets = require('lint_actions.offsets')

describe('Byte offsets', function()
  describe('byte offsets to LSP positions', function()
    for _, encoding in ipairs({ 'utf-8', 'utf-16', 'utf-32' }) do
      describe(encoding, function()
        -- Each row is a UTF-8 byte boundary and its column in the three encodings.
        local boundaries = {
          { byte = 0, columns = { 0, 0, 0 } },
          { byte = 1, columns = { 1, 1, 1 } }, -- ASCII
          { byte = 3, columns = { 3, 2, 2 } }, -- accented letter
          { byte = 7, columns = { 7, 4, 3 } }, -- supplementary code point
          { byte = 10, columns = { 10, 5, 4 } }, -- three-byte code point
          { byte = 11, columns = { 11, 6, 5 } }, -- ASCII before a combining mark
          { byte = 13, columns = { 13, 7, 6 } }, -- combining mark
        }
        local index = ({ ['utf-8'] = 1, ['utf-16'] = 2, ['utf-32'] = 3 })[encoding]

        for _, boundary in ipairs(boundaries) do
          it('counts code units at byte ' .. boundary.byte, function()
            eq(
              offsets.to_position('aé😀中é', boundary.byte, encoding),
              { line = 0, character = boundary.columns[index] }
            )
          end)
        end

        it('clamps to the text bounds', function()
          for _, text in ipairs({ '', 'abc', 'a\nb', 'a\n' }) do
            eq(offsets.to_position(text, -10, encoding), { line = 0, character = 0 })
            eq(offsets.to_position(text, #text + 10, encoding), offsets.to_position(text, #text, encoding))
          end
        end)
      end)
    end
  end)

  describe('line boundaries', function()
    for _, case in ipairs({
      { name = 'LF', text = 'a\nb', positions = { { 0, 0 }, { 0, 1 }, { 1, 0 }, { 1, 1 } } },
      { name = 'CRLF', text = 'a\r\nb', positions = { { 0, 0 }, { 0, 1 }, { 0, 1 }, { 1, 0 }, { 1, 1 } } },
      { name = 'empty lines and final LF', text = '\n\n', positions = { { 0, 0 }, { 1, 0 }, { 2, 0 } } },
    }) do
      it(case.name .. ' advances only after the newline', function()
        for byte, position in ipairs(case.positions) do
          for _, encoding in ipairs({ 'utf-8', 'utf-16', 'utf-32' }) do
            eq(offsets.to_position(case.text, byte - 1, encoding), { line = position[1], character = position[2] })
          end
        end
      end)
    end
  end)
end)
