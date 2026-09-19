;;; Плагины docker CLI: `docker compose` и `docker buildx`.
;;;
;;; docker ищет плагины в ~/.docker/cli-plugins (на Guix нет /usr/libexec/…).
;;; Симлинки на бинарники из стора кладёт Guix Home; сам ~/.docker/config.json
;;; (туда пишет `docker login`) не трогаем — он остаётся обычным файлом.
;;;
;;; Сам Docker Engine — системный сервис, systems/docker.scm.

(define-module (home docker)
  #:use-module (gnu home services)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (packages docker)
  #:export (%docker-cli-services))

(define %docker-cli-services
  (list (simple-service 'docker-cli-plugins home-files-service-type
                        `((".docker/cli-plugins/docker-compose"
                           ,(file-append docker-compose-plugin "/bin/docker-compose"))
                          (".docker/cli-plugins/docker-buildx"
                           ,(file-append docker-buildx-plugin "/bin/docker-buildx"))))))
