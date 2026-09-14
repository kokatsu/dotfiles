-- https://github.com/oxalica/nil
-- https://github.com/oxalica/nil/blob/main/docs/configuration.md

-- nixd と併用する。評価が要る補完・定義ジャンプ・hover は nixd に任せ、
-- nil は静的診断 (未使用束縛や旧構文の警告) と code action だけを出す
local overlapping = {
  'completionProvider',
  'definitionProvider',
  'documentFormattingProvider',
  'documentHighlightProvider',
  'documentSymbolProvider',
  'hoverProvider',
  'referencesProvider',
  'renameProvider',
  'semanticTokensProvider',
}

---@type vim.lsp.Config
return {
  settings = {
    ['nil'] = {
      nix = {
        flake = {
          autoArchive = false,
          autoEvalInputs = false,
        },
      },
    },
  },
  on_attach = function(client)
    for _, capability in ipairs(overlapping) do
      client.server_capabilities[capability] = nil
    end
  end,
}
