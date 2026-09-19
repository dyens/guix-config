;;; dy-rust.el --- Rust -*- lexical-binding: t; -*-
;;
;; rust-mode поверх rust-ts-mode (tree-sitter), команды cargo из rust-mode
;; остаются. rustic не нужен.

(use-package rust-mode
  :after evil
  :init
  ;; До загрузки rust-mode: от этого зависит, от какого режима он наследуется.
  (setq rust-mode-treesitter-derive (treesit-language-available-p 'rust))
  :mode ("\\.rs\\'" . rust-mode)
  :custom
  (rust-format-on-save t)
  :hook
  ((rust-mode . eglot-ensure)
   (rust-mode . (lambda ()
                  (let ((n evil-normal-state-local-map))
                    (keymap-set n "<SPC> m c" #'rust-run-clippy)
                    (keymap-set n "<SPC> m C" #'rust-compile)
                    (keymap-set n "<SPC> m r" #'rust-run)
                    (keymap-set n "<SPC> T a" #'rust-test)
                    (keymap-set n "<SPC> T b" #'dy-rust-test-buffer)
                    (keymap-set n "<SPC> t" #'dy-rust-test-at-point)
                    (keymap-set n "<SPC> =" #'eglot-format-buffer)))))
  :config
  (require 'rust-cargo)

  (defun dy-rust--module-path ()
    "src/foo/bar.rs -> foo::bar."
    (let* ((relative (file-relative-name buffer-file-name (project-root (project-current))))
           (path (string-join (cdr (split-string relative "/")) "::")))
      (string-remove-suffix ".rs" path)))

  (defun dy-rust-test-buffer ()
    "cargo test для модуля текущего файла."
    (interactive)
    (compile (format "%s test %s" rust-cargo-bin (dy-rust--module-path))))

  (defun dy-rust-test-at-point ()
    "cargo test для функции под курсором (в модуле tests)."
    (interactive)
    (let ((fname (save-excursion
                   (end-of-line)
                   (and (re-search-backward "^[ \t]\\{0,4\\}fn[ \t]+\\([a-zA-Z0-9_]+\\)" nil t)
                        (match-string-no-properties 1)))))
      (unless fname (user-error "Курсор не внутри fn"))
      (compile (format "%s test %s::tests::%s" rust-cargo-bin (dy-rust--module-path) fname)))))

(provide 'dy-rust)
