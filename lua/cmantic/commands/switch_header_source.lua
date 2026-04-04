local header_source = require('cmantic.header_source')

local M = {}

function M.execute()
  local bufnr = vim.api.nvim_get_current_buf()
  local uri = vim.uri_from_bufnr(bufnr)
  local match = header_source.get_matching(uri)
  if not match then
    local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'clangd' })
    for _, client in ipairs(clients) do
      local resp = client:request_sync('textDocument/switchSourceHeader', {
        uri = uri,
      }, 3000, bufnr)
      if resp and resp.result then
        match = resp.result
        break
      end
    end
  end
  if not match then
    vim.notify('[C-mantic] No matching header/source file found', vim.log.levels.WARN)
    return
  end
  local fname = vim.uri_to_fname(match)
  vim.cmd.edit(fname)
end

return M
