;;; early-init.el --- до GUI и до пакетов -*- lexical-binding: t; -*-

;;; Где что лежит.
;;
;; Этот каталог Guix Home кладёт в ~/.config/emacs симлинком в /gnu/store,
;; то есть он READ-ONLY. Поэтому:
;;   - код и данные конфига (lisp/, snippets/, alarm.wav) берём из
;;     `dy-config-dir' — каталога, где лежит этот файл;
;;   - всё, что Emacs пишет сам (eln-cache, бэкапы, история, custom.el,
;;     transient, project-list, …), уходит в `user-emacs-directory',
;;     который мы переносим в ~/.local/state/emacs/.
;;
;; Переназначить `user-emacs-directory' надо ЗДЕСЬ: пакеты, которые
;; загрузятся позже (savehist, transient, project, recentf, url, tramp),
;; вычисляют свои пути от него в момент загрузки.

(defconst dy-config-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Каталог конфига (read-only).")

(setq user-emacs-directory
      (expand-file-name "emacs/" (or (getenv "XDG_STATE_HOME") "~/.local/state")))
(make-directory user-emacs-directory t)

;; Нативная компиляция: кэш .eln — туда же, а не в read-only каталог.
(when (fboundp 'startup-redirect-eln-cache)
  (startup-redirect-eln-cache (expand-file-name "eln-cache/" user-emacs-directory)))

;; Значение по умолчанию вычислено ещё при сборке Emacs (от ~/.emacs.d).
(setq auto-save-list-file-prefix
      (expand-file-name "auto-save-list/.saves-" user-emacs-directory))

;;; Пакеты.
;;
;; package.el не используется: все пакеты ставит Guix (home/emacs.scm),
;; они уже в `load-path', а их autoloads подгружает сам Emacs из Guix.
(setq package-enable-at-startup nil)

;;; Быстрый старт.
(defvar dy--file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil
      gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist dy--file-name-handler-alist
                  gc-cons-threshold (* 16 1024 1024)
                  gc-cons-percentage 0.1)))

;;; Без панелей — до создания первого фрейма, чтобы не мигали.
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(setq menu-bar-mode nil
      tool-bar-mode nil
      scroll-bar-mode nil)

(setq inhibit-startup-screen t)
