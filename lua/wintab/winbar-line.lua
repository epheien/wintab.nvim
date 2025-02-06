local M = {}

local edge_width = 1

---@class Elem
---@field label string

---@param elem Elem|string
---@return string
local function get_label(elem)
  if type(elem) == 'string' then
    return elem
  else
    return elem.label
  end
end

local function set_label(elem, label)
  if type(elem) == 'string' then
    return label
  else
    elem.label = label
    return elem
  end
end

---@param elems table[]
---@param start? integer
---@param finish? integer
---@param sep? string
---@return string
local function render_to_text(elems, start, finish, sep)
  local texts = {}
  for _, elem in ipairs(vim.list_slice(elems, start, finish)) do
    table.insert(texts, get_label(elem))
  end
  return table.concat(texts, sep)
end

local function calc_width(elems, start, finish) ---@diagnostic disable-line
  return vim.api.nvim_strwidth(render_to_text(elems, start, finish))
end

--- 从左到右
local function calc_range_from_start(elems, width, start) ---@diagnostic disable-line)
  local remain = width
  for i = start, #elems do
    local label_width = vim.api.nvim_strwidth(get_label(elems[i]))
    remain = remain - label_width
    if remain <= 0 then
      return start, i, remain
    end
  end
  return start, #elems, remain
end

--- 从右到左
local function calc_range_from_finish(elems, width, finish) ---@diagnostic disable-line)
  local remain = width
  for i = finish, 1, -1 do
    local label_width = vim.api.nvim_strwidth(get_label(elems[i]))
    remain = remain - label_width
    if remain == 0 then
      return i, finish, remain
    elseif remain < 0 then
      -- NOTE: 为了简化处理, 向左对齐, 这样 remain 就只代表右侧的余数
      return calc_range_from_start(elems, width - edge_width, i + 1)
    end
  end
  return 1, finish, remain
end

-- 计算显示窗口合适的位置, 如果边缘非结束, 那么需要预留 2 格空间作为导航
-- <a b  c  d
-- a  b  c d>
-- <a b  c d>
---@param elems string[]|table[]
---@param win_width integer
---@param topi integer 窗口开始的索引
---@param selected integer
---@return integer 起始索引
---@return integer 结束索引(包含)
---@return integer 余数/剩余 表示包含结束索引的内容后, 剩余多少空间, 可为负数
local function calc_range(elems, win_width, topi, selected) ---@diagnostic disable-line
  topi = math.min(topi, selected)
  -- 计算 topi 到 selected 需要的宽度
  local text_width = calc_width(elems, topi, selected)
  local prefix_width = 0
  local suffix_width = 0
  if topi ~= 1 then
    prefix_width = edge_width
  end
  if selected ~= #elems then
    suffix_width = edge_width
  end
  -- 显示窗口能正常显示, 那么从 topi 开始尽可能显示更多的内容
  if prefix_width + text_width + suffix_width <= win_width then
    -- 从 topi 向右找结束的索引
    return calc_range_from_start(elems, win_width - prefix_width, topi)
  else
    -- 从 selected 向左找开始的索引
    return calc_range_from_finish(elems, win_width - suffix_width, selected)
  end
end

-- 会修改 elems 元素的 label 成员, 如果元素为对象的话
---@param elems string[]|Elem[]
---@param win_width integer
---@param start integer
---@param selected integer
---@return table
---@return integer top index or window
local function render(elems, win_width, start, selected) ---@diagnostic disable-line
  local line = render_to_text(elems)
  if #line <= win_width then
    return elems, start
  end

  local s, e, remain = calc_range(elems, win_width, start, selected)
  local center = {}
  local prefix = ''
  local suffix = ''
  if s ~= 1 then
    -- 左侧最多只留下 edge_width 的空间
    -- 如果 remain > 0 可从左侧显示更多的字符
    local length = edge_width - 1 + math.max(remain, 0)
    local label = get_label(elems[s - 1])
    prefix = set_label(elems[s - 1], '<' .. label:sub(#label - length + 1, #label))
  end

  if remain < 0 then
    center = vim.list_slice(elems, s, e - 1)
    local label = get_label(elems[e])
    suffix = set_label(elems[e], label:sub(1, #label + remain - 1) .. '>')
  else
    center = vim.list_slice(elems, s, e)
    if e ~= #elems then
      suffix = get_label(elems[e + 1]):sub(1, edge_width - 1) .. '>'
      suffix = set_label(elems[e + 1], suffix)
    end
  end

  local result = {}
  if get_label(prefix) ~= '' then
    table.insert(result, prefix)
  end
  vim.list_extend(result, center)
  if get_label(suffix) ~= '' then
    table.insert(result, suffix)
  end
  return result, s
end

M.calc_range = calc_range
M.render = render

return M
