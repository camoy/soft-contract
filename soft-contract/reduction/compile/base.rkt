#lang typed/racket/base

(provide (all-defined-out))

(require "../../utils/main.rkt"
         "../../ast/main.rkt"
         "../../runtime/main.rkt"
         "../../proof-relation/main.rkt"
         racket/set
         racket/match)

(define/memo (↓ₓ [l : -l] [x : Var-Name]) : -⟦e⟧
  (define -blm.undefined (-blm l 'Λ (list 'defined?) (list 'undefined)))
  (λ (ρ Γ 𝒞 σ M ⟦k⟧)
    (define α (ρ@ ρ x))
    (define-values (Vs old?) (σ@ σ α))
    (define s (and old? (canonicalize Γ x)))
    (define φs (-Γ-facts Γ))
    (for*/ans ([V Vs] #:when (plausible-V-s? φs V s))
      (match V
        ['undefined (⟦k⟧ -blm.undefined Γ 𝒞 σ M)]
        [(-● ps) ; precision hack
         (define ps*
           (for/fold ([ps : (℘ -o) ps]) ([φ φs])
             (match (φ->e φ)
               [(-@ (? -o? o) (list (== s)) _) (set-add ps o)]
               [_ ps])))
         (define V* (if (eq? ps ps*) V (-● ps*))) ; keep old instance
         (⟦k⟧ (-W (list V*) s) Γ 𝒞 σ M)]
        [_ (⟦k⟧ (-W (list V) s) Γ 𝒞 σ M)]))))

(define ↓ₚᵣₘ : (-prim → -⟦e⟧)
  (let ([meq : (HashTable Any -⟦e⟧) (make-hasheq)] ; `eq` doesn't work for String but ok
        [m   : (HashTable Any -⟦e⟧) (make-hash  )])
    
    (: ret-p : -prim → -⟦e⟧)
    (define (ret-p p) (ret-W¹ p p))
    
    (match-lambda
      [(? symbol? o)  (hash-ref! meq o (λ () (ret-p o)))]
      [(and B (-b b)) (hash-ref! meq b (λ () (ret-p B)))]
      [p              (hash-ref! m   p (λ () (ret-p p)))])))

(define/memo (ret-W¹ [V : -V] [v : -s]) : -⟦e⟧
  (λ (ρ Γ 𝒞 σ M ⟦k⟧)
    (⟦k⟧ (-W (list V) v) Γ 𝒞 σ M)))

(define-syntax-rule (with-δσ δσ e ...)
  (let-values ([(ςs δσ₀ δσₖ δM) (let () e ...)])
    (values ςs (⊔σ δσ₀ δσ) δσₖ δM)))

(define ⟦void⟧ (↓ₚᵣₘ -void))
(define ⟦tt⟧ (↓ₚᵣₘ -tt))
(define ⟦ff⟧ (↓ₚᵣₘ -ff))
