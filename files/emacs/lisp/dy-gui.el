;;; dy-gui.el --- тема, шрифт, номера строк -*- lexical-binding: t; -*-

;; Тема. ef-maris-dark задана точными 24-битными цветами; в терминале без
;; truecolor Emacs огрубляет её до 256 цветов, и выглядит она плохо. Так
;; бывает по ssh без `SendEnv COLORTERM' (см. README, «Облачная VM»).
;; Тогда — встроенная modus-vivendi: она рассчитана и на 256 цветов.
(defun dy-truecolor-p ()
  (or (display-graphic-p) (>= (display-color-cells) 16777216)))

(use-package ef-themes
  :config
  (load-theme (if (dy-truecolor-p) 'ef-maris-dark 'modus-vivendi) t))

;; Шрифт — только если он есть (пакет font-aporetic ставится в home/dyens.scm,
;; в терминале шрифт задаёт терминал). Через хук, чтобы работало и для
;; фреймов, созданных из `emacs --daemon'.
(defun dy-set-font (&optional frame)
  (with-selected-frame (or frame (selected-frame))
    (when (and (display-graphic-p)
               (find-font (font-spec :family "Aporetic Serif Mono")))
      (set-face-attribute 'default nil :family "Aporetic Serif Mono" :height 130))))
(add-hook 'after-make-frame-functions #'dy-set-font)
(dy-set-font)

(setq frame-resize-pixelwise t)

(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

(setq-default fill-column 80)
(global-display-fill-column-indicator-mode 1)

(show-paren-mode 1)
(global-prettify-symbols-mode 1)

(provide 'dy-gui)
