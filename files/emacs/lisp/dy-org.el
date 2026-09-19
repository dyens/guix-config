;;; dy-org.el --- org, agenda, capture, denote -*- lexical-binding: t; -*-

(use-package org
  :after evil
  :custom
  (org-directory "~/org")
  (org-agenda-files (list "agenda.org"))
  (org-startup-folded t)
  (org-log-done 'time)
  (org-confirm-babel-evaluate nil)
  (org-startup-with-inline-images t)
  (org-src-preserve-indentation nil)
  (org-edit-src-content-indentation 0)
  (org-clock-sound (expand-file-name "alarm.wav" dy-config-dir))
  :hook
  ((org-babel-after-execute . dy-org-refresh-images)
   (org-clock-in . dy-clock-in)
   (org-clock-out . dy-clock-out)
   (org-mode . (lambda ()
                 (keymap-set evil-normal-state-local-map "<SPC> m f" #'clear-image-cache))))
  :config
  ;; Org 9.8 (Emacs 31) переименовал функцию; старая — для Org постарше.
  (defun dy-org-refresh-images ()
    (if (fboundp 'org-link-preview-refresh)
        (org-link-preview-refresh)
      (org-redisplay-inline-images)))

  (org-babel-do-load-languages
   'org-babel-load-languages
   '((python . t)
     (shell . t)
     (emacs-lisp . t)))

  ;; Помодоро: при clock-in каждые 20 минут напоминать об отдыхе.
  (defvar dy-pomodoro-timer nil)
  (defun dy-clock-in ()
    (setq dy-pomodoro-timer
          (run-with-timer (* 60 20) (+ (* 60 20) 5)
                          (lambda ()
                            (require 'dy-notify)
                            (dy-notify "Нужно отдохнуть 5 мин")))))
  (defun dy-clock-out ()
    (when (timerp dy-pomodoro-timer)
      (cancel-timer dy-pomodoro-timer))))

(use-package org-agenda
  :after evil
  :commands org-agenda
  :bind (:map evil-normal-state-map ("<SPC> a a" . org-agenda)))

(use-package org-capture
  :after evil
  :commands org-capture
  :custom
  (org-capture-templates
   '(("t" "Tasks" entry (file+headline "~/org/agenda.org" "Tasks")
      "* TODO %?\nSCHEDULED: %(org-insert-time-stamp (org-read-date nil t \"+1d\"))\n")
     ("m" "Meetings" entry (file+headline "~/org/agenda.org" "Meetings")
      "* Meeting: %(org-insert-time-stamp (org-read-date nil t \"\"))\n%?")
     ("c" "Captures" entry (file+headline "~/org/agenda.org" "Captures")
      "* Capture %?\n%(org-insert-time-stamp (org-read-date nil t \"\"))\n%c")))
  :bind (:map evil-normal-state-map ("<SPC> a c" . org-capture)))

;; <sh TAB, <el TAB, <py TAB — блоки кода.
(use-package org-tempo
  :after org
  :config
  (add-to-list 'org-structure-template-alist '("sh" . "src shell"))
  (add-to-list 'org-structure-template-alist '("el" . "src emacs-lisp"))
  (add-to-list 'org-structure-template-alist '("py" . "src python")))

(use-package denote
  :hook (dired-mode . denote-dired-mode)
  :bind
  (("C-c b n" . denote)
   ("C-c b r" . denote-rename-file)
   ("C-c b l" . denote-link)
   ("C-c b b" . denote-backlinks)
   ("C-c b d" . denote-dired)
   ("C-c b g" . denote-grep))
  :custom
  (denote-directory (expand-file-name "~/dev/blog/pages"))
  (denote-known-keywords '("blog" "linux" "emacs" "python" "guile"))
  :config
  (denote-rename-buffer-mode 1))

(provide 'dy-org)
