#lang typed/racket/base

(provide prim-runtime^)

(require typed/racket/unit
         typed/racket/unsafe
         set-extras
         "../ast/main.rkt"
         "../runtime/signatures.rkt")

(unsafe-require/typed syntax/id-table
  [#:opaque Parse-Prim-Table free-id-table?]
  [(make-free-id-table make-parse-prim-table) (#:phase (U #f Integer) → Parse-Prim-Table)]
  [(free-id-table-ref parse-prim-table-ref) (∀ (X) Parse-Prim-Table Identifier (→ X) → (U X -prim))]
  [(free-id-table-set! parse-prim-table-set!) (Parse-Prim-Table Identifier -prim → Void)]
  [(free-id-table-count parse-prim-table-count) (Parse-Prim-Table → Index)]
  [(in-free-id-table in-parse-prim-table) (Parse-Prim-Table → (Sequenceof Identifier -prim))]

  [#:opaque Alias-Table #|HACK|# mutable-free-id-table?]
  [(make-free-id-table make-alias-table) (#:phase (U #f Integer) → Alias-Table)]
  [(free-id-table-ref alias-table-ref) (∀ (X) Alias-Table Identifier (→ X) → (U X Identifier))]  
  [(free-id-table-set! alias-table-set!) (Alias-Table Identifier Identifier → Void)]
  [(free-id-table-count alias-table-count) (Alias-Table → Index)]
  [(in-free-id-table in-alias-table) (Alias-Table → (Sequenceof Identifier Identifier))])

(unsafe-provide Parse-Prim-Table
                make-parse-prim-table
                parse-prim-table-ref
                parse-prim-table-set!
                parse-prim-table-count
                in-parse-prim-table

                Alias-Table
                make-alias-table
                alias-table-ref
                alias-table-set!
                alias-table-count
                in-alias-table)

;; TODO: tmp. hack. Signature doesn't need to be this wide.
(define-signature prim-runtime^
  ([⊢?/quick : (-R -σ (℘ -t) -o -W¹ * → Boolean)]
   [make-total-pred : (Index → Symbol → -⟦o⟧)]
   [implement-predicate : (-M -σ -Γ Symbol (Listof -W¹) → (℘ -ΓA))]
   [ts->bs : ((Listof -?t) → (Option (Listof Base)))]
   [extract-list-content : (-σ -St → (℘ -V))]
   [unchecked-ac : (-σ -Γ -st-ac -W¹ → (℘ -W¹))]
   [arity-check/handler : (∀ (X) (-Γ → (℘ X)) (-Γ → (℘ X)) -Γ -W¹ Arity → (℘ X))]

   [get-weakers : (Symbol → (℘ Symbol))]
   [get-strongers : (Symbol → (℘ Symbol))]
   [get-exclusions : (Symbol → (℘ Symbol))]

   [add-implication! : (Symbol Symbol → Void)]
   [add-exclusion! : (Symbol Symbol → Void)]
   [set-range! : (Symbol Symbol → Void)]
   [update-arity! : (Symbol Arity → Void)]
   [set-partial! : (Symbol Natural → Void)]

   [prim-table : (HashTable Symbol -Prim)]
   [const-table : Parse-Prim-Table]
   [alias-table : Alias-Table]
   [debug-table : (HashTable Symbol Any)]
   [opq-table : (HashTable Symbol -●)]
   [range-table : (HashTable Symbol Symbol)]
   [arity-table : (HashTable Symbol Arity)]
   [partial-prims : (HashTable Symbol Natural)]

   [add-alias! : (Identifier Identifier → Void)]
   [add-const! : (Identifier -prim → Void)]))