#lang racket
(provide parse parse-define parse-e env-define)
(require "ast.rkt")

;; [Listof S-Expr] -> Prog
(define (parse s)
  (match s
    [(cons (and (cons 'define _) d) s)
     (match (parse s)
       [(Prog ds e)
        (Prog (cons (parse-define d) ds) e)])]
    [(cons e '()) (Prog '() (parse-e e '()))]
    [_ (error "program parse error")]))

(define (env-define s)
  (match s
    [(cons (and (cons 'define _) d) s)
     (match (parse s)
       [(Prog ds e)
        (cons (env-define* d '()) ds)])]))

(define (env-define* s env)
  (match s
    [(list 'define (list-rest (? symbol? f) xs) e)
     (if (andmap symbol? xs)
         ( (cons f (parse-e e '())) env)
         (error "parse definition error"))]
    [_ (error "Parse defn error" s)]))

;; S-Expr -> Defn
(define (parse-define s)
  (match s
    [(list 'define (list-rest (? symbol? f) xs) e)
     (if (andmap symbol? xs)
         (Defn f xs (parse-e e '() #t))
         (error "parse definition error"))]
    [_ (error "Parse defn error" s)]))

;; Expr -> Lam
(define (parse-thunk e env)
  (Lam (gensym 'thunk) '() (parse-e e env))
)

(define (lookup-expr x cenv)
    (match cenv
      ['() (error "undefined variable:" x)]
      [(cons (cons y y-exp) rest)
        (match (eq? x y)
          [#t y-exp]
          [#f (lookup-expr x rest)])])
)

;; S-Expr -> Expr
(define (parse-e s env [def #f])
  (match s
    [(? integer?)                  (Int s)]
    [(? boolean?)                  (Bool s)]
    [(? char?)                     (Char s)]
    [(? string?)                   (Str s)]
    ['eof                          (Eof)]
    ;;; [(? symbol?)                   (Var s)]
    [(? symbol?)                   (if def (Var s)
                                   (App (parse-thunk (lookup-expr s env) env) '()))]
    [(list 'quote (list))          (Empty)]
    [(list (? (op? op0) p0))       (Prim0 p0)]
    
    [(list 'box e)                 (Prim1 'box (parse-thunk e env))] ; CHANGED
    [(list 'unbox e)               (App (Prim1 'unbox (parse-e e env)) '())] ; CHANGED
    [(list 'car e)                 (App (Prim1 'car (parse-e e env)) '())] ; CHANGED
    [(list 'cdr e)                 (App (Prim1 'cdr (parse-e e env)) '())] ; CHANGED
    [(list (? (op? op1) p1) e)     (Prim1 p1 (parse-e e env))]
    
    [(list 'cons e1 e2)            (Prim2 'cons (parse-thunk e1 env) (parse-thunk e2 env))] ; CHANGED
    [(list (? (op? op2) p2) e1 e2) (Prim2 p2 (parse-e e1 env) (parse-e e2 env))]
    
    [(list (? (op? op3) p3) e1 e2 e3)
     (Prim3 p3 (parse-e e1 env) (parse-e e2 env) (parse-e e3 env))]
    [(list 'begin e1 e2)
     (Begin (parse-e e1 env) (parse-e e2 env))]
    [(list 'if e1 e2 e3)
     (If (parse-e e1 env) (parse-e e2 env) (parse-e e3 env))]
    [(list 'let (list (list (? symbol? x) e1)) e2)
     (Let x (parse-thunk e1 env) (parse-e e2 (cons (cons x e1) env)))]
    [(cons 'match (cons e ms))
     (parse-match (parse-thunk e env) ms)]
    [(list (or 'lambda 'λ) xs e)
     (if (and (list? xs)
              (andmap symbol? xs))
         (Lam (gensym 'lambda) xs (parse-e e env))
         (error "parse lambda error"))]
    [(cons e es)
     (App (parse-e e env) (map parse-thunk es env))]    
    [_ (error "Parse error" s)]))

(define (parse-match e ms env)
  (match ms
    ['() (Match e '() '())]
    [(cons (list p r) ms)
     (match (parse-match e ms env)
       [(Match e ps es)
        (Match e
               (cons (parse-pat p) ps)
               (cons (parse-e r env) es))])]))

(define (parse-pat p)
  (match p
    [(? boolean?) (PLit p)]
    [(? integer?) (PLit p)]
    [(? char?)    (PLit p)]
    ['_           (PWild)]
    [(? symbol?)  (PVar p)]
    [(list 'quote (list))
     (PLit '())]
    [(list 'box p)
     (PBox (parse-pat p))]
    [(list 'cons p1 p2)
     (PCons (parse-pat p1) (parse-pat p2))]
    [(list 'and p1 p2)
     (PAnd (parse-pat p1) (parse-pat p2))]))

(define op0
  '(read-byte peek-byte void))

(define op1
  '(add1 sub1 zero? char? write-byte eof-object?
         integer->char char->integer
         box unbox empty? cons? box? car cdr
         vector? vector-length string? string-length))
(define op2
  '(+ - < = cons eq? make-vector vector-ref make-string string-ref))
(define op3
  '(vector-set!))

(define (op? ops)
  (λ (x)
    (and (symbol? x)
         (memq x ops))))
