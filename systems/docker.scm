;;; Docker Engine из статических бинарников (packages/docker.scm) —
;;; системный сервис shepherd.
;;;
;;; Штатный docker-service-type Guix привязан к пакету docker 20.10 и отдельному
;;; сервису containerd. Здесь проще: dockerd сам запускает свой containerd
;;; (managed containerd, из того же пакета) — один сервис.
;;;
;;; Статические бинарники не обёрнуты, как guix-овский docker, поэтому PATH
;;; для dockerd задан явно: iptables, ip, modprobe и т.п.
;;;
;;; Пользователь в группе "docker" ходит в сокет без sudo: добавьте её
;;; в supplementary-groups (см. systems/t1.scm). Плагины compose/buildx
;;; ставит home (home/docker.scm).

(define-module (systems docker)
  #:use-module (gnu packages base)              ; coreutils
  #:use-module (gnu packages compression)       ; xz, pigz
  #:use-module (gnu packages linux)             ; iptables, iproute, kmod, util-linux, procps
  #:use-module (gnu packages version-control)   ; git
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (gnu system shadow)              ; user-group
  #:use-module (guix gexp)
  #:use-module (json)
  #:use-module (packages docker)
  #:export (docker-static-services))

(define (daemon-json insecure-registries dns)
  "daemon.json: без systemd — cgroupfs; пул адресов сетей compose вне 172.x."
  (plain-file
   "daemon.json"
   (scm->json-string
    `(("data-root" . "/var/lib/docker")
      ("group" . "docker")
      ("exec-opts" . #("native.cgroupdriver=cgroupfs"))
      ;; По умолчанию Docker раздаёт сетям 172.17–172.31.x — это пересекается
      ;; с сетями за VPN (например, ruclaw: 172.31.0.0/20, …). Сети compose
      ;; берём из 10.210.0.0/16 по /24.
      ("default-address-pools" . #((("base" . "10.210.0.0/16") ("size" . 24))))
      ("log-driver" . "json-file")
      ("log-opts" . (("max-size" . "50m") ("max-file" . "3")))
      ("insecure-registries" . ,(list->vector insecure-registries))
      ,@(if (null? dns) '() `(("dns" . ,(list->vector dns))))))))

(define* (docker-static-services #:key
                                 (insecure-registries '())
                                 (dns '()))
  "Сервисы Docker: группа docker, dockerd, docker CLI в системном профиле.
INSECURE-REGISTRIES — реестры по http / с самоподписанным сертификатом.
DNS — DNS-серверы для контейнеров (пусто — как у хоста)."
  (list
   (simple-service 'docker-group account-service-type
                   (list (user-group (name "docker") (system? #t))))

   ;; docker, ctr и т.п. — в PATH всем.
   (simple-service 'docker-cli profile-service-type (list docker-engine))

   (simple-service
    'dockerd shepherd-root-service-type
    (list
     (shepherd-service
      (provision '(dockerd))
      ;; Как у штатного сервиса Guix: cgroup смонтирован, сеть поднята.
      (requirement '(user-processes file-system-/sys/fs/cgroup
                                    networking udev elogind))
      (documentation "Docker Engine (статическая сборка).")
      (start
       #~(make-forkexec-constructor
          (list #$(file-append docker-engine "/bin/dockerd")
                "--config-file" #$(daemon-json insecure-registries dns)
                "-p" "/var/run/docker.pid")
          #:pid-file "/var/run/docker.pid"
          #:log-file "/var/log/docker.log"
          #:environment-variables
          (list (string-append
                 "PATH="
                 (string-join
                  (list #$(file-append docker-engine "/bin") ; containerd, runc, docker-proxy
                        #$(file-append iptables "/sbin")
                        #$(file-append iptables "/bin")
                        #$(file-append iproute "/sbin")
                        #$(file-append kmod "/bin")           ; modprobe br_netfilter, overlay
                        #$(file-append util-linux "/bin")
                        #$(file-append util-linux "/sbin")
                        #$(file-append coreutils "/bin")
                        #$(file-append procps "/bin")
                        #$(file-append xz "/bin")
                        #$(file-append pigz "/bin")
                        #$(file-append git "/bin"))            ; контексты сборки из git
                  ":"))
                ;; modprobe в Guix ищет модули здесь, а не в /lib/modules.
                "LINUX_MODULE_DIRECTORY=/run/booted-system/kernel/lib/modules"
                "HOME=/root")))
      (stop #~(make-kill-destructor)))))))
