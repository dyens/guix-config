;;; dy-python.el --- Python -*- lexical-binding: t; -*-
;;
;; Пакетов pytest, ruff-format и flymake-ruff нет в Guix, поэтому здесь
;; их маленькие замены: pytest — через `compile', ruff — через reformatter.
;; Линтинг ruff даёт LSP (выбор «ruff» в dy-eglot.el).

(require 'dy-string)

;;; Форматирование: ruff (сам ruff — из окружения проекта).
(use-package reformatter
  :config
  (reformatter-define dy-ruff-format
    :program "ruff"
    :args (list "format" "--stdin-filename" (or (buffer-file-name) input-file))
    :lighter " RuffFmt"
    :group 'python)
  (reformatter-define dy-ruff-sort
    :program "ruff"
    :args (list "check" "--fix" "--select" "I" "--exit-zero"
                "--stdin-filename" (or (buffer-file-name) input-file))
    :lighter " RuffSort"
    :group 'python))

(defun dy-format-python-buffer ()
  "ruff format + сортировка импортов."
  (interactive)
  (unless (executable-find "ruff")
    (user-error "ruff не найден: активируйте окружение проекта"))
  (dy-ruff-format-buffer)
  (dy-ruff-sort-buffer))

;;; pytest через compile.
(defcustom dy-pytest-arguments "--disable-warnings -x --ff --color=yes"
  "Аргументы pytest по умолчанию."
  :type 'string
  :group 'python)

(defun dy-pytest--root ()
  (if-let* ((project (project-current)))
      (project-root project)
    default-directory))

(defun dy-pytest--run (target &optional args comint)
  "pytest ARGS TARGET из корня проекта. COMINT — интерактивный буфер (для pdb)."
  (let ((default-directory (dy-pytest--root)))
    (compile (string-trim (format "pytest %s %s" (or args dy-pytest-arguments) (or target "")))
             comint)))

(defun dy-pytest--file ()
  (file-relative-name (buffer-file-name) (dy-pytest--root)))

(defun dy-pytest--node-at-point ()
  "file.py::Class::test_name для теста под курсором."
  (let ((defun-name (python-info-current-defun)))
    (unless defun-name
      (user-error "Курсор не внутри функции"))
    (concat (dy-pytest--file) "::" (string-replace "." "::" defun-name))))

(defun dy-pytest-one () (interactive) (dy-pytest--run (dy-pytest--node-at-point)))
(defun dy-pytest-module () (interactive) (dy-pytest--run (dy-pytest--file)))
(defun dy-pytest-all () (interactive) (dy-pytest--run nil))
(defun dy-pytest-pdb-one ()
  (interactive)
  (dy-pytest--run (dy-pytest--node-at-point) (concat dy-pytest-arguments " --pdb") t))
(defun dy-pytest-again () (interactive) (recompile))
(defun dy-pytest-update-snapshot-one ()
  (interactive)
  (dy-pytest--run (dy-pytest--node-at-point) "--snapshot-update"))
(defun dy-pytest-update-snapshot-all ()
  (interactive)
  (dy-pytest--run nil "--snapshot-update"))

(defun dy-toggle-eldoc-doc-buffer ()
  "Показать/спрятать буфер *eldoc*."
  (interactive)
  (if-let* ((win (get-buffer-window "*eldoc*")))
      (delete-window win)
    (eldoc-doc-buffer t)))

;;; Python-режим.
(use-package python
  :after evil
  :custom
  (python-indent-def-block-scale 1)
  (python-shell-interpreter (if (executable-find "ipython") "ipython" "python3"))
  (python-shell-interpreter-args (if (executable-find "ipython") "-i --simple-prompt" "-i"))
  (python-shell-enable-font-lock nil)
  :hook
  ((python-base-mode . dy-python-setup)
   (python-base-mode . eglot-ensure)
   (python-base-mode . flyspell-prog-mode)
   (python-base-mode . dy-python-keys))
  :config
  (defun dy-python-setup ()
    (setq-local fill-column 79))

  (defun dy-python-keys ()
    (let ((n evil-normal-state-local-map)
          (v evil-visual-state-local-map))
      (keymap-set n "<SPC> =" #'dy-format-python-buffer)
      (keymap-set n "<SPC> m d" #'dy-python-create-docstring)
      (keymap-set v "<SPC> m a" #'dy-python-dict-kwargs-toogle)
      (keymap-set n "<SPC> m i" #'dy-python-add-noqa)
      (keymap-set n "<SPC> m t" #'dy-python-add-type-ignore)
      (keymap-set n "<SPC> m s" #'dy-py-split-string)
      (keymap-set n "<SPC> m R" #'run-python)
      (keymap-set v "<SPC> m r" #'python-shell-send-region)
      (keymap-set n "<SPC> m b" #'python-shell-send-buffer)
      (keymap-set n "<SPC> t" #'dy-pytest-one)
      (keymap-set n "<SPC> T a" #'dy-pytest-all)
      (keymap-set n "<SPC> T b" #'dy-pytest-module)
      (keymap-set n "<SPC> T p" #'dy-pytest-pdb-one)
      (keymap-set n "<SPC> T T" #'dy-pytest-again)
      (keymap-set n "K" #'dy-toggle-eldoc-doc-buffer)))

  ;; pdb в shell-буфере: показывать текущую строку в исходнике.
  (add-hook 'shell-mode-hook
            (lambda ()
              (add-hook 'comint-output-filter-functions
                        #'python-pdbtrack-comint-output-filter-function nil t))))

;;; Вставки в код.
(defun dy-python-add-noqa ()
  "Дописать \"# noqa: КОДЫ\" по диагностикам flymake на этой строке."
  (interactive)
  (let* ((diags (flymake-diagnostics (line-beginning-position) (line-end-position)))
         (codes (delete-dups
                 (delq nil (mapcar (lambda (d)
                                     (let ((text (flymake-diagnostic-text d)))
                                       (when (string-match "\\b\\([A-Z]+[0-9]+\\)\\b" text)
                                         (match-string 1 text))))
                                   diags)))))
    (save-excursion
      (end-of-line)
      (insert (if codes
                  (format "  # noqa: %s" (string-join codes ","))
                "  # noqa")))))

(defun dy-python-add-type-ignore ()
  (interactive)
  (save-excursion
    (end-of-line)
    (insert "  # type: ignore")))

;;; Docstring по сигнатуре: SPC m d внутри def/class.
(defun dy-python-split-args (arg-string)
  "\"a: int = 1, b\" -> ((\"a\" \"int\" \"1\") (\"b\" nil nil))."
  (mapcar (lambda (arg)
            (let* ((arg-value (split-string arg "[[:blank:]]*=[[:blank:]]*" t))
                   (name-type (split-string (car arg-value) "[[:blank:]]*:[[:blank:]]*" t)))
              (list (car name-type) (nth 1 name-type) (nth 1 arg-value))))
          (seq-remove #'string-blank-p
                      (mapcar #'string-trim
                              (split-string arg-string "[[:blank:]]*,[[:blank:]]*" t)))))

(defun dy--python-add-docstring-to-function (fname fargs-string shift)
  (let* ((header (dy-capitalize-first-char (string-replace "_" " " fname)))
         (args (seq-remove (lambda (arg) (member (car arg) '("self" "cls" "*" "/")))
                           (dy-python-split-args fargs-string))))
    (search-forward ":")
    (insert "\n" shift (format "\"\"\"%s." header))
    (when args
      (insert "\n")
      (dolist (arg args)
        (insert "\n" shift (format ":param %s: %s" (car arg) (string-replace "_" " " (car arg)))))
      (insert "\n" shift))
    (insert "\"\"\"")))

(defun dy--python-add-docstring-to-class (classname shift)
  (let* ((case-fold-search nil)
         (words (string-trim (replace-regexp-in-string "\\([A-Z]\\)" " \\1" classname))))
    (search-forward ":")
    (insert "\n" shift "\"\"\"" (dy-capitalize-first-char (downcase words)) ".\"\"\"")))

(defun dy-python-create-docstring ()
  "Вставить docstring в текущую функцию или класс."
  (interactive)
  (python-nav-beginning-of-defun 1)
  (back-to-indentation)
  (let* ((block-type (thing-at-point 'word))
         (shift (make-string (+ 4 (current-column)) ?\s)))
    (cond
     ((string= block-type "class")
      (re-search-forward "[ \t]*class[ \t]*\\([a-zA-Z0-9_]+\\)" nil t)
      (dy--python-add-docstring-to-class (match-string-no-properties 1) shift))
     ((member block-type '("def" "async"))
      (re-search-forward "def[ \t]+\\([a-zA-Z0-9_]+\\)[ \t]*(" nil t)
      ;; Аргументы — всё между скобками: forward-sexp понимает вложенные
      ;; скобки и строки, регулярке пришлось бы угадывать символы.
      (let ((fname (match-string-no-properties 1))
            (start (point)))
        (backward-char)
        (forward-sexp)
        (dy--python-add-docstring-to-function
         fname (buffer-substring-no-properties start (1- (point))) shift))))))

;;; a=1, b=2  <->  "a": 1, "b": 2  (SPC m a на выделении).
(defun dy-python-dict-kwargs-toogle (start end)
  (interactive "r")
  (save-restriction
    (narrow-to-region start end)
    (goto-char (point-min))
    (if (seq-contains-p (buffer-string) ?=)
        (while (re-search-forward "\\([_0-9a-zA-Z]+\\)\\s-*=\\s-*" nil t)
          (replace-match "\"\\1\": "))
      (while (re-search-forward "\"\\([_0-9a-zA-Z]+\\)\"\\s-*:\\s-*" nil t)
        (replace-match "\\1=")))))

;;; Разбить длинную строку на несколько в скобках (SPC m s).
(defun dy-py-split-string (&optional quote line-length)
  (interactive)
  (let ((quote (or quote "'"))
        (line-length (or line-length 70))
        (done nil))
    (save-excursion
      (search-backward quote)
      (insert "(\n")
      (indent-according-to-mode)
      (forward-char 1)
      (while (not done)
        (re-search-forward (format "[[:space:]%s]" quote))
        (if (equal (match-string-no-properties 0) " ")
            (when (>= (current-column) line-length)
              (insert (format "%s\n%s" quote quote))
              (indent-according-to-mode))
          (setq done t)))
      (insert "\n)")
      (indent-according-to-mode))))

;;; Виртуальные окружения.
(use-package pyvenv
  :after python
  :config
  (defun pyvenv-workon-local (&optional venv-dir-name)
    "Активировать .venv в корне проекта."
    (interactive)
    (pyvenv-activate (expand-file-name (or venv-dir-name ".venv") (dy-pytest--root))))
  (defun pipenvenv () (interactive) (setenv "WORKON_HOME" (expand-file-name "~/.local/share/virtualenvs")))
  (defun poetryenv () (interactive) (setenv "WORKON_HOME" (expand-file-name "~/.cache/pypoetry/virtualenvs/")))
;;  (poetryenv)
)

(provide 'dy-python)
