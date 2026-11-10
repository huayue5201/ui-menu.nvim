local M = {}

function M.check()
	local h = vim.health
	h.start("ui-menu.nvim")

	if vim.fn.has("nvim-0.10") == 1 then
		h.ok("Neovim >= 0.10")
	else
		h.warn("Neovim >= 0.10 recommended")
	end

	local ok, menu = pcall(require, "ui_menu")
	if not ok then
		h.error("failed to load ui_menu: " .. tostring(menu))
		return
	end
	h.ok("module loads")

	if menu.config.replace_select then
		if vim.ui.select ~= menu.select_wrapper then
			h.error("replace_select=true but vim.ui.select was not taken over")
		else
			h.ok("vim.ui.select is taken over")
		end
	else
		h.info("replace_select=false (only exports M.select)")
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
