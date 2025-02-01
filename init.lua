local utils = require('wintab.utils')

local M = {}

local separator = ''

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
_G.wintab_handle_click = wintab_handle_click

local function adjust_by_width(items, width) return items end

---@param components wintab.Component[]
---@return string
local function winbar(components)
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

M.wintab = function()
  local bufnrs = utils.get_valid_buffers()
  local components = {}
  for _, bufnr in ipairs(bufnrs) do
    table.insert(components, Component.new(bufnr))
  end
  return winbar(components)
end
_G.wintab = M.wintab

return M
