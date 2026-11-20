# ui-menu.nvim

A cursor-anchored floating select menu with zero-dependency fuzzy matching and
optional takeover of `vim.ui.select`.

- Index column: `1-9` to pick directly, `<C-g>` + digits to jump to any item
- Type-to-filter: built-in `matchfuzzypos`, Unicode/CJK friendly
- Anchored to the cursor, auto width, scrolling for long lists
- End-of-line virtual text / structured icons (dropbar-style shapes)
- Animated frames: `opts.tick` passes `format_item(item, frame)`
- No telescope / fzf-native / nui required

## Installation

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/huayue5201/ui-menu.nvim" })
require("ui_menu").setup({ replace_select = true })
```

With lazy.nvim:

```lua
{
  "huayue5201/ui-menu.nvim",
  priority = 999, -- must run before other plugins' config takes over vim.ui.select
  config = function()
    require("ui_menu").setup({ replace_select = true })
  end,
}
```

Just want to use it directly without changing global behavior:

```lua
require("ui_menu").setup()
require("ui_menu").select(items, { prompt = "Pick: ", format_item = tostring }, function(item)
  print(vim.inspect(item))
end)
```

## Configuration

```lua
require("ui_menu").setup({
  width = 64,
  min_width = 30,
  max_height = 14,
  border = "rounded",
  tick = 90,
  mouse = true,           -- click a row to pick, wheel to move, right click to cancel
  replace_select = false, -- true = take over vim.ui.select
  should_replace = nil,   -- fun(items, opts): boolean? only used when taking over
})
```

When `should_replace` returns `false`, the original implementation is used. For
example, only take over selections that have no preview requirement:

```lua
should_replace = function(_, _) return true end
```

## Usage

- `M.select(items, opts, on_choice)`: same as `vim.ui.select`, returns whether it opened
- `opts.tick = true|number`: animation mode, second arg of `format_item(item, frame)` increments
- `opts.position = "center"`: pin to screen center instead of following the cursor
- `opts.on_tab = fun()`: close the menu and call it when `<Tab>` is pressed (e.g. map ⇄ list toggle)
- `format_item` may return a second value `virt_text`: `{ {text, hl}, ... }` shown at end of line
- Structured items: `name/text/label` + `icon/icon_hl/name_hl`
- `M.spinner(frames?)`, `M.frames`, `M.config` are exported for reuse

Keys (while the menu is open): `j/k/<Down>/<Up>/<C-n>/<C-p>` to move, `gg/G` for
first/last, `1-9` to pick directly, `i/f//` to start typing, `<C-g>` for index
mode, `?` for help, `<CR>` to confirm, `Esc/q` to cancel.

Mouse: click a row to pick it, wheel to move, right click to cancel, click the
input box to start typing. Disable with `mouse = false`.

## Highlights

`UiMenuNormal`, `UiMenuSel`, `UiMenuBorder`, `UiMenuTitle`, `UiMenuLabel`,
`UiMenuLabelDim`, `UiMenuIndex`, `UiMenuError`, `UiMenuMatch`.

All link to regular groups (`Pmenu`, `PmenuSel`, `FloatBorder`, `Title`, ...)
with `default = true`, so colors follow the colorscheme; they are re-linked on
`ColorScheme` so `:hi clear`-ing themes still work. Override any of them to
restyle the menu.

## Scope vs. pickers

This plugin only provides "a small popup attached to the cursor". For full-width
previews (file contents, diffs, images) use a dedicated picker instead of adding
previews here.

## Tests

```sh
./tests/run.sh
```

## License

MIT
