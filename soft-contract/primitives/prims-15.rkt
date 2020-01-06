#lang typed/racket/base

(provide prims-15@)

(require racket/contract
         typed/racket/unit
         racket/path
         "def.rkt"
         "signatures.rkt")

(define-unit prims-15@
  (import prim-runtime^)
  (export)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; 15.1 Paths
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; 15.1.1 Manipulating Paths
  (def-pred path?)
  (def-pred path-for-some-system?)
  (def-pred path-string?)
  (def-pred complete-path?)
  (def string->path (string? . -> . path?))
  (def path->string (path? . -> . string?))
  (def build-path
    (((or/c path-string? path-for-some-system? 'up 'same))
     #:rest (listof (or/c (and/c (or/c path-string? path-for-some-system?)
                                 (not/c complete-path?))
                          (or/c 'up 'same)))
     . ->* . path-for-some-system?))
  (def path-replace-extension
    ((or/c path-string? path-for-some-system?) (or/c string? bytes?) . -> . path-for-some-system?))

  ;; 15.1.2 More Path Utilities
  (def file-name-from-path ((or/c path-string? path-for-some-system?) . -> . (or/c #f path-for-some-system?)))
  (def filename-extension ((or/c path-string? path-for-some-system?) . -> . (or/c #f bytes?)))
  (def path-only ((or/c path-string? path-for-some-system?) . -> . (or/c #f path-for-some-system?)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; 15.2 Filesystem
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


  ;; 15.2.2 Files
  (def file-exists? (path-string? . -> . boolean?))
  (def delete-file (path-string? . -> . void?))

  ;; 15.2.6 More File and Directory Utilities
  (def file->list (path-string? . -> . list?))
  (def file->lines (path-string? . -> . (listof string?)))
  (def file->value (path-string? . -> . any/c))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; 15.6
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (def current-inexact-milliseconds (-> real?))
  (def time-apply
    (procedure? list? . -> . (values list?
                                     exact-integer?
                                     exact-integer?
                                     exact-integer?)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; 15.7
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (def getenv (string? . -> . (or/c string? not)))
  (def putenv (string? string? . -> . boolean?))
  )
