;;; Pi coding agent: декларативно нужные Pi packages и свои ruclaw skills.
;;;
;;; Собственно бинарник `pi' ставится пакетом packages/pi-coding-agent.scm.
;;; Расширения Pi — это не Guix-пакеты, а Pi packages из npm/git/local;
;;; `pi install' пишет декларацию в ~/.pi/agent/settings.json и ставит npm
;;; зависимости в ~/.pi/agent/npm. Поэтому здесь активация делает ровно это,
;;; но идемпотентно: если source уже упомянут в settings.json, не трогает.
;;;
;;; Важно: если активация была без сети и установка не удалась, homerec не
;;; падает. Повторить руками:
;;;
;;;     pi update --extensions
;;;     # или: pi install npm:pi-mcp-adapter
;;;
;;; RuClaw profile, agents, skills и runner кладём в ~/.config/pi-ruclaw.
;;; В home/base.scm: pi-ruclaw запускает launch.py,
;;; pi-ruclaw-runner — runner/run.py.

(define-module (home pi)
  #:use-module (gnu home services)
  #:use-module (gnu packages base)
  #:use-module (gnu packages gnome)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (packages pi-coding-agent)
  #:export (%pi-services))

(define %pi-package-sources
  '("npm:pi-subagents"
    "npm:pi-web-access"
    "npm:pi-mcp-adapter"
    "npm:@juicesharp/rpiv-ask-user-question@2.15.0"))

(define %pi-retired-package-sources
  '("npm:pi-intercom"
    "npm:pi-lsp"))

(define pi-ruclaw-files
  (local-file "../files/pi-ruclaw" "pi-ruclaw" #:recursive? #t))

(define %pi-services
  (list
   (simple-service 'pi-comment-tools home-profile-service-type
                   (list diffutils libnotify))

   (simple-service 'pi-models-config home-files-service-type
                   `((".pi/agent/models.json"
                      ,(local-file "../files/pi-models.json"))))

   (simple-service 'pi-prompt-templates home-files-service-type
                   `((".pi/agent/prompts/wait-what.md"
                      ,(local-file "../files/pi-ruclaw/prompts/wait-what.md"))
                     (".pi/agent/prompts/compare.md"
                      ,(local-file "../files/pi-ruclaw/prompts/compare.md"))
                     (".pi/agent/prompts/ruclaw-incident.md"
                      ,(local-file "../files/pi-ruclaw/prompts/ruclaw-incident.md"))))

   (simple-service 'pi-compare-skill home-files-service-type
                   `((".pi/agent/skills/compare"
                      ,(local-file "../files/pi-ruclaw/skills/compare"
                                   "pi-compare-skill" #:recursive? #t))))

   (simple-service 'pi-comment-extension home-files-service-type
                   `((".pi/agent/extensions/comment.ts"
                      ,(local-file "../files/pi-extensions/comment.ts"))
                     (".pi/agent/extensions/notify.ts"
                      ,(local-file "../files/pi-extensions/notify.ts"))
                     (".pi/agent/extensions/pi-emacs.el"
                      ,(local-file "../files/emacs/lisp/dy-pi.el"))))

   ;; LSP binaries come from the project environment, like Emacs/Eglot.
   ;; Individual files, not a directory symlink: node_modules must be writable.
   (simple-service 'pi-lsp-config home-files-service-type
                   `((".pi/agent/lsp.json"
                      ,(local-file "../files/pi-lsp.json"))
                     (".pi/agent/extensions/lsp-manual/package.json"
                      ,(local-file "../files/pi-extensions/lsp-manual/package.json"))
                     (".pi/agent/extensions/lsp-manual/index.ts"
                      ,(local-file "../files/pi-extensions/lsp-manual/index.ts"))
                     (".pi/agent/extensions/lsp-manual/adapter.ts"
                      ,(local-file "../files/pi-extensions/lsp-manual/adapter.ts"))))

   (simple-service 'pi-mcp-config
                   home-xdg-configuration-files-service-type
                   `(("mcp/mcp.json"
                      ,(local-file "../files/pi-mcp.json"))))

   ;; Shared plan-cycle v2: default only in pi-ruclaw, not a global Pi autoload.
   (simple-service 'pi-plan-cycle-runtime
                   home-xdg-configuration-files-service-type
                   `(("pi-plan-cycle"
                      ,(local-file "../files/pi-extensions/plan-cycle"
                                   "pi-plan-cycle-v2" #:recursive? #t))))

   (simple-service 'pi-ruclaw-skills
                   home-xdg-configuration-files-service-type
                   `(("pi-ruclaw" ,pi-ruclaw-files)))

   (simple-service
    'pi-packages home-activation-service-type
    #~(begin
        (use-modules (ice-9 textual-ports))
        (let* ((home (getenv "HOME"))
               (agent-dir (string-append home "/.pi/agent"))
               (settings (string-append agent-dir "/settings.json"))
               (pi #$(file-append pi-coding-agent "/bin/pi"))
               (path (string-append #$(file-append pi-coding-agent "/bin")
                                    ":" home "/.guix-home/profile/bin"
                                    ":" home "/.guix-profile/bin"
                                    ":" (or (getenv "PATH") ""))))
          (setenv "PATH" path)
          (unless (file-exists? agent-dir)
            (mkdir-p agent-dir))
          (define (settings-text)
            (if (file-exists? settings)
                (call-with-input-file settings get-string-all)
                ""))
          (for-each
           (lambda (source)
             (when (string-contains (settings-text) source)
               (format #t "Removing retired Pi package ~a...~%" source)
               (unless (zero? (system* pi "remove" source))
                 (format (current-error-port)
                         "warning: failed to remove Pi package ~a; retry with `pi remove ~a'~%"
                         source source))))
           (list #$@%pi-retired-package-sources))
          ;; pi-lsp is a pinned dependency of our manual-check adapter, not an
          ;; independently loaded Pi package with an automatic write/edit hook.
          (let ((lsp-dir (string-append agent-dir "/extensions/lsp-manual")))
            (unless
                (zero?
                 (system* "node" "-e"
                          "try { const p = process.argv[1]; const wanted = require(p + '/package.json').dependencies['pi-lsp']; const installed = require(p + '/node_modules/pi-lsp/package.json').version; if (wanted !== installed) process.exit(1); for (const dep of ['vscode-jsonrpc', 'vscode-languageserver-protocol']) require.resolve(dep, {paths: [p + '/node_modules/pi-lsp']}); } catch { process.exit(1); }"
                          lsp-dir))
              (format #t "Installing manual LSP adapter dependencies...~%")
              (unless (zero? (system* "npm" "install" "--prefix" lsp-dir
                                     "--omit=dev" "--omit=peer" "--ignore-scripts"
                                     "--package-lock=false"))
                (format (current-error-port)
                        "warning: LSP dependencies unavailable; retry npm install --prefix ~a --omit=dev --omit=peer --ignore-scripts --package-lock=false~%"
                        lsp-dir))))
          (for-each
           (lambda (source)
             ;; Достаточно текстовой проверки: `pi install' сам корректно
             ;; обновляет JSON, а нам важно не гонять npm на каждый homerec.
             (unless (string-contains (settings-text) source)
               (format #t "Installing Pi package ~a...~%" source)
               (let ((status (system* pi "install" source)))
                 (unless (zero? status)
                   (format (current-error-port)
                           "warning: failed to install Pi package ~a; retry with `pi update --extensions'~%"
                           source)))))
           (list #$@%pi-package-sources)))))))
