#lang typed/racket/base

(provide prim-runtime@)
(require racket/match
         racket/set
         syntax/parse/define
         typed/racket/unit
         set-extras
         "../utils/main.rkt"
         "../ast/main.rkt"
         "../runtime/main.rkt"
         "../signatures.rkt"
         "signatures.rkt")

(define-unit prim-runtime@
  (import proof-system^ widening^)
  (export prim-runtime^)

  (: unchecked-ac : -σ -Γ -st-ac -W¹ → (℘ -W¹))
  ;; unchecked struct accessor, assuming the value is already checked to be the right struct.
  ;; This is only for use internally, so it's safe (though imprecise) to ignore field wraps
  (define (unchecked-ac σ Γ ac W)
    (define-set seen : ⟪α⟫ #:eq? #t #:as-mutable-hash? #t)
    (match-define (-W¹ V s) W)
    (match-define (-st-ac 𝒾 i) ac)
    (define φs (-Γ-facts Γ))
    (define s* (?t@ ac s))
    (let go ([V : -V V])
      (match V
        [(-St (== 𝒾) αs)
         (for/set: : (℘ -W¹) ([V* (in-set (σ@ σ (list-ref αs i)))]
                              #:when (plausible-V-t? φs V* s*))
           (-W¹ V* s*))]
        [(-St* (-St/C _ (== 𝒾) _) α _)
         (cond [(seen-has? α) ∅]
               [else
                (seen-add! α)
                (for/union : (℘ -W¹) ([V (in-set (σ@ σ α))]
                                      #:when (plausible-V-t? φs V s))
                           (go V))])]
        [(? -●?) {set (-W¹ -●.V s*)}]
        [_ ∅])))

  (: ⊢?/quick : -R -σ (℘ -t) -o -W¹ * → Boolean)
  ;; Perform a relatively cheap check (i.e. no SMT call) if `(o W ...)` returns `R`
  (define (⊢?/quick R σ Γ o . Ws)
    (define-values (Vs ss) (unzip-by -W¹-V -W¹-t Ws))
    (eq? R (first-R (apply p∋Vs σ o Vs)
                    (Γ⊢t Γ (apply ?t@ o ss)))))

  (: implement-predicate : -M -σ -Γ Symbol (Listof -W¹) → (℘ -ΓA))
  (define (implement-predicate M σ Γ o Ws)
    (define ss (map -W¹-t Ws))
    (define A
      (case (apply MΓ⊢oW M σ Γ o Ws)
        [(✓) -tt.Vs]
        [(✗) -ff.Vs]
        [(?) -Bool.Vs]))
    {set (-ΓA (-Γ-facts Γ) (-W A (apply ?t@ o ss)))})

  (define/memoeq (make-total-pred [n : Index]) : (Symbol → -⟦o⟧)
    (λ (o)
      (λ (⟪ℋ⟫ ℒ Σ Γ Ws)
        (cond [(equal? n (length Ws))
               (match-define (-Σ σ _ M) Σ)
               (implement-predicate M σ Γ o Ws)]
              [else
               {set (-ΓA (-Γ-facts Γ) (blm-arity (-ℒ-app ℒ) o n (map -W¹-V Ws)))}]))))

  (define alias-table : (HashTable Symbol Symbol) (make-hasheq))
  (define const-table : (HashTable Symbol -prim) (make-hasheq))
  (define prim-table  : (HashTable Symbol -⟦o⟧) (make-hasheq))
  (define opq-table   : (HashTable Symbol -●) (make-hasheq))
  (define debug-table : (HashTable Symbol Any) (make-hasheq))

  (: get-prim : Symbol → (Option -⟦o⟧))
  (define (get-prim o) (hash-ref prim-table o #f))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Helpers for some of the primitives
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (: ts->bs : (Listof -?t) → (Option (Listof Base)))
  (define (ts->bs ts)
    (foldr (λ ([t : -?t] [?bs : (Option (Listof Base))])
             (and ?bs (-b? t) (cons (-b-unboxed t) ?bs)))
           '()
           ts))

  ;; Return an abstract value approximating all list element in `V`
  (define (extract-list-content [σ : -σ] [V : -St]) : (℘ -V)
    (define-set seen : ⟪α⟫ #:eq? #t #:as-mutable-hash? #t)
    (match-define (-Cons αₕ αₜ) V)
    (define Vs (σ@ σ αₕ))
    (let loop! ([αₜ : ⟪α⟫ αₜ])
      (unless (seen-has? αₜ)
        (seen-add! αₜ)
        (for ([Vₜ (σ@ σ αₜ)])
          (match Vₜ
            [(-Cons αₕ* αₜ*)
             (for ([Vₕ (σ@ σ αₕ*)])
               (set! Vs (Vs⊕ σ Vs Vₕ)))
             (loop! αₜ*)]
            [(-b (list)) (void)]
            [_ (set! Vs (Vs⊕ σ Vs (-● ∅)))]))))
    Vs)

  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Implication and Exclusion
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (define implication-table : (HashTable Symbol (℘ Symbol)) (make-hasheq))
  (define exclusion-table : (HashTable Symbol (℘ Symbol)) (make-hasheq))
  (define implication-table⁻¹ : (HashTable Symbol (℘ Symbol)) (make-hasheq))

  (: add-implication! : Symbol Symbol → Void)
  ;; Extend implication table and take care of transitivity
  (define (add-implication! p q)
    (unless (map-has? implication-table p q)
      (map-add! implication-table   p q #:eq? #t)
      (map-add! implication-table⁻¹ q p #:eq? #t)
      ;; implication is reflexive
      (add-implication! p p)
      (add-implication! q q)
      ;; implication is transitive
      (for ([q* (in-set (get-weakers q))])
        (add-implication! p q*))
      (for ([p₀ (in-set (get-strongers p))])
        (add-implication! p₀ q))
      ;; (r → ¬q) and (q₀ → q) implies r → ¬q₀
      (for* ([r (in-set (get-exclusions q))])
        (add-exclusion! p r))))

  (: add-exclusion! : Symbol Symbol → Void)
  ;; Extend exclusion table and take care of inferring existing implication
  (define (add-exclusion! p q)
    (unless (map-has? exclusion-table p q)
      (map-add! exclusion-table p q #:eq? #t)
      ;; (p → ¬q) and (q₀ → q) implies (p → ¬q₀)
      (for ([q₀ (in-set (get-strongers q))])
        (add-exclusion! p q₀))
      (for ([p₀ (in-set (get-strongers p))])
        (add-exclusion! p₀ q))
      ;; exclusion is symmetric
      (add-exclusion! q p)))

  (:* get-weakers get-strongers get-exclusions : Symbol → (℘ Symbol))
  (define (get-weakers    p) (hash-ref implication-table   p mk-∅eq))
  (define (get-strongers  p) (hash-ref implication-table⁻¹ p mk-∅eq))
  (define (get-exclusions p) (hash-ref exclusion-table     p mk-∅eq))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Range
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (define range-table : (HashTable Symbol Symbol) (make-hasheq))
  (define partial-prims : (HashTable Symbol Natural) (make-hasheq))

  (: set-range! : Symbol Symbol → Void)
  (define (set-range! o r) (hash-set-once! range-table o r))

  (: set-partial! : Symbol Natural → Void)
  (define (set-partial! o n) (hash-set! partial-prims o n))

  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Arity
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (define arity-table : (HashTable Symbol Arity) (make-hasheq))

  (: update-arity! : Symbol Arity → Void)
  (define (update-arity! o a)
    (cond [(hash-ref arity-table o #f) =>
           (λ ([a₀ : Arity])
             (unless (arity-includes? a₀ a)
               (hash-set! arity-table o (normalize-arity (list a₀ a)))))]
          [else
           (hash-set! arity-table o a)]))

  (: arity-check/handler (∀ (X) (-Γ → (℘ X)) (-Γ → (℘ X)) -Γ -W¹ Arity → (℘ X)))
  (define (arity-check/handler t f Γ W arity)
    (match-define (-W¹ V s) W) ; ignore `Γ` and `s` for now
    (define (on-t) (t Γ)) ; TODO
    (define (on-f) (f Γ)) ; TODO
    (cond [(V-arity V) =>
           (λ ([a : Arity])
             ((if (arity-includes? a arity) t f) Γ))]
          [else (∪ (t Γ) (f Γ))]))
  
  )
