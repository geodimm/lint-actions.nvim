<!-- panvimdoc-ignore-start -->

# markdownlint with nvim-lint

<!-- panvimdoc-ignore-end -->

markdownlint-cli can fix most of the issues it reports.
This integration turns those fixes into Neovim code actions.
It reads output nvim-lint has already collected, so markdownlint does not run twice.

## Requirements

- Neovim 0.11 or newer.

- [nvim-lint](https://github.com/mfussenegger/nvim-lint).

- [markdownlint-cli](https://github.com/igorshubovych/markdownlint-cli), available as `markdownlint`.

## Configuration

Configure nvim-lint first, then enable the integration:

```lua
local lint = require('lint')
lint.linters_by_ft.markdown = { 'markdownlint' }

require('lint_actions').setup({
  integrations = {
    nvim_lint = {
      markdownlint = true,
    },
  },
})
```

markdownlint includes `fixInfo` only in JSON output.
The integration adds `--json` and replaces the plain-text parser with a JSON parser that produces the same diagnostics.

Your existing CLI arguments are kept, and an existing `--json` is not added a second time.

Trigger nvim-lint after saving the buffer, for example:

```lua
vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = '*.md',
  callback = function()
    require('lint').try_lint('markdownlint')
  end,
})
```

Actions are only kept when the buffer is unmodified.
A lint run started while the buffer is modified still updates diagnostics, but its fixes are dropped, because they cannot be matched reliably against the current buffer.

## Advanced configuration

Add any extra CLI arguments before calling `attach()`; they are preserved:

```lua
local markdownlint = require('lint').linters.markdownlint

markdownlint.args = vim.list_extend(markdownlint.args, {
  '--config',
  '/path/to/markdownlint.yaml',
})

require('lint_actions').setup({
  integrations = {
    nvim_lint = {
      markdownlint = true,
    },
  },
})
```

The default linter name is `markdownlint`.
You can point the integration at a different name or at a linter definition, and change the source it publishes under:

```lua
require('lint_actions').setup({
  integrations = {
    nvim_lint = {
      markdownlint = {
        linter = 'my_markdownlint',
        source = 'my-markdownlint',
      },
    },
  },
})
```

`require('lint_actions.integrations.markdownlint').attach()` accepts the same options for direct use.

To write an adapter for a different tool, see `:h lint-actions-nvim-lint`.

## Actions

Each fixable finding gets its own `quickfix` action:

```text
Fix MD018: No space after hash on atx style heading
```

There is also one whole-file action, with the kind `source.fixAll.markdownlint`:

```text
Fix all markdownlint issues
```

That whole-file edit follows markdownlint's own ordering, de-duplication, and overlap rules.
Findings for rules with no `fixInfo` still appear as diagnostics but have no action.

## Format on save

If a formatter already runs `markdownlint --fix` on save, remove markdownlint from that formatter's configuration.
Otherwise it applies the fixes before an action can be offered.
Keep it in nvim-lint so `BufWritePost` still refreshes diagnostics and code actions.

With [Conform.nvim](https://github.com/stevearc/conform.nvim), drop the markdown entry from `formatters_by_ft`:

```lua
formatters_by_ft = {
  -- markdown = { 'markdownlint' },
}
```

Remove the formatter's markdownlint definition if nothing else references it.
