;;; dy-go.el --- Go -*- lexical-binding: t; -*-
;;
;; Встроенный go-ts-mode (tree-sitter) вместо пакета go-mode. Форматирование
;; и импорты — через gopls: `eglot-format-buffer'. Пакета gotest в Guix нет,
;; `dy-go-test-current-test' ниже делает то же самое.

(defun dy-go--test-name-at-point ()
  "Имя функции TestXxx/BenchmarkXxx, внутри которой курсор."
  (save-excursion
    (end-of-line)
    (when (re-search-backward "^func[ \t]+\\(\\(?:Test\\|Benchmark\\|Example\\|Fuzz\\)[A-Za-z0-9_]*\\)" nil t)
      (match-string-no-properties 1))))

(defun dy-go-test-current-test ()
  "go test -run '^Имя$' для теста под курсором, в каталоге пакета."
  (interactive)
  (let ((name (or (dy-go--test-name-at-point) (user-error "Курсор не внутри Test-функции"))))
    (compile (format "go test -v -run '^%s$' ." name))))

(defun dy-go-test-package ()
  "go test для пакета текущего файла."
  (interactive)
  (compile "go test -v ."))

(use-package go-ts-mode
  :after evil
  :mode (("\\.go\\'" . go-ts-mode)
         ("/go\\.mod\\'" . go-mod-ts-mode))
  :hook
  ((go-ts-mode . eglot-ensure)
   (go-ts-mode . (lambda ()
                   (keymap-set evil-normal-state-local-map "<SPC> t" #'dy-go-test-current-test)
                   (keymap-set evil-normal-state-local-map "<SPC> T b" #'dy-go-test-package)
                   (keymap-set evil-normal-state-local-map "<SPC> =" #'eglot-format-buffer)))))

(provide 'dy-go)
