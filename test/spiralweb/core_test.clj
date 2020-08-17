(ns spiralweb.core-test
 (:require [clojure.test :refer :all]
           [spiralweb.core :refer :all]))

; Token tests

(deftest nl-tests
 (is (success? (nl [\newline])))
 (is (failure? (nl nil)))
 (is (failure? (nl "asdf"))))
