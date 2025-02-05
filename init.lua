local utils = require('wintab.utils')

local M = {}

local separator = ''
local wintab_augroup = vim.api.nvim_create_augroup('wintab', {})

---@class wintab.Component
---@field bufnr integer
local Component = {}
Component.__index = Component
M.Component = Component

---@param bufnr integer
function Component.new(bufnr)
  local self = setmetatable({}, Component)
  self.bufnr = bufnr
  return self
end

---@param active? boolean
---@return string
---@return integer
function Component:render(active)
  local label = string.format(' %s ', vim.api.nvim_buf_get_name(self.bufnr))
  local hl = active and 'MyTabLineSel' or 'MyTabLineNotSel'
  local click = string.format('%%%d@v:lua.wintab_handle_click@', self.bufnr)
  return string.format('%s%%#%s#%s', click, hl, label), vim.api.nvim_strwidth(label)
end

---@param minwid integer
---@param clicks integer
---@param button string
---@param modifiers string
local function wintab_handle_click(minwid, clicks, button, modifiers) ---@diagnostic disable-line
  local id = minwid -- minwid 可直接用于 id
  --print('mouse click', id, clicks, button, modifiers)
  vim.cmd.buffer(id)
end

local function adjust_by_width(items, width) return items end

---@param components wintab.Component[]
---@return string
function M.winbar(components)
  local renders = {}
  local bufnr = vim.api.nvim_get_current_buf()
  local total_width = 0
  local active_width = 0
  local active_index = 0
  for idx, item in ipairs(components) do
    local active = item.bufnr == bufnr
    local text, width = item:render(active)
    total_width = total_width + width
    if active then
      active_width = total_width
      active_index = idx
    end
    table.insert(renders, text)
  end
  total_width = total_width + #separator * #components
  active_width = active_width + #separator * active_index
  local win_width = vim.api.nvim_win_get_width(0)
  if total_width > win_width then
    renders = adjust_by_width(renders, win_width)
  end
  return table.concat(renders, separator) .. '%#MyTabLineFill#'
end

M.callback = {
  default = function()
    local bufnrs = utils.get_valid_buffers()
    local components = {}
    for _, bufnr in ipairs(bufnrs) do
      table.insert(components, Component.new(bufnr))
    end
    return components
  end,
}

function M.register_callback(key, callback) M.callback[key] = callback end

M.wintab = function(key)
  local func = M.callback[key or 'default']
  if type(func) == 'function' then
    local components = func()
    return M.winbar(components or {})
  end
  return ''
end

---@param key? string
---@param win? integer
function M.init(key, win)
  local winid = win or vim.api.nvim_get_current_win()
  vim.api.nvim_create_autocmd('WinClosed', {
    group = wintab_augroup,
    callback = function(event)
      -- NOTE: event.match 的类型为 string
      if tonumber(event.match) == winid then
        local bufnr = vim.fn.bufnr('#')
        -- 如果没有可用的轮转缓冲区的话, 那这个窗口就直接关闭就好了
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        vim.api.nvim_open_win(bufnr, true, {
          split = 'left',
          win = tonumber(event.match),
        })
        winid = vim.api.nvim_get_current_win()
        vim.w[winid].winbar = vim.wo[winid].winbar
      end
    end,
  })
  vim.api.nvim_set_option_value(
    'winbar',
    string.format('%%!v:lua.wintab("%s")', key or 'default'),
    { win = winid }
  )
end

_G.wintab = M.wintab
_G.wintab_handle_click = wintab_handle_click

return M
