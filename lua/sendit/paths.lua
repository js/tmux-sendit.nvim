local M = {}

local function _get_root()
  -- try LSP root first
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients > 0 and clients[1].config.root_dir then
    return clients[1].config.root_dir
  end

  -- try common project markers
  local root = vim.fs.root(0, {
    ".git",
    "package.json",
    "Cargo.toml",
    "pyproject.toml",
    "go.mod",
    "Makefile",
    "README.md",
  })
  if root then
    return root
  end

  -- fall abck to current working directory
  return vim.fn.getcwd()
end

function M.get_relative_path()
  local abs_path = vim.api.nvim_buf_get_name(0)
  local root = _get_root()

  if abs_path:find(root, 1, true) == 1 then
    return abs_path:sub(#root + 2)
  end

  -- fallback
  return vim.fn.expand("%:.")
end

return M
