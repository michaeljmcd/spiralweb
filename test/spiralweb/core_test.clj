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
 (let [cb "@code asdf asdf [a=b]\nasdfasdf\nddddd\n  @<asdf>\n@="
       exp '[[{:type :code, :options [{:type :property, :value {:name "a", :value "b"}}], :name "asdf asdf", :lines ({:type :newline, :value "\n"} {:type :text, :value "asdfasdf"} {:type :newline, :value "\n"} {:type :text, :value "ddddd"} {:type :newline, :value "\n"} {:type :text, :value "  "} {:type :chunk-reference, :name "asdf", :indent-level 0} {:type :newline, :value "\n"})}] ()]
       act (code-definition cb)]
       (pr-str act)
  (is (= exp act))
  (is (success? act))))

(deftest tangle-tests
 (let [simple-web "@doc asdf [out=asdf.md]\nasdfasdfasdf\n@code bop [out=foo.c]\ninvalid\n@=\nasdf\nasdf\n@code quuz\nprintln foo\n@="
       output-chunk '{:lines ({:type :newline, :value "\n"}
             {:type :text, :value "invalid"}
             {:type :newline, :value "\n"}),
     :name "bop",
     :options ({:type :property, :value {:name "out", :value "foo.c"}}),
     :type :code}]
  (is (= (list output-chunk) (extract-output-chunks simple-web))))

 (let [nested-ref-web "@code bop [out=a.txt]\n   @<foo>\nasdf\n@=asdf\n@code foo\nquuz\n      @<asdf>\n@=\n@code asdf\ndef\n@="
       output-chunk '{:lines (
               ),
     :name "bop",
     :options ({:type :property, :value {:name "out", :value "a.txt"}}),
     :type :code}]
     ;(is (= (list output-chunk) (extract-output-chunks nested-ref-web)))
 )
 )
