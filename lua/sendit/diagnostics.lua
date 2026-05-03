---@class sendit.DiagnosticsModule
---@field severity_name fun(d: vim.Diagnostic): string
---@field format fun(d: vim.Diagnostic, rel_path: string): string
local M = {}

---@param d vim.Diagnostic
---@return string
function M.severity_name(d)
  return vim.diagnostic.severity[d.severity] or "UNKNOWN"
end

---Format a diagnostic as "rel_path:line SEVERITY: message"
---@param d vim.Diagnostic
---@param rel_path string
---@return string
function M.format(d, rel_path)
  local msg = (d.message or ""):gsub("\n", " ")
  return rel_path .. ":" .. (d.lnum + 1) .. " " .. M.severity_name(d) .. ": " .. msg
end

return M
