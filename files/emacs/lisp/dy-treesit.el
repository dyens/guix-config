;;; dy-treesit.el --- tree-sitter режимы -*- lexical-binding: t; -*-
;;
;; Грамматики ставит Guix (tree-sitter-* в home/emacs.scm), Emacs находит
;; их по TREE_SITTER_GRAMMAR_PATH из профиля. `treesit-install-language-grammar'
;; не нужен и не работал бы: он компилирует грамматику на месте.
;;
;; Режим переназначаем только если грамматика действительно есть —
;; иначе при открытии файла была бы ошибка вместо обычного режима.
;; Go и Rust настроены в dy-go.el и dy-rust.el.

;; Путь из TREE_SITTER_GRAMMAR_PATH попадает в `treesit-extra-load-path'
;; только при загрузке treesit.el. `treesit-language-available-p' — функция
;; на C и без него работает, но грамматик Guix не видит и отвечает nil.
(require 'treesit)

(defun dy-treesit-remap (from to lang)
  "Открывать FROM как TO, если есть грамматика LANG."
  (when (treesit-language-available-p lang)
    (add-to-list 'major-mode-remap-alist (cons from to))))

(dy-treesit-remap 'python-mode     'python-ts-mode     'python)
(dy-treesit-remap 'sh-mode         'bash-ts-mode       'bash)
(dy-treesit-remap 'js-json-mode    'json-ts-mode       'json)
(dy-treesit-remap 'conf-toml-mode  'toml-ts-mode       'toml)
(dy-treesit-remap 'dockerfile-mode 'dockerfile-ts-mode 'dockerfile)

(provide 'dy-treesit)
