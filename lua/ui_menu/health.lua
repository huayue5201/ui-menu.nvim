local M = {}

function M.check()
	local h = vim.health
	h.start("ui-menu.nvim")

	if vim.fn.has("nvim-0.10") == 1 then
		h.ok("Neovim >= 0.10")
	else
		h.warn("建议 Neovim >= 0.10")
	end

	local ok, menu = pcall(require, "ui_menu")
	if not ok then
		h.error("无法加载 ui_menu: " .. tostring(menu))
		return
	end
	h.ok("模块可加载")

	if menu.config.replace_select then
		if vim.ui.select ~= menu.select_wrapper then
			h.error("replace_select=true 但 vim.ui.select 未被接管")
		else
			h.ok("vim.ui.select 已被接管")
		end
	else
		h.info("replace_select=false（只导出 M.select）")
	end
	h.info(("config: width=%s min_width=%s max_height=%s border=%s tick=%s"):format(
		menu.config.width,
		menu.config.min_width,
		menu.config.max_height,
		menu.config.border,
		menu.config.tick
	))
end

return M
