#lang typed/racket/base

(require typed/racket/unit
         racket/match
         racket/set
         set-extras
         "../utils/debug.rkt"
         "../utils/def.rkt"
         "../utils/pretty.rkt"
         "../ast/signatures.rkt"
         "../proof-relation/signatures.rkt"
         "../signatures.rkt"
         "signatures.rkt"
         )

(provide instr@)

(define-unit instr@
  (import local-prover^ pretty-print^ widening^)
  (export instr^)

  (: ℋ+ : -ℋ -edge  → (Values -ℋ Boolean))
  ;; Add edge on top of call history.
  ;; If the target is already there, return the history chunk up to first time the target
  ;; is seen
  (define (ℋ+ ℋ x)

    (: match? : (-edge → Boolean))
    (define match?
      (match-let ([(-edge tgt src) x])
        (match-lambda
          [(-edge tgt* _) (and (not (symbol? tgt*)) (tgt=? tgt* tgt))])))

    (define ?ℋ (memf match? ℋ))
    (if ?ℋ (values ?ℋ #t) (values (cons x ℋ) #f)))
  
  (define H∅
    (let ([ℋ∅ : -ℋ '()])
      (-ℋ->-H ℋ∅)))

  (: H+ : -H -edge → (Values -H Boolean))
  (define (H+ H e)
    (define-values (ℋ* looped?) (ℋ+ (-H->-ℋ H) e))
    (values (-ℋ->-H ℋ*) looped?))

  (: ⌊ρ⌋ : -ρ → -⌊ρ⌋)
  (define (⌊ρ⌋ ρ)
    (for/hasheq : -⌊ρ⌋ ([(x α) ρ])
      (match (⟪α⟫->-α (cast α ⟪α⟫))
        [(-α.x x H) (values x (map -edge-src (-H->-ℋ H)))])))

  (define ⌊ρ⌋₀ : -⌊ρ⌋ (hasheq))

  (:* strip-fn strip-ct : -V → -edge.tgt)
  (define (strip-fn V) (list 'fn (strip-V V)))
  (define (strip-ct V) (list 'ct (strip-V V)))

  (: strip-V : -V → -edge.tgt)
  (define strip-V
    (match-lambda
      [(-Clo xs ⟦e⟧ ρ) (list 'flat (cons ⟦e⟧ (⌊ρ⌋ ρ)))]
      [(-And/C _ (-⟪α⟫ℓ _ ℓ₁) (-⟪α⟫ℓ _ ℓ₂)) (list 'and/c ℓ₁ ℓ₂)]
      [(-Or/C  _ (-⟪α⟫ℓ _ ℓ₁) (-⟪α⟫ℓ _ ℓ₂)) (list  'or/c ℓ₁ ℓ₂)]
      [(-Not/C (-⟪α⟫ℓ _ ℓ)) (list 'not/c ℓ)]
      [(-One-Of/C bs) bs]
      [(-St/C _ (-𝒾 𝒾 _) ⟪α⟫ℓs) (cons 𝒾 (map -⟪α⟫ℓ-loc ⟪α⟫ℓs))]
      [(-Vectorof (-⟪α⟫ℓ _ ℓ)) (list 'vectorof ℓ)]
      [(-Vector/C ⟪α⟫ℓs) (cons 'vector/c (map -⟪α⟫ℓ-loc ⟪α⟫ℓs))]
      [(-Hash/C (-⟪α⟫ℓ _ ℓₖ) (-⟪α⟫ℓ _ ℓᵥ)) (list 'hash/c ℓₖ ℓᵥ)]
      [(-Set/C (-⟪α⟫ℓ _ ℓ)) (list 'set/c ℓ)]
      [(-=> αs βs) (list '-> (get-ℓ αs) (if (list? βs) (get-ℓ βs) 'any))]
      [(-=>i αs (list _ _ ℓ)) (list '->i ℓ)]
      [(-Case-> cases) (list 'case-> (map strip-V cases))]
      [(-x/C α)
       (match-define (or (-α.x/c x _) (-α.imm-listof x _ _)) (⟪α⟫->-α α))
       (list 'recursive-contract/c (assert x))]
      [(? -o? o) (list 'prim o)]
      [(-Ar _ α _)
       (match (⟪α⟫->-α α)
         [(-α.fn ctx _) (list 'arr (-ctx-loc ctx))]
         [(-α.imm (-Fn● _ tag)) (list 'arr● (strip-tag tag))])]
      [(-∀/C xs ⟦c⟧ ρ) (list '∀/c (cons ⟦c⟧ (⌊ρ⌋ ρ)))]
      [(-Seal/C x _ _) (list 'seal/c x)]
      [(and c (or (? ->/c?) (? -≥/c?) (? -</c?) (? -≤/c?) (? -≡/c?))) (list 'flat c)]
      [(? integer? t) (format-symbol "•~a" (n-sub t))]
      [(-Fn● _ tag) (list 'Fn● (strip-tag tag))]
      [(-● ps) (list '● (show-ps ps))]
      [V (error 'strip-V "~a not expected" V)]))

  (define show-ps : ((℘ -h) → (Listof Symbol))
    ;; Cache to fix order
    (let ([m : (HashTable (℘ -h) (Listof Symbol)) (make-hash)])
      (λ (ps)
        (hash-ref! m ps (λ () (set-map ps (λ ([h : -h]) (string->symbol (format "~a" (show-h h))))))))))

  (: strip-tag : HV-Tag → Symbol)
  (define (strip-tag tag)
    (match tag
      [(cons o _) (if (string? o) (string->symbol o) o)]
      ['† '†]))

  (define get-ℓ : ((-maybe-var -⟪α⟫ℓ) → (-maybe-var ℓ))
    (match-lambda
      [(? list? l) (map -⟪α⟫ℓ-loc l)]
      [(-var l x) (-var (map -⟪α⟫ℓ-loc l) (-⟪α⟫ℓ-loc x))]))

  (: tgt=? : -edge.tgt -edge.tgt → Boolean)
  (define tgt=?
    (match-lambda**
     [((? list? l₁) (? list? l₂)) (and (equal? (length l₁) (length l₂)) (andmap tgt=? l₁ l₂))]
     [((cons ⟦e⟧₁ _) (cons ⟦e⟧₂ _)) (eq? ⟦e⟧₁ ⟦e⟧₂)]
     [(t₁ t₂) (equal? t₁ t₂)]))
  )
