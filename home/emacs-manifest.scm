;; Emacs со всеми пакетами из home/emacs.scm — без guix home.
;; Чтобы попробовать конфиг files/emacs на машине, где свой ~/.emacs.d:
;;
;;     guix shell -m home/emacs-manifest.scm -- emacs --init-directory=files/emacs

(add-to-load-path (dirname (dirname (current-filename))))
(use-modules (guix profiles) (home emacs))

(packages->manifest %emacs-packages)
