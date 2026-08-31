-- FIX: Auto-create undo directory to prevent E828 error
local undodir = vim.fn.stdpath("state") .. "/undo"
if vim.fn.isdirectory(undodir) == 0 then
  vim.fn.mkdir(undodir, "p")
end
vim.opt.undodir = undodir
vim.opt.undofile = true

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = 'a'
vim.opt.clipboard = 'unnamedplus'
vim.opt.breakindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.termguicolors = true
vim.opt.signcolumn = 'yes'
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- DYNAMIC THEME LOGIC
_G.reload_matugen_colors = function()
  vim.schedule(function()
    local matugen_path = vim.fn.stdpath("config") .. "/matugen_colors.lua"
    local overrides = {}

    if vim.fn.filereadable(matugen_path) == 1 then
      local chunk = loadfile(matugen_path)
      if chunk then
        local colors = chunk()
        if type(colors) == "table" then
          overrides = { all = colors, mocha = colors }
        end
      end
    end

    for k, _ in pairs(package.loaded) do
      if k:match("^catppuccin") then
        package.loaded[k] = nil
      end
    end

    vim.cmd("hi clear")
    if vim.fn.exists("syntax_on") then
      vim.cmd("syntax reset")
    end
    vim.g.colors_name = nil

    require("catppuccin").setup({
      flavour = "mocha",
      compile = { enabled = false },
      color_overrides = overrides,
      integrations = {
        cmp = true,
        gitsigns = true,
        nvimtree = true,
        treesitter = true,
        bufferline = true,
        telescope = { enabled = true },
        indent_blankline = { enabled = true },
        native_lsp = {
          enabled = true,
          underlines = {
            errors      = { "undercurl" },
            hints       = { "undercurl" },
            warnings    = { "undercurl" },
            information = { "undercurl" },
          },
        },
      },
    })

    vim.cmd("colorscheme catppuccin")

    local ok_lualine, lualine = pcall(require, "lualine")
    if ok_lualine then
      lualine.setup { options = { theme = 'catppuccin-mocha' } }
    end

    vim.cmd("redraw!")
    vim.notify("Matugen colors reloaded!", vim.log.levels.INFO)
  end)
end

_G.reload_matugen_colors()

-- PLUGIN CONFIGURATIONS
require('nvim-treesitter').setup {
  highlight = { enable = true },
  indent    = { enable = true },
}

require("ibl").setup()
require('gitsigns').setup()
require('nvim-autopairs').setup({})
require('Comment').setup()
require('which-key').setup()

require("nvim-tree").setup({
  filters = { dotfiles = false },
  view    = { width = 30 }
})

local telescope = require('telescope')
telescope.setup {
  extensions = {
    ["ui-select"] = { require("telescope.themes").get_dropdown {} }
  }
}
pcall(telescope.load_extension, 'ui-select')

local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Find Files' })
vim.keymap.set('n', '<leader>fg', builtin.live_grep,  { desc = 'Live Grep' })
vim.keymap.set('n', '<leader>fb', builtin.buffers,    { desc = 'Find Buffers' })
vim.keymap.set('n', '<C-n>', ':NvimTreeToggle<CR>',   { desc = 'Toggle File Explorer' })

require("bufferline").setup{
  options = {
    mode           = "buffers",
    diagnostics    = "nvim_lsp",
    separator_style = "slant",
    offsets = {
      {
        filetype   = "NvimTree",
        text       = "File Explorer",
        text_align = "left",
        separator  = true
      }
    },
  }
}

vim.keymap.set("n", "<Tab>",   ":BufferLineCycleNext<CR>", { silent = true })
vim.keymap.set("n", "<S-Tab>", ":BufferLineCyclePrev<CR>", { silent = true })
vim.keymap.set("n", "<leader>x", ":bdelete<CR>",           { silent = true, desc = "Close Buffer" })

local cmp     = require 'cmp'
local luasnip = require 'luasnip'

require("luasnip.loaders.from_vscode").lazy_load()

cmp.setup {
  snippet = {
    expand = function(args)
      luasnip.lsp_expand(args.body)
    end,
  },
  mapping = cmp.mapping.preset.insert {
    ['<C-n>']     = cmp.mapping.select_next_item(),
    ['<C-p>']     = cmp.mapping.select_prev_item(),
    ['<C-d>']     = cmp.mapping.scroll_docs(-4),
    ['<C-f>']     = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<CR>']      = cmp.mapping.confirm {
      behavior = cmp.ConfirmBehavior.Replace,
      select   = true,
    },
    ['<Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      elseif luasnip.expand_or_jumpable() then
        luasnip.expand_or_jump()
      else
        fallback()
      end
    end, { 'i', 's' }),
  },
  sources = {
    { name = 'nvim_lsp' },
    { name = 'luasnip' },
    { name = 'buffer' },
    { name = 'path' },
  },
}

-- LSP SETUP
local capabilities = require('cmp_nvim_lsp').default_capabilities()

local function setup_server(server_name, config)
  local ok, server_config = pcall(require, "lspconfig.server_configurations." .. server_name)
  if not ok then return end

  local default_config = server_config.default_config
  local final_config   = vim.tbl_deep_extend("force", default_config, config or {})
  final_config.capabilities = vim.tbl_deep_extend("force", final_config.capabilities or {}, capabilities)

  vim.api.nvim_create_autocmd("FileType", {
    pattern  = final_config.filetypes,
    callback = function(args)
      local instance_config = vim.tbl_deep_extend("force", {}, final_config)
      local root_dir = final_config.root_dir
      if type(root_dir) == "function" then
        root_dir = root_dir(args.file)
      end
      instance_config.root_dir = root_dir or vim.fs.dirname(args.file)
      vim.lsp.start(instance_config)
    end,
  })
end

setup_server("gopls", {})
setup_server("pyright", {})
setup_server("nil_ls", {})
setup_server("lua_ls", {
  settings = {
    Lua = {
      runtime   = { version = 'LuaJIT' },
      globals   = { 'vim' },
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
    },
  }
})

-- FILE WATCHER: Reload when Matugen updates matugen_colors.lua
local uv           = vim.uv or vim.loop
local matugen_path = vim.fn.stdpath("config") .. "/matugen_colors.lua"
local watcher      = uv.new_fs_event()
local reload_timer = nil

watcher:start(matugen_path, {}, vim.schedule_wrap(function(err, filename, events)
  if not err then
    if reload_timer then
      reload_timer:stop()
      reload_timer:close()
    end
    reload_timer = uv.new_timer()
    reload_timer:start(100, 0, vim.schedule_wrap(function()
      _G.reload_matugen_colors()
      if reload_timer then
        reload_timer:stop()
        reload_timer:close()
        reload_timer = nil
      end
    end))
  end
end))

vim.api.nvim_create_autocmd("Signal", {
  pattern  = "SIGUSR1",
  callback = function()
    _G.reload_matugen_colors()
  end,
})
