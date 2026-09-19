;;; Emacs целиком из Guix: сам Emacs, все пакеты, грамматики tree-sitter
;;; и конфиг из files/emacs/.
;;;
;;; package.el не используется: всё, что упомянуто в files/emacs/lisp/*.el
;;; через use-package, должно быть в %emacs-packages. Новый пакет —
;;; строка здесь + use-package там, затем guix home reconfigure.
;;;
;;; Конфиг ложится в ~/.config/emacs (read-only, из стора). Всё, что Emacs
;;; пишет сам, уходит в ~/.local/state/emacs — см. files/emacs/early-init.el.
;;;
;;; Попробовать без guix home (например, на хосте с другим ~/.emacs.d):
;;;     guix shell -m home/emacs-manifest.scm -- emacs --init-directory=files/emacs

(define-module (home emacs)
  #:use-module (gnu home services)
  #:use-module (gnu packages)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:export (%emacs-packages
            %emacs-services))

(define %emacs-packages
  (map specification->package
       '("emacs-next"                   ; 31, как собранный из исходников на хосте

         ;; evil
         "emacs-evil"
         "emacs-evil-collection"
         "emacs-evil-escape"
         "emacs-evil-multiedit"
         "emacs-iedit"
         "emacs-avy"
         "emacs-string-inflection"

         ;; Минибуфер и дополнение
         "emacs-vertico"
         "emacs-orderless"
         "emacs-marginalia"
         "emacs-consult"
         "emacs-embark"
         "emacs-corfu"

         ;; Инструменты
         "emacs-magit"
         "emacs-perspective"
         "emacs-ace-window"
         "emacs-expand-region"
         "emacs-rg"
         "emacs-wgrep"
         "emacs-direnv"
         "direnv"                       ; emacs-direnv вызывает бинарник
         "emacs-vterm"
         "emacs-yasnippet"
         "emacs-kkp"
         "emacs-ef-themes"
         "emacs-denote"
         "emacs-reformatter"            ; ruff-format в dy-python.el

         ;; Языки и форматы
         "emacs-rust-mode"
         "emacs-pyvenv"
         "emacs-dockerfile-mode"
         "emacs-docker-compose-mode"
         "emacs-yaml-mode"
         "emacs-markdown-mode"

         ;; Guile и Guix (dy-scheme.el)
         "emacs-geiser-guile"
         "emacs-macrostep-geiser"
         "emacs-guix"
         "emacs-lispyville"
         "emacs-rainbow-delimiters"

         ;; Грамматики tree-sitter (dy-treesit.el, dy-go.el, dy-rust.el)
         "tree-sitter-python"
         "tree-sitter-go"
         "tree-sitter-gomod"
         "tree-sitter-rust"
         "tree-sitter-bash"
         "tree-sitter-json"
         "tree-sitter-toml"
         "tree-sitter-yaml"
         "tree-sitter-dockerfile"

         ;; Орфография (flyspell-prog-mode в Python)
         "aspell"
         "aspell-dict-en"
         "aspell-dict-ru")))

(define %emacs-services
  (list (simple-service 'emacs-config
                        home-xdg-configuration-files-service-type
                        `(("emacs" ,(local-file "../files/emacs" "emacs-config"
                                                #:recursive? #t))))))
