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
check(vim.ui.select == before, "默认不接管 vim.ui.select")
-- 直接调用 M.select（用 1 选中，避免依赖 UI 状态）
local got
menu._read_key = function()
	return "1"
end
menu.select({ "alpha", "beta" }, { prompt = "Pick: " }, function(item)
	got = item
end)
check(got == "alpha", "M.select 应能选中第 1 项")

-- 显式接管后，空列表立刻回调 nil
menu.setup({ replace_select = true })
check(vim.ui.select ~= before, "replace_select 应替换 vim.ui.select")
local called = 0
vim.ui.select({}, {}, function(item)
	called = called + 1
	check(item == nil, "空列表回调 nil")
end)
check(called == 1, "空列表应立刻回调")

-- 关闭接管应恢复原实现
menu.setup({ replace_select = false })
check(vim.ui.select == before, "replace_select=false 应恢复原实现")
print("ok: ui_menu 冒烟")
