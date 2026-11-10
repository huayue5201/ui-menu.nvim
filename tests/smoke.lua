-- 最小依赖冒烟：只 require + select，不依赖任何插件。
vim.opt.rtp:prepend(vim.fn.getcwd())

local menu = require("ui_menu")
local function check(c, m)
	if not c then
		error("FAIL: " .. m, 0)
	end
end

local before = vim.ui.select
menu.setup({})
check(vim.ui.select == before, "vim.ui.select is not replaced by default")
-- 直接调用 M.select（用 1 选中，避免依赖 UI 状态）
local got
menu._read_key = function()
	return "1"
end
menu.select({ "alpha", "beta" }, { prompt = "Pick: " }, function(item)
	got = item
end)
check(got == "alpha", "M.select should pick item 1")

-- 显式接管后，空列表立刻回调 nil
menu.setup({ replace_select = true })
check(vim.ui.select ~= before, "replace_select should replace vim.ui.select")
local called = 0
vim.ui.select({}, {}, function(item)
	called = called + 1
	check(item == nil, "empty list calls back nil")
end)
check(called == 1, "empty list should call back immediately")

-- 关闭接管应恢复原实现
menu.setup({ replace_select = false })
check(vim.ui.select == before, "replace_select=false should restore the original implementation")
print("ok: ui_menu smoke test")
