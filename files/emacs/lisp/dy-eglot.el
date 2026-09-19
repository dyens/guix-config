;;; dy-eglot.el --- LSP -*- lexical-binding: t; -*-
;;
;; Серверы (pyright, ruff, gopls, rust-analyzer) берутся из окружения
;; проекта — venv, guix shell, .envrc через direnv, — а не из home: у каждого
;; проекта свои версии.

;;; Python: какой сервер — спрашиваем при запуске.
(defun dy-eglot-python-lsp-cmd (&optional _interactive _project)
  "Выбрать LSP-сервер для Python и вернуть его команду."
  (let ((servers '(("pyright" . ("pyright-langserver" "--stdio"))
                   ("ty"      . ("ty" "server"))
                   ("ruff"    . ("ruff" "server"))
                   ("pylsp"   . ("pylsp")))))
    (cdr (assoc-string (completing-read "Python LSP: " (mapcar #'car servers) nil t)
                       servers))))

;;; Python: pyright и активный venv.
;;
;; В venv на Fedora пакеты лежат в lib64/, а не в lib/, и pyright их не
;; находит сам. Собираем site-packages из обоих и отдаём в extraPaths.
;; eglot-workspace-configuration должен быть buffer-local plist (не функцией),
;; иначе сервер получает его ненадёжно.
(defun dy-eglot--venv-site-packages (venv)
  "Вектор каталогов site-packages из VENV (lib/ и lib64/)."
  (let (paths)
    (dolist (lib (list (expand-file-name "lib" venv) (expand-file-name "lib64" venv)))
      (when (file-directory-p lib)
        (dolist (pydir (directory-files lib t "^python"))
          (let ((sp (expand-file-name "site-packages" pydir)))
            (when (file-directory-p sp)
              (push sp paths))))))
    (vconcat (nreverse paths))))

(defun dy-eglot--python-setup ()
  "Настроить eglot для Python под активный virtualenv."
  (when-let* ((venv (getenv "VIRTUAL_ENV")))
    (let ((python (expand-file-name "bin/python" venv)))
      (setq-local eglot-initialization-options `(:pythonPath ,python))
      (setq-local eglot-workspace-configuration
                  `(:python (:pythonPath ,python
                             :analysis (:extraPaths ,(dy-eglot--venv-site-packages venv))))))))

(add-hook 'python-base-mode-hook #'dy-eglot--python-setup)

(use-package eglot
  :config
  (add-to-list 'eglot-server-programs
               '((python-mode python-ts-mode) . dy-eglot-python-lsp-cmd)))

(provide 'dy-eglot)
