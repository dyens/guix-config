;;; dy-common-lisp.el --- Common Lisp: SLY и SBCL -*- lexical-binding: t; -*-

(use-package sly
  :commands (sly sly-mode)
  :hook (lisp-mode . sly-mode)
  :custom
  (inferior-lisp-program "sbcl"))

;; Общие инструменты скобок настраиваются в dy-scheme.el.
(add-hook 'lisp-mode-hook #'lispyville-mode)
(add-hook 'lisp-mode-hook #'rainbow-delimiters-mode)
(add-hook 'lisp-mode-hook #'electric-pair-local-mode)
(add-hook 'sly-mrepl-mode-hook #'rainbow-delimiters-mode)

;;; Сочетания по образцу dy-scheme.el.
(defun dy-common-lisp-keys ()
  (let ((n evil-normal-state-local-map))
    (keymap-set n "<SPC> m r" #'sly)
    (keymap-set n "<SPC> m d" #'sly-eval-defun)
    (keymap-set n "<SPC> m b" #'sly-eval-buffer)
    (keymap-set n "<SPC> m l" #'sly-eval-last-expression)
    (keymap-set n "<SPC> m c" #'sly-compile-defun)
    (keymap-set n "<SPC> m e" #'sly-macroexpand-1)))
(add-hook 'lisp-mode-hook #'dy-common-lisp-keys)

(provide 'dy-common-lisp)
