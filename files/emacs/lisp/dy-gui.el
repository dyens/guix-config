;;; dy-gui.el --- тема, шрифт, номера строк -*- lexical-binding: t; -*-

(use-package ef-themes
  :config
  (load-theme 'ef-maris-dark t))

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
