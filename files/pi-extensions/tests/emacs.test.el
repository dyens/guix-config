;;; emacs.test.el --- Pi Emacs integration tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(load (expand-file-name "../../emacs/lisp/dy-pi.el"
                        (file-name-directory load-file-name)) nil t)

(ert-deftest pi-comment-is-not-a-file-and-does-not-overwrite-draft ()
  (let ((file (make-temp-file "pi-answer-"))
        (metadata "{\"socket\":\"/tmp/pi-test\",\"token\":\"t\",\"session\":\"s\"}"))
    (unwind-protect
        (progn
          (with-temp-file file (insert "Original"))
          (pi-emacs-open-comment metadata "id-1" file)
          (let ((first (current-buffer)))
            (should (equal (buffer-name) "*pi-comment*"))
            (should-not buffer-file-name)
            (should (eq (key-binding (kbd "C-c C-c")) #'pi-emacs-submit))
            (insert " draft")
            (pi-emacs-open-comment metadata "id-2" file)
            (should-not (eq first (current-buffer)))
            (with-current-buffer first
              (should (string-match-p "draft" (buffer-string))))))
      (delete-file file)
      (dolist (buffer (buffer-list))
        (when (string-prefix-p "*pi-comment" (buffer-name buffer))
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer))))))

(ert-deftest pi-collect-only-real-comments-and-exact-context ()
  (let ((root (make-temp-file "pi-project-" t)))
    (unwind-protect
        (with-temp-buffer
          (emacs-lisp-mode)
          (setq buffer-file-name (expand-file-name "sample.el" root))
          (insert ";; Pi: top question\n(message \"Pi: not a comment\")\n"
                  ";; ordinary\n;; Pi: middle question\n"
                  "(a)\n(b)\n(c)\n(d)\n(e)\n(f)\n")
          ;; The collection must widen without changing the caller's restriction.
          (narrow-to-region 1 2)
          (let ((notes (pi-emacs--collect root)))
            (should (= (length notes) 2))
            (should (string-match-p "sample.el:1 \\[unsaved buffer\\]" (car notes)))
            (should (string-match-p "6: (b)" (car notes)))
            (should-not (string-match-p "7: (c)" (car notes)))
            (should (string-match-p "9: (e)" (cadr notes)))
            (should-not (string-match-p "10: (f)" (cadr notes)))
            (should (= (point-max) 2))))
      (delete-directory root t))))

(ert-deftest pi-collect-c-and-python-comments-not-strings ()
  (let ((root (make-temp-file "pi-project-" t)))
    (unwind-protect
        (dolist (case '((c-mode "a.c" "// Pi: why?\nchar *s = \"Pi: nope\";\n")
                        (python-mode "a.py" "# Pi: why?\nx = 'Pi: nope'\n")))
          (with-temp-buffer
            (funcall (nth 0 case))
            (setq buffer-file-name (expand-file-name (nth 1 case) root))
            (insert (nth 2 case))
            (should (= (length (pi-emacs--collect root)) 1))))
      (delete-directory root t))))

(ert-deftest pi-submit-keeps-text-on-failure-and-clears-target-on-success ()
  (with-temp-buffer
    (pi-emacs-compose-mode)
    (insert "Draft")
    (setq pi-emacs--target '((session . "s")) pi-emacs--kind "notes")
    (cl-letf (((symbol-function 'pi-emacs--send) (lambda (&rest _) (user-error "Pi busy"))))
      (should-error (pi-emacs-submit) :type 'user-error))
    (should pi-emacs--target)
    (should (equal (buffer-string) "Draft"))
    (cl-letf (((symbol-function 'pi-emacs--send) #'ignore)) (pi-emacs-submit))
    (should-not pi-emacs--target)))

(ert-deftest pi-compose-evil-keybindings ()
  (skip-unless (require 'evil nil t))
  (let ((was-enabled (bound-and-true-p evil-mode)))
    (unwind-protect
        (progn
          (evil-mode 1)
          (with-temp-buffer
            (pi-emacs-compose-mode)
            (dolist (state '(normal visual insert))
              (evil-change-state state)
              (should (eq (key-binding (kbd "C-c C-c")) #'pi-emacs-submit))
              (should (eq (key-binding (kbd "C-c C-k")) #'pi-emacs-cancel)))
            (should (eq (key-binding (kbd "C-c p c")) #'pi-send-comments))))
      (unless was-enabled (evil-mode -1)))))

(ert-deftest pi-send-lines-directly-with-source-and-without-moving-point ()
  (with-temp-buffer
    (setq buffer-file-name "/tmp/sample.el")
    (insert "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\n")
    (goto-char 7) ; Inside the second line.
    (let ((position (point)) sent)
      (cl-letf (((symbol-function 'pi-emacs--select-target) (lambda () 'target))
                ((symbol-function 'pi-emacs--send) (lambda (&rest args) (setq sent args))))
        (pi-send-region-or-lines))
      (should (equal (car sent) 'target))
      (should (equal (cadr sent) "snippet"))
      (should (equal (nth 2 sent)
                     "/tmp/sample.el:2-7 [unsaved buffer]\n\ntwo\nthree\nfour\nfive\nsix\nseven\n"))
      (should (= (point) position))
      (should (eq (key-binding (kbd "C-c p s")) #'pi-send-region-or-lines)))))

(ert-deftest pi-send-region-exactly-and-preserve-it-on-failure ()
  (with-temp-buffer
    (insert "before SELECT after\nnext")
    (goto-char 8)
    (set-mark 14)
    (let ((transient-mark-mode t) (mark-active t) sent)
      (cl-letf (((symbol-function 'pi-emacs--select-target) (lambda () 'target))
                ((symbol-function 'pi-emacs--send) (lambda (&rest args) (setq sent args))))
        (pi-send-region-or-lines))
      (should (string-suffix-p "\n\nSELECT" (nth 2 sent)))
      (cl-letf (((symbol-function 'pi-emacs--select-target) (lambda () 'target))
                ((symbol-function 'pi-emacs--send) (lambda (&rest _) (user-error "Pi busy"))))
        (should-error (pi-send-region-or-lines) :type 'user-error))
      (should (equal (buffer-string) "before SELECT after\nnext"))
      (should (= (point) 8))
      (should (= (mark) 14)))))

(ert-deftest pi-send-lines-at-end-and-reject-empty-text ()
  (with-temp-buffer
    (insert "one\ntwo")
    (goto-char (point-max))
    (let (sent)
      (cl-letf (((symbol-function 'pi-emacs--select-target) (lambda () 'target))
                ((symbol-function 'pi-emacs--send) (lambda (&rest args) (setq sent args))))
        (pi-send-region-or-lines)
        (should (string-suffix-p ":2-2\n\ntwo" (nth 2 sent)))
        (erase-buffer)
        (should-error (pi-send-region-or-lines) :type 'user-error)))))

(ert-deftest pi-server-start-sets-name-and-refuses-running-server ()
  (let ((server-name "initial") started)
    (cl-letf (((symbol-function 'server-running-p) (lambda (&rest _) nil))
              ((symbol-function 'server-start) (lambda (&rest _) (setq started server-name))))
      (pi-emacs-server-start "work")
      (should (equal started "work")))
    (cl-letf (((symbol-function 'server-running-p) (lambda (&rest _) t)))
      (should-error (pi-emacs-server-start "personal") :type 'user-error)
      (should (equal server-name "work")))))
