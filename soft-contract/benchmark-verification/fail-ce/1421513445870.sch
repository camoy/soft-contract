(module f racket
  (provide (contract-out 
            [f (->i ([x number?]
                     [y number?])
                    [res (x y) (and/c number? (>=/c 0))])]))

  (define (f x y)
    (+ x 9)))


