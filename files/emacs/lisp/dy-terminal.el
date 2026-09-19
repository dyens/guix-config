;;; dy-terminal.el --- emacs -nw: клавиатура и буфер обмена -*- lexical-binding: t; -*-

;; Kitty keyboard protocol.
;;
;; В обычном терминале часть сочетаний схлопывается в один байт:
;;   C-i == TAB, C-m == RET, C-[ == ESC
;; а Control+пунктуация (C-;, C-., C-,) не отправляется вовсе. Терминалы
;; с протоколом kitty (alacritty >= 0.13, kitty, foot, wezterm, ghostty)
;; шлют их отдельными escape-последовательностями. `global-kkp-mode'
;; договаривается о протоколе сам и ничего не делает там, где его нет.
(use-package kkp
  :config
  ;; kkp декодирует Ctrl+i обратно в "\t" — то есть снова в TAB. Настоящий
  ;; TAB через kkp не идёт вовсе, так что "\t" от kkp — это всегда Ctrl+i.
  ;; Превращаем его в отдельное событие <C-i>: TAB остаётся свободным
  ;; (org-cycle), а <C-i> можно повесить на evil-jump-forward (dy-evil.el).
  (defun dy-kkp--distinguish-c-i (result)
    (if (equal result "\t") [C-i] result))
  (advice-add 'kkp--translate-terminal-input :filter-return #'dy-kkp--distinguish-c-i)
  (global-kkp-mode 1))

;; Буфер обмена через OSC 52 — встроенными средствами, без clipetty
;; (его нет в Guix). Каждый kill уходит терминалу escape-последовательностью,
;; терминал кладёт его в системный буфер обмена. Работает через ssh и tmux
;; (в tmux нужен `set -g set-clipboard on'). Вставка ИЗ системного буфера —
;; Ctrl+Shift+V терминала: чтение OSC 52 терминалы блокируют.
;;
;; Срабатывает для TERM=xterm*, alacritty, screen*/tmux* — для них Emacs
;; грузит term/xterm.el.
(setq xterm-extra-capabilities '(setSelection))

(provide 'dy-terminal)
