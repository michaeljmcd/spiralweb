(ns spiralweb.core-test
 (:require [clojure.test :refer :all]
           [spiralweb.core :refer :all]
           [taoensso.timbre :as t :refer [debug error]]))

; Token tests

(deftest nl-tests
 (is (success? (nl [\newline])))
 (is (failure? (nl nil)))
 (is (failure? (nl "asdf"))))

(deftest non-breaking-ws-tests
 (is (= '[[\space] ()] (non-breaking-ws [\space])))
 (is (success? (non-breaking-ws [\space])))
 (is (failure? (non-breaking-ws [\a \space]))))

(deftest code-definition-tests
 (let [cb "@code asdf asdf [a=b]\nasdfasdf\nddddd\n  @<asdf>\n@end"
       exp '[[{:type :code, :options [{:type :property, :value {:name "a", :value "b"}}], :name "asdf asdf", :lines ({:type :newline, :value "\n"} {:type :text, :value "asdfasdf"} {:type :newline, :value "\n"} {:type :text, :value "ddddd"} {:type :newline, :value "\n"} {:type :text, :value "  "} {:type :chunk-reference, :name "asdf", :indent-level 0} {:type :newline, :value "\n"})}] ()]
       act (code-definition cb)]
       (pr-str act)
  (is (= exp act))
  (is (success? act))))

(deftest tangle-tests
 (let [circular-text "@code a\n@<b>\n@end\n@code b\n@<a>\n@end"
       result (tangle-text circular-text [])]
    (is (= nil result))))
