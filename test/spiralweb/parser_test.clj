(ns spiralweb.parser-test
 (:require [clojure.test :refer :all]
           [spiralweb.parser :refer :all]
           [edessa.parser :refer [success? failure? apply-parser result]]
           [taoensso.timbre :as t :refer [debug error]]))

(deftest nl-tests
 (is (success? (apply-parser nl [\newline])))
 (is (failure? (apply-parser nl nil)))
 (is (failure? (apply-parser nl "asdf"))))

(deftest non-breaking-ws-tests
 (is (= '[\space] (result (apply-parser non-breaking-ws [\space]))))
 (is (success? (apply-parser non-breaking-ws [\space])))
 (is (failure? (apply-parser non-breaking-ws [\a \space]))))

(deftest text-tests
  (is (= [{:type :text :value "asdf"}]
         (result (apply-parser t-text "asdf"))))
  (is (failure? (apply-parser t-text "@foo")))
  (is (failure? (apply-parser t-text "[foo")))
  (is (failure? (apply-parser t-text "]foo")))
  (is (failure? (apply-parser t-text "=foo")))
  (is (failure? (apply-parser t-text ",foo")))
  (is (failure? (apply-parser t-text "\nfoo"))))

(deftest code-end-tests
  (is (= [{:type :code-end :value "@end"}]
         (result (apply-parser code-end "@end"))))
  (is (failure? (apply-parser code-end "@en"))))

(deftest doc-directive-tests
  (is (= [{:type :doc-directive :value "@doc"}]
         (result (apply-parser doc-directive "@doc"))))
  (is (failure? (apply-parser doc-directive "@do"))))

(deftest code-directive-tests
  (is (= [{:type :code-directive :value "@code"}]
         (result (apply-parser code-directive "@code"))))
  (is (failure? (apply-parser code-directive "@cod"))))

(deftest at-directive-tests
  (is (= [{:type :at-directive :value "@"}]
         (result (apply-parser at-directive "@@"))))
  (is (failure? (apply-parser at-directive "@"))))

(deftest comma-directive-tests
  (is (= [{:type :comma :value ","}]
         (result (apply-parser comma ",33"))))
  (is (failure? (apply-parser comma "33"))))

(deftest code-definition-tests
 (let [cb "@code asdf asdf [a=b]\nasdfasdf\nddddd\n  @<asdf>\n@end"
       exp '[{:type :code, :options [{:type :property, :value {:name "a", :value "b"}}], :name "asdf asdf", :lines ({:type :text, :value "asdfasdf"} {:type :newline, :value "\n"} {:type :text, :value "ddddd"} {:type :newline, :value "\n"} {:type :text, :value "  "} {:type :chunk-reference, :name "asdf", :indent-level 0} {:type :newline, :value "\n"})}]
       act (apply-parser code-definition cb)]
       (pr-str act)
  (is (= exp (result act)))
  (is (success? act))))

