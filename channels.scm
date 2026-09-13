(list (channel
       (name 'guix)
       (url "https://git.guix.gnu.org/guix.git")
       (branch "master")
       (commit "002b1a13c27a9fcaf52afe185820baed59d45507")
       (introduction
        (make-channel-introduction
         "9edb3f66fd807b096b48283debdcddccfea34bad"
         (openpgp-fingerprint
          "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
      ;; home-sops-secrets-service-type — расшифровка files/secrets/*.yaml.
      (channel
       (name 'sops-guix)
       (url "https://github.com/fishinthecalculator/sops-guix.git")
       (branch "main")
       (commit "c53e27e533836ea8595626ba6796dee5362f8c4a")
       (introduction
        (make-channel-introduction
         "0bbaf1fdd25266c7df790f65640aaa01e6d2dbc9"
         (openpgp-fingerprint
          "8D10 60B9 6BB8 292E 829B  7249 AED4 1CC1 93B7 01E2")))))
