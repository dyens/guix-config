;;; dy-scheme.el --- Guile и Guix -*- lexical-binding: t; -*-
;;
;; REPL — `guix repl', а не голый guile: в нём уже есть модули Guix из
;; `guix pull' (вместе с каналами, например sops-guix) и скомпилированные
;; .go к ним. Голому guile пришлось бы указывать пути руками, а .scm Guix
;; без .go он компилировал бы при каждом запуске.
;;
;; Сочетания в scheme-mode (SPC m …):
;;   r  REPL              e  раскрыть макрос (macrostep)
;;   d  eval определения  b  eval буфера     l  eval выражения перед курсором
;;   g b / g l / g s  собрать / проверить lint / скачать исходник пакета под курсором
;; Плюс M-. / M-, — к определению и обратно (в том числе в исходники Guix),
;; C-c . — остальные команды guix-devel, M-x guix — пакеты, профили, поколения.

;;; Geiser.
(use-package geiser
  :custom
  (geiser-active-implementations '(guile))
  (geiser-default-implementation 'guile)
  (geiser-repl-history-filename (expand-file-name "geiser-history" user-emacs-directory))
  (geiser-repl-query-on-kill-p nil))

(use-package geiser-guile
  :after geiser
  :custom
  (geiser-guile-binary '("guix" "repl"))
  :config
  ;; Модули этого репозитория: (systems base), (home base), (packages …).
  ;; $GUIX_CONFIG выставляет home/base.scm (#:repo).
  (when-let* ((repo (getenv "GUIX_CONFIG")))
    (add-to-list 'geiser-guile-load-path (expand-file-name repo))))

(use-package macrostep-geiser
  :after geiser-mode
  :config
  (add-hook 'geiser-mode-hook #'macrostep-geiser-setup)
  (add-hook 'geiser-repl-mode-hook #'macrostep-geiser-setup))

;;; Emacs-Guix: отступы и подсветка форм Guix, сборка пакета под курсором.
;; Команды, которым нужен Guile (сборка, lint), запускают свой REPL
;; на модулях того Guix, с которым собран emacs-guix. Отступы и подсветка —
;; чистый elisp, REPL им не нужен.
(use-package guix
  :commands (guix guix-devel-mode guix-prettify-mode)
  :hook
  ((scheme-mode . guix-devel-mode)
   ;; /gnu/store/0123…-hello → /gnu/store/…-hello в выводе и логах.
   (shell-mode . guix-prettify-mode)
   (dired-mode . guix-prettify-mode)))

;;; Структурное редактирование в стиле evil.
;; lispyville: d/c/y/x не ломают баланс скобок, > и < в normal —
;; затянуть/вытолкнуть соседнее выражение, M-j/M-k — переставить выражения.
(use-package lispyville
  :hook ((scheme-mode emacs-lisp-mode lisp-data-mode) . lispyville-mode)
  :config
  (lispyville-set-key-theme
   '(operators c-w prettify text-objects
     (atom-movement t) slurp/barf-cp additional additional-insert)))

(use-package rainbow-delimiters
  :hook ((scheme-mode emacs-lisp-mode lisp-data-mode geiser-repl-mode) . rainbow-delimiters-mode))

(add-hook 'scheme-mode-hook #'electric-pair-local-mode)
(add-hook 'emacs-lisp-mode-hook #'electric-pair-local-mode)

;;; Сочетания.
(defun dy-scheme-keys ()
  (let ((n evil-normal-state-local-map))
    (keymap-set n "<SPC> m r" #'geiser)
    (keymap-set n "<SPC> m d" #'geiser-eval-definition)
    (keymap-set n "<SPC> m b" #'geiser-eval-buffer)
    (keymap-set n "<SPC> m l" #'geiser-eval-last-sexp)
    (keymap-set n "<SPC> m e" #'macrostep-expand)
    (keymap-set n "<SPC> m g b" #'guix-devel-build-package-definition)
    (keymap-set n "<SPC> m g l" #'guix-devel-lint-package)
    (keymap-set n "<SPC> m g s" #'guix-devel-download-package-source)))
(add-hook 'scheme-mode-hook #'dy-scheme-keys)

;;; Сниппеты самого Guix: guix-package, guix-origin, … (scheme-mode) и
;;; шаблоны сообщений коммитов. В `guix pull' они не входят, но лежат в его
;;; git-кэше каналов — он есть на любой машине, где делали pull.
(with-eval-after-load 'yasnippet
  (dolist (dir (file-expand-wildcards "~/.cache/guix/checkouts/*/etc/snippets/yas"))
    (add-to-list 'yas-snippet-dirs dir t))
  (yas-reload-all))

(provide 'dy-scheme)
