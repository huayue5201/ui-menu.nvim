-- 用户视角：ui_menu（可选接管 vim.ui.select 的浮窗菜单）。
--
--   nvim --headless -u NONE -l tests/menu.lua
--
-- 覆盖：
--   1. 过滤：空查询返回全部、模糊命中带高亮位置、无命中为空
--   2. 标签：所有行连续编号、右对齐到同一列
--   3. 数字键直接选中、<C-n> 移动 + <CR> 选中
--   4. 输入字符过滤、<BS> 退格、<C-u> 清空
--   5. Esc 取消 → 回调 (nil, nil)
--   6. 单飞：菜单开着时第二次调用只返回 false，不叠第二层；结束后能再开
--   6c. 输入模式下 Esc 只退回导航模式，不关菜单；再按 Esc 才取消
--   6d. ? 打开按键帮助浮窗，任意键收起
--   8. 大写查询走大小写不敏感的兜底，命中位置必须 0-based（高亮不偏格）；中文位置正确
--   9. 输入模式的数字是查询字符（不是直接选中）；中文可输入、<BS> 多字节安全
--   10. 列表超过 max_height 时滚动，选中项始终在视口内
--   11. 锚点贴光标所在的屏幕行列（长行折行时不跑到行首），且始终钳制在屏幕内
--   14. 索引模式：<C-g> + 数字 + <CR>（越界不选、<BS>/<C-u> 可编辑、过滤后作用于结果）
--   13. gg 首项 / G 末项（g 后接其它键不作数）
--   12. 每一行都带序号，文本列对齐（第 19 项以后也一样）；输入模式下序号变暗；关菜单后 buffer 全部释放
--   7. 默认不接管；replace_select=true 后接管，M.original_select 保留原实现
--   15. 动画模式：opts.tick 超时推进帧号，format_item(item, frame) 拿到递增帧
--
-- 退出码：有失败 1，全通过 0。

vim.opt.rtp:prepend(vim.fn.getcwd())

local menu = require("ui_menu")
local function cp(n)
	io.stderr:write("CP " .. n .. "\n")
end

local fails = {}
local function check(cond, msg)
	if not cond then
		fails[#fails + 1] = msg
	end
end

local kc = vim.keycode
local function feed(keys)
	vim.api.nvim_feedkeys(keys, "n", false)
end

----------------------------------------------------------------------
-- 1. 过滤
----------------------------------------------------------------------

local items = { "alpha", "beta", "gamma", "delta" }
check(#menu.filter(items, "", tostring) == 4, "empty query should return all items")
local hits = menu.filter(items, "ga", tostring)
check(#hits == 1 and hits[1].text == "gamma", "query ga should match gamma")
check(type(hits[1].positions) == "table" and #hits[1].positions == 2, "a match should carry two highlight positions")
check(#menu.filter(items, "zzz", tostring) == 0, "no match should return empty")

----------------------------------------------------------------------
-- 2. 标签
----------------------------------------------------------------------

check(menu.label(1) == "1" and menu.label(19) == "19", "every row has an index (no missing labels after 19)")
check(menu.label_width(4) == 2 and menu.label_width(140) == 3, "label width: at least 2, grows with item count")
check(menu.line(2, "x", 2) == " 2 x", "line text = right-aligned index + space + content")
check(menu.line(12, "x", 2) == "12 x", "two-digit index filling 2 columns gets no padding")

----------------------------------------------------------------------
-- 3/4/5. 键位：数字选中、移动、输入过滤、退格、清空、取消
----------------------------------------------------------------------

local function run(keys, given_items, opts)
	local got = { called = 0 }
	feed(keys)
	menu.select(given_items or items, opts or {}, function(item, idx)
		got.called = got.called + 1
		got.item, got.idx = item, idx
	end)
	return got
end

local r = run("2")
check(r.called == 1 and r.item == "beta", "pressing 2 should pick beta, got " .. tostring(r.item))

r = run(kc("<C-n>") .. kc("<C-n>") .. kc("<CR>"))
check(r.item == "gamma", "after two <C-n>, <CR> should pick gamma, got " .. tostring(r.item))

r = run(kc("<C-p>") .. kc("<CR>"))
check(r.item == "delta", "<C-p> should wrap to the last item")

r = run("i" .. "ga" .. kc("<CR>"))
check(r.item == "gamma", "after i enters input mode, typing ga should pick gamma, got " .. tostring(r.item))

r = run("f" .. "ga" .. kc("<CR>"))
check(r.item == "gamma", "f should also enter input mode, got " .. tostring(r.item))

r = run("ga" .. kc("<CR>"))
check(r.item == "alpha", "letters do not enter the query in navigation mode (should pick first), got " .. tostring(r.item))

r = run("jj" .. kc("<CR>"))
check(r.item == "gamma", "j should move down in navigation mode, got " .. tostring(r.item))

r = run("ijk" .. kc("<C-u>") .. kc("<CR>"))
check(r.item == "alpha", "j/k are query characters in input mode (<C-u> clears and should pick first again)")

r = run("i" .. "gm" .. kc("<BS>") .. "amm" .. kc("<CR>"))
check(r.item == "gamma", "typing after backspace should still match gamma, got " .. tostring(r.item))

r = run("i" .. "zzz" .. kc("<C-u>") .. kc("<CR>"))
check(r.item == "alpha", "after <C-u> clears the query, <CR> should pick the first item")

r = run(kc("<Esc>"))
check(r.called == 1 and r.item == nil, "Esc should call back with (nil, nil)")

-- M-<pivot> 已移除：M-s 不再选第 11 项，只剩 1-9 与 <C-g> 索引模式
r = run(kc("<M-s>") .. kc("<CR>"), { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l" })
check(r.item == "a", "M-<pivot> should be gone (stays on first item), got " .. tostring(r.item))

----------------------------------------------------------------------
-- 5b. 提示文本在边框中间（含输入模式标记）
----------------------------------------------------------------------

local titles, bodies, cursors, marks, inputs = {}, {}, {}, {}, {}
local orig_rk_title = menu._read_key
local title_reads = 0
menu._read_key = function()
	title_reads = title_reads + 1
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		local cfg = vim.api.nvim_win_get_config(w)
		local parts = {}
		if cfg.title then
			for _, chunk in ipairs(cfg.title) do
				parts[#parts + 1] = chunk[1]
			end
		end
		local text = table.concat(parts)
		local buf = vim.api.nvim_win_get_buf(w)
		local body = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		if cfg.relative ~= "" and body[1] and body[1]:find("❯", 1, true) then
			local hl = {}
			for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
				hl[#hl + 1] = (m[4] or {}).hl_group
			end
			inputs[#inputs + 1] = { line = body[1], cursor = vim.api.nvim_win_get_cursor(w), hl = hl }
		end
		if text == "Pick: " then
			titles[#titles + 1] = { text = text, pos = cfg.title_pos }
			bodies[#bodies + 1] = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
			cursors[#cursors + 1] = vim.api.nvim_win_get_cursor(w)
			local hl = {}
			for _, m in
				ipairs(vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(w), -1, 0, -1, { details = true }))
			do
				hl[#hl + 1] = (m[4] or {}).hl_group
			end
			marks[#marks + 1] = hl
		end
	end
	if title_reads == 1 then
		return "i"
	elseif title_reads == 2 then
		return "g"
	end
	return nil
end
menu.select({ "alpha", "beta" }, { prompt = "Pick: ", format_item = tostring }, function() end)
menu._read_key = orig_rk_title
check(#titles >= 2, "border title should update before every key read")
check(titles[1] and titles[1].text:find("Pick: ", 1, true) ~= nil, "title should contain the prompt")
check(titles[1] and titles[1].pos == "center", "title should be centered (title_pos = center)")
-- 输入框是**独立的浮窗**，贴在列表下方；列表本身不再有输入行
local last_body = bodies[#bodies]
check(last_body and last_body[1] ~= nil and not last_body[1]:find("❯", 1, true), "the list should no longer have an input row")
local last_input = inputs[#inputs]
check(last_input ~= nil, "input mode should show a separate input popup")
check(
	last_input and last_input.line == " ❯ g ",
	"input popup content should be the query, got " .. tostring(last_input and last_input.line)
)
check(
	last_input and last_input.cursor[1] == 1 and last_input.cursor[2] == 6,
	"cursor should sit at the end of the query in the input popup (1,6), got " .. vim.inspect(last_input and last_input.cursor)
)
check(bodies[1] and bodies[1][1] == "  1 alpha", "no query row in navigation mode")
-- 输入框的光标格要有 Cursor 高亮：浮窗里的真光标未必被终端显示，这一格保证位置可见
local last_marks = (last_input and last_input.hl) or {}
local has_cursor = false
for _, g in ipairs(last_marks) do
	if g == "Cursor" then
		has_cursor = true
	end
end
check(has_cursor, "input popup should mark the cursor with a Cursor-highlighted cell")

----------------------------------------------------------------------
-- 6. 单飞
----------------------------------------------------------------------

-- 菜单开着的时候再调一次：立即返回 false，且不会叠第二层
local first = { called = 0 }
local second_result = nil
feed("2")
menu.select({ "one", "two" }, {}, function(item)
	first.called = first.called + 1
	first.item = item
	-- 菜单内部回调时 _busy 已经放开：再开一次应能成功（用 Esc 立刻关掉，避免阻塞）
	feed(kc("<Esc>"))
	second_result = menu.select({ "x" }, {}, function() end)
end)
check(first.called == 1 and first.item == "two", "first call should pick normally")
check(second_result == true, "the menu should open again after closing")

-- 真正在菜单开着时重入：用一次嵌套调用模拟（第二次直接返回 false）
local reentry, reentry_cancelled = nil, false
local started = false
local orig_read_key = menu._read_key
menu._read_key = function()
	if not started then
		started = true
		reentry = menu.select({ "nested" }, { prompt = "nested: " }, function(item)
			reentry_cancelled = item == nil
		end)
	end
	return nil -- 立刻结束当前菜单
end
menu.select({ "outer" }, {}, function() end)
menu._read_key = orig_read_key
check(reentry == false, "re-entry while open should return false (no second layer)")
check(reentry_cancelled, "rejected request should get a nil callback so callers do not hang")
check(menu._busy == false, "_busy should reset after the menu closes")

----------------------------------------------------------------------
-- 6b. 浮窗被外部关掉：循环必须立刻结束，不能变成"看不见的菜单"继续吃键
----------------------------------------------------------------------

local ext = { n = 0 }
local orig_read_key_6b = menu._read_key
menu._read_key = function()
	-- 模拟"读键期间浮窗被 :q / 切 tab / 别的插件关掉"，同时手上还有键要继续消费
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		local cfg = vim.api.nvim_win_get_config(w)
		local text = ""
		if cfg.title then
			for _, chunk in ipairs(cfg.title) do
				text = text .. chunk[1]
			end
		end
		if text:find("External: ", 1, true) then
			vim.api.nvim_win_close(w, true)
		end
	end
	return "1" -- 本来会选中第 1 项，但窗口已经没了
end
menu.select({ "a", "b" }, { prompt = "External: " }, function(item)
	ext.n = ext.n + 1
	ext.item = item
end)
menu._read_key = orig_read_key_6b
-- WinClosed 会往队列里塞一个 Esc 用来解除阻塞；这里是模拟关闭，Esc 没人消费，先冲掉
pcall(vim.fn.feedkeys, "", "x")
check(ext.n == 1, "external close should end the menu with exactly one callback, got " .. ext.n .. " callbacks")
check(ext.item == nil, "external close should count as cancel (callback nil)")
check(menu._busy == false, "_busy should reset after external close")

----------------------------------------------------------------------
-- 6c. Esc 的两段语义：输入模式 -> 导航模式 -> 取消
----------------------------------------------------------------------

-- 第一次 Esc 只退出输入模式（查询保留），第二次 Esc 才取消
r = run("i" .. "ga" .. kc("<Esc>") .. kc("<Esc>"))
check(r.called == 1 and r.item == nil, "Esc twice from input mode cancels, got " .. tostring(r.item))

-- 退出输入模式后查询仍在：Esc 之后按 <CR> 应选中过滤后的第一项（gamma）
r = run("i" .. "ga" .. kc("<Esc>") .. kc("<CR>"))
check(r.item == "gamma", "Esc leaving input mode keeps the query (gamma), got " .. tostring(r.item))

-- 退出输入模式后 j/k 恢复为移动
r = run("i" .. kc("<Esc>") .. "j" .. kc("<CR>"))
check(r.item == "beta", "after Esc, j should move again, got " .. tostring(r.item))

-- 浮窗用 enter=true 才能画真光标，关掉后必须把焦点还给原窗口
local before_win = vim.api.nvim_get_current_win()
r = run("2")
check(vim.api.nvim_get_current_win() == before_win, "focus should return to the original window after closing")

----------------------------------------------------------------------
-- 6d. ? 打开按键帮助浮窗
----------------------------------------------------------------------

local help_wins = {}
local orig_rk_help = menu._read_key
local help_reads = 0
menu._read_key = function()
	help_reads = help_reads + 1
	local found = nil
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		local cfg = vim.api.nvim_win_get_config(w)
		local text = ""
		if cfg.title then
			for _, chunk in ipairs(cfg.title) do
				text = text .. chunk[1]
			end
		end
		if text == " Help " then
			found = { win = w, lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false) }
		end
	end
	help_wins[help_reads] = found
	if help_reads == 1 then
		return "?"
	elseif help_reads == 2 then
		return "x" -- 任意键只收帮助
	end
	return nil
end
menu.select({ "alpha", "beta" }, { prompt = "Query: ", format_item = tostring }, function() end)
menu._read_key = orig_rk_help
check(help_wins[1] == nil, "no help popup before ?")
check(help_wins[2] ~= nil, "help popup should appear after ?")
local hl = help_wins[2] and table.concat(help_wins[2].lines, "\n") or ""
check(hl:find("<Esc>", 1, true) ~= nil and hl:find("<CR>", 1, true) ~= nil, "help should list key bindings")
check(#vim.api.nvim_list_wins() >= 1, "no window should remain after closing help")

----------------------------------------------------------------------
-- 8. 大小写 / 多字节：兜底位置也必须跟 matchfuzzypos 一样是 0-based
----------------------------------------------------------------------

-- matchfuzzypos 是大小写敏感的（"FOO" 匹配不到 "foo bar"），所以大写查询走兜底；
-- 兜底曾经把 find 的 1-based 位置塞进 positions，高亮整体偏一格。
local up = menu.filter({ "foo bar" }, "FOO", tostring)
check(#up == 1, "uppercase query should match foo bar, got " .. #up .. " matches")
local up_pos = up[1] and table.concat(up[1].positions or {}, ",") or ""
check(up_pos == "0,1,2", "fallback positions should be 0-based byte offsets 0,1,2, got " .. up_pos)

local cjk = menu.filter({ "zhong 中文" }, "中文", tostring)
check(
	#cjk == 1 and cjk[1].positions[1] == 6,
	"CJK query should match and report char-start bytes, got " .. vim.inspect(cjk[1] and cjk[1].positions)
)
check(
	#(cjk[1] and cjk[1].positions or {}) == 2,
	"CJK matches should not split chars into bytes, got " .. vim.inspect(cjk[1] and cjk[1].positions)
)

----------------------------------------------------------------------
-- 9. 输入模式下的数字是查询字符；中文可输入、退格安全
----------------------------------------------------------------------

-- 导航模式按 1 选第 1 项（"b2"）；输入模式按 1 应过滤出 "a1"
r = run("1", { "b2", "a1" })
check(r.item == "b2", "pressing 1 in navigation mode should pick item 1, got " .. tostring(r.item))
r = run("i" .. "1" .. kc("<CR>"), { "b2", "a1" })
check(r.item == "a1", "pressing 1 in input mode should filter, not pick item 1, got " .. tostring(r.item))

r = run("i" .. "中" .. kc("<BS>") .. "英" .. kc("<CR>"), { "中文", "英文" })
check(r.item == "英文", "CJK input and <BS> should work, got " .. tostring(r.item))

----------------------------------------------------------------------
-- 10. 超过 max_height 时滚动，选中项始终可见
----------------------------------------------------------------------

local many = {}
for i = 1, 40 do
	many[i] = ("item%02d"):format(i)
end
local seen = {}
local orig_rk_scroll = menu._read_key
local reads = 0
local old_max = menu.config.max_height
menu.config.max_height = 5
menu._read_key = function()
	reads = reads + 1
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		local cfg = vim.api.nvim_win_get_config(w)
		local text = ""
		if cfg.title then
			for _, chunk in ipairs(cfg.title) do
				text = text .. chunk[1]
			end
		end
		if text == "Many: " then
			seen[#seen + 1] = {
				height = vim.api.nvim_win_get_height(w),
				lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false),
				cursor = vim.api.nvim_win_get_cursor(w),
			}
		end
	end
	if reads <= 20 then
		return kc("<C-n>")
	end
	return kc("<Esc>")
end
menu.select(many, { prompt = "Many: ", format_item = tostring }, function() end)
menu._read_key = orig_rk_scroll
menu.config.max_height = old_max

local tall = false
for _, s in ipairs(seen) do
	if s.height > 5 then
		tall = true
	end
end
check(#seen > 0, "should be able to sample the menu popup")
check(not tall, "popup height should not exceed max_height=5")
local last_seen = seen[#seen]
check(
	last_seen and #last_seen.lines == 5,
	"viewport should have exactly 5 rows, got " .. tostring(last_seen and #last_seen.lines)
)
check(
	last_seen and last_seen.lines[5] and last_seen.lines[5]:find("item21", 1, true) ~= nil,
	"item 21 should scroll to the viewport bottom, got " .. tostring(last_seen and last_seen.lines[5])
)
check(
	last_seen and last_seen.cursor[1] == 5,
	"selected item should be on the last viewport row, got " .. vim.inspect(last_seen and last_seen.cursor)
)

----------------------------------------------------------------------
-- 11. 锚点用光标所在屏幕行列（长行折行时不能跑到行首）
----------------------------------------------------------------------

local anchor = {}
vim.wo.wrap = true
vim.api.nvim_buf_set_lines(0, 0, -1, false, { string.rep("abcdefghij", 20) })
vim.api.nvim_win_set_cursor(0, { 1, 95 })
vim.cmd("redraw")
-- 期望值用 screenpos 独立算：光标在第 1 个屏幕行的后面几行，行首则在第 1 行
local want = vim.fn.screenpos(0, 1, 96)
local line_start = vim.fn.screenpos(0, 1, 1)
local orig_rk_anchor = menu._read_key
menu._read_key = function()
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		local cfg = vim.api.nvim_win_get_config(w)
		local text = ""
		if cfg.title then
			for _, chunk in ipairs(cfg.title) do
				text = text .. chunk[1]
			end
		end
		if text == "Anchor: " then
			anchor = vim.tbl_extend("force", anchor, {
				win = w,
				row = cfg.row,
				col = cfg.col,
				width = cfg.width,
			})
		end
	end
	return kc("<Esc>")
end
menu.select({ "a", "b" }, { prompt = "Anchor: " }, function() end)
menu._read_key = orig_rk_anchor

check(anchor.win ~= nil, "menu popup should open")
check(want.row > line_start.row, "test precondition: cursor should be on a wrapped screen row, got " .. vim.inspect(want))
check(
	anchor.row == want.row,
	("menu should stick to cursor screen row %d, got %s (line start on row %d)"):format(
		want.row,
		tostring(anchor.row),
		line_start.row
	)
)
check(anchor.col == want.col, ("menu should stick to cursor screen column %d, got %s"):format(want.col, tostring(anchor.col)))
-- 宽度是自适应的（config.width 只是上限），比的是浮窗实际宽度
check(
	anchor.col + anchor.width <= vim.go.columns + 1,
	("menu should not exceed the right edge (col=%s, width=%d, columns=%d)"):format(
		tostring(anchor.col),
		tostring(anchor.width),
		vim.go.columns
	)
)

----------------------------------------------------------------------
-- 12. 每一行都带序号、文本列对齐；输入模式下序号变暗；关菜单后 buffer 全部释放
----------------------------------------------------------------------

local many3 = {}
for i = 1, 30 do
	many3[i] = ("abc%02d"):format(i)
end
local snap = {}
local old_max3 = menu.config.max_height
menu.config.max_height = 40
-- render 会把视口高度再按屏幕行数收窄（vim.go.lines - 4），headless 默认只有 24 行，
-- 不放大就拿不到第 21 行。测完后恢复。
local old_lines3 = vim.o.lines
vim.o.lines = 44
local orig_rk_label = menu._read_key
local step = 0
menu._read_key = function()
	step = step + 1
	if step == 5 then
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			local cfg = vim.api.nvim_win_get_config(w)
			local text = ""
			if cfg.title then
				for _, chunk in ipairs(cfg.title) do
					text = text .. chunk[1]
				end
			end
			if text == "Lbl: " then
				local buf = vim.api.nvim_win_get_buf(w)
				snap.lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				snap.marks = {}
				snap.label_hl = {}
				for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
					if m[4].hl_group == "UiMenuMatch" then
						snap.marks[#snap.marks + 1] = { line = m[2], col = m[3] }
					elseif m[4].hl_group == "UiMenuLabel" or m[4].hl_group == "UiMenuLabelDim" then
						snap.label_hl[m[2]] = m[4].hl_group
					end
				end
			end
		end
	end
	local keys = { "i", "a", "b", "c", kc("<Esc>"), kc("<Esc>") }
	return keys[step]
end
local bufs_before = {}
for _, b in ipairs(vim.api.nvim_list_bufs()) do
	bufs_before[b] = true
end
menu.select(many3, { prompt = "Lbl: ", format_item = tostring }, function() end)
menu._read_key = orig_rk_label
menu.config.max_height = old_max3
vim.o.lines = old_lines3

local marks_by_line = {}
for _, m in ipairs(snap.marks or {}) do
	marks_by_line[m.line] = marks_by_line[m.line] or {}
	table.insert(marks_by_line[m.line], m.col)
end
-- 标签列宽 2（30 项），所有行都是 " 数字 文本"：文本从 0-based 列 4 开始，命中在 4,5,6
local labeled = table.concat(marks_by_line[0] or {}, ",")
-- 第 21 行同样是 "21 abc21"，文本列与第 1 行完全一致（这正是补齐序号的点）
local unlabeled = table.concat(marks_by_line[20] or {}, ",")
check(labeled == "4,5,6", "row 1 highlight columns should be 4,5,6, got " .. labeled)
check(unlabeled == "4,5,6", "row 21 highlight columns should also be 4,5,6, got " .. unlabeled)
-- 快照时已输入 "abc"，处于输入模式：序号压成注释色，不冒充快捷键
check(snap.label_hl[0] == "UiMenuLabelDim", "index should dim in input mode, got " .. tostring(snap.label_hl[0]))

for _, b in ipairs(vim.api.nvim_list_bufs()) do
	check(
		bufs_before[b] or not vim.api.nvim_buf_is_valid(b),
		"no scratch buffer should leak after closing: " .. tostring(b)
	)
end

-- 帮助浮窗也走一遍：'?' 开、Esc 收、Esc 关，buffer 同样不能漏
local orig_rk_help = menu._read_key
local hstep = 0
menu._read_key = function()
	hstep = hstep + 1
	local keys = { "?", kc("<Esc>"), kc("<Esc>") }
	return keys[hstep]
end
menu.select({ "a" }, { prompt = "Help: " }, function() end)
menu._read_key = orig_rk_help
for _, b in ipairs(vim.api.nvim_list_bufs()) do
	check(
		bufs_before[b] or not vim.api.nvim_buf_is_valid(b),
		"no scratch buffer should leak after closing help: " .. tostring(b)
	)
end

----------------------------------------------------------------------
-- 7. 接管 vim.ui.select
----------------------------------------------------------------------

local orig = vim.ui.select
-- 默认不接管：只导出 M.select
menu.setup({ max_height = 10 })
check(vim.ui.select == orig, "default setup should not replace vim.ui.select")
-- 显式开启接管
menu.setup({ max_height = 10, replace_select = true })
check(menu.original_select ~= nil, "setup should keep the original implementation")
check(vim.ui.select ~= orig, "after setup{ replace_select = true }, vim.ui.select should be the menu")

local via_ui = { called = 0 }
feed("3")
vim.ui.select({ "one", "two", "three" }, { prompt = "Pick: " }, function(item)
	via_ui.called = via_ui.called + 1
	via_ui.item = item
end)
check(via_ui.called == 1 and via_ui.item == "three", "vim.ui.select should go through the menu and pick item 3")

-- 空列表：立刻回调 nil，不弹窗
local empty = { called = 0 }
vim.ui.select({}, {}, function(item)
	empty.called = empty.called + 1
	empty.item = item
end)
check(empty.called == 1 and empty.item == nil, "empty list should call back nil immediately")

vim.ui.select = orig

----------------------------------------------------------------------
-- 13. gg / G：跳到首项 / 末项；g 后接其它键不作数
----------------------------------------------------------------------

local five = { "a", "b", "c", "d", "e" }

local r_gg = run(kc("<C-n>") .. kc("<C-n>") .. kc("<C-n>") .. "gg" .. kc("<CR>"), five)
check(r_gg.item == "a", "after moving down 3 times, gg should return to first, got " .. tostring(r_gg.item))

local r_G = run("G" .. kc("<CR>"), five)
check(r_G.item == "e", "G should pick the last item, got " .. tostring(r_G.item))

-- g 后接非 g：作废那个 g，后面的键按原语义处理（gj = 下移一次）
local r_gj = run("g" .. "j" .. kc("<CR>"), five)
check(r_gj.item == "b", "gj should count as one move down (g ignored), got " .. tostring(r_gj.item))

-- 小写 g 回车：没有 gg，仍停在当前项
local r_g_cr = run(kc("<C-n>") .. "g" .. kc("<CR>"), five)
check(r_g_cr.item == "b", "a single g then <CR> should keep the current item, got " .. tostring(r_g_cr.item))

----------------------------------------------------------------------
-- 14. 索引模式：<C-g> + 数字 + <CR>
----------------------------------------------------------------------

local many = {}
for i = 1, 40 do
	many[i] = ("item%02d"):format(i)
end

local r_idx = run(kc("<C-g>") .. "2" .. "1" .. kc("<CR>"), many)
check(r_idx.item == "item21", "index mode 21 should pick item 21, got " .. tostring(r_idx.item))

-- 越界时 <CR> 不选、也不关菜单；选中行停在「最后有效的那一项」（99 越界 → 停在 9）
-- <Esc> 退回导航模式后 <CR> 选中的就是这一项
local r_bad = run(kc("<C-g>") .. "9" .. "9" .. kc("<CR>") .. kc("<Esc>") .. kc("<CR>"), many)
check(r_bad.item == "item09", "after out-of-range, Esc should pick the last valid item 9, got " .. tostring(r_bad.item))

-- <BS> 删一位后重新生效；<C-u> 清空后敲新的也生效
local r_bs = run(kc("<C-g>") .. "3" .. "9" .. kc("<BS>") .. kc("<CR>"), many)
check(r_bs.item == "item03", "39 backspaced to 3 should pick item 3, got " .. tostring(r_bs.item))
local r_cu = run(kc("<C-g>") .. "3" .. "9" .. kc("<C-u>") .. "7" .. kc("<CR>"), many)
check(r_cu.item == "item07", "<C-u> then 7 should pick item 7, got " .. tostring(r_cu.item))

-- 输入模式里 <C-g> 转入索引模式，序号作用于**过滤后**的结果
local r_filtered = run("i" .. "m0" .. kc("<C-g>") .. "2" .. kc("<CR>"), { "m01", "x", "m02", "m03" })
check(r_filtered.item == "m02", "index should apply to filtered results, got " .. tostring(r_filtered.item))

-- M-<pivot> 已移除：按 M-a 不再选第 10 项
local r_ma = run(kc("<M-a>") .. kc("<CR>"), many)
check(r_ma.item == "item01", "M-<pivot> should be gone, got " .. tostring(r_ma.item))

----------------------------------------------------------------------
-- 15. 动画模式：opts.tick 超时推进帧号，format_item(item, frame) 拿到递增帧
----------------------------------------------------------------------
-- 15a. spinner 助手：帧号取模、无帧时回退到 base / 第一帧、自定义帧序列
local spin15 = menu.spinner()
check(spin15(nil, "◐") == "◐", "should fall back to base without a frame")
check(spin15(nil) == menu.frames[1], "should use the first frame without a frame or base")
check(spin15(0) == menu.frames[1] and spin15(1) == menu.frames[2], "frame index should start at the first frame")
check(spin15(#menu.frames) == menu.frames[1], "frame index should wrap around the frame count")
local spin15b = menu.spinner({ "a", "b" })
check(spin15b(3) == "b" and spin15b(nil, "x") == "x", "custom frame sequences should work")

local frames15 = {}
local idx15 = 0
local keys15 = { nil, nil, nil, kc("<CR>") }
local orig_rk15 = menu._read_key
menu._read_key = function()
	idx15 = idx15 + 1
	return keys15[idx15]
end
local chosen15
menu.select({ "busy", "idle" }, {
	prompt = "Anim: ",
	tick = true, -- 用 M.config.tick
	format_item = function(item, frame)
		frames15[#frames15 + 1] = frame
		return (frame and ("frame" .. frame) or "static") .. " " .. item
	end,
}, function(item)
	chosen15 = item
end)
menu._read_key = orig_rk15
check(chosen15 == "busy", "animation mode should still pick normally (got " .. tostring(chosen15) .. ")")
check(#frames15 >= 6, "animation mode should repaint every frame, format_item called " .. #frames15 .. " callbacks")
local maxf15, monotone15 = 0, true
for _, f in ipairs(frames15) do
	if type(f) == "number" then
		maxf15 = math.max(maxf15, f)
	else
		monotone15 = false
	end
end
check(maxf15 >= 2, "frame index should increase so the spinner turns, max=" .. maxf15)
check(monotone15, "format_item should always get a numeric frame in animation mode")

----------------------------------------------------------------------
-- 12. position = "center" 固定居中，不跟随光标
----------------------------------------------------------------------

local centered
local orig_rk_center = menu._read_key
menu._read_key = function()
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		local cfg = vim.api.nvim_win_get_config(w)
		local text = ""
		if cfg.title then
			for _, chunk in ipairs(cfg.title) do
				text = text .. chunk[1]
			end
		end
		if text == "Center: " then
			centered = cfg
		end
	end
	return kc("<Esc>")
end
menu.select({ "a", "b" }, { prompt = "Center: ", position = "center" }, function() end)
menu._read_key = orig_rk_center

check(centered ~= nil, "centered select should open a popup")
if centered then
	local want_row = math.floor((vim.go.lines - centered.height) / 2) + 1
	local want_col = math.floor((vim.go.columns - centered.width) / 2)
	check(
		centered.row == want_row,
		("menu should be fixed on the center row (want=%d got=%d)"):format(want_row, centered.row)
	)
	check(
		centered.col == want_col,
		("menu should be fixed on the center column (want=%d got=%d)"):format(want_col, centered.col)
	)
end

----------------------------------------------------------------------
-- 13. on_tab：列表里按 <Tab> 交给调用方（地图 ⇄ 列表）
----------------------------------------------------------------------

local switched = false
local orig_rk_tab = menu._read_key
menu._read_key = function()
	return kc("<Tab>")
end
local selected_tab = false
menu.select({ "a", "b" }, {
	prompt = "Tab: ",
	on_tab = function()
		switched = true
	end,
}, function()
	selected_tab = true
end)
menu._read_key = orig_rk_tab
check(switched, "<Tab> should call on_tab")
check(not selected_tab, "<Tab> should not trigger the selection callback")

----------------------------------------------------------------------
-- 收尾
----------------------------------------------------------------------

if #fails == 0 then
	print(
		"ok: popup select menu (filter/labels/keys/cancel/single-flight/scroll/anchor/vim.ui.select takeover) behaves as expected"
	)
	vim.cmd("qall!")
end

for _, msg in ipairs(fails) do
	io.stderr:write("FAIL " .. msg .. "\n")
end
io.stderr:write(("%d checks failed\n"):format(#fails))
vim.cmd("cq")
