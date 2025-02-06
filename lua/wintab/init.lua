local utils = require('wintab.utils')
local winbar_line = require('wintab.winbar-line')

local M = {}

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

function Component:get_label()
  local label = self.label
  if label == '' then
    local bufname = vim.api.nvim_buf_get_name(self.bufnr)
    label = string.format(' %s ', bufname == '' and '[No Name]' or bufname)
  end
  return label
end

---@param active? boolean
---@param label? string
---@return string
---@return string
function Component:render(active, label)
  label = label or self:get_label()
  local hl = active and 'WintabSel' or 'WintabNotSel'
  local click = string.format('%%%d@v:lua.wintab_handle_click@', self.bufnr)
  return string.format('%s%%#%s#%s', click, hl, label), label
end

---@class wintab.State
---@field winid integer
---@field selected integer
---@field topi integer top index of window

---@class wintab.Wintab
---@field id string
---@field winbar string
---@field augroup integer
---@field state wintab.State
---@field fn function
local Wintab = {}
Wintab.__index = Wintab

---@param winid integer
---@param winbar? string
---@return wintab.Wintab
function Wintab.new(winid, winbar)
  local self = setmetatable({}, Wintab)
  self.id = 'wintab_' .. string.match(tostring(self), '0x%x+')
  self.winbar = winbar or ''
  self.augroup = vim.api.nvim_create_augroup(self.id, {})
  self.state = {
    winid = winid,
    selected = 1,
    topi = 1,
  }
  return self
end

function Wintab:cleanup()
  vim.api.nvim_del_augroup_by_id(self.augroup)
  M.unregister_callback(self.id)
end

function Wintab:active_buffer() return vim.api.nvim_win_get_buf(self.state.winid) end

function Wintab:next_buffer()
  local items = self.fn(self)
  local active = self:active_buffer()
  for i, item in ipairs(items) do
    if item.bufnr == active then
      return items[(i % #items) + 1].bufnr
    end
  end
  return -1
end

function Wintab:prev_buffer()
  local items = self.fn(self)
  local active = self:active_buffer()
  for i, item in ipairs(items) do
    if item.bufnr == active then
      return items[((i - 1 - 1) % #items) + 1].bufnr
    end
  end
  return -1
end

---@param what string 'next' or 'prev'
function Wintab:navigate(what)
  local active = self:active_buffer()
  local alter = active
  if what == 'prev' then
    alter = self:prev_buffer()
  else
    alter = self:next_buffer()
  end
  if alter ~= -1 and alter ~= active then
    vim.api.nvim_win_set_buf(self.state.winid, alter)
  end
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

---@param components wintab.Component[]
---@param state? wintab.State
---@return string
function M.winbar(components, state)
  state = state or {}
  local elems = {}
  local selected = state.selected or 1
  local bufnr = vim.api.nvim_win_get_buf(state.winid or 0)
  local win_width = vim.api.nvim_win_get_width(state.winid or 0)
  for idx, item in ipairs(components) do
    local active = item.bufnr == bufnr
    if active then
      selected = idx
    end
    table.insert(elems, { active = active, object = item, index = idx, label = item:get_label() })
  end
  local result, topi = winbar_line.render(elems, win_width, state.topi or 1, selected)
  state.topi = topi
  state.selected = selected
  local renders = {}
  for _, item in ipairs(result) do
    table.insert(renders, (item.object:render(item.active, item.label)))
  end
  return table.concat(renders) .. '%#WintabFill#'
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
  local obj = M.callback[key or 'default']
  local components = {}
  if type(obj) == 'function' then
    components = obj()
    return M.winbar(components or {})
  else
    components = obj.fn(obj)
    require('utils').log_to_file(vim.inspect(obj))
    return M.winbar(components or {}, obj.state)
  end
end

---@param win? integer
---@param fn? function
function M.init(win, fn)
  fn = fn or M.default_wintab_fn
  local object = Wintab.new(win or vim.api.nvim_get_current_win())
  local winbar = string.format('%%!v:lua.wintab("%s")', object.id)
  object.winbar = winbar
  object.fn = fn
  M.register_callback(object.id, object)
  vim.api.nvim_create_autocmd('WinClosed', {
    group = object.augroup,
    callback = function(event)
      -- NOTE: event.match 的类型为 string
      if tonumber(event.match) == object.state.winid then
        local match_bufnr = vim.api.nvim_win_get_buf(object.state.winid)
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
        object.state.winid = vim.api.nvim_get_current_win()
        vim.w[object.state.winid].winbar = vim.wo[object.state.winid].winbar
        -- NOTE: 用于修正在不同的 tabpage 删除缓冲时触发的窗口关闭
        vim.schedule(function() pcall(vim.api.nvim_win_close, tonumber(event.match), false) end)
      end
    end,
  })
  vim.api.nvim_set_option_value('winbar', winbar, { win = object.state.winid })
  return object
end

_G.wintab = M.wintab
_G.wintab_handle_click = wintab_handle_click

return M
