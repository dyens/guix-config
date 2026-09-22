;;; Секрет Telegram-бота для уведомлений — как home/wireguard.scm.
;;;
;;; files/secrets/telegram.yaml, ключ "telegram.env" -> расшифровывается в
;;; /run/user/<uid>/secrets/telegram.env, права 400. Внутри две строки:
;;;
;;;     TELEGRAM_BOT_TOKEN=…
;;;     TELEGRAM_CHAT_ID=…
;;;
;;; Читает его files/claude/hooks/notify.sh — хук Claude Code на события
;;; Stop и PermissionRequest. Отдельным модулем, а не внутри home/claude.scm,
;;; потому что канал общий: тот же секрет пригодится, если уведомления
;;; понадобятся ещё откуда-нибудь.
;;;
;;; Отправка идёт через SOCKS Xray-клиента (127.0.0.1:10808): с t1
;;; api.telegram.org недоступен напрямую. Подробности — README, раздел
;;; «Уведомления в Telegram».

(define-module (home telegram)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (sops secrets)
  #:use-module (sops home services sops)
  #:export (%telegram-secrets))

(define %telegram-secrets
  (list (simple-service 'telegram-secret home-sops-secrets-service-type
                        (list (sops-secret
                               (key '("telegram.env"))
                               (file (local-file "../files/secrets/telegram.yaml"
                                                 "telegram.yaml"))
                               (permissions #o400))))))
