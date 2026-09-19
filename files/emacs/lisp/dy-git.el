;;; dy-git.el --- ссылка на текущее место в GitHub/GitLab -*- lexical-binding: t; -*-

(require 'magit)

(defun dy-get-git-origin-url ()
  "https-адрес remote origin."
  (let ((url (magit-git-output "config" "--get" "remote.origin.url")))
    (cond
     ((string-match "\\`git@\\([^:]+\\):\\(.*?\\)\\(?:\\.git\\)?\\'" url)
      (format "https://%s/%s" (match-string 1 url) (match-string 2 url)))
     ((string-match "\\`\\(https?://.*?\\)\\(?:\\.git\\)?\\'" url)
      (match-string 1 url))
     (t (user-error "Не удалось разобрать origin: %s" url)))))

(defun dy-open-in-github (&optional mode)
  "Открыть текущий файл (и выделенные строки) в браузере.
MODE: `branch' — по текущей ветке, `rev' — по коммиту HEAD."
  (let* ((ref (if (eq mode 'rev) (magit-rev-abbrev "HEAD") (magit-get-current-branch)))
         (file (magit-file-relative-name (buffer-file-name)))
         (lines (if (use-region-p)
                    (format "#L%d-L%d"
                            (line-number-at-pos (region-beginning))
                            (line-number-at-pos (1- (region-end))))
                  (format "#L%d" (line-number-at-pos)))))
    (browse-url (format "%s/blob/%s/%s%s" (dy-get-git-origin-url) ref file lines))))

(defun dy-open-in-github-branch () (interactive) (dy-open-in-github 'branch))
(defun dy-open-in-github-rev () (interactive) (dy-open-in-github 'rev))

(provide 'dy-git)
