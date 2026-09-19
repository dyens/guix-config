;;; dy-evil.el --- evil и сочетания на SPC -*- lexical-binding: t; -*-

(use-package evil
  :init
  (setq evil-want-integration t
        evil-want-keybinding nil          ; клавиши для режимов — evil-collection
        evil-want-C-i-jump nil
        evil-want-C-u-scroll nil          ; C-u настроен ниже вручную
        ;; В терминале не перехватывать сырой ESC: протокол kitty (kkp,
        ;; dy-terminal.el) уже различает ESC/Meta/escape-последовательности,
        ;; а перехват evil съедал бы ведущий \e каждой из них.
        evil-intercept-esc nil
        evil-cross-lines t                ; f/t через строки
        evil-vsplit-window-right t
        evil-split-window-below t
        evil-undo-system 'undo-redo
        evil-symbol-word-search t)
  :config
  (evil-mode 1)
  ;; w/b по символам: abc_abc — одно слово.
  (defalias #'forward-evil-word #'forward-evil-symbol)

  ;; C-o — назад, C-i — вперёд. C-i и TAB в Emacs — одна клавиша [9]:
  ;; - GUI: Ctrl+i приходит как [9], а физический Tab — как <tab>,
  ;;   поэтому "C-i" можно занять, не задев Tab;
  ;; - терминал: kkp превращает Ctrl+i в отдельное [C-i] (dy-terminal.el),
  ;;   его и занимаем, TAB остаётся для org-cycle.
  (if (display-graphic-p)
      (keymap-set evil-normal-state-map "C-i" #'evil-jump-forward)
    (define-key evil-normal-state-map [C-i] #'evil-jump-forward))

  (keymap-set evil-normal-state-map "C-;" #'iedit-mode)
  (keymap-set evil-insert-state-map "C-;" #'iedit-mode)

  (keymap-set evil-normal-state-map "<SPC> f" #'find-file)
  (keymap-set evil-normal-state-map "<SPC> b" #'switch-to-buffer)
  (keymap-set evil-normal-state-map "<SPC> c" #'compile)
  (keymap-set evil-normal-state-map "<SPC> #" #'comment-line)
  (keymap-set evil-visual-state-map "<SPC> #" #'comment-line)
  (keymap-set evil-normal-state-map "<SPC> j" #'evil-avy-goto-char-timer)

  (keymap-set evil-normal-state-map "C-u" #'evil-scroll-up)
  (keymap-set evil-visual-state-map "C-u" #'evil-scroll-up)
  (keymap-set evil-normal-state-map "<SPC> u" #'universal-argument)

  ;; Ссылка на текущую строку в GitHub/GitLab, путь:строка в kill-ring.
  (require 'dy-git)
  (require 'dy-tools)
  (dolist (map (list evil-normal-state-map evil-visual-state-map))
    (keymap-set map "<SPC> m b" #'dy-open-in-github-branch)
    (keymap-set map "<SPC> m B" #'dy-open-in-github-rev))
  (keymap-set evil-normal-state-map "<SPC> m l" #'dy-copy-file-and-line)

  ;; «Быстрая функция»: SPC ~ назначает команду на SPC `.
  (defun dy--function-not-found ()
    (interactive)
    (user-error "Быстрая функция не задана: SPC ~"))
  (defun dy--set-fast-function (fn)
    "Повесить команду FN на SPC `."
    (interactive "aКоманда: ")
    (keymap-set evil-normal-state-map "<SPC> `" fn))
  (keymap-set evil-normal-state-map "<SPC> `" #'dy--function-not-found)
  (keymap-set evil-normal-state-map "<SPC> ~" #'dy--set-fast-function)
  (keymap-set evil-visual-state-map "<SPC> ~" #'dy--set-fast-function)

  ;; Обернуть выделение в пару символов.
  (require 'dy-insert-pair)
  (keymap-set evil-visual-state-map "<SPC> q" #'dy-insert-pair-completion)

  ;; Ошибки flymake (eglot, ruff и т.п.).
  (keymap-set evil-normal-state-map "<SPC> ." #'flymake-goto-next-error)
  (keymap-set evil-normal-state-map "<SPC> ," #'flymake-goto-prev-error)

  ;; Сдвиг выделения без выхода из visual.
  (defun dy-evil-shift-left-visual ()
    (interactive)
    (evil-shift-left (region-beginning) (region-end))
    (evil-normal-state)
    (evil-visual-restore))
  (defun dy-evil-shift-right-visual ()
    (interactive)
    (evil-shift-right (region-beginning) (region-end))
    (evil-normal-state)
    (evil-visual-restore))
  (keymap-set evil-visual-state-map ">" #'dy-evil-shift-right-visual)
  (keymap-set evil-visual-state-map "<" #'dy-evil-shift-left-visual)

  ;; SPC z — развернуть окно на весь фрейм и обратно.
  (defvar dy-window-configuration nil)
  (define-minor-mode dy-window-single-toggle
    "Одно окно / вернуть прежнюю раскладку."
    :lighter " [M]"
    (if (one-window-p)
        (when dy-window-configuration
          (set-window-configuration dy-window-configuration))
      (setq dy-window-configuration (current-window-configuration))
      (delete-other-windows)))
  (keymap-set evil-normal-state-map "<SPC> z" #'dy-window-single-toggle)

  ;; SPC = в JSON — отформатировать буфер.
  (dolist (hook '(js-json-mode-hook json-ts-mode-hook))
    (add-hook hook (lambda ()
                     (keymap-set evil-normal-state-local-map "<SPC> =" #'json-pretty-print-buffer)))))

(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

(use-package evil-escape
  :after evil
  :custom
  (evil-escape-key-sequence "fd")
  :config
  (evil-escape-mode 1))

(use-package evil-multiedit
  :after evil
  :bind
  ((:map evil-visual-state-map
         ("R" . evil-multiedit-match-all)
         ("M-d" . evil-multiedit-match-and-next))
   (:map evil-normal-state-map
         ("M-d" . evil-multiedit-match-and-next))
   (:map evil-insert-state-map
         ("M-d" . evil-multiedit-toggle-marker-here)))
  :config
  (evil-ex-define-cmd "ie[dit]" #'evil-multiedit-ex-match))

(use-package string-inflection
  :commands (string-inflection-all-cycle string-inflection-underscore
             string-inflection-camelcase string-inflection-kebab-case))

(provide 'dy-evil)
