;;; dy-globals.el --- пути, бэкапы, история, мелочи -*- lexical-binding: t; -*-

(setq user-full-name "Alexander Kapustin"
      user-mail-address "dyens@mail.ru")

;; custom.el — в state: конфиг read-only, а Customize пишет сюда.
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(load custom-file 'noerror 'nomessage)

(setq ring-bell-function 'ignore
      use-short-answers t
      read-process-output-max (* 1024 1024)   ; для LSP
      search-default-mode #'char-fold-to-regexp
      enable-recursive-minibuffers t)
(setq-default indent-tabs-mode nil)

;; Прокрутка.
(setq mouse-wheel-scroll-amount '(1)
      mouse-wheel-progressive-speed t
      scroll-conservatively 101
      hscroll-margin 1
      hscroll-step 1
      scroll-preserve-screen-position t)

;; Бэкапы: много и в одном месте, а не рядом с файлами.
(let ((backups (expand-file-name "backups/" user-emacs-directory))
      (autosaves (expand-file-name "auto-save/" user-emacs-directory)))
  (make-directory autosaves t)
  (setq backup-directory-alist `(("." . ,backups))
        auto-save-file-name-transforms `((".*" ,autosaves t))))
;; Место дешёвое: старые версии не удалять вовсе.
(setq delete-old-versions -1
      version-control t
      vc-make-backup-files t)

;; История минибуфера и kill-ring между сессиями.
(use-package savehist
  :custom
  (history-length 1000)
  (history-delete-duplicates t)
  (savehist-additional-variables '(kill-ring search-ring regexp-search-ring))
  :config
  (savehist-mode 1))

(setq zoneinfo-style-world-list
      '(("Etc/UTC" "UTC")
        ("Europe/Moscow" "Moscow")
        ("Asia/Irkutsk" "Irkutsk")
        ("America/New_York" "New York")))

(keymap-global-set "C-x C-p" #'eval-print-last-sexp)

;; Окна: переиспользовать уже открытые, а не плодить новые.
(setq display-buffer-base-action
      '((display-buffer-reuse-window
         display-buffer-reuse-mode-window
         display-buffer-same-window
         display-buffer-in-previous-window)))
(add-to-list 'display-buffer-alist
             '("\\`\\*compilation\\*\\'"
               display-buffer-reuse-window
               (reusable-frames . visible)))

(superword-mode 1)
(put 'scroll-left 'disabled nil)
(put 'narrow-to-region 'disabled nil)

(provide 'dy-globals)
