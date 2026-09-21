;;; Динамический загрузчик по пути FHS: /lib64/ld-linux-x86-64.so.2.
;;;
;;; Готовые бинарники не из Guix прошиты на этот путь, а в Guix его нет.
;;; Так ломается всё, что скачивают пакетные менеджеры языков: колёса PyPI
;;; (`uv sync` ставит ruff — 24 МБ собранного Rust), ноды из corepack,
;;; бинарники из npm. Сообщение при этом обманчивое:
;;;
;;;     bash: ./ruff: cannot execute: required file not found
;;;
;;; «не найден» не сам бинарник, а его загрузчик.
;;;
;;; ЭТО ОТСТУПЛЕНИЕ ОТ ЧИСТОТЫ, осознанное. Машина начинает запускать чужие
;;; бинарники, и то, что должно было сломаться громко, теперь работает
;;; тихо. Плата за то, чтобы `uv sync` не требовал плясок. Альтернатива без
;;; правки системы — `guix shell -F --container` (эмуляция FHS в
;;; контейнере), но она тянет изоляцию и возню с docker.
;;;
;;; ОДНОГО ЗАГРУЗЧИКА МАЛО. Своим путём поиска он найдёт только библиотеки
;;; собственного glibc (libc, libm, libdl, libpthread, librt). Всё
;;; остальное надо показать явно: ruff тянет ещё libgcc_s.so.1 из
;;; gcc-toolchain, и без этого будет
;;;
;;;     error while loading shared libraries: libgcc_s.so.1
;;;
;;; Лечится строкой в .envrc проекта (gcc-toolchain должен быть в manifest):
;;;
;;;     export LD_LIBRARY_PATH=$GUIX_ENVIRONMENT/lib
;;;
;;; Проверено на t1 по шагам, см. README, «Готовые бинарники (uv, npm)».
;;;
;;; Подключается и в systems/base.scm (vm, laptop), и в systems/t1.scm —
;;; t1 не использует make-system и собирает operating-system сам.

(define-module (systems fhs)
  #:use-module (gnu services)           ; extra-special-file
  #:use-module (gnu packages base)      ; glibc
  #:use-module (guix gexp)              ; file-append
  #:export (%fhs-loader-service))

(define %fhs-loader-service
  (extra-special-file "/lib64/ld-linux-x86-64.so.2"
                      (file-append glibc "/lib/ld-linux-x86-64.so.2")))
