#lang typed/racket/base
(require typed/rackunit "../parse/main.rkt")

(for* ([dir (list "programs/safe" "programs/fail" "programs/fail-ce")]
       [file (in-directory dir)])
  (cond
    [(directory-exists? file)
     (printf "Dir: ~a~n" file)]
    [(regexp-match-exact? #rx".*rkt" (path->string file))
     (printf "Rkt: ~a~n" file)
     (define str (path->string file))
     (test-case str (test-not-exn str (λ () (file->module str))))]))
