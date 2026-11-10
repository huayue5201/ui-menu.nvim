# ui-menu.nvim

贴光标的浮窗选择菜单，零依赖模糊匹配，可选接管 `vim.ui.select`。

- 序号列：1-9 直选，`<C-g>` + 数字跳到任意项
- 输入过滤：内建 `matchfuzzypos`，支持中文
- 光标锚定、宽度自适应、超长列表滚动
- 行尾虚拟文本 / 结构化图标（dropbar 形状）
- 动画帧：`opts.tick` 给 `format_item(item, frame)`
- 不依赖 telescope / fzf-native / nui

## 安装

```lua
-- vim.pack / lazy.nvim 均可，setup 是关键
{
  dir = "~/neovim-plugins/ui-menu.nvim",
  priority = 999, -- 需要早于其它插件的 config 接管 vim.ui.select
  config = function()
    require("ui_menu").setup({ replace_select = true })
  end,
}
```

只想直接用、不想改动全局：

```lua
require("ui_menu").setup()
require("ui_menu").select(items, { prompt = "Pick: ", format_item = tostring }, function(item)
  print(vim.inspect(item))
end)
```

## 配置

```lua
require("ui_menu").setup({
  width = 64,
  min_width = 30,
  max_height = 14,
  border = "rounded",
  tick = 90,
  replace_select = false, -- true = 接管 vim.ui.select
  should_replace = nil,   -- fun(items, opts): boolean? 仅接管时生效
})
```

`should_replace` 返回 `false` 时交给原实现，例如只接管没有预览需求的选择：

```lua
should_replace = function(_, _) return true end
```

## 用法

- `M.select(items, opts, on_choice)`：同 `vim.ui.select`，返回是否成功打开
- `opts.tick = true|number`：动画模式，`format_item(item, frame)` 第二参递增
- `opts.position = "center"`：固定屏幕居中，不跟随光标
- `opts.on_tab = fun()`：菜单里按 `<Tab>` 时关闭菜单并调用它（例如地图 ⇄ 列表切换）
- `format_item` 返回第二值 `virt_text`：`{ {text, hl}, ... }` 挂在行尾
- 结构化条目：`name/text/label` + `icon/icon_hl/name_hl`
- `M.spinner(frames?)`、`M.frames`、`M.config` 供外部复用

键位（菜单打开时）：`j/k/<Down>/<Up>/<C-n>/<C-p>` 移动，`gg/G` 首尾，`1-9` 直选，
`i/f//` 输入，`<C-g>` 索引模式，`?` 帮助，`<CR>` 确认，`Esc/q` 取消。

## 高亮

`UiMenuLabel`、`UiMenuLabelDim`、`UiMenuIndex`、`UiMenuError`、`UiMenuMatch`；
均以 `default = true` 链接到常规组，可被主题覆盖。

## 与 picker 的分工

本插件只做“贴着光标的小浮窗”。需要整宽预览（文件内容、diff、图片）请用专门的 picker，
不要往这里加预览。

## 测试

```sh
./tests/run.sh
```

## License

MIT
