;; extends

; Map "console" to bash highlighting
((fenced_code_block
  (info_string
    (language) @_lang)
  (code_fence_content) @injection.content)
  (#eq? @_lang "console")
  (#set! injection.language "bash"))
