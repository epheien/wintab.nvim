local utils = require('wintab.utils')

local M = {}

local separator = ''

vim.cmd([[
    hi default WintabSel    ctermfg=238 ctermbg=117 guifg=#444444 guibg=#8ac6f2
    hi default WintabNotSel ctermfg=247 ctermbg=240 guifg=#969696 guibg=#585858
    hi default WintabFill   ctermfg=240 ctermbg=238 guifg=#585858 guibg=#444444
]])

---@class wintab.Component
---@field bufnr integer
---@field label string
local Component = {}
Component.__index = Component
M.Component = Component

---@param bufnr integer
---@param label? string
function Component.new(bufnr, label)
  local self = setmetatable({}, Component)
  self.bufnr = bufnr
  self.label = label or ''
  return self
end

---@param active? boolean
---@return string
---@return integer
function Component:render(active)
  local label = self.label
  if label == '' then
    local bufname = vim.api.nvim_buf_get_name(self.bufnr)
    label = string.format(' %s ', bufname == '' and '[No Name]' or bufname)
  end
  local hl = active and 'WintabSel' or 'WintabNotSel'
  local click = string.format('%%%d@v:lua.wintab_handle_click@', self.bufnr)
  return string.format('%s%%#%s#%s', click, hl, label), vim.api.nvim_strwidth(label)
end

---@class wintab.Wintab
---@field id string
---@field winid integer
---@field winbar string
---@field augroup integer
---@field state table
local Wintab = {}
Wintab.__index = Wintab

---@param winid integer
---@param winbar? string
---@return wintab.Wintab
function Wintab.new(winid, winbar)
  local self = setmetatable({}, Wintab)
  self.id = 'wintab_' .. string.match(tostring(self), '0x%x+')
  self.winid = winid
  self.winbar = winbar or ''
  self.augroup = vim.api.nvim_create_augroup(self.id, {})
  self.state = {}
  return self
end

function Wintab:cleanup()
  vim.api.nvim_del_augroup_by_id(self.augroup)
  M.unregister_callback(self.id)
end

---@param minwid integer
---@param clicks integer
---@param button string
---@param modifiers string
local function wintab_handle_click(minwid, clicks, button, modifiers) ---@diagnostic disable-line
  local bufnr = minwid -- minwid 可直接用于 id
  local winid = vim.fn.getmousepos().winid
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.api.nvim_set_current_win(winid)
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
  return table.concat(renders, separator) .. '%#WintabFill#'
end

M.callback = {}

function M.default_wintab_fn(_)
  local bufnrs = utils.get_valid_buffers()
  local components = {}
  for _, bufnr in ipairs(bufnrs) do
    table.insert(components, Component.new(bufnr))
  end
  return components
end

function M.register_callback(key, callback) M.callback[key] = callback end

function M.unregister_callback(key) M.callback[key] = nil end

M.wintab = function(key)
  local func = M.callback[key or 'default']
  if type(func) == 'function' then
    local components = func()
    return M.winbar(components or {})
  end
  return ''
end

---@param win? integer
---@param fn? function
function M.init(win, fn)
  fn = fn or M.default_wintab_fn
  local object = Wintab.new(win or vim.api.nvim_get_current_win())
  local winbar = string.format('%%!v:lua.wintab("%s")', object.id)
  object.winbar = winbar
  M.register_callback(object.id, function() return fn(object) end)
  vim.api.nvim_create_autocmd('WinClosed', {
    group = object.augroup,
    callback = function(event)
      -- NOTE: event.match 的类型为 string
      if tonumber(event.match) == object.winid then
        local match_bufnr = vim.api.nvim_win_get_buf(object.winid)
        local alter_bufnr = vim.fn.bufnr('#')
        local target_bufnr = -1
        -- 如果没有可用的轮转缓冲区的话, 那这个窗口就直接关闭就好了
        local components = fn(object)
        for _, component in ipairs(components) do
          if component.bufnr == alter_bufnr and vim.api.nvim_buf_is_valid(component.bufnr) then
            target_bufnr = component.bufnr
            goto out
          end
        end
        for _, component in ipairs(components) do
          if component.bufnr ~= match_bufnr and vim.api.nvim_buf_is_valid(component.bufnr) then
            target_bufnr = component.bufnr
            goto out
          end
        end
        if target_bufnr < 0 then
          return
        end
        ::out::
        vim.api.nvim_open_win(target_bufnr, true, {
          split = 'above',
          win = tonumber(event.match),
        })
        object.winid = vim.api.nvim_get_current_win()
        vim.w[object.winid].winbar = vim.wo[object.winid].winbar
        -- NOTE: 用于修正在不同的 tabpage 删除缓冲时触发的窗口关闭
        vim.schedule(function() pcall(vim.api.nvim_win_close, tonumber(event.match), false) end)
      end
    end,
  })
  vim.api.nvim_set_option_value('winbar', winbar, { win = object.winid })
  return object
end

_G.wintab = M.wintab
_G.wintab_handle_click = wintab_handle_click

return M
