#lang racket/base

(require rackunit
         redis
         "common.rkt")

(provide
 client-tests)

(define client-tests
  (test-suite
   "client"

   (check-true (redis-select-db! test-client 0))
   (check-true (redis-flush-all! test-client))

   (check-equal? (redis-echo test-client "hello") "hello")
   (check-equal? (redis-ping test-client) "PONG")

   (test-commands "AUTH"
     (check-exn
      (lambda (e)
        (and (exn:fail:redis? e)
             (check-equal? (exn-message e) "Client sent AUTH, but no password is set")))
      (lambda _
        (redis-auth! test-client "hunter2"))))

   (test-commands "APPEND"
     (check-equal? (redis-bytes-append! test-client "a" "hello") 5)
     (check-equal? (redis-bytes-append! test-client "a" "world!") 11))

   (test-commands "BITCOUNT"
     (check-equal? (redis-bytes-bitcount test-client "a") 0)
     (check-true (redis-bytes-set! test-client "a" "hello"))
     (check-equal? (redis-bytes-bitcount test-client "a") 21))

   (test-commands "BITOP"
     (redis-bytes-set! test-client "a" "hello")
     (check-equal? (redis-bytes-bitwise-not! test-client "a") 5)
     (check-equal? (redis-bytes-get test-client "a") #"\227\232\223\223\220")
     (redis-bytes-set! test-client "a" #"\xFF")
     (redis-bytes-set! test-client "b" #"\x00")
     (redis-bytes-bitwise-and! test-client "c" "a" "b")
     (check-equal? (redis-bytes-get test-client "c") #"\x00"))

   (test-commands "client"
     (check-not-false (redis-client-id test-client))
     (check-equal? (redis-client-name test-client) "racket-redis")
     (check-true (redis-set-client-name! test-client "custom-name"))
     (check-equal? (redis-client-name test-client) "custom-name"))

   (test-commands "DBSIZE"
     (check-equal? (redis-key-count test-client) 0)
     (check-true (redis-bytes-set! test-client "a" "1"))
     (check-equal? (redis-key-count test-client) 1))

   (test-commands "DECR and DECRBY"
     (check-equal? (redis-bytes-decr! test-client "a") -1)
     (check-equal? (redis-bytes-decr! test-client "a") -2)
     (check-equal? (redis-bytes-decr! test-client "a" 3) -5)
     (check-equal? (redis-key-type test-client "a") 'string)

     (check-true (redis-bytes-set! test-client "a" "1.5"))
     (check-exn
      (lambda (e)
        (and (exn:fail:redis? e)
             (check-equal? (exn-message e) "value is not an integer or out of range")))
      (lambda _
        (redis-bytes-decr! test-client "a"))))

   (test-commands "DEL"
     (check-equal? (redis-remove! test-client "a") 0)
     (check-equal? (redis-remove! test-client "a" "b") 0)
     (check-true (redis-bytes-set! test-client "a" "1"))
     (check-equal? (redis-remove! test-client "a" "b") 1)
     (check-true (redis-bytes-set! test-client "a" "1"))
     (check-true (redis-bytes-set! test-client "b" "2"))
     (check-equal? (redis-remove! test-client "a" "b") 2))

   (test-commands "EVAL"
     (check-equal? (redis-script-eval! test-client "return 1") 1)
     (check-equal? (redis-script-eval! test-client "return {KEYS[1], ARGV[1], ARGV[2]}"
                                       #:keys '("a")
                                       #:args '("b" "c"))
                   '(#"a" #"b" #"c")))

   (test-commands "HEXISTS, HSET, HMSET, HGETALL, HDEL, HLEN, HKEYS, HVALS"
     (check-false (redis-hash-has-key? test-client "notahash" "a"))
     (check-true (redis-hash-set! test-client "simple-hash" "a" "1"))
     (check-true (redis-hash-has-key? test-client "simple-hash" "a"))
     (check-equal? (redis-hash-get test-client "simple-hash") (hash #"a" #"1"))
     (check-equal? (redis-hash-get test-client "simple-hash" "a") #"1")
     (check-equal? (redis-hash-remove! test-client "simple-hash" "a") 1)
     (check-equal? (redis-hash-get test-client "simple-hash") (hash))

     (check-true (redis-hash-set! test-client "alist-hash" '(("a" . "1")
                                                        ("b" . "2")
                                                        ("c" . "3"))))
     (check-equal? (redis-hash-get test-client "alist-hash") (hash #"a" #"1"
                                                              #"b" #"2"
                                                              #"c" #"3"))
     (check-equal? (redis-hash-get test-client "alist-hash" "a") #"1")
     (check-equal? (redis-hash-get test-client "alist-hash" "a" "b") (hash #"a" #"1"
                                                                      #"b" #"2"))
     (check-equal? (redis-hash-get test-client "alist-hash" "a" "d" "b") (hash #"a" #"1"
                                                                          #"b" #"2"
                                                                          #"d" (redis-null)))

     (check-equal? (redis-hash-length test-client "notahash") 0)
     (check-equal? (redis-hash-length test-client "alist-hash") 3)

     (check-equal? (redis-hash-keys test-client "notahash") null)
     (check-equal? (sort (redis-hash-keys test-client "alist-hash") bytes<?)
                   (sort'(#"a" #"b" #"c") bytes<?))

     (check-equal? (redis-hash-values test-client "notahash") null)
     (check-equal? (sort (redis-hash-values test-client "alist-hash") bytes<?)
                   (sort '(#"1" #"2" #"3") bytes<?)))

   (test-commands "{M,}GET and SET"
     (check-false (redis-has-key? test-client "a"))
     (check-true (redis-bytes-set! test-client "a" "1"))
     (check-equal? (redis-bytes-get test-client "a") #"1")
     (check-false (redis-bytes-set! test-client "a" "2" #:unless-exists? #t))
     (check-equal? (redis-bytes-get test-client "a") #"1")
     (check-false (redis-bytes-set! test-client "b" "2" #:when-exists? #t))
     (check-false (redis-has-key? test-client "b"))
     (check-true (redis-bytes-set! test-client "b" "2" #:unless-exists? #t))
     (check-true (redis-has-key? test-client "b"))
     (check-equal? (redis-bytes-get test-client "a" "b") '(#"1" #"2")))

   (test-commands "INCR, INCRBY and INCRBYFLOAT"
     (check-equal? (redis-bytes-incr! test-client "a") 1)
     (check-equal? (redis-bytes-incr! test-client "a") 2)
     (check-equal? (redis-bytes-incr! test-client "a" 3) 5)
     (check-equal? (redis-bytes-incr! test-client "a" 1.5) "6.5")
     (check-equal? (redis-key-type test-client "a") 'string))

   (test-commands "LINDEX, LLEN, LPUSH, LPOP, BLPOP"
     (check-equal? (redis-list-length test-client "a") 0)
     (check-equal? (redis-list-prepend! test-client "a" "1") 1)
     (check-equal? (redis-list-prepend! test-client "a" "2" "3") 3)
     (check-equal? (redis-list-length test-client "a") 3)
     (check-equal? (redis-list-ref test-client "a" 1) #"2")
     (check-equal? (redis-list-pop-left! test-client "a") #"3")
     (check-equal? (redis-list-pop-left! test-client "a") #"2")
     (check-equal? (redis-list-pop-left! test-client "a") #"1")
     (check-equal? (redis-list-pop-left! test-client "a") (redis-null))

     (check-exn
      exn:fail:contract?
      (lambda _
        (redis-list-pop-left! test-client "a" "b")))

     (check-exn
      exn:fail:contract?
      (lambda _
        (redis-list-pop-left! test-client "a" #:timeout 10)))

     (redis-list-append! test-client "a" "1")
     (check-equal? (redis-list-pop-left! test-client "a" #:block? #t) '(#"a" #"1"))

     (redis-list-append! test-client "b" "2")
     (check-equal? (redis-list-pop-left! test-client "a" "b" #:block? #t) '(#"b" #"2")))

   (test-commands "LINSERT"
     (check-equal? (redis-list-prepend! test-client "a" "1") 1)
     (check-equal? (redis-list-prepend! test-client "a" "2") 2)
     (check-equal? (redis-list-insert! test-client "a" "3" #:before "1") 3)
     (check-false (redis-list-insert! test-client "a" "3" #:before "8"))
     (check-equal? (redis-sublist test-client "a") '(#"2" #"3" #"1"))
     (check-equal? (redis-list-insert! test-client "a" "4" #:after "3") 4)
     (check-equal? (redis-sublist test-client "a") '(#"2" #"3" #"4" #"1")))

   (test-commands "LTRIM"
     (check-equal? (redis-list-prepend! test-client "a" "2") 1)
     (check-equal? (redis-list-prepend! test-client "a" "2") 2)
     (check-true (redis-list-trim! test-client "a" #:start 1))
     (check-equal? (redis-sublist test-client "a") '(#"2")))

   (test-commands "PERSIST, PEXPIRE and PTTL"
     (check-false (redis-expire-in! test-client "a" 200))
     (check-equal? (redis-key-ttl test-client "a") 'missing)
     (check-true (redis-bytes-set! test-client "a" "1"))
     (check-equal? (redis-key-ttl test-client "a") 'persisted)
     (check-true (redis-expire-in! test-client "a" 20))
     (check-true (> (redis-key-ttl test-client "a") 5))
     (check-true (redis-persist! test-client "a"))
     (check-equal? (redis-key-ttl test-client "a") 'persisted))

   (test-commands "PF*"
     (check-true (redis-hll-add! test-client "a" "1"))
     (check-true (redis-hll-add! test-client "a" "2"))
     (check-false (redis-hll-add! test-client "a" "1"))
     (check-equal? (redis-hll-count test-client "a") 2)
     (check-equal? (redis-hll-count test-client "a" "b") 2)
     (check-true (redis-hll-add! test-client "b" "1"))
     (check-equal? (redis-hll-count test-client "a" "b") 2)
     (check-true (redis-hll-merge! test-client "c" "a" "b"))
     (check-equal? (redis-hll-count test-client "c") 2))

   (test-commands "RENAME"
     (check-true (redis-bytes-set! test-client "a" "1"))
     (check-true (redis-bytes-set! test-client "b" "2"))
     (check-true (redis-rename! test-client "a" "c"))
     (check-false (redis-has-key? test-client "a"))
     (check-false (redis-rename! test-client "c" "b" #:unless-exists? #t))
     (check-true (redis-has-key? test-client "c")))

   (test-commands "RPUSH, RPOP, BRPOP, BRPOPLPUSH"
     (check-equal? (redis-list-append! test-client "a" "1") 1)
     (check-equal? (redis-list-append! test-client "a" "2") 2)
     (check-equal? (redis-list-pop-right! test-client "a") #"2")
     (check-equal? (redis-list-pop-right! test-client "a") #"1")
     (check-equal? (redis-list-pop-right! test-client "a") (redis-null))

     (check-exn
      exn:fail:contract?
      (lambda _
        (redis-list-pop-right! test-client "a" "b")))

     (check-exn
      exn:fail:contract?
      (lambda _
        (redis-list-pop-right! test-client "a" #:timeout 10)))

     (check-exn
      exn:fail:contract?
      (lambda _
        (redis-list-pop-right! test-client "a" "b" #:dest "b" #:block? #t)))

     (redis-list-append! test-client "a" "1")
     (check-equal? (redis-list-pop-right! test-client "a" #:block? #t) '(#"a" #"1"))

     (redis-list-append! test-client "b" "2")
     (check-equal? (redis-list-pop-right! test-client "a" "b" #:block? #t) '(#"b" #"2"))

     (redis-list-append! test-client "b" "2")
     (check-equal? (redis-list-pop-right! test-client "b" #:dest "a") #"2")
     (check-equal? (redis-list-pop-right! test-client "a") #"2")

     (redis-list-append! test-client "b" "2")
     (check-equal? (redis-list-pop-right! test-client "b" #:dest "a" #:block? #t) #"2")
     (check-equal? (redis-list-pop-right! test-client "a") #"2"))

   (test-commands "TOUCH"
     (check-equal? (redis-touch! test-client "a") 0)
     (check-equal? (redis-touch! test-client "a" "b") 0)
     (check-true (redis-bytes-set! test-client "a" "1"))
     (check-true (redis-bytes-set! test-client "b" "2"))
     (check-equal? (redis-touch! test-client "a" "b" "c") 2))

   (test-suite
    "streams"

    (test-commands "XADD, XDEL, XINFO, XLEN and XRANGE"
      (define first-id (redis-stream-add! test-client "a" "message" "hello"))
      (define second-id (redis-stream-add! test-client "a" "message" "goodbye"))
      (check-equal? (redis-stream-length test-client "a") 2)
      (define info (redis-stream-get test-client "a"))
      (check-equal? (redis-stream-info-length info) 2)
      (check-equal? (redis-stream-range test-client "a")
                    (list (redis-stream-info-first-entry info)
                          (redis-stream-info-last-entry info)))
      (check-equal? (redis-stream-remove! test-client "a" first-id) 1)
      (check-equal? (redis-stream-remove! test-client "a" first-id) 0)
      (check-equal? (redis-stream-range test-client "a")
                    (list (redis-stream-info-last-entry info)))))

   (check-equal? (redis-quit! test-client) (void))))

(module+ test
  (require rackunit/text-ui)
  (run-tests client-tests))