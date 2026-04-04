local has_e2e = os.getenv('E2E') == '1'

local function skip_if_no_e2e()
  if not has_e2e then
    pending('E2E tests require E2E=1 and clangd')
    return true
  end
  return false
end

describe('e2e smoke', function()
  describe('clangd availability', function()
    it('clangd is attached to C/C++ buffers', function()
      if skip_if_no_e2e() then return end
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'int main() { return 0; }' })
      vim.bo[bufnr].filetype = 'cpp'
      vim.api.nvim_set_current_buf(bufnr)

      local clients = {}
      vim.wait(5000, function()
        clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'clangd' })
        return #clients > 0
      end, 100)

      assert.is_true(#clients > 0, 'clangd should be attached')
    end)
  end)
end)
