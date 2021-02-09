(ns spiralweb.core-test
 (:require [clojure.test :refer :all]
           [spiralweb.core :refer :all]
           [edessa.parser :refer [success? failure? apply-parser result]]
           [taoensso.timbre :as t :refer [debug error]]))

; Token tests

(deftest nl-tests
 (is (success? (apply-parser nl [\newline])))
 (is (failure? (apply-parser nl nil)))
 (is (failure? (apply-parser nl "asdf"))))

(deftest non-breaking-ws-tests
 (is (= '[\space] (result (apply-parser non-breaking-ws [\space]))))
 (is (success? (apply-parser non-breaking-ws [\space])))
 (is (failure? (apply-parser non-breaking-ws [\a \space]))))

(deftest code-definition-tests
 (let [cb "@code asdf asdf [a=b]\nasdfasdf\nddddd\n  @<asdf>\n@end"
       exp '[{:type :code, :options [{:type :property, :value {:name "a", :value "b"}}], :name "asdf asdf", :lines ({:type :newline, :value "\n"} {:type :text, :value "asdfasdf"} {:type :newline, :value "\n"} {:type :text, :value "ddddd"} {:type :newline, :value "\n"} {:type :text, :value "  "} {:type :chunk-reference, :name "asdf", :indent-level 0} {:type :newline, :value "\n"})}]
       act (apply-parser code-definition cb)]
       (pr-str act)
  (is (= exp (result act)))
  (is (success? act))))

(deftest tangle-tests
 (let [circular-text "@code a\n@<b>\n@end\n@code b\n@<a>\n@end"
       result (tangle-text circular-text [])]
    (is (= nil result))))
