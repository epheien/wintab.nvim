local M = {}

local fn = vim.fn

-- The provided api nvim_is_buf_valid filters out all invalid or unlisted buffers
--- @param buf table
function M.is_valid(buf)
  if not buf.bufnr or buf.bufnr < 1 then
    return false
  end
  local valid = vim.api.nvim_buf_is_valid(buf.bufnr)
  if not valid then
    return false
  end
  return buf.listed == 1
end

---@return integer
function M.get_buf_count() return #fn.getbufinfo({ buflisted = 1 }) end

---@return integer[]
function M.get_valid_buffers()
  local bufs = vim.fn.getbufinfo()
  local valid_bufs = {}
  for _, buf in ipairs(bufs) do
    if M.is_valid(buf) then
      table.insert(valid_bufs, buf.bufnr)
    end
  end
  return valid_bufs
end

return M
