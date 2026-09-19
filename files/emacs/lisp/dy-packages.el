;;; dy-packages.el --- инструменты: git, проекты, терминал, файлы -*- lexical-binding: t; -*-

;;; Git

(use-package magit
  :after evil
  :commands magit-status
  :custom
  (magit-display-buffer-function #'magit-display-buffer-traditional)
  :bind (:map evil-normal-state-map ("<SPC> g" . magit-status))
  :config
  (require 'dy-string)

  (defun dy--commit-insert-with-selection (prefix message)
    "Вставить \"PREFIX MESSAGE\" и выделить MESSAGE, чтобы сразу его переписать."
    (insert (format "%s %s\n" prefix message))
    (evil-previous-line 1)
    (evil-end-of-line)
    (evil-visual-state 1)
    (evil-backward-char (1- (length message))))

  (defun dy--branch-description (raw)
    "feature-name-here -> Feature name here."
    (dy-capitalize-first-char (replace-regexp-in-string "-" " " (downcase raw))))

  (defun dy-git-commit-setup ()
    "Заготовка сообщения коммита из имени ветки.
PCS-123-add-feature           -> PCS-123: Add feature
feat/PCS-123-add-feature      -> feat(PCS-123): Add feature
feat/PCS-123, feat/JIRA-X-Y   -> feat(PCS-123): "
    (when-let* ((branch (magit-get-current-branch)))
      (cond
       ;; Conventional: feat/…, fix/…, …
       ((string-match "\\`\\(feat\\|fix\\|chore\\|refactor\\|docs\\|hotfix\\)/\\(.*\\)" branch)
        (let ((type (match-string 1 branch))
              (rest (match-string 2 branch)))
          (cond
           ((string-match "\\`\\([A-Z][A-Z0-9]+-[0-9]+\\)-\\(.+\\)\\'" rest)
            (dy--commit-insert-with-selection
             (format "%s(%s):" type (match-string 1 rest))
             (dy--branch-description (match-string 2 rest))))
           ((string-match "\\`\\([A-Z][A-Z0-9]+-[0-9]+\\|JIRA-[A-Za-z0-9-]+\\)\\'" rest)
            (insert (format "%s(%s): " type (match-string 1 rest)))))))
       ;; Задача в начале ветки: PCS-123-описание (регистр ключа не важен).
       ((let ((case-fold-search nil)
              (up (upcase branch)))
          (when (string-match "\\`\\([A-Z][A-Z0-9]+-[0-9]+\\)-\\(.+\\)\\'" up)
            (dy--commit-insert-with-selection
             (concat (match-string 1 up) ":")
             (dy--branch-description (match-string 2 up)))
            t))))))
  (add-hook 'git-commit-setup-hook #'dy-git-commit-setup))

(use-package smerge-mode
  :after evil
  :hook
  (smerge-mode . (lambda ()
                   (keymap-set evil-normal-state-local-map "<SPC> j" #'smerge-next)
                   (keymap-set evil-normal-state-local-map "<SPC> k" #'smerge-prev)
                   (keymap-set evil-normal-state-local-map "<SPC> <SPC>" #'smerge-keep-current)
                   (keymap-set evil-normal-state-local-map "<SPC> h" #'smerge-keep-lower)
                   (keymap-set evil-normal-state-local-map "<SPC> l" #'smerge-keep-upper))))

;;; Проекты и окна

(use-package project
  :after evil
  :custom
  (project-vc-merge-submodules nil)
  :config
  (setq project-compilation-buffer-name-function
        (lambda (_mode) (format "*compilation: %s*" (project-name (project-current)))))
  (keymap-set evil-normal-state-map "<SPC> p" project-prefix-map))

(use-package perspective
  :after evil
  :custom
  (persp-suppress-no-prefix-key-warning t)
  (persp-state-default-file (expand-file-name "perspective" user-emacs-directory))
  :config
  (keymap-set evil-normal-state-map "<SPC> l" perspective-map)
  (persp-mode 1))

(use-package ace-window
  :after evil
  :bind (:map evil-normal-state-map ("<SPC> w" . ace-window)))

(use-package expand-region
  :after evil
  :bind (:map evil-normal-state-map ("<SPC> e" . er/expand-region)))

;;; Поиск

(use-package rg
  :commands (rg rg-project rg-dwim))

;; Правка результатов grep/rg прямо в буфере.
(use-package wgrep
  :commands wgrep-change-to-wgrep-mode)

;;; Сборка

(use-package compile
  :custom
  (compilation-scroll-output 'first-error)
  (comint-buffer-maximum-size 2000)
  :hook
  ;; Длинный вывод тормозит — обрезаем.
  (compilation-filter . comint-truncate-buffer)
  ;; ANSI-цвета в выводе.
  (compilation-filter . ansi-color-compilation-filter)
  :config
  (require 'dy-notify)
  (defcustom dy-notify-after-compilation t
    "Уведомлять о завершении компиляции."
    :type 'boolean
    :group 'compilation)
  (add-hook 'compilation-finish-functions
            (lambda (_buffer status)
              (when dy-notify-after-compilation
                (dy-notify "Компиляция в Emacs завершена" status)))))

(use-package transient
  :hook (transient-exit . transient-save))

;;; Окружение проекта: .envrc (direnv) — venv, GOPATH, guix shell и т.п.
(use-package direnv
  :config
  (direnv-mode 1))

;;; Терминал

(use-package vterm
  :commands vterm
  :custom
  (vterm-timer-delay 0.01)
  :hook
  (vterm-mode . (lambda ()
                  (display-fill-column-indicator-mode -1)
                  (display-line-numbers-mode -1)
                  ;; M-d в терминале — удалить слово в шелле, а не
                  ;; evil-multiedit. Только в этом буфере: nil в локальной
                  ;; карте не помог бы (пропустил бы клавишу в глобальную).
                  (evil-local-set-key 'insert (kbd "M-d") #'vterm--self-insert))))

;;; Файлы

(use-package dired
  :commands (dired dired-jump)
  :bind (("C-x C-j" . dired-jump))
  :custom
  (dired-listing-switches "-agho --group-directories-first")
  (dired-dwim-target t)
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-guess-shell-alist-user '((".*" "xdg-open"))))

;;; Сниппеты: snippets/ из конфига (read-only, свои сниппеты — туда, в репозиторий).
(use-package yasnippet
  :after evil
  :custom
  (yas-snippet-dirs (list (expand-file-name "snippets" dy-config-dir)))
  :bind (:map evil-normal-state-map ("C-l" . yas-expand-from-trigger-key))
  :config
  (yas-global-mode 1))

;;; Орфография (aspell ставится в home/emacs.scm).
(use-package ispell
  :custom
  (ispell-program-name "aspell"))

;;; Разные режимы

(use-package dockerfile-mode
  :mode ("Dockerfile\\'" . dockerfile-mode))

(use-package docker-compose-mode
  :mode ("docker-compose.*\\.ya?ml\\'" . docker-compose-mode))

(use-package yaml-mode
  :mode ("\\.ya?ml\\'" . yaml-mode))

(use-package markdown-mode
  :mode ("\\.md\\'" . gfm-mode)
  :custom
  (markdown-command "pandoc -f gfm -t html5 --standalone"))

(provide 'dy-packages)
