#lang typed/racket/base

;; This module provides static information about the program available from parsing

(provide with-initialized-static-info
         get-struct-arity
         struct-all-immutable?
         struct-mutable?
         assignable?
         add-assignable!
         add-struct-info!
         add-top-level!
         top-levels
         current-static-info ; just for debugging
         )

(require racket/match
         "../utils/set.rkt"
         "definition.rkt")

(define-new-subtype -struct-info (Vector->struct-info (Vectorof Boolean)))
(struct -static-info ([structs : (HashTable -𝒾 -struct-info)]
                      [assignables : (HashTable (U -x -𝒾) #t)]
                      [top-level-defs : (HashTable -𝒾 #t)])
  #:transparent)

(define (new-static-info)
  (define cons-info (Vector->struct-info (vector-immutable #f #f)))
  (define box-info (Vector->struct-info (vector-immutable #t)))
  (-static-info (make-hash (list (cons -𝒾-cons cons-info)
                                 (cons -𝒾-box  box-info)))
                (make-hash)
                (make-hash)))

(define current-static-info : (Parameterof -static-info) (make-parameter (new-static-info)))

(define-syntax-rule (with-initialized-static-info e ...)
  (parameterize ([current-static-info (new-static-info)])
    e ...))

(: get-struct-info : -𝒾 → -struct-info)
(define (get-struct-info 𝒾)
  (match-define (-static-info structs _ _) (current-static-info))
  (hash-ref structs 𝒾 (λ () (error 'get-struct-info "Nothing for ~a" (-𝒾-name 𝒾)))))

(define (get-struct-arity [𝒾 : -𝒾]) : Index (vector-length (get-struct-info 𝒾)))
(define (struct-mutable? [𝒾 : -𝒾] [i : Index]) (vector-ref (get-struct-info 𝒾) i))
(define (struct-all-immutable? [𝒾 : -𝒾])
  (not (for/or : Boolean ([mut? (in-vector (get-struct-info 𝒾))])
         mut?)))
(define (add-struct-info! [𝒾 : -𝒾] [arity : Index] [mutables : (Setof Index)])
  (define v
    (for/vector : (Vectorof Boolean) #:length arity ([i arity])
      (∋ mutables i)))
  (define m (-static-info-structs (current-static-info)))
  (cond
    [(hash-ref m 𝒾 #f) =>
     (λ ([v₀ : -struct-info])
       (cond [(equal? v₀ v) (void)]
             [else (error 'add-struct-info!
                          "inconsistent struct information for ~a:~n - ~a~n - ~a"
                          (-𝒾-name 𝒾)
                          v₀
                          v)]))]
    [else
     (hash-set! m 𝒾 (Vector->struct-info v))]))

(define (add-assignable! [x : (U -x -𝒾)])
  (hash-set! (-static-info-assignables (current-static-info)) x #t))
(define (assignable? [x : (U Symbol -x -𝒾)]) : Boolean
  (cond
    [(or (-x? x) (-𝒾? x))
     (hash-has-key? (-static-info-assignables (current-static-info)) x)]
    [else (assignable? (-x x))]))

(define (add-top-level! [𝒾 : -𝒾])
  (hash-set! (-static-info-top-level-defs (current-static-info)) 𝒾 #t))
(define (top-levels) : (Listof -𝒾)
  (hash-keys (-static-info-top-level-defs (current-static-info))))
