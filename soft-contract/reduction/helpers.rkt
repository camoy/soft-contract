#lang typed/racket/base

(provide (all-defined-out))

(require racket/match
         (except-in racket/list remove-duplicates)
         racket/set
         "../utils/main.rkt"
         "../ast/main.rkt"
         "../runtime/main.rkt"
         "../proof-relation/main.rkt")

(: acc : -σ -X (-ℰ → -ℰ) (-σ -Γ -X -W → (Values -Δσ (℘ -ΓW) (℘ -ΓE) -ΔX (℘ -ℐ)))
        → -Δσ (℘ -ΓW) (℘ -ΓE) -ΔX (℘ -ℐ)
        → (Values -Δσ (℘ -ΓW) (℘ -ΓE) -ΔX (℘ -ℐ)))
;; Bind-ish. Takes care of store widening.
;; Caller takes care of stack accumulation and what to do with result.
(define ((acc σ X f comp) δσ ΓWs ΓEs δX ℐs)
  (define ℐs*
    (map/set
     (match-lambda
       [(-ℐ (-ℋ ℒ bnd    ℰ ) τ)
        (-ℐ (-ℋ ℒ bnd (f ℰ)) τ)])
     ℐs))
  (define σ* (⊔/m σ δσ))
  (define X* (∪ X δX))
  (for/fold ([δσ : -Δσ δσ]
             [ΓWs* : (℘ -ΓW) ∅]
             [ΓEs* : (℘ -ΓE) ΓEs]
             [δX : (℘ -α) δX]
             [ℐs* : (℘ -ℐ) ℐs*])
            ([ΓW ΓWs])
    (match-define (-ΓW Γ* W) ΓW)
    (define-values (δσ+ ΓWs+ ΓEs+ δX+ ℐs+) (comp σ* Γ* X* W))
    (values (⊔/m δσ δσ+) (∪ ΓWs* ΓWs+) (∪ ΓEs* ΓEs+) (∪ δX δX+) (∪ ℐs* ℐs+))))

(define-syntax-rule (with-guarded-arity n* (l Γ Vs) e ...)
  (let ([n n*]
        [m (length Vs)])
    (cond
      [(= n m) e ...]
      [else
       (define Cs (make-list n 'any/c))
       (values ⊥σ ∅ {set (-ΓE Γ (-blm l 'Λ Cs Vs))} ∅ ∅)])))

;; Memoized compilation of primitives because `Λ` needs a ridiculous number of these
(define ⇓ₚᵣₘ : (-prim → -⟦e⟧) 
  (let ([meq : (HashTable Any -⟦e⟧) (make-hasheq)] ; `eq` doesn't work for String but ok
        [m   : (HashTable Any -⟦e⟧) (make-hash  )])
    
    (: ret-p : -prim → -⟦e⟧)
    (define (ret-p p) (ret-W¹ (-W¹ p p)))
    
    (match-lambda
      [(? symbol? o)  (hash-ref! meq o (λ () (ret-p o)))]
      [(and B (-b b)) (hash-ref! meq b (λ () (ret-p B)))]
      [p              (hash-ref! m   p (λ () (ret-p p)))])))

(define/memo (⇓ₓ [l : Mon-Party] [x : Var-Name]) : -⟦e⟧
  (λ (M σ X ℒ)
    (match-define (-ℒ ρ Γ 𝒞) ℒ)
    (define s : -s
      (cond
        [(∋ X (ρ@ ρ x)) #f]
        [else (canonicalize Γ x)]))
    (define φs (-Γ-facts Γ))
    (define-values (ΓWs ΓEs)
      (for*/fold ([ΓWs : (℘ -ΓW) ∅]
                  [ΓEs : (℘ -ΓE) ∅])
                 ([V (σ@ σ (ρ@ ρ x))] #:when (plausible-V-s? φs V s))
        (match V
          ['undefined
           (values
            ΓWs
            (set-add
             ΓEs
             (-ΓE Γ (-blm l 'Λ (list 'defined?) (list 'undefined)))))]
          [(-● ps)
           (define ps*
             (for/fold ([ps : (℘ -o) ps]) ([φ φs])
               (match (φ->e φ)
                 [(-@ (? -o? o) (list (== s)) _)
                  (set-add ps o)]
                 [_ ps])))
           (define V* (if (equal? ps ps*) V (-● ps*)))
           (values (set-add ΓWs (-ΓW Γ (-W (list V*) s))) ΓEs)]
          [else (values (set-add ΓWs (-ΓW Γ (-W (list V) s))) ΓEs)])))
    (values ⊥σ ΓWs ΓEs ∅ ∅)))

(define/memo (ret-W¹ [W : -W¹]) : -⟦e⟧
  (match-define (-W¹ V v) W)
  (λ (M σ X ℒ)
    (values ⊥σ {set (-ΓW (-ℒ-cnd ℒ) (-W (list V) v))} ∅ ∅ ∅)))

(define ⟦void⟧ (⇓ₚᵣₘ -void))
(define ⟦tt⟧ (⇓ₚᵣₘ -tt))
(define ⟦ff⟧ (⇓ₚᵣₘ -ff))
