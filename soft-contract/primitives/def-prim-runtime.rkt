#lang typed/racket/base

;; This module provides runtime support for the def-prim DSL

(provide (all-defined-out))
(require racket/match
         racket/set
         "../utils/set.rkt"
         "../utils/map.rkt"
         "../utils/function.rkt"
         "../utils/pretty.rkt"
         "../utils/def.rkt"
         "../utils/list.rkt"
         "../ast/definition.rkt"
         "../runtime/main.rkt"
         "../proof-relation/main.rkt")

(define-type -⟦o⟧! (-⟪ℋ⟫ -ℓ -l -Σ -Γ (Listof -W¹) → (℘ -ΓA)))
(define-type Prim-Thunk (-Γ → (℘ -ΓA)))

(: unchecked-ac : -σ -st-ac -W¹ → (℘ -W¹))
;; unchecked struct accessor, assuming the value is already checked to be the right struct.
;; This is only for use internally, so it's safe (though imprecise) to ignore field wraps
(define (unchecked-ac σ ac W)
  (define-set seen : -⟪α⟫ #:eq? #t #:as-mutable-hash? #t)
  (match-define (-W¹ (list V) s) W)
  (match-define (-st-ac 𝒾 i) ac)
  (define s* (-?@ ac s))
  (let go ([V : -V V])
    (match V
      [(-St (== 𝒾) αs)
       (for/set: : (℘ -W¹) ([V* (in-set (σ@ σ (list-ref αs i)))])
         (-W¹ V* s*))]
      [(-St* (== 𝒾) _ α _)
       (cond [(seen-has? α) ∅]
             [else
              (seen-add! α)
              (for/union : (℘ -W¹) ([V (in-set (σ@ σ α))]) (go V))])]
      [(? -●?) {set (-W¹ -●/V s*)}]
      [_ ∅])))

(: ⊢?/quick : -R -σ -Γ -o -W¹ * → Boolean)
;; Perform a relatively cheap check (i.e. no SMT call) if `(o W ...)` returns `R`
(define (⊢?/quick R σ Γ o . Ws)
  (define-values (Vs ss) (unzip-by -W¹-V -W¹-s Ws))
  (eq? R (first-R (apply p∋Vs σ o Vs)
                  (Γ⊢e Γ (apply -?@ o ss)))))

(: blm : -Γ -l -l (U -V -v) -W¹ → (℘ -ΓA))
(define (blm Γ who whom why what)
  {set (-ΓA Γ (-blm who whom (list why) (list (-W¹-V what))))})

(: implement-predicate : -M -σ -Γ Symbol (Listof -W¹) → (℘ -ΓA))
(define (implement-predicate M σ Γ o Ws)
  (define ss (map -W¹-s Ws))
  (define A
    (case (apply MΓ⊢oW M σ Γ o Ws)
      [(✓) -True/Vs]
      [(✗) -False/Vs]
      [(?) -Bool/Vs]))
  {set (-ΓA Γ (-W A (apply -?@ o ss)))})

(define/memoeq (total-pred [n : Index]) : (Symbol → -⟦o⟧!)
  (define cs (list (format-symbol "~a values" n)))
  (λ (o)
    (λ (⟪ℋ⟫ ℓ l Σ Γ Ws)
      (cond [(equal? n (length Ws))
             (match-define (-Σ σ _ M) Σ)
             (implement-predicate M σ Γ o Ws)]
            [else
             {set (-ΓA Γ (-blm l o cs (map -W¹-V Ws)))}]))))

(define alias-table : (HashTable Symbol Symbol) (make-hasheq))
(define alias-internal-table : (HashTable Symbol (U -st-mk -st-p -st-ac -st-mut)) (make-hasheq))
(define const-table : (HashTable Symbol -b) (make-hasheq))
(define prim-table  : (HashTable Symbol -⟦o⟧!) (make-hasheq))
(define opq-table   : (HashTable Symbol -●) (make-hasheq))
(define debug-table : (HashTable Symbol Any) (make-hasheq))

(define (get-defined-prim-names)
  ;; TODO def-opq table
  (∪ (list->seteq (hash-keys const-table))
     (list->seteq (hash-keys prim-table))
     (list->seteq (hash-keys alias-table))
     (list->seteq (hash-keys alias-internal-table))))

;; range can't be:
;;  - `Syntaxof Any`, b/c can't convert to contract
;;  - `Any`, because TR doens't know how to wrap it
(: get-prim-parse-result : Symbol → (Values (U 'quote 'const) Symbol))
(define (get-prim-parse-result name)
  (cond [(hash-has-key? prim-table name) (values 'quote name)]
        [(hash-has-key? const-table name) (values 'const name)]
        [(hash-ref alias-table name #f) => get-prim-parse-result]
        [(hash-has-key? alias-internal-table name) (values 'const name)]
        [(hash-ref opq-table name #f) =>
         (λ ([V : -V])
           (error 'get-prim "TODO: opq-table"))]
        [else (error 'get-prim-parse-result "~a" name)]))
