#lang typed/racket/base

(provide (all-defined-out))

(require racket/match
         racket/set
         typed/racket/unit
         bnf
         unreachable
         intern
         set-extras
         "../ast/signatures.rkt"
         )

(E . ≜ . -e)

(#|Run-time Values|# V . ::= . -prim
                               (St -𝒾 (Listof α))
                               (Vect (Listof α))
                               (Vect-Of [content : α] [length : #|restricted|# V^])
                               (Hash-Of [key : α] [val : α] [immut? : Boolean])
                               (Set-Of [elems : α] [immut? : Boolean])
                               Fn
                               (Guarded [ctx : Ctx] [guard : Prox/C] [val : α])
                               (Sealed α)
                               C
                               T
                               (-● (℘ P)))
(#|Identities     |# T . ::= . -b α (T:@ -o (Listof T)))
(#|Stores         |# Σ .  ≜  . (Immutable-HashTable T (Pairof V^ N)))
(#|Store Deltas   |# ΔΣ . ≜  . (Immutable-HashTable T (Pairof V^ N)))
(#|Values Lists   |# W .  ≜  . (Listof V^))
(#|Non-Prim Funcs |# Fn . ::= . (Clo -formals E (℘ α) ℓ)
                                (Case-Clo (Listof Clo) ℓ))
(#|Contracts      |# C . ::= . (And/C α α ℓ)
                               (Or/C α α ℓ)
                               (Not/C α ℓ)
                               (One-Of/C (℘ Base))
                               Prox/C
                               (Seal/C α)
                               P)
(#|Proxies        |# Prox/C . ::= . Fn/C
                               (St/C -𝒾 (Listof α) ℓ)
                               (Vectof/C α ℓ)
                               (Vect/C (Listof α) ℓ)
                               (Hash/C α α ℓ)
                               (Set/C α ℓ))
(#|Func. Contracts|# Fn/C . ::= . (==> [doms : (-var α)]
                                       [rng : (Option (Listof α))]
                                       ℓ)
                               (==>i [doms : (Listof Dom)] [mk-rng : Dom])
                               (∀/C (Listof Symbol) E (℘ α))
                               (Case-=> (Listof ==>))) 
(#|Errors         |# Err . ::= . (Err:Raised String ℓ)
                                 (Err:Undefined Symbol ℓ)
                                 (Err:Values Natural E W ℓ)
                                 (Err:Arity [proc : (U V ℓ)] [args : (U Natural W)] [site : ℓ])
                                 (Err:Sealed [seal : Symbol] [site : ℓ])
                                 (Blm [violator : -l]
                                      [site : ℓ]
                                      [origin : ℓ]
                                      [ctc : W]
                                      [val : W]))
(#|Predicates     |# P . ::= . Q (P:¬ Q))
(#|Pos. Predicates|# Q . ::= . -o (P:> T) (P:≥ T) (P:< T) (P:≤ T) (P:= T) (P:arity-includes Natural))
(#|Caches         |# $ .  ≜  . (Mutable-HashTable $:Key (Pairof R (℘ Err))))
(#|Result         |# R .  ≜  . (Immutable-HashTable ΔΣ W^))
(#|Decisions      |# Dec . ::= . '✓ '✗)
(#|Maybe Decisions|# ?Dec . ≜ . (Option Dec))
(#|Run-time Ctxs  |# -H .  ≜  . (Listof K))
(#|Call Edge      |# K .  ≜  . (Pairof ℓ ℓ))
(#|Addresses      |# α . ::= . γ (α:dyn β H))
(#|Static Addrs   |# γ . ::= . (γ:lex Symbol)
                               (γ:top -𝒾)
                               (γ:wrp -𝒾)
                               (γ:hv HV-Tag)
                               ;; Only use this in the prim DSL where all values are finite
                               ;; with purely syntactic components
                               (γ:imm #|restricted|# V)
                               ;; indirection for `listof` to keep in-sync with regular listof contracts
                               (γ:imm:listof     Symbol #|elem, ok with care|# V ℓ)
                               (γ:imm:ref-listof Symbol #|elem, ok with care|# V ℓ)) 
(#|Addr. Bases    |# β . ::= . ; escaped parameter
                               Symbol
                               ; mutable cell
                               (β:mut (U Symbol -𝒾))
                               ; struct field
                               (β:fld -𝒾 ℓ Natural)
                               ; for varargs
                               (β:var:car (U ℓ Symbol) (Option Natural))
                               (β:var:cdr (U ℓ Symbol) (Option Natural))
                               ;; for wrapped mutable struct
                               (β:st -𝒾 Ctx)
                               ;; for vector indices
                               (β:idx ℓ Natural)
                               ;; for vect-of content
                               (β:vct ℓ)
                               ;; for hash-of content
                               (β:hash:key ℓ)
                               (β:hash:val ℓ)
                               ;; for set-of content
                               (β:set:elem ℓ)
                               ;; for wrapped vector
                               (β:unvct Ctx)
                               ;; for wrapped hash
                               (β:unhsh Ctx)
                               ;; for wrapped set
                               (β:unset Ctx)
                               ;; for contract components
                               (β:and/c:l ℓ)
                               (β:and/c:r ℓ)
                               (β:or/c:l ℓ)
                               (β:or/c:r ℓ)
                               (β:not/c ℓ)
                               (β:x/c Symbol)
                               (β:vect/c ℓ Natural)
                               (β:vectof ℓ)
                               (β:hash/c:key ℓ)
                               (β:hash/c:val ℓ)
                               (β:set/c:elem ℓ)
                               (β:st/c -𝒾 ℓ Natural)
                               (β:dom ℓ Natural)
                               (β:rst ℓ)
                               (β:rng ℓ [arity : Natural] [index : Natural])
                               ;; for wrapped function
                               (β:fn Ctx)
                               ;; For values wrapped in seals
                               (β:sealed Symbol) ; points to wrapped objects
                               )
(#|Cache Keys     |# $:Key . ::= . ($:Key:Mon Σ Ctx V V^)
                                   ($:Key:App Σ ℓ V W)
                                   ($:Key:App/rest Σ ℓ V W V^)
                                   ($:Key:Hv Σ α))
(#|Named Domains  |# Dom . ::= . (Dom [name : Symbol] [ctc : (U Clo α)] ℓ))
(#|Cardinalities  |# N . ::= . 0 1 'N)
(#|Havoc Tags     |# HV-Tag . ≜ . (Option -l))
(#|Mon. Contexts  |# Ctx . ::= . (Ctx [pos : -l] [neg : -l] [origin : ℓ] [site : ℓ]))
(#|Cache Tags     |# $:Tag . ::= . 'app 'mon 'flc)
(#|Abstract Values|# V^ . ≜ . (℘ V))
(#|Abs. Val. Lists|# W^ . ≜ . (℘ W))

;; Size-change Stuff
(#|Size-change Graphs|# SCG . ≜ . (Immutable-HashTable (Pairof Integer Integer) Ch))
(#|Changes           |# Ch . ::= . '↓ '↧)

(#|Addr. Substitutions|# S . ≜ . (HashTable α α))


(define-interner H -H
  #:intern-function-name mk-H
  #:unintern-function-name inspect-H)

;; Convenient patterns
(define-syntax-rule (define-St-matcher (P α ...) St-id)
  (define-match-expander P
    (syntax-rules () [(_ α ...) (St (== St-id) (list α ...))])
    (syntax-rules () [(_ α ...) (St St-id (list α ...))])))
(define-syntax-rule (define-St/G-matcher P St-id)
  (define-match-expander P
    (syntax-rules () [(_ α) (Guarded _ (St/C (== St-id) _ _) α)])))
(define-St-matcher (Cons αₕ αₜ) -𝒾-cons)
(define-St/G-matcher Guarded-Cons -𝒾-cons)
(define-St-matcher (Box α) -𝒾-box)
(define-St/G-matcher Guarded-Box -𝒾-box)

(define ⊥R : R (hash))
(define H₀ : H (mk-H '()))
(define ⊥Σ : Σ (hash))
(define ⊥ΔΣ : ΔΣ (hash))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Signatures
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-signature sto^
  ([⧺ : (ΔΣ * → ΔΣ)]
   [lookup : ((U T:@ α) Σ → V^)]
   [unpack : ((U T:@ α V^) Σ → V^)]
   [unpack-W : (W Σ → W)]
   [alloc : (α V^ → ΔΣ)]
   [alloc-lex : ((U Symbol -𝒾) V^ → ΔΣ)]
   [alloc-lex* : ((Listof (U Symbol -𝒾)) W → ΔΣ)]
   [alloc-vararg : (Symbol W → ΔΣ)]
   [alloc-rest : ([(U Symbol ℓ) W] [#:tail V^] . ->* . (Values V^ ΔΣ))]
   [alloc-each : (W (Natural → β) → (Values (Listof α) ΔΣ))]
   [unalloc-prefix : (Natural V^ Σ → (Option (Pairof W V^)))]
   [resolve-lex : ((U Symbol -𝒾) → α)]
   [mut : ((U α T:@) V^ → ΔΣ)] 
   [ΔΣ⊔ : (ΔΣ ΔΣ → ΔΣ)]
   [close : (Σ (℘ Symbol) → (Values (℘ α) ΔΣ))]
   [stack-copy : ((℘ α) Σ → ΔΣ)] 
   [ambiguous? : (T Σ → Boolean)]
   
   ;; Old
   #;[alloc-rest-args : ([-Σ ℓ -H -φ (Listof -V^)] [#:end -V] . ->* . (Values -V -φ))]
   #;[unalloc : (-σ -δσ -V → (℘ (Listof -V^)))]
   #;[unalloc-prefix : (-σ -δσ -V Natural → (℘ (Pairof (Listof -V^) -V)))]
   ))

(define-signature cache^
  ([⊥$ : (→ $)] 
   [R-of : ([(U V V^ W)] [ΔΣ] . ->* . R)]
   [ΔΣ⧺R : (ΔΣ R → R)]
   [R⧺ΔΣ : (R ΔΣ → R)]
   [collapse-R : (R → (Option (Pairof W^ ΔΣ)))]
   [collapse-R/ΔΣ : (R → (Option ΔΣ))]
   [split-by-arity : (W^ Natural → (Values W^ W^))]
   [$⊔! : ($ $:Key R (℘ Err) → Void)]))

(define-signature val^
  ([collapse-W^ : (W^ → W)]
   [collapse-W^-by-arities : (W^ → (Immutable-HashTable Natural W))] 
   [V/ : (S → V → V)]
   [W⊔ : (W W → W)]
   [Ctx-with-site : (Ctx ℓ → Ctx)]
   [Ctx-flip : (Ctx → Ctx)]
   [C-flat? : (V Σ → Boolean)]
   [C^-flat? : (V^ Σ → Boolean)]
   [arity : (V → (Option Arity))]
   [guard-arity : (Fn/C → Arity)]
   [collect-behavioral-values : (W^ Σ → V^)]
   [behavioral? : (V Σ → Boolean)]
   [with-negative-party : (-l V → V)]
   [with-positive-party : (-l V → V)]
   #;[fresh-sym! : (→ -s)]
   #;[guard-arity : (case->
                   [==> → Arity]
                   [Fn/C → (Option Arity)])]
   #;[blm-arity : (-l ℓ ℓ Arity W → Blm)]
   #;[in-scope? : ((U α S) (℘ α) → Boolean)]
   #;[cmp-sets : (?Cmp (℘ Any))]
   #;[set-lift-cmp : (∀ (X) (?Cmp X) → (?Cmp (℘ X)))]
   #;[fold-cmp : (∀ (X) (?Cmp X) (Listof X) (Listof X) → ?Ord)]
   #;[join-by-max : (∀ (X) (?Cmp X) → (?Joiner X))]
   #;[compact-with : (∀ (X) (?Joiner X) → (℘ X) X → (℘ X))]
   #;[iter-⊔ : (∀ (X) ((℘ X) X → (℘ X)) → (℘ X) (℘ X) → (℘ X))]
   
   #;[Ctx-with-site : (Ctx ℓ → Ctx)]
   #;[Ctx-with-origin : (Ctx ℓ → Ctx)]
   #;[X/C->binder : (X/C → Symbol)]
   #;[estimate-list-lengths : ((U Σ Σᵥ) V → (℘ (U #f Arity)))]
   ))

(define-signature pretty-print^
  ([show-α : (α → Sexp)]
   [show-V : (V → Sexp)]
   [show-V^ : (V^ → Sexp)]
   [show-W : (W → Sexp)]
   [show-Σ : (Σ → (Listof Sexp))])) 
