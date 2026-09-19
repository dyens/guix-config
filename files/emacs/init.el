;;; init.el --- точка входа -*- lexical-binding: t; -*-
;;
;; Минимальный конфиг под Guix: все пакеты ставит Guix (home/emacs.scm),
;; здесь только настройка. `use-package' встроен в Emacs; `:ensure' не
;; нужен — пакет или уже в load-path, или его нет в home/emacs.scm.
;;
;; Модули — в lisp/, по одному на тему. Порядок важен: dy-evil раньше
;; всего, что вешает сочетания на evil-*-state-map.

(add-to-list 'load-path (expand-file-name "lisp" dy-config-dir))

(require 'dy-globals)     ; пути, бэкапы, история, мелочи
(require 'dy-gui)         ; тема, шрифт, номера строк
(require 'dy-terminal)    ; emacs -nw: kkp, буфер обмена через OSC 52
(require 'dy-evil)        ; evil и сочетания на SPC
(require 'dy-completion)  ; vertico, orderless, consult, embark, corfu
(require 'dy-packages)    ; magit, project, vterm, dired, …
(require 'dy-treesit)     ; tree-sitter режимы
(require 'dy-eglot)       ; LSP
(require 'dy-python)
(require 'dy-go)
(require 'dy-rust)
(require 'dy-scheme)      ; Guile и Guix: geiser, emacs-guix, lispyville
(require 'dy-org)         ; org, agenda, capture, denote
