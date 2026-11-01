;;; dy-pi.el --- Existing Emacs integration for Pi -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'json)
(require 'project)
(require 'server)
(require 'subr-x)

(defvar pi-emacs--sessions nil)
(defvar-local pi-emacs--target nil)
(defvar-local pi-emacs--request-id nil)
(defvar-local pi-emacs--kind nil)

(defun pi-emacs-server-start (name)
  "Start this Emacs server with NAME.  Never replace a running server."
  (interactive "sPi Emacs server name: ")
  (unless (string-match-p "\\`[a-zA-Z0-9_-]\\{1,64\\}\\'" name)
    (user-error "Use letters, digits, _ and - (1–64 characters)"))
  (when (and (processp server-process) (process-live-p server-process))
    (user-error "This Emacs already runs server %s" server-name))
  (when (server-running-p name)
    (user-error "Server name %s is already in use" name))
  (setq server-name name)
  (server-start)
  (message "In Pi: /emacs %s" name))

(defun pi-emacs--decode (text)
  (let ((json-object-type 'alist) (json-key-type 'symbol))
    (json-read-from-string text)))

(defun pi-emacs-register (metadata)
  "Register the Pi endpoint described by JSON METADATA."
  (let ((target (pi-emacs--decode metadata)))
    (setq pi-emacs--sessions
          (cl-remove-if (lambda (entry)
                          (or (equal (alist-get 'socket entry) (alist-get 'socket target))
                              (not (file-exists-p (alist-get 'socket entry)))))
                        pi-emacs--sessions))
    (push target pi-emacs--sessions)))

(defun pi-emacs-unregister (socket)
  (setq pi-emacs--sessions
        (cl-remove-if (lambda (entry) (equal socket (alist-get 'socket entry)))
                      pi-emacs--sessions)))

(defun pi-emacs--send (target kind text &optional id)
  "Send one request and wait for acknowledgement without closing Emacs."
  (let ((buffer (generate-new-buffer " *pi-ack*")) process)
    (unwind-protect
        (progn
          (setq process (make-network-process
                         :name "pi-emacs" :family 'local
                         :service (alist-get 'socket target)
                         :buffer buffer :coding 'utf-8-unix :noquery t
                         :sentinel #'ignore))
          (process-send-string
           process
           (concat (json-encode `((token . ,(alist-get 'token target))
                                  (session . ,(alist-get 'session target))
                                  (kind . ,kind) (id . ,id) (text . ,text))) "\n"))
          (let ((deadline (+ (float-time) 30)))
            (while (and (< (float-time) deadline)
                        (with-current-buffer buffer
                          (not (save-excursion (goto-char (point-min))
                                               (search-forward "\n" nil t))))
                        (process-live-p process))
              (accept-process-output process 0.1)))
          (let* ((raw (with-current-buffer buffer (buffer-string)))
                 (reply (and (string-match-p "\n" raw) (pi-emacs--decode raw))))
            (unless reply (user-error "Pi unavailable or no acknowledgement; text kept in buffer"))
            (when (alist-get 'error reply) (user-error "%s" (alist-get 'error reply)))
            (unless (eq (alist-get 'ok reply) t) (user-error "Invalid Pi acknowledgement"))))
      (when (processp process) (delete-process process))
      (kill-buffer buffer))))

(defvar pi-emacs-compose-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'pi-emacs-submit)
    (define-key map (kbd "C-c C-k") #'pi-emacs-cancel)
    map))

(define-derived-mode pi-emacs-compose-mode text-mode "Pi Comment"
  "Edit a message for Pi; C-c C-c sends, C-c C-k cancels."
  (setq-local header-line-format "Pi | C-c C-c send | C-c C-k cancel")
  ;; This buffer is not a visited file: no answer backups or autosaves.
  (setq-local buffer-auto-save-file-name nil))

(defun pi-emacs-open-comment (metadata id file)
  "Open FILE in a compose buffer bound to the exact Pi request ID."
  (let* ((target (pi-emacs--decode metadata))
         (base "*pi-comment*")
         (existing (get-buffer base))
         (name (if (and existing
                        (with-current-buffer existing
                          (or (buffer-modified-p) pi-emacs--target)))
                   (generate-new-buffer-name base) base))
         (buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (erase-buffer)
      (insert-file-contents file)
      (pi-emacs-compose-mode)
      (setq pi-emacs--target target pi-emacs--request-id id pi-emacs--kind "comment"
            header-line-format (format "Pi %s | %s | C-c C-c send | C-c C-k cancel"
                                       (alist-get 'session target) (alist-get 'cwd target)))
      (set-buffer-modified-p nil)
      (goto-char (point-min)))
    (pop-to-buffer buffer)))

(defun pi-emacs-submit ()
  (interactive)
  (unless pi-emacs--target (user-error "No Pi target in this buffer"))
  (pi-emacs--send pi-emacs--target pi-emacs--kind (buffer-string) pi-emacs--request-id)
  (setq pi-emacs--target nil)
  (set-buffer-modified-p nil)
  (message "Sent to Pi"))

(defun pi-emacs-cancel ()
  (interactive)
  (when (and pi-emacs--target (equal pi-emacs--kind "comment"))
    (pi-emacs--send pi-emacs--target "cancel" "" pi-emacs--request-id))
  (setq pi-emacs--target nil)
  (kill-buffer (current-buffer)))

(defun pi-emacs--context (marker)
  "Return two lines above MARKER and five below, with line numbers."
  (save-excursion
    (goto-char marker)
    (forward-line 6)
    (let ((end (point)))
      (goto-char marker)
      (forward-line -2)
      (let* ((first (line-number-at-pos))
             (lines (split-string (buffer-substring-no-properties (point) end) "\n")))
        (mapconcat (lambda (line)
                     (prog1 (format "%d: %s" first line) (setq first (1+ first))))
                   (if (equal (car (last lines)) "") (butlast lines) lines)
                   "\n")))))

(defun pi-emacs--collect (root)
  "Collect Pi: markers in actual comments from open file buffers under ROOT."
  (let (notes)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and buffer-file-name (not (file-remote-p buffer-file-name))
                   (file-in-directory-p buffer-file-name root))
          (save-restriction
            (widen)
            (save-excursion
              (goto-char (point-min))
              (let ((case-fold-search nil))
                (while (re-search-forward "\\bPi:[ \t]*\\([^\n]*\\)" nil t)
                  (let* ((marker (match-beginning 0))
                         (text (string-trim (match-string-no-properties 1)))
                         (line (line-number-at-pos marker))
                         (comment (save-excursion (nth 4 (syntax-ppss marker)))))
                    (when (and comment (not (string-empty-p text)))
                      (let ((context (pi-emacs--context marker)))
                        (push (format "%s:%d%s\nPi: %s\n%s"
                                      (file-relative-name buffer-file-name root) line
                                      (if (buffer-modified-p) " [unsaved buffer]" "")
                                      text context) notes)))))))))))
    (nreverse notes)))

(defun pi-emacs--select-target ()
  "Choose a live registered Pi session."
  (setq pi-emacs--sessions
        (cl-remove-if-not (lambda (entry) (file-exists-p (alist-get 'socket entry)))
                          pi-emacs--sessions))
  (unless pi-emacs--sessions (user-error "Connect Pi first with /emacs %s" server-name))
  (let ((choices (mapcar (lambda (entry)
                           (cons (format "%s — %s" (alist-get 'cwd entry)
                                         (alist-get 'session entry)) entry))
                         pi-emacs--sessions)))
    (if (= (length choices) 1) (cdar choices)
      (cdr (assoc (completing-read "Pi session: " choices nil t) choices)))))

(defun pi-send-region-or-lines ()
  "Send the active region, or the current line and five below, directly to Pi."
  (interactive)
  (let* ((region (use-region-p))
         (start (if region (region-beginning) (line-beginning-position)))
         (end (if region (region-end)
                (save-excursion (forward-line 6) (point))))
         (text (buffer-substring-no-properties start end))
         (source (or buffer-file-name (buffer-name)))
         (first (line-number-at-pos start))
         (last (line-number-at-pos (if (> end start) (1- end) end))))
    (when (string-empty-p (string-trim text)) (user-error "No text to send"))
    (pi-emacs--send
     (pi-emacs--select-target) "snippet"
     (format "%s:%d-%d%s\n\n%s" source first last
             (if (and buffer-file-name (buffer-modified-p)) " [unsaved buffer]" "")
             text))
    (message "Sent to Pi")))

(defun pi-send-comments ()
  "Preview Pi: comments from open buffers of the current project."
  (interactive)
  (let* ((project (project-current t))
         (root (project-root project))
         (notes (pi-emacs--collect root)))
    (unless notes (user-error "No Pi: comments in open project buffers"))
    (let* ((target (pi-emacs--select-target))
           (buffer (generate-new-buffer "*pi-comments*")))
      (with-current-buffer buffer
        (insert (format "Project: %s\n\n" root) (string-join notes "\n\n"))
        (pi-emacs-compose-mode)
        (setq pi-emacs--target target pi-emacs--kind "notes"
              header-line-format (format "Pi %s | %s | C-c C-c send | C-c C-k cancel"
                                         (alist-get 'session target) (alist-get 'cwd target)))
        (set-buffer-modified-p nil)
        (goto-char (point-min)))
      (pop-to-buffer buffer))))

(global-set-key (kbd "C-c p c") #'pi-send-comments)
(global-set-key (kbd "C-c p s") #'pi-send-region-or-lines)

(with-eval-after-load 'evil
  (evil-define-key '(normal visual insert) pi-emacs-compose-mode-map
    (kbd "C-c C-c") #'pi-emacs-submit
    (kbd "C-c C-k") #'pi-emacs-cancel))

(provide 'dy-pi)
;;; dy-pi.el ends here
