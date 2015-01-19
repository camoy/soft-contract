(module strnum? racket
  (provide/contract [strnum? (->i ([x any/c]) (res (x) (and/c boolean? (λ (a) (equal? a (or (string? x) (number? x)))))))])
  (define (strnum? x)
    (or (string? x) (number? x))))

(require 'strnum?)
(strnum? •)
