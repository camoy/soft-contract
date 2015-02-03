(module assert racket (provide/contract [assert ((not/c false?) . -> . any/c)]))
(module m racket
  (provide/contract [main (-> any/c)])
  (require (submod ".." assert))
  (define (f x y) (if x (f y x) (g x y)))
  (define (g x y) (assert y))
  (define (h x) (assert x))
  (define (main) (if (< 0 1) (f (< 0 1) (< 1 0)) (h (< 1 0)))))
(require 'm)
(main)
