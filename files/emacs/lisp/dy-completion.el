;;; dy-completion.el --- минибуфер и дополнение -*- lexical-binding: t; -*-

(use-package vertico
  :config
  (vertico-mode 1))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion basic)))))

(use-package marginalia
  :bind (:map minibuffer-local-map ("M-A" . marginalia-cycle))
  :config
  (marginalia-mode 1))

(use-package consult
  :after evil
  :custom
  (consult-preview-key nil)
  (consult-ripgrep-args "rg --null --line-buffered --color=never --max-columns=1000 --path-separator / --smart-case --no-heading --with-filename --line-number --search-zip --hidden")
  :bind
  (:map evil-normal-state-map
        ("<SPC> I" . consult-imenu)
        ("<SPC> s" . consult-ripgrep)
        ("<SPC> o" . consult-outline)))

(use-package embark
  :bind
  (("C-." . embark-act)
   ("C-h B" . embark-bindings)))

(use-package embark-consult
  :after (embark consult))

(use-package corfu
  :custom
  (corfu-auto t)
  :config
  (global-corfu-mode 1))

;; Встроен в Emacs 30+.
(use-package which-key
  :config
  (which-key-mode 1))

(use-package emacs
  :custom
  (tab-always-indent 'complete)
  (completion-cycle-threshold 3)
  :config
  ;; Подсказка в `completing-read-multiple'.
  (defun dy-crm-indicator (args)
    (cons (concat "[CRM] " (car args)) (cdr args)))
  (advice-add #'completing-read-multiple :filter-args #'dy-crm-indicator)
  ;; Курсор не заходит в приглашение минибуфера.
  (setq minibuffer-prompt-properties
        '(read-only t cursor-intangible t face minibuffer-prompt))
  (add-hook 'minibuffer-setup-hook #'cursor-intangible-mode))

(provide 'dy-completion)
