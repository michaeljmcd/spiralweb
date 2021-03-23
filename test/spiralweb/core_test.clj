(ns spiralweb.core-test
 (:require [clojure.test :refer :all]
           [clojure.java.io :as io]
           [spiralweb.core :refer :all]
           [edessa.parser :refer [success? failure? apply-parser result]]
           [taoensso.timbre :as t :refer [debug error merge-config!]]))

(merge-config! {:level :info})

(deftest tangle-edge-case-tests
 (let [circular-text "@code a\n@<b>\n@end\n@code b\n@<a>\n@end"
       result (tangle-text circular-text [])]
    (is (= nil result))))
(defn load-resource [name] (-> name io/resource slurp))

(deftest simple-tangle-test
 (let [simple-text (load-resource "simple.sw")]
  (is (= "\nprint('Hello World')\n\n" ; TODO: FIXME
         (with-out-str (tangle-text simple-text ["My Code"]))))))
(deftest related-chunk-tangle-test
 (let [text (load-resource "simple-related.sw")]
  (is (= "\nprint('Hello World')\nif true:\n   print(1 + 2)\n\n"
         (with-out-str (tangle-text text ["Example"]))))))
